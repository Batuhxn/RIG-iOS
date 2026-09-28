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
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import device_test_support as signing


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
            with patch.dict(os.environ, environment), \
                    patch.object(signing.subprocess, 'check_output', return_value='arm64\n') as archs, \
                    patch.object(signing.subprocess, 'run'), contextlib.redirect_stdout(io.StringIO()):
                signing.verify(root, artifact)
                manifest = (artifact / 'signing-manifest.json').read_text()
                for forbidden in (self.team, self.profile['UUID'], self.profile['Name'], 'synthetic-device-id'):
                    self.assertNotIn(forbidden, manifest)
                archs.return_value = 'x86_64\n'
                with self.assertRaises(ValueError):
                    signing.verify(root, artifact)
                archs.return_value = 'arm64\n'
                embedded = copy.deepcopy(self.profile)
                embedded['UUID'] = '00000000-0000-4000-8000-000000000002'
                (root / 'embedded-profile.plist').write_bytes(plistlib.dumps(embedded))
                with self.assertRaises(ValueError):
                    signing.verify(root, artifact)
                (root / 'embedded-profile.plist').write_bytes(plistlib.dumps(self.profile))
                entitlements = dict(self.profile['Entitlements'], **{'application-identifier': 'wrong.app'})
                (root / 'entitlements.plist').write_bytes(plistlib.dumps(entitlements))
                with self.assertRaises(ValueError):
                    signing.verify(root, artifact)


if __name__ == '__main__':
    unittest.main()
