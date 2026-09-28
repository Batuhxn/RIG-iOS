#!/bin/bash
set -euo pipefail
set +x
umask 077

fail() {
  echo "ERROR: $1" >&2
  exit 1
}
# Never include BASH_COMMAND, expanded arguments or signing metadata in errors.
trap 'echo "ERROR: Device-test stage failed" >&2' ERR
if [[ "${1:-}" != --cleanup ]]; then
  echo '[1/9] Validate environment and secrets'
fi

# Mirrors release_testflight.sh project generation and signing, with no Apple
# service credentials or upload command. Raw diagnostics stay in RUNNER_TEMP.
[[ "${RUNNER_OS:-}" == macOS ]] || fail 'macOS runner required'
[[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]] \
  || fail 'Invalid workflow run environment'
[[ -n "${RUNNER_TEMP:-}" && -n "${GITHUB_WORKSPACE:-}" ]] \
  || fail 'Required runner paths are missing'
secret_dir="$RUNNER_TEMP/rig-device-test-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
keychain="$secret_dir/device-test.keychain-db"
output="$GITHUB_WORKSPACE/build/device-test"
export RIG_DEVICE_SECRET_DIR="$secret_dir"
export RIG_DEVICE_OUTPUT="$output"

cleanup() {
  local entry
  local original_keychains=()
  if [[ -f "$secret_dir/original-keychains" ]]; then
    while IFS= read -r entry; do original_keychains+=("$entry"); done < "$secret_dir/original-keychains"
    security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1 || true
  fi
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  if [[ -f "$secret_dir/installed-profiles" ]]; then
    while IFS= read -r entry; do
      case "$entry" in
        "$HOME/Library/MobileDevice/Provisioning Profiles/"*.mobileprovision|"$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision)
          rm -f "$entry" 2>/dev/null ;;
      esac
    done < "$secret_dir/installed-profiles"
  fi
  # Archives, DerivedData, decoded profiles, entitlements and raw logs are private.
  rm -rf "$secret_dir" 2>/dev/null
}
if [[ "${1:-}" == --cleanup ]]; then cleanup; exit 0; fi

for name in APPLE_TEAM_ID IOS_DISTRIBUTION_P12_BASE64 IOS_DISTRIBUTION_P12_PASSWORD IOS_ADHOC_PROFILE_BASE64; do
  if [[ -z "${!name:-}" ]]; then fail "Missing required secret: $name"; fi
