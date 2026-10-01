#!/usr/bin/env python3
"""Private TestFlight signing checks and deliberately small public diagnostics."""
import base64
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
VERSION = '0.2'
LOG_NAMES = ('generation', 'archive', 'export', 'signature', 'ipa-validation',
             'architectures', 'apple-validation', 'upload')
SOURCE_ERROR = re.compile(r'(?:^|[\s/])(Sources|Tests)/([A-Za-z0-9_+./-]+\.swift):(\d+)(?::(\d+))?:\s*(error|warning):')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    return plistlib.loads(path.read_bytes())


def decode(root):
    for variable, filename in [('IOS_DISTRIBUTION_P12_BASE64', 'certificate.p12'),
                               ('IOS_APP_STORE_PROFILE_BASE64', 'profile.mobileprovision'),
                               ('ASC_PRIVATE_KEY_BASE64', 'AuthKey_' + os.environ['ASC_KEY_ID'] + '.p8')]:
        raw = base64.b64decode(os.environ[variable], validate=True)
        require(bool(raw), 'Empty signing material')
        (root / filename).write_bytes(raw)


def prepare(root):
    profile = load(root / 'profile.plist')
    entitlements = profile['Entitlements']
    team = os.environ['APPLE_TEAM_ID']
    require(team in profile['TeamIdentifier'], 'Profile team mismatch')
    require(entitlements['application-identifier'] == team + '.' + BUNDLE, 'Profile bundle mismatch')
    require(not entitlements.get('get-task-allow'), 'Development profile forbidden')
    require('ProvisionedDevices' not in profile and not profile.get('ProvisionsAllDevices'),
            'App Store profile required')
    require(entitlements.get('beta-reports-active'), 'TestFlight entitlement required')
    require(profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
            'Expired profile')
    require(str(uuid.UUID(profile['UUID'])).upper() == profile['UUID'].upper(), 'Invalid profile UUID')
    certs = {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}
    identities = re.findall(r'([A-F0-9]{40}) "Apple Distribution:[^"\r\n]+"',
                            (root / 'identities.txt').read_text())
    matching = sorted(set(identities) & certs)
    require(len(matching) == 1, 'Exactly one matching Apple Distribution identity required')
    (root / 'uuid').write_text(profile['UUID'])
    (root / 'certificate-sha').write_text(matching[0])
    options = dict(method='app-store-connect', destination='export', signingStyle='manual',
                   teamID=team, signingCertificate=matching[0], manageAppVersionAndBuildNumber=False,
                   provisioningProfiles={BUNDLE: profile['UUID']})
    (root / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))


def verify(root):
    app = root / 'ipa/Payload/RIG.app'
    info = load(app / 'Info.plist')
    require(info['CFBundleIdentifier'] == BUNDLE, 'Bundle mismatch')
    require(info['CFBundleShortVersionString'] == VERSION, 'Version mismatch')
    require(info['CFBundleVersion'] == os.environ['RC_BUILD_NUMBER'], 'Build mismatch')
    require(info['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'Platform mismatch')
    require(info['DTPlatformName'] == 'iphoneos', 'SDK platform mismatch')
    require(int(info['DTSDKName'].removeprefix('iphoneos').split('.')[0]) >= 26, 'SDK too old')
    require(info.get('ITSAppUsesNonExemptEncryption') is False, 'Encryption metadata mismatch')
    require((app / 'PrivacyInfo.xcprivacy').is_file(), 'Privacy manifest missing')
    require(load(root / 'export-profile.plist')['UUID'] == (root / 'uuid').read_text(),
            'Exported profile mismatch')
    entitlements = load(root / 'export-entitlements.plist')
    require(entitlements['application-identifier'] == os.environ['APPLE_TEAM_ID'] + '.' + BUNDLE,
            'Signed bundle mismatch')
    require(not entitlements.get('get-task-allow') and entitlements.get('beta-reports-active'),
            'Distribution entitlements missing')
    archs = subprocess.check_output(['lipo', '-archs', str(app / 'RIG')],
                                    stderr=subprocess.DEVNULL, text=True).strip()
    require(archs == 'arm64', 'arm64 required')
    (root / 'architectures.log').write_text(archs + '\n')


def sanitize(root, output):
    """Publish only fixed status words and existing source locations, never tool prose.

    A compiler's message can contain an arbitrary credential, including one not
    stored in GitHub Secrets. Exact-value redaction cannot prove it is safe.
    """
    require(output.is_dir() and not output.is_symlink(), 'Artifact directory missing')
    completed = set((root / 'completed').read_text().splitlines()) if (root / 'completed').exists() else set()
    staging = root / 'sanitized-staging'
    staging.mkdir(mode=0o700)
    for name in LOG_NAMES:
        path = root / (name + '.log')
        if not path.exists():
            continue
        require(path.is_file() and not path.is_symlink(), 'Unsafe log file')
        text = path.read_text(encoding='utf-8')
        lines = [name + ': ' + ('completed' if name in completed else 'failed or incomplete')]
        if name in ('generation', 'archive', 'export'):
            for match in SOURCE_ERROR.finditer(text):
                relative = Path(match.group(1)) / match.group(2)
                require('..' not in relative.parts, 'Unsafe source path')
                if relative.is_file():
                    location = str(relative) + ':' + match.group(3)
                    if match.group(4):
                        location += ':' + match.group(4)
                    lines.append(location + ': ' + match.group(5))
        (staging / (name + '.log')).write_text('\n'.join(lines) + '\n', encoding='utf-8')
    # Validate every staged byte before making any file visible to upload-artifact.
    for path in staging.iterdir():
        require(path.is_file() and path.name in {name + '.log' for name in LOG_NAMES},
                'Unexpected sanitized file')
        require(len(path.read_bytes()) < 1000000, 'Sanitized log too large')
    for path in staging.iterdir():
        path.replace(output / path.name)


def manifest(root, output):
    build = os.environ['RC_BUILD_NUMBER']
    commit = os.environ['GITHUB_SHA']
    require(re.fullmatch(r'[1-9][0-9]*', build), 'Invalid build')
    require(re.fullmatch(r'[0-9a-fA-F]{40}', commit), 'Invalid commit')
    completed = set((root / 'completed').read_text().splitlines()) if (root / 'completed').exists() else set()
    # Only fixed keys and validated non-secret values are allowed into artifacts.
    report = dict(bundle=BUNDLE, version=VERSION, build=build, commit=commit,
                  architecture='arm64' if 'ipa-validation' in completed else 'unverified',
                  ipa_validation='passed' if 'ipa-validation' in completed else 'not completed',
                  apple_validation='passed' if 'apple-validation' in completed else 'not completed',
                  upload='accepted by Apple; processing pending' if 'upload' in completed else
                         ('disabled' if os.environ['RC_UPLOAD'] == 'false' else 'not completed'))
    (output / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')


def main():
    command = sys.argv[1]
    root = Path(os.environ['RIG_SECRET_DIR'])
    output = Path(os.environ['RIG_ARTIFACT_DIR'])
    try:
        if command == 'decode':
            decode(root)
        elif command == 'prepare':
            prepare(root)
        elif command == 'verify':
            verify(root)
        elif command == 'sanitize':
            sanitize(root, output)
        elif command == 'manifest':
            manifest(root, output)
        else:
            raise ValueError('Unknown command')
    except Exception:
        # Never print malformed input, subprocess arguments, or tool stderr.
        print('Release support step failed: ' + command, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
