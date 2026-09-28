#!/usr/bin/env python3
"""Host tests for signing validation and credential-free diagnostics; no Apple tools."""
import base64
import contextlib
import copy
import datetime
import hashlib
import io
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import device_test_support as signing


class StageDiagnosticsTests(unittest.TestCase):
    def run_script(self, overrides):
        bash = os.environ.get('RIG_TEST_BASH') or shutil.which('bash')
        if not bash:
            self.skipTest('bash is unavailable')
        environment = dict(os.environ)
        for name in (*signing.SECRET_NAMES, 'RUNNER_OS', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT',
                     'RUNNER_TEMP', 'GITHUB_WORKSPACE'):
            environment.pop(name, None)
        environment.update(overrides)
        return subprocess.run([bash, 'scripts/device_test.sh'], cwd=Path(__file__).resolve().parents[1],
                              env=environment, capture_output=True, text=True)

    def test_invalid_runner_is_diagnosed_before_exit(self):
        result = self.run_script({})
        self.assertEqual(result.returncode, 1)
        self.assertIn('[1/9] Validate environment and secrets', result.stdout)
        self.assertIn('ERROR: macOS runner required', result.stderr)

    def test_missing_secret_is_diagnosed_without_values(self):
        result = self.run_script(dict(RUNNER_OS='macOS', GITHUB_RUN_ID='1', GITHUB_RUN_ATTEMPT='1',
                                     RUNNER_TEMP='/synthetic-temp', GITHUB_WORKSPACE='/synthetic-workspace'))
        self.assertEqual(result.returncode, 1)
        self.assertIn('[1/9] Validate environment and secrets', result.stdout)
        self.assertIn('ERROR: Missing required secret: APPLE_TEAM_ID', result.stderr)

    def test_invalid_team_is_diagnosed_without_secret_echo(self):
        secrets = {name: 'synthetic-sensitive-value' for name in signing.SECRET_NAMES}
        result = self.run_script(dict(secrets, RUNNER_OS='macOS', GITHUB_RUN_ID='1', GITHUB_RUN_ATTEMPT='1',
                                     RUNNER_TEMP='/synthetic-temp', GITHUB_WORKSPACE='/synthetic-workspace'))
        self.assertEqual(result.returncode, 1)
        self.assertIn('ERROR: Invalid Apple team ID format', result.stderr)
        self.assertNotIn('synthetic-sensitive-value', result.stdout + result.stderr)

    def test_private_command_failures_have_safe_stage_diagnostics(self):
        scenarios = [
            ('decode', '[2/9] Decode signing material', 'Failed to decode signing material'),
            ('create-keychain', '[3/9] Create temporary keychain', 'Failed to create temporary keychain'),
            ('import', '[4/9] Import Apple Distribution certificate', 'Failed to import Apple Distribution P12'),
            ('find-identity', '[5/9] Read and validate Ad Hoc provisioning profile', 'Failed to query signing identity'),
            ('cms', '[5/9] Read and validate Ad Hoc provisioning profile', 'Failed to decode provisioning profile'),
            ('prepare', '[5/9] Read and validate Ad Hoc provisioning profile', 'Provisioning profile/certificate validation failed'),
        ]
        for command, marker, error in scenarios:
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'bin').mkdir()
                (root / 'temp').mkdir()
                (root / 'workspace').mkdir()
                stubs = {
                    'security': '''#!/bin/bash
if [[ "$1" == "$RIG_TEST_FAIL_COMMAND" ]]; then
  echo synthetic-raw-signing-stderr >&2
  exit 1
fi
if [[ "$1" == list-keychains && "$*" != *" -s"* ]]; then
  echo '\"synthetic-default-keychain\"'
fi
''',
                    'python3': '''#!/bin/bash
if [[ "$2" == "$RIG_TEST_FAIL_COMMAND" ]]; then
  echo synthetic-raw-signing-stderr >&2
  exit 1
fi
''',
                    'openssl': '#!/bin/bash\necho synthetic-keychain-password\n',
                }
                for name, text in stubs.items():
                    path = root / 'bin' / name
                    path.write_text(text, encoding='utf-8')
                    path.chmod(0o755)
                environment = {name: 'synthetic-secret-value' for name in signing.SECRET_NAMES}
                environment.update(APPLE_TEAM_ID='TESTTEAM01', RUNNER_OS='macOS', GITHUB_RUN_ID='1',
                                   GITHUB_RUN_ATTEMPT='1', RUNNER_TEMP=str(root / 'temp'),
                                   GITHUB_WORKSPACE=str(root / 'workspace'), RIG_TEST_FAIL_COMMAND=command,
                                   PATH=str(root / 'bin') + os.pathsep + os.environ['PATH'])
                result = self.run_script(environment)
                self.assertEqual(result.returncode, 1)
                self.assertIn(marker, result.stdout)
                self.assertIn('ERROR: ' + error, result.stderr)
                self.assertNotIn('synthetic-raw-signing-stderr', result.stdout + result.stderr)
                self.assertNotIn('synthetic-secret-value', result.stdout + result.stderr)
                self.assertFalse((root / 'temp/rig-device-test-1-1').exists())


