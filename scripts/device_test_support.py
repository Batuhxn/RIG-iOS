#!/usr/bin/env python3
"""Private signing checks and allowlisted artifacts for device_test.sh."""
import base64
import contextlib
import datetime
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import uuid
from pathlib import Path

BUNDLE = 'dev.rig.app'
SECRET_NAMES = ('APPLE_TEAM_ID', 'IOS_DISTRIBUTION_P12_BASE64',
                'IOS_DISTRIBUTION_P12_PASSWORD', 'IOS_ADHOC_PROFILE_BASE64')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    return plistlib.loads(path.read_bytes())


def validate_profile(profile, team):
    entitlements = profile.get('Entitlements', {})
    require(profile.get('TeamIdentifier') == [team], 'Profile team mismatch')
    require(entitlements.get('application-identifier') == team + '.' + BUNDLE,
            'Profile application identifier mismatch')
    require(entitlements.get('get-task-allow') is False, 'Distribution profile required')
    devices = profile.get('ProvisionedDevices')
    require(isinstance(devices, list) and len(devices) > 0
            and all(isinstance(device, str) and device for device in devices),
            'Registered devices required')
    require(not profile.get('ProvisionsAllDevices'), 'Enterprise profile forbidden')
    require(not entitlements.get('beta-reports-active'), 'TestFlight profile forbidden')
    expiry = profile.get('ExpirationDate')
    require(isinstance(expiry, datetime.datetime), 'Profile expiration missing')
    require(expiry.replace(tzinfo=datetime.timezone.utc) > datetime.datetime.now(datetime.timezone.utc),
            'Profile expired')
    profile_uuid = profile.get('UUID', '')
    require(str(uuid.UUID(profile_uuid)).upper() == profile_uuid.upper(), 'Invalid profile UUID')
    name = profile.get('Name')
    require(isinstance(name, str) and name and not any(ord(c) < 32 for c in name),
            'Invalid profile name')
    return entitlements


def decode(root):
    for variable, filename in [('IOS_DISTRIBUTION_P12_BASE64', 'certificate.p12'),
                               ('IOS_ADHOC_PROFILE_BASE64', 'profile.mobileprovision')]:
        raw = base64.b64decode(os.environ[variable], validate=True)
        require(bool(raw), 'Empty signing material')
        (root / filename).write_bytes(raw)


