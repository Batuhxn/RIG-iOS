#!/usr/bin/env python3
"""Synthetic release security tests; no Apple credentials or macOS tools."""
import base64
import datetime
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
import uuid
import zipfile
from pathlib import Path
from unittest.mock import patch

import release_support as release

REPO = Path(__file__).resolve().parents[1]
TEAM = 'ABCDE12345'
KEY = 'KEY1234567'
ISSUER = '12345678-1234-1234-1234-123456789abc'
CERT = b'synthetic distribution certificate'
CERT_SHA = hashlib.sha1(CERT).hexdigest().upper()
PROFILE_UUID = str(uuid.uuid4()).upper()
SECRET = 'SYNTHETIC_SECRET_VALUE_NEVER_PUBLISH'


def profile():
    return dict(TeamIdentifier=[TEAM], UUID=PROFILE_UUID,
                ExpirationDate=datetime.datetime(2030, 1, 1),
                DeveloperCertificates=[CERT],
                Entitlements={'application-identifier': TEAM + '.dev.rig.app',
                              'get-task-allow': False, 'beta-reports-active': True})


def executable(path, content):
    path.write_text(content)
    path.chmod(0o700)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.runner = self.base / 'runner'
        self.workspace = self.base / 'workspace'
        self.home = self.base / 'home'
        self.bin = self.base / 'bin'
        for directory in (self.runner, self.workspace, self.home, self.bin):
            directory.mkdir()
        self.profile_file = self.base / 'profile.plist'
        self.profile_file.write_bytes(plistlib.dumps(profile()))
        self.entitlements_file = self.base / 'entitlements.plist'
        self.entitlements_file.write_bytes(plistlib.dumps(profile()['Entitlements']))
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        HOME=str(self.home), RUNNER_OS='macOS', GITHUB_REF='refs/heads/main',
                        GITHUB_RUN_ID='123', GITHUB_RUN_ATTEMPT='1',
                        RUNNER_TEMP=str(self.runner), GITHUB_WORKSPACE=str(self.workspace),
                        GITHUB_SHA='a' * 40, RC_BUILD_NUMBER='1', RC_UPLOAD='false',
                        APPLE_TEAM_ID=TEAM, ASC_KEY_ID=KEY, ASC_ISSUER_ID=ISSUER,
                        IOS_DISTRIBUTION_P12_PASSWORD=SECRET,
                        IOS_DISTRIBUTION_P12_BASE64=base64.b64encode(b'synthetic p12').decode(),
                        IOS_APP_STORE_PROFILE_BASE64=base64.b64encode(b'synthetic profile').decode(),
                        ASC_PRIVATE_KEY_BASE64=base64.b64encode(b'synthetic p8').decode(),
                        RIG_TEST_PROFILE=str(self.profile_file),
                        RIG_TEST_ENTITLEMENTS=str(self.entitlements_file),
                        RIG_TEST_CERT_SHA=CERT_SHA,
                        RIG_TEST_COMMANDS=str(self.base / 'commands'),
                        RIG_TEST_SECRET=SECRET)
        executable(self.bin / 'security', '''#!/bin/bash
echo "security $1" >> "$RIG_TEST_COMMANDS"
[[ "${RIG_TEST_FAIL:-}" == "security-$1" ]] && { echo "$RIG_TEST_SECRET" >&2; exit 1; }
case "$1" in
  list-keychains) [[ "$*" == *" -s"* ]] || echo '"synthetic-default-keychain"' ;;
  find-identity) echo "  1) $RIG_TEST_CERT_SHA \\"Apple Distribution: Synthetic\\"" ;;
  cms) cat "$RIG_TEST_PROFILE" ;;
esac
''')
        executable(self.bin / 'openssl', '#!/bin/bash\necho synthetic-keychain-password\n')
        executable(self.bin / 'xcodegen', '''#!/bin/bash
echo "xcodegen $1" >> "$RIG_TEST_COMMANDS"
[[ "${RIG_TEST_FAIL:-}" == xcodegen ]] && exit 1
exit 0
''')
        executable(self.bin / 'xcodebuild', '''#!/usr/bin/env python3
import os, pathlib, sys, zipfile, plistlib
args = sys.argv[1:]
stage = 'archive' if 'archive' in args else 'export'
with open(os.environ['RIG_TEST_COMMANDS'], 'a') as record: record.write('xcodebuild ' + stage + '\\n')
print(os.environ['RIG_TEST_SECRET'])
print('Sources/App/RIGApp.swift:12:4: error: synthetic error ' + os.environ['RIG_TEST_SECRET'])
if os.environ.get('RIG_TEST_FAIL') == stage: sys.exit(1)
if stage == 'export':
    dest = pathlib.Path(args[args.index('-exportPath') + 1])
    dest.mkdir(parents=True)
    info = dict(CFBundleIdentifier='dev.rig.app', CFBundleShortVersionString='0.2',
                CFBundleVersion='1', CFBundleSupportedPlatforms=['iPhoneOS'],
                DTPlatformName='iphoneos', DTSDKName='iphoneos26.0',
                ITSAppUsesNonExemptEncryption=False)
    with zipfile.ZipFile(dest / 'RIG.ipa', 'w') as z:
        z.writestr('Payload/RIG.app/Info.plist', plistlib.dumps(info))
        z.writestr('Payload/RIG.app/PrivacyInfo.xcprivacy', b'placeholder')
        z.writestr('Payload/RIG.app/embedded.mobileprovision', b'placeholder')
        z.writestr('Payload/RIG.app/RIG', b'synthetic executable')
''')
        executable(self.bin / 'codesign', '''#!/bin/bash
[[ "${RIG_TEST_FAIL:-}" == codesign ]] && { echo "$RIG_TEST_SECRET" >&2; exit 1; }
if [[ "$1" == -d ]]; then cat "$RIG_TEST_ENTITLEMENTS"; fi
''')
        executable(self.bin / 'lipo', '#!/bin/bash\necho arm64\n')
        executable(self.bin / 'xcrun', '''#!/bin/bash
echo "xcrun $2" >> "$RIG_TEST_COMMANDS"
[[ "${RIG_TEST_FAIL:-}" == "$2" ]] && { echo "$RIG_TEST_SECRET" >&2; exit 1; }
echo 'Request accepted'
''')

    def run_release(self, **overrides):
        env = dict(self.env, **overrides)
        return subprocess.run(['bash', 'scripts/release_testflight.sh'], cwd=REPO,
                              env=env, capture_output=True, text=True)

    def artifact(self):
        return self.workspace / 'build/rc1/artifact'

    def assert_clean(self):
        self.assertFalse((self.runner / 'rig-release-123-1').exists())
        self.assertFalse(list(self.home.rglob('*.mobileprovision')))

    def test_missing_secret_and_bad_base64_are_safe(self):
        for change, expected in [({'ASC_PRIVATE_KEY_BASE64': ''}, 'Missing required secret'),
                                 ({'ASC_PRIVATE_KEY_BASE64': 'bad!'}, 'Failed to decode')]:
            with self.subTest(change=change):
                result = self.run_release(**change)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected, result.stderr)
                self.assertNotIn(SECRET, result.stdout + result.stderr)
                self.assert_clean()

    def test_import_profile_archive_export_and_apple_fail_closed(self):
        for failure, expected in [('security-import', 'Failed to import'),
                                  ('archive', 'Release archive failed'),
                                  ('export', 'IPA export failed'),
                                  ('--validate-app', 'Apple validation failed')]:
            with self.subTest(failure=failure):
                result = self.run_release(RIG_TEST_FAIL=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected, result.stderr)
                self.assertNotIn(SECRET, result.stdout + result.stderr)
                self.assertNotIn('xcrun --upload-app', (self.base / 'commands').read_text())
                self.assert_clean()
                for path in self.artifact().glob('*'):
                    self.assertNotIn(SECRET, path.read_text())
                (self.base / 'commands').unlink()
                if self.artifact().exists():
                    for path in self.artifact().iterdir(): path.unlink()
                    self.artifact().rmdir()

    def test_profile_mismatch(self):
        bad = profile()
        bad['Entitlements']['application-identifier'] = TEAM + '.other.app'
        self.profile_file.write_bytes(plistlib.dumps(bad))
        result = self.run_release()
        self.assertIn('Profile and certificate validation failed', result.stderr)
        self.assertNotIn(SECRET, result.stdout + result.stderr)
        self.assert_clean()

    def test_upload_off_and_successful_upload(self):
        for enabled in (False, True):
            with self.subTest(enabled=enabled):
                result = self.run_release(RC_UPLOAD='true' if enabled else 'false')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                commands = (self.base / 'commands').read_text()
                self.assertEqual('xcrun --upload-app' in commands, enabled)
                report = json.loads((self.artifact() / 'manifest.json').read_text())
                self.assertEqual(report['apple_validation'], 'passed')
                self.assertEqual(report['architecture'], 'arm64')
                self.assertEqual(report['upload'] == 'disabled', not enabled)
                self.assert_clean()
                for path in self.artifact().iterdir():
                    self.assertNotIn(SECRET, path.read_text())
                    path.unlink()
                self.artifact().rmdir()
                (self.base / 'commands').unlink()

    def test_sanitizer_failure_removes_artifact(self):
        # A symlink at the fixed raw-log path makes sanitization reject the run.
        executable(self.bin / 'xcodegen', '''#!/bin/bash
rm -f "$RIG_SECRET_DIR/generation.log"
ln -s "$RIG_TEST_PROFILE" "$RIG_SECRET_DIR/generation.log"
''')
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Artifact preparation failed', result.stderr)
        self.assertFalse(self.artifact().exists())
        self.assert_clean()

    def test_prepare_rejects_certificate_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'profile.plist').write_bytes(plistlib.dumps(profile()))
            (root / 'identities.txt').write_text('  1) ' + 'A' * 40 + ' "Apple Distribution: Other"')
            with patch.dict(os.environ, {'APPLE_TEAM_ID': TEAM}):
                with self.assertRaises(ValueError):
                    release.prepare(root)

    def test_sanitizer_keeps_location_but_never_tool_prose(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / 'artifact'
            artifact.mkdir()
            (root / 'archive.log').write_text(
                '-----BEGIN PRIVATE KEY-----\n' + SECRET + '\n-----END PRIVATE KEY-----\n'
                'Authorization: Bearer ' + SECRET + '\n'
                '/private/runner/work/RIG-iOS/Sources/App/RIGApp.swift:12:4: error: ' + SECRET + '\n')
            original = Path.cwd()
            try:
                os.chdir(REPO)
                release.sanitize(root, artifact)
            finally:
                os.chdir(original)
            content = (artifact / 'archive.log').read_text()
            self.assertIn('Sources/App/RIGApp.swift:12:4: error', content)
            self.assertNotIn(SECRET, content)
            self.assertNotIn('PRIVATE KEY', content)


if __name__ == '__main__':
    unittest.main()