class DeviceSigningTests(unittest.TestCase):
    def setUp(self):
        self.team = 'TESTTEAM01'
        self.cert = b'synthetic certificate fixture, never a real credential'
        self.profile = dict(
            UUID='00000000-0000-4000-8000-000000000001', Name='Synthetic device test',
            TeamIdentifier=[self.team], ProvisionedDevices=['synthetic-device-id'],
            ExpirationDate=datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
            + datetime.timedelta(days=1), DeveloperCertificates=[self.cert],
            Entitlements={'application-identifier': self.team + '.dev.rig.app',
                          'get-task-allow': False})

    def test_valid_adhoc_profile(self):
        signing.validate_profile(self.profile, self.team)

    def test_rejects_unsafe_profiles(self):
        mutations = [
            ('TeamIdentifier', ['OTHERTEAM1']), ('ProvisionedDevices', []),
            ('ProvisionedDevices', None), ('ProvisionsAllDevices', True),
            ('UUID', '../../profile'), ('Name', 'bad\nname'),
            ('ExpirationDate', datetime.datetime(2000, 1, 1)),
            ('Entitlements', {'application-identifier': self.team + '.*', 'get-task-allow': False}),
            ('Entitlements', {'application-identifier': self.team + '.dev.rig.app', 'get-task-allow': True}),
            ('Entitlements', {'application-identifier': self.team + '.dev.rig.app'}),
            ('Entitlements', {'application-identifier': self.team + '.dev.rig.app',
                              'get-task-allow': False, 'beta-reports-active': True}),
        ]
        for key, value in mutations:
            with self.subTest(key=key, value=value):
                profile = copy.deepcopy(self.profile)
                profile[key] = value
                with self.assertRaises(ValueError):
                    signing.validate_profile(profile, self.team)

    def test_prepare_options_and_certificate_match(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / 'artifact'
            artifact.mkdir()
            (root / 'profile.plist').write_bytes(plistlib.dumps(self.profile))
            digest = hashlib.sha1(self.cert).hexdigest().upper()
            (root / 'identities.txt').write_text('1) ' + digest + ' "Apple Distribution: Fixture"\n')
            with patch.dict(os.environ, APPLE_TEAM_ID=self.team), contextlib.redirect_stdout(io.StringIO()):
                signing.prepare(root, artifact)
            options = signing.load(artifact / 'ExportOptions.plist')
            self.assertEqual(options['method'], 'ad-hoc')
            self.assertEqual(options['destination'], 'export')
            self.assertEqual(options['signingStyle'], 'manual')
            self.assertEqual(options['teamID'], self.team)
            self.assertEqual(options['provisioningProfiles'], {'dev.rig.app': self.profile['Name']})
            self.assertTrue(options['stripSwiftSymbols'])
            self.assertNotIn('compileBitcode', options)
            (root / 'identities.txt').write_text('No valid identity')
            with patch.dict(os.environ, APPLE_TEAM_ID=self.team), self.assertRaises(ValueError):
                signing.prepare(root, artifact)

    def test_log_redaction_and_allowlist(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / 'artifact'
            artifact.mkdir()
            (root / 'profile.plist').write_bytes(plistlib.dumps(self.profile))
            password = 'synthetic-password-fixture'
            certificate = base64.b64encode(self.cert).decode()
            log = '\n'.join([password, self.team, self.profile['Name'], self.profile['UUID'],
                             'synthetic-device-id', certificate, self.cert.hex(),
                             '<plist><data>certificate bytes</data></plist>',
                             '-----BEGIN PRIVATE KEY-----\nprivate bytes\n-----END PRIVATE KEY-----',
                             'Apple Distribution: Fixture', '** ARCHIVE SUCCEEDED **'])
            for filename in ('archive.log', 'export.log', 'keychain.log', 'identities.txt'):
                (root / filename).write_text(log)
            with patch.dict(os.environ, IOS_DISTRIBUTION_P12_PASSWORD=password):
                signing.sanitize(root, artifact)
            self.assertEqual({p.name for p in artifact.iterdir()}, {'archive.log', 'export.log'})
            cleaned = (artifact / 'archive.log').read_text()
            for forbidden in (password, self.team, self.profile['Name'], self.profile['UUID'],
                              'synthetic-device-id', certificate, self.cert.hex(),
                              'certificate bytes', 'private bytes', 'Fixture'):
                self.assertNotIn(forbidden, cleaned)
            self.assertIn('** ARCHIVE SUCCEEDED **', cleaned)

    def test_exported_ipa_validation_and_sanitized_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / 'artifact'
            artifact.mkdir()
            app = root / 'Payload/RIG.app'
            app.mkdir(parents=True)
            (app / 'RIG').write_bytes(b'synthetic executable')
            (app / 'embedded.mobileprovision').write_bytes(b'synthetic CMS fixture')
            ipa = root / 'synthetic.ipa'
            ipa.write_bytes(b'synthetic zip fixture')
            info = dict(CFBundleIdentifier='dev.rig.app', CFBundleExecutable='RIG',
                        DTPlatformName='iphoneos', CFBundleSupportedPlatforms=['iPhoneOS'],
                        CFBundleShortVersionString='0.2', CFBundleVersion='1')
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            (root / 'uuid').write_text(self.profile['UUID'])
            (root / 'certificate-sha').write_text(hashlib.sha1(self.cert).hexdigest().upper())
            (root / 'signer-0').write_bytes(self.cert)
            (root / 'embedded-profile.plist').write_bytes(plistlib.dumps(self.profile))
            (root / 'entitlements.plist').write_bytes(plistlib.dumps(self.profile['Entitlements']))
            environment = dict(RIG_DEVICE_APP=str(app), RIG_DEVICE_IPA=str(ipa),
                               APPLE_TEAM_ID=self.team, GITHUB_SHA='synthetic-commit', GITHUB_RUN_NUMBER='1')
            profile_data = copy.deepcopy(self.profile)
            entitlement_data = copy.deepcopy(self.profile['Entitlements'])
            def extract(command, **kwargs):
                if command[0] == 'security':
                    (root / 'embedded-profile.plist').write_bytes(plistlib.dumps(profile_data))
                elif '--entitlements' in command:
                    self.assertEqual(command[2:5], ['--entitlements', '-', '--xml'])
                    kwargs['stdout'].write(plistlib.dumps(entitlement_data, fmt=plistlib.FMT_XML))

            with patch.dict(os.environ, environment), \
                    patch.object(signing.subprocess, 'check_output', return_value='arm64\n') as archs, \
                    patch.object(signing.subprocess, 'run', side_effect=extract), \
                    contextlib.redirect_stdout(io.StringIO()) as console:
                signing.verify(root, artifact)
                expected_markers = [
                    '[9.1] Validate exported app Info.plist', '[9.2] Validate device architecture',
                    '[9.3] Validate embedded provisioning profile', '[9.4] Validate signed entitlements',
                    '[9.5] Validate exported signing certificate', '[9.6] Validate version/build metadata',
                    '[9.7] Write sanitized signing manifest',
                ]
                self.assertEqual(console.getvalue().splitlines()[:7], expected_markers)
                self.assertEqual(signing.load(root / 'entitlements.plist'), entitlement_data)
                manifest = (artifact / 'signing-manifest.json').read_text()
                for forbidden in (self.team, self.profile['UUID'], self.profile['Name'], 'synthetic-device-id'):
                    self.assertNotIn(forbidden, manifest)
                def check_failure(number, message):
                    with contextlib.redirect_stdout(io.StringIO()) as failed_console:
                        with self.assertRaises(signing.VerificationError):
                            signing.verify(root, artifact)
                    lines = failed_console.getvalue().splitlines()
                    self.assertEqual(lines[:-1], expected_markers[:number])
                    self.assertEqual(lines[-1], 'ERROR: ' + message)
                    for forbidden in (self.team, self.profile['UUID'], self.profile['Name'], 'synthetic-device-id'):
                        self.assertNotIn(forbidden, failed_console.getvalue())
                bad_info = dict(info, CFBundleIdentifier='synthetic-wrong-bundle')
                (app / 'Info.plist').write_bytes(plistlib.dumps(bad_info))
                check_failure(1, 'Exported bundle metadata validation failed')
                (app / 'Info.plist').write_bytes(plistlib.dumps(info))
                archs.return_value = 'x86_64\n'
                check_failure(2, 'Exported architecture validation failed')
                archs.return_value = 'arm64\n'
                profile_data['UUID'] = '00000000-0000-4000-8000-000000000002'
                check_failure(3, 'Embedded provisioning profile validation failed')
                profile_data = copy.deepcopy(self.profile)
                entitlement_data['application-identifier'] = 'wrong.app'
                check_failure(4, 'Signed entitlements validation failed')
                entitlement_data = copy.deepcopy(self.profile['Entitlements'])
                (root / 'signer-0').write_bytes(b'synthetic-wrong-certificate')
                check_failure(5, 'Exported signing certificate validation failed')
                (root / 'signer-0').write_bytes(self.cert)
                bad_info = dict(info, CFBundleVersion='synthetic-invalid-build')
                (app / 'Info.plist').write_bytes(plistlib.dumps(bad_info))
                check_failure(6, 'Exported version/build validation failed')
                (app / 'Info.plist').write_bytes(plistlib.dumps(info))
                (artifact / 'signing-manifest.json').unlink()
                (artifact / 'signing-manifest.json').mkdir()
                check_failure(7, 'Signing manifest creation failed')

    def test_verification_failures_emit_only_safe_stage_errors(self):
        errors = [
            'Exported bundle metadata validation failed', 'Exported architecture validation failed',
            'Embedded provisioning profile validation failed', 'Signed entitlements validation failed',
            'Exported signing certificate validation failed', 'Exported version/build validation failed',
            'Signing manifest creation failed',
        ]
        for number, error in enumerate(errors, 1):
            with self.subTest(stage=number), contextlib.redirect_stdout(io.StringIO()) as console:
                with self.assertRaises(signing.VerificationError) as raised:
                    with signing.verification_stage(number, 'Synthetic stage', error):
                        raise subprocess.CalledProcessError(1, ['synthetic-secret-command'],
                                                            stderr='synthetic-secret-stderr')
                self.assertEqual(str(raised.exception), error)
                self.assertEqual(console.getvalue(), f'[9.{number}] Synthetic stage\nERROR: {error}\n')

    def test_invalid_entitlement_output_is_rejected_without_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / 'RIG.app'
            app.mkdir()
            (app / 'RIG').write_bytes(b'synthetic executable')
            (app / 'embedded.mobileprovision').write_bytes(b'synthetic CMS fixture')
            (app / 'Info.plist').write_bytes(plistlib.dumps(dict(
                CFBundleIdentifier='dev.rig.app', CFBundleExecutable='RIG',
                DTPlatformName='iphoneos', CFBundleSupportedPlatforms=['iPhoneOS'])))
            (root / 'uuid').write_text(self.profile['UUID'])
            def extract(command, **kwargs):
                if command[0] == 'security':
                    (root / 'embedded-profile.plist').write_bytes(plistlib.dumps(self.profile))
                else:
                    kwargs['stdout'].write(b'synthetic-entitlement-human-readable-value')
            environment = dict(RIG_DEVICE_APP=str(app), RIG_DEVICE_IPA=str(root / 'fixture.ipa'),
                               APPLE_TEAM_ID=self.team, RIG_DEVICE_SECRET_DIR=str(root),
                               RIG_DEVICE_OUTPUT=str(root))
            with patch.dict(os.environ, environment), patch.object(sys, 'argv', ['support', 'verify']), \
                    patch.object(signing.subprocess, 'check_output', return_value='arm64'), \
                    patch.object(signing.subprocess, 'run', side_effect=extract), \
                    contextlib.redirect_stdout(io.StringIO()) as console, \
                    contextlib.redirect_stderr(io.StringIO()) as errors:
                self.assertEqual(signing.main(), 1)
            self.assertIn('[9.4] Validate signed entitlements', console.getvalue())
            self.assertIn('ERROR: Signed entitlements validation failed', console.getvalue())
            self.assertNotIn('[9.5]', console.getvalue())
            for forbidden in ('synthetic-entitlement-human-readable-value', self.team, self.profile['UUID']):
                self.assertNotIn(forbidden, console.getvalue() + errors.getvalue())
            self.assertEqual(errors.getvalue(), '')
            self.assertFalse((root / 'artifact/signing-manifest.json').exists())


if __name__ == '__main__':
    unittest.main()