def prepare(root, artifact):
    profile = load(root / 'profile.plist')
    team = os.environ['APPLE_TEAM_ID']
    validate_profile(profile, team)
    certs = {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}
    identities = re.findall(r'([A-F0-9]{40}) "Apple Distribution:[^"\r\n]+"',
                            (root / 'identities.txt').read_text())
    matching = sorted(set(identities) & certs)
    require(len(matching) == 1, 'Exactly one matching Apple Distribution identity required')
    (root / 'uuid').write_text(profile['UUID'])
    (root / 'certificate-sha').write_text(matching[0])
    # Mask runtime signing metadata before any later command can emit it.
    for value in (profile['UUID'], profile['Name'], matching[0]):
        value = value.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print('::add-mask::' + value)
    options = dict(method='ad-hoc', destination='export', signingStyle='manual',
                   teamID=team, signingCertificate=matching[0],
                   provisioningProfiles={BUNDLE: profile['Name']},
                   stripSwiftSymbols=True, manageAppVersionAndBuildNumber=False)
    (artifact / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
    print('PASS: valid Ad Hoc profile and matching Apple Distribution certificate')


class VerificationError(ValueError):
    """A stage already emitted a fixed, credential-free diagnostic."""


@contextlib.contextmanager
def verification_stage(number, title, error):
    print(f'[9.{number}] {title}', flush=True)
    try:
        yield
    except Exception:
        # Use stdout because the shell keeps raw Python stderr private. Never
        # print exception details, subprocess arguments or malformed values.
        print('ERROR: ' + error, flush=True)
        raise VerificationError(error) from None


def verify(root, artifact):
    with verification_stage(1, 'Validate exported app Info.plist', 'Exported bundle metadata validation failed'):
        app = Path(os.environ['RIG_DEVICE_APP'])
        ipa = Path(os.environ['RIG_DEVICE_IPA'])
        info = load(app / 'Info.plist')
        require(info.get('CFBundleIdentifier') == BUNDLE, 'IPA bundle identifier mismatch')
        require(info.get('DTPlatformName') == 'iphoneos'
                and info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], 'Device platform required')
        executable_name = info.get('CFBundleExecutable', '')
        require(bool(executable_name) and Path(executable_name).name == executable_name,
                'Invalid executable name')
        executable = app / executable_name
        require(executable.is_file(), 'Executable missing')
    with verification_stage(2, 'Validate device architecture', 'Exported architecture validation failed'):
        archs = subprocess.check_output(['lipo', '-archs', str(executable)], stderr=subprocess.DEVNULL,
                                        text=True).strip().split()
        require('arm64' in archs and not any(a in archs for a in ('x86_64', 'i386')),
                'Device executable must contain arm64')
    with verification_stage(3, 'Validate embedded provisioning profile', 'Embedded provisioning profile validation failed'):
        require((app / 'embedded.mobileprovision').is_file(), 'Embedded provisioning profile missing')
        with (root / 'embedded-errors.log').open('wb') as errors:
            subprocess.run(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision'),
                            '-o', str(root / 'embedded-profile.plist')],
                           check=True, stdout=subprocess.DEVNULL, stderr=errors)
        profile = load(root / 'embedded-profile.plist')
        validate_profile(profile, os.environ['APPLE_TEAM_ID'])
        require(profile['UUID'] == (root / 'uuid').read_text(), 'Embedded profile UUID mismatch')
    with verification_stage(4, 'Validate signed entitlements', 'Signed entitlements validation failed'):
        # TN3125: --xml forces machine-readable XML instead of DER display text.
        with (root / 'entitlements.plist').open('wb') as output, (root / 'signature.log').open('ab') as errors:
            subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(app)],
                           check=True, stdout=output, stderr=errors)
        entitlements = load(root / 'entitlements.plist')
        require(entitlements.get('application-identifier') == os.environ['APPLE_TEAM_ID'] + '.' + BUNDLE,
                'Signed application identifier mismatch')
        require(entitlements.get('get-task-allow') is False, 'Signed app must disable debugging')
    with verification_stage(5, 'Validate exported signing certificate', 'Exported signing certificate validation failed'):
        # Check the actual exported signer, not just the archive signing settings.
        prefix = str(root / 'signer-')
        # The prefix is optional, so codesign requires the --option=value form.
        subprocess.run(['codesign', '-d', '--extract-certificates=' + prefix, str(app)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        actual_signer = hashlib.sha1((root / 'signer-0').read_bytes()).hexdigest().upper()
        require(actual_signer == (root / 'certificate-sha').read_text(), 'Exported signing identity mismatch')
    with verification_stage(6, 'Validate version/build metadata', 'Exported version/build validation failed'):
        version = info.get('CFBundleShortVersionString', '')
        build = info.get('CFBundleVersion', '')
        require(isinstance(version, str) and re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', version),
                'Invalid marketing version')
        require(isinstance(build, str) and re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', build),
                'Invalid build version')
    with verification_stage(7, 'Write sanitized signing manifest', 'Signing manifest creation failed'):
        # No names, device IDs, UUIDs, team IDs, entitlements or certificate bytes.
        manifest = dict(commit=os.environ['GITHUB_SHA'], run_number=os.environ['GITHUB_RUN_NUMBER'],
                        bundle_identifier=BUNDLE, version=version, build=build,
                        architectures=archs, configuration='Release', sdk='iphoneos',
                        export_method='ad-hoc', signing_style='manual',
                        signer='Apple Distribution', registered_device_count=len(profile['ProvisionedDevices']),
                        codesign_verified=True, embedded_profile_matches=True,
                        application_identifier_matches=True,
                        ipa_sha256=hashlib.sha256(ipa.read_bytes()).hexdigest())
        (artifact / 'signing-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Bundle identifier: ' + BUNDLE)
    print('CFBundleShortVersionString: ' + version)
    print('CFBundleVersion: ' + build)
    print('Executable architectures: ' + ' '.join(archs))
    print('PASS: signature, embedded Ad Hoc profile and signed entitlements')


def sanitize_text(text, sensitive):
    # Remove dumps as whole blocks before exact-value redaction.
    text = re.sub(r'-----BEGIN [^-]+-----.*?-----END [^-]+-----',
                  '[REDACTED PEM]', text, flags=re.S)
    text = re.sub(r'<\?xml.*?</plist>|<plist\b.*?</plist>|<data>.*?</data>',
                  '[REDACTED signing data]', text, flags=re.S)
    for value in sorted(sensitive, key=len, reverse=True):
        if value:
            text = text.replace(value, '[REDACTED]')
    # Catch long binary encodings and standard device identifiers as a backstop.
    text = re.sub(r'[A-Za-z0-9+/=]{80,}', '[REDACTED encoded data]', text)
    text = re.sub(r'\b[0-9A-Fa-f]{40}\b|\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b',
                  '[REDACTED identifier]', text)
    text = re.sub(r'Apple Distribution:[^"\r\n]*', 'Apple Distribution: [REDACTED]', text)
    return text


def sanitize(root, artifact):
    sensitive = {os.environ.get(name, '') for name in SECRET_NAMES}
    sensitive.add(str(root))
    for filename in ('profile.plist', 'embedded-profile.plist'):
        if not (root / filename).is_file():
            continue
        profile = load(root / filename)
        for key in ('UUID', 'Name', 'TeamName'):
            value = profile.get(key)
            if isinstance(value, str):
                sensitive.add(value)
        for key in ('TeamIdentifier', 'ApplicationIdentifierPrefix', 'ProvisionedDevices'):
            sensitive.update(profile.get(key, []))
        sensitive.update(value for value in profile.get('Entitlements', {}).values()
                         if isinstance(value, str))
        for cert in profile.get('DeveloperCertificates', []):
            sensitive.update((base64.b64encode(cert).decode(), cert.hex(),
                              hashlib.sha1(cert).hexdigest().upper()))
    # Explicit diagnostic allowlist; never publish import/CMS output or identity lists.
    for name in ('generation.log', 'archive.log', 'export.log', 'signature.log'):
        path = root / name
        if path.is_file():
            text = sanitize_text(path.read_text(errors='replace'), sensitive)
            (artifact / name).write_text(text, encoding='utf-8')


def main():
    root = Path(os.environ['RIG_DEVICE_SECRET_DIR'])
    artifact = Path(os.environ['RIG_DEVICE_OUTPUT']) / 'artifact'
    command = sys.argv[1]
    try:
        if command == 'decode':
            decode(root)
        elif command == 'prepare':
            prepare(root, artifact)
        elif command == 'verify':
            verify(root, artifact)
        elif command == 'sanitize':
            sanitize(root, artifact)
        else:
            raise ValueError('Unknown command')
    except VerificationError:
        return 1
    except Exception:
        # Malformed signing inputs must never appear in a traceback or log.
        print('Device signing step failed: ' + command + '. No signing data was printed.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