done
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail 'Invalid Apple team ID format'
[[ ! -e "$secret_dir" && ! -e "$output" ]] || fail 'Signing or artifact directory already exists'
mkdir -p "$secret_dir" "$output/artifact" 2>/dev/null || fail 'Failed to create temporary directories'
finish() {
  local status=$?
  trap - EXIT INT TERM ERR
  # Sanitization fails closed: never publish raw logs when filtering fails.
  if ! python3 scripts/device_test_support.py sanitize; then
    echo 'ERROR: Failed to sanitize diagnostics' >&2
    rm -f "$output/artifact/"*.log
    status=1
  fi
  cleanup
  exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

security list-keychains -d user > "$secret_dir/keychain-list.txt" 2> "$secret_dir/identity-errors.log" \
  || fail 'Failed to query keychain search list'
while IFS= read -r entry; do
  entry="${entry#*\"}"
  entry="${entry%\"*}"
  printf '%s\n' "$entry" >> "$secret_dir/original-keychains"
done < "$secret_dir/keychain-list.txt"
echo '[2/9] Decode signing material'
python3 scripts/device_test_support.py decode 2> "$secret_dir/decode-errors.log" \
  || fail 'Failed to decode signing material'
echo '[3/9] Create temporary keychain'
keychain_password=$(openssl rand -hex 32 2> "$secret_dir/keychain.log") \
  || fail 'Failed to generate temporary keychain password'
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$keychain" > "$secret_dir/keychain.log" 2>&1 \
  || fail 'Failed to create temporary keychain'
security set-keychain-settings -lut 21600 "$keychain" >> "$secret_dir/keychain.log" 2>&1 \
  || fail 'Failed to configure temporary keychain'
security unlock-keychain -p "$keychain_password" "$keychain" >> "$secret_dir/keychain.log" 2>&1 \
  || fail 'Failed to unlock temporary keychain'
echo '[4/9] Import Apple Distribution certificate'
security import "$secret_dir/certificate.p12" -k "$keychain" -P "$IOS_DISTRIBUTION_P12_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security >> "$secret_dir/keychain.log" 2>&1 \
  || fail 'Failed to import Apple Distribution P12'
original_keychains=()
while IFS= read -r entry; do original_keychains+=("$entry"); done < "$secret_dir/original-keychains"
security list-keychains -d user -s "$keychain" "${original_keychains[@]}" >> "$secret_dir/keychain.log" 2>&1 \
  || fail 'Failed to configure keychain search list'
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" \
  "$keychain" >> "$secret_dir/keychain.log" 2>&1 \
  || fail 'Failed to configure codesign access'
echo '[5/9] Read and validate Ad Hoc provisioning profile'
security find-identity -v -p codesigning "$keychain" > "$secret_dir/identities.txt" 2> "$secret_dir/identity-errors.log" \
  || fail 'Failed to query signing identity'
security cms -D -i "$secret_dir/profile.mobileprovision" -o "$secret_dir/profile.plist" 2> "$secret_dir/profile-errors.log" \
  || fail 'Failed to decode provisioning profile'
python3 scripts/device_test_support.py prepare 2> "$secret_dir/prepare-errors.log" \
  || fail 'Provisioning profile/certificate validation failed'
profile_uuid=$(cat "$secret_dir/uuid" 2> "$secret_dir/metadata-errors.log") \
  || fail 'Failed to read validated profile metadata'
certificate_sha=$(cat "$secret_dir/certificate-sha" 2>> "$secret_dir/metadata-errors.log") \
  || fail 'Failed to read validated certificate metadata'
echo '[6/9] Install provisioning profile'
# Xcode 26 also searches UserData; install the same profile in both locations.
for directory in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$directory" 2>> "$secret_dir/profile-errors.log" || fail 'Failed to create profile directory'
  target="$directory/$profile_uuid.mobileprovision"
  [[ ! -e "$target" ]] || fail 'Refusing to overwrite an existing profile'
  printf '%s\n' "$target" >> "$secret_dir/installed-profiles"
  cp "$secret_dir/profile.mobileprovision" "$target" 2>> "$secret_dir/profile-errors.log" \
    || fail 'Failed to install provisioning profile'
done

echo '[7/9] Generate Xcode project'
xcodegen generate > "$secret_dir/generation.log" 2>&1 || fail 'Failed to generate Xcode project'
xcodebuild -project RIG.xcodeproj -list >> "$secret_dir/generation.log" 2>&1 \
  || fail 'Failed to open generated Xcode project'
echo '[8/9] Archive and export'
xcodebuild archive -project RIG.xcodeproj -scheme RIG -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -arch arm64 \
  -archivePath "$secret_dir/RIG.xcarchive" -derivedDataPath "$secret_dir/DerivedData" \
  CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_IDENTITY="$certificate_sha" \
  PRODUCT_BUNDLE_IDENTIFIER=dev.rig.app PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" \
  OTHER_CODE_SIGN_FLAGS="--keychain $keychain" > "$secret_dir/archive.log" 2>&1 \
  || fail 'Failed to archive app'
echo 'Exporting the archive for registered devices.'
xcodebuild -exportArchive -archivePath "$secret_dir/RIG.xcarchive" \
  -exportOptionsPlist "$output/artifact/ExportOptions.plist" \
  -exportPath "$secret_dir/export" > "$secret_dir/export.log" 2>&1 \
  || fail 'Failed to export Ad Hoc IPA'
echo '[9/9] Verify exported IPA'
shopt -s nullglob
ipas=("$secret_dir/export/"*.ipa)
[[ ${#ipas[@]} -eq 1 && -s "${ipas[0]}" ]] || fail 'Expected one nonempty IPA'
unzip -tqq "${ipas[0]}" > "$secret_dir/zip.log" 2>&1 || fail 'IPA archive integrity check failed'
unzip -q "${ipas[0]}" -d "$secret_dir/ipa" >> "$secret_dir/zip.log" 2>&1 || fail 'Failed to extract IPA'
apps=("$secret_dir/ipa/Payload/"*.app)
[[ ${#apps[@]} -eq 1 && -d "${apps[0]}" ]] || fail 'Expected one app in IPA Payload'
app="${apps[0]}"
[[ -f "$app/embedded.mobileprovision" ]] || fail 'Embedded provisioning profile missing'
codesign --verify --deep --strict "$app" > "$secret_dir/signature.log" 2>&1 || fail 'IPA signature verification failed'
security cms -D -i "$app/embedded.mobileprovision" -o "$secret_dir/embedded-profile.plist" 2> "$secret_dir/embedded-errors.log" \
  || fail 'Failed to decode embedded provisioning profile'
codesign -d --entitlements :- "$app" > "$secret_dir/entitlements.plist" 2>> "$secret_dir/signature.log" \
  || fail 'Failed to read signed entitlements'
export RIG_DEVICE_APP="$app"
export RIG_DEVICE_IPA="${ipas[0]}"
python3 scripts/device_test_support.py verify 2> "$secret_dir/verify-errors.log" \
  || fail 'Exported IPA validation failed'
# Only a fully verified IPA may enter the artifact staging directory.
cp "${ipas[0]}" "$output/artifact/RIG-AdHoc.ipa" 2> "$secret_dir/staging-errors.log" \
  || fail 'Failed to stage verified IPA'
echo 'PASS: Ad Hoc IPA verified; sanitized artifact ready.'
