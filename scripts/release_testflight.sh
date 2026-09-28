#!/bin/bash
set -euo pipefail
umask 077

# Invoke only through the manual release workflow on an ephemeral macOS runner.
[[ "${RUNNER_OS:-}" == macOS && "${GITHUB_REF:-}" == refs/heads/main ]]
[[ "${RC_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]]
[[ "${RC_UPLOAD:-}" == true || "${RC_UPLOAD:-}" == false ]]
for name in APPLE_TEAM_ID IOS_DISTRIBUTION_P12_BASE64 IOS_DISTRIBUTION_P12_PASSWORD IOS_APP_STORE_PROFILE_BASE64 ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_BASE64; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required secret: $name" >&2
    exit 1
  fi
done
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ && "$ASC_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]
[[ "$ASC_ISSUER_ID" =~ ^[a-fA-F0-9-]{36}$ ]]
mkdir -p build/rc1
secret_dir=$(mktemp -d "$RUNNER_TEMP/rig-signing.XXXXXX")
keychain="$secret_dir/release.keychain-db"
original_keychains=()
while IFS= read -r entry; do
  entry="${entry#*\"}"
  entry="${entry%\"*}"
  original_keychains+=("$entry")
done < <(security list-keychains -d user)
installed_profiles=()
cleanup() {
  security list-keychains -d user -s "${original_keychains[@]}" || true
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  for entry in "${installed_profiles[@]}"; do rm -f "$entry"; done
  rm -rf "$secret_dir"
}
trap cleanup EXIT

export RIG_SECRET_DIR="$secret_dir"
python3 - <<'PY'
import base64, os
from pathlib import Path
root = Path(os.environ['RIG_SECRET_DIR'])
for name, filename in [('IOS_DISTRIBUTION_P12_BASE64', 'certificate.p12'),
                       ('IOS_APP_STORE_PROFILE_BASE64', 'profile.mobileprovision'),
                       ('ASC_PRIVATE_KEY_BASE64', 'AuthKey_' + os.environ['ASC_KEY_ID'] + '.p8')]:
    (root / filename).write_bytes(base64.b64decode(os.environ[name], validate=True))
PY
keychain_password=$(openssl rand -hex 32)
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$secret_dir/certificate.p12" -k "$keychain" -P "$IOS_DISTRIBUTION_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security list-keychains -d user -s "$keychain" "${original_keychains[@]}"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security find-identity -v -p codesigning "$keychain" > "$secret_dir/identities.txt"
security cms -D -i "$secret_dir/profile.mobileprovision" > "$secret_dir/profile.plist"
python3 - <<'PY'
import datetime, hashlib, os, plistlib, re
from pathlib import Path
root = Path(os.environ['RIG_SECRET_DIR'])
p = plistlib.loads((root / 'profile.plist').read_bytes())
e = p['Entitlements']
team = os.environ['APPLE_TEAM_ID']
assert team in p['TeamIdentifier'], 'Profile team mismatch'
assert e['application-identifier'] == team + '.dev.rig.app', 'Profile bundle ID mismatch'
assert not e.get('get-task-allow'), 'Development profile is forbidden'
assert 'ProvisionedDevices' not in p and not p.get('ProvisionsAllDevices'), 'App Store profile required'
assert e.get('beta-reports-active'), 'TestFlight profile entitlement required'
assert p['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Expired profile'
certs = {hashlib.sha1(c).hexdigest().upper() for c in p['DeveloperCertificates']}
identities = re.findall(r'([A-F0-9]{40}) ' + chr(34) + 'Apple Distribution:', (root / 'identities.txt').read_text())
matching = [c for c in identities if c in certs]
assert len(matching) == 1, 'Exactly one valid matching Apple Distribution identity required'
assert re.fullmatch(r'[A-Fa-f0-9-]{36}', p['UUID']), 'Invalid profile UUID'
(root / 'uuid').write_text(p['UUID'])
(root / 'certificate-sha').write_text(matching[0])
options = dict(method='app-store-connect', destination='export', signingStyle='manual',
               teamID=team, signingCertificate=matching[0], manageAppVersionAndBuildNumber=False,
               provisioningProfiles={'dev.rig.app': p['UUID']})
(root / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY
profile_uuid=$(cat "$secret_dir/uuid")
certificate_sha=$(cat "$secret_dir/certificate-sha")
for directory in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$directory"
  target="$directory/$profile_uuid.mobileprovision"
  [[ ! -e "$target" ]] || { echo "Refusing to overwrite an existing profile" >&2; exit 1; }
  cp "$secret_dir/profile.mobileprovision" "$target"
  installed_profiles+=("$target")
done
xcodegen generate 2>&1 | tee build/rc1/generation.log
xcodebuild archive -project RIG.xcodeproj -scheme RIG -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/rc1/RIG.xcarchive \
  -derivedDataPath build/rc1/DerivedData CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_IDENTITY="$certificate_sha" \
  PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" MARKETING_VERSION=0.2 \
  CURRENT_PROJECT_VERSION="$RC_BUILD_NUMBER" \
  OTHER_CODE_SIGN_FLAGS="--keychain $keychain" 2>&1 | tee build/rc1/archive.log
xcodebuild -exportArchive -archivePath build/rc1/RIG.xcarchive \
  -exportOptionsPlist "$secret_dir/ExportOptions.plist" \
  -exportPath build/rc1/export 2>&1 | tee build/rc1/export.log
ipas=(build/rc1/export/*.ipa)
[[ ${#ipas[@]} -eq 1 && -f "${ipas[0]}" ]]
ipa="${ipas[0]}"
unzip -q "$ipa" -d "$secret_dir/ipa"
app="$secret_dir/ipa/Payload/RIG.app"
codesign --verify --deep --strict --verbose=2 "$app" 2>&1 | tee build/rc1/signature.log
security cms -D -i "$app/embedded.mobileprovision" > "$secret_dir/export-profile.plist"
codesign -d --entitlements :- "$app" > "$secret_dir/export-entitlements.plist" 2>> build/rc1/signature.log
python3 - <<'PY' 2>&1 | tee build/rc1/ipa-validation.log
import os, plistlib
from pathlib import Path
root = Path(os.environ['RIG_SECRET_DIR'])
app = root / 'ipa/Payload/RIG.app'
p = plistlib.loads((app / 'Info.plist').read_bytes())
assert p['CFBundleIdentifier'] == 'dev.rig.app'
assert p['CFBundleShortVersionString'] == '0.2'
assert p['CFBundleVersion'] == os.environ['RC_BUILD_NUMBER']
assert p['CFBundleSupportedPlatforms'] == ['iPhoneOS']
assert p['DTPlatformName'] == 'iphoneos'
assert int(p['DTSDKName'].removeprefix('iphoneos').split('.')[0]) >= 26
assert p.get('ITSAppUsesNonExemptEncryption') is False
assert (app / 'PrivacyInfo.xcprivacy').is_file()
profile = plistlib.loads((root / 'export-profile.plist').read_bytes())
assert profile['UUID'] == (root / 'uuid').read_text()
e = plistlib.loads((root / 'export-entitlements.plist').read_bytes())
assert e['application-identifier'] == os.environ['APPLE_TEAM_ID'] + '.dev.rig.app'
assert not e.get('get-task-allow') and e.get('beta-reports-active')
print('PASS: signed distribution IPA, bundle, version, SDK, privacy and entitlements')
PY
lipo -archs "$app/RIG" | tee build/rc1/architectures.log
[[ "$(lipo -archs "$app/RIG")" == arm64 ]]
export API_PRIVATE_KEYS_DIR="$secret_dir"
xcrun altool --validate-app -f "$ipa" --type ios --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee build/rc1/apple-validation.log
{
  echo "Commit: $GITHUB_SHA"
  echo "Bundle: dev.rig.app"
  echo "Version: 0.2 ($RC_BUILD_NUMBER)"
  echo "Upload explicitly enabled: $RC_UPLOAD"
  xcodebuild -version
  xcodegen --version
  shasum -a 256 "$ipa"
} > build/rc1/manifest.txt
if [[ "$RC_UPLOAD" == true ]]; then
  xcrun altool --upload-app -f "$ipa" --type ios --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee build/rc1/upload.log
  echo 'Upload accepted; App Store Connect processing and tester availability remain separate.' >> build/rc1/manifest.txt
else
  echo 'IPA validated. Upload disabled.' >> build/rc1/manifest.txt
fi
