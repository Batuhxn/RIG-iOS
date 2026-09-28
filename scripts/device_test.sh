#!/bin/bash
set -euo pipefail
set +x
umask 077

# Mirrors release_testflight.sh project generation and signing, with no Apple
# service credentials or upload command. Raw diagnostics stay in RUNNER_TEMP.
[[ "${RUNNER_OS:-}" == macOS ]]
[[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]]
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
          rm -f "$entry" ;;
      esac
    done < "$secret_dir/installed-profiles"
  fi
  # Archives, DerivedData, decoded profiles, entitlements and raw logs are private.
  rm -rf "$secret_dir"
}
if [[ "${1:-}" == --cleanup ]]; then cleanup; exit 0; fi

for name in APPLE_TEAM_ID IOS_DISTRIBUTION_P12_BASE64 IOS_DISTRIBUTION_P12_PASSWORD IOS_ADHOC_PROFILE_BASE64; do
  if [[ -z "${!name:-}" ]]; then echo "Missing required secret: $name" >&2; exit 1; fi
done
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]
[[ ! -e "$secret_dir" && ! -e "$output" ]]
mkdir -p "$secret_dir" "$output/artifact"
finish() {
  local status=$?
  trap - EXIT INT TERM
  # Sanitization fails closed: never publish raw logs when filtering fails.
  if ! python3 scripts/device_test_support.py sanitize; then
    rm -f "$output/artifact/"*.log
    status=1
  fi
  cleanup
  exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while IFS= read -r entry; do
  entry="${entry#*\"}"
  entry="${entry%\"*}"
  printf '%s\n' "$entry" >> "$secret_dir/original-keychains"
done < <(security list-keychains -d user)
python3 scripts/device_test_support.py decode
keychain_password=$(openssl rand -hex 32)
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$keychain" > "$secret_dir/keychain.log" 2>&1
security set-keychain-settings -lut 21600 "$keychain" >> "$secret_dir/keychain.log" 2>&1
security unlock-keychain -p "$keychain_password" "$keychain" >> "$secret_dir/keychain.log" 2>&1
security import "$secret_dir/certificate.p12" -k "$keychain" -P "$IOS_DISTRIBUTION_P12_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security >> "$secret_dir/keychain.log" 2>&1
original_keychains=()
while IFS= read -r entry; do original_keychains+=("$entry"); done < "$secret_dir/original-keychains"
security list-keychains -d user -s "$keychain" "${original_keychains[@]}" >> "$secret_dir/keychain.log" 2>&1
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" \
  "$keychain" >> "$secret_dir/keychain.log" 2>&1
security find-identity -v -p codesigning "$keychain" > "$secret_dir/identities.txt" 2> "$secret_dir/identity-errors.log"
security cms -D -i "$secret_dir/profile.mobileprovision" -o "$secret_dir/profile.plist" 2> "$secret_dir/profile-errors.log"
python3 scripts/device_test_support.py prepare
profile_uuid=$(cat "$secret_dir/uuid")
certificate_sha=$(cat "$secret_dir/certificate-sha")
# Xcode 26 also searches UserData; install the same profile in both locations.
for directory in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$directory"
  target="$directory/$profile_uuid.mobileprovision"
  [[ ! -e "$target" ]] || { echo "Refusing to overwrite an existing profile" >&2; exit 1; }
  printf '%s\n' "$target" >> "$secret_dir/installed-profiles"
  cp "$secret_dir/profile.mobileprovision" "$target"
done

echo 'Generating RIG.xcodeproj and archiving Release for iphoneos/arm64.'
xcodegen generate > "$secret_dir/generation.log" 2>&1
xcodebuild -project RIG.xcodeproj -list >> "$secret_dir/generation.log" 2>&1
xcodebuild archive -project RIG.xcodeproj -scheme RIG -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -arch arm64 \
  -archivePath "$secret_dir/RIG.xcarchive" -derivedDataPath "$secret_dir/DerivedData" \
  CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_IDENTITY="$certificate_sha" \
  PRODUCT_BUNDLE_IDENTIFIER=dev.rig.app PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" \
  OTHER_CODE_SIGN_FLAGS="--keychain $keychain" > "$secret_dir/archive.log" 2>&1
echo 'Exporting the archive for registered devices.'
xcodebuild -exportArchive -archivePath "$secret_dir/RIG.xcarchive" \
  -exportOptionsPlist "$output/artifact/ExportOptions.plist" \
  -exportPath "$secret_dir/export" > "$secret_dir/export.log" 2>&1
shopt -s nullglob
ipas=("$secret_dir/export/"*.ipa)
[[ ${#ipas[@]} -eq 1 && -s "${ipas[0]}" ]] || { echo 'Expected one nonempty IPA' >&2; exit 1; }
unzip -tqq "${ipas[0]}" > "$secret_dir/zip.log" 2>&1
unzip -q "${ipas[0]}" -d "$secret_dir/ipa" >> "$secret_dir/zip.log" 2>&1
apps=("$secret_dir/ipa/Payload/"*.app)
[[ ${#apps[@]} -eq 1 && -d "${apps[0]}" ]]
app="${apps[0]}"
[[ -f "$app/embedded.mobileprovision" ]]
codesign --verify --deep --strict "$app" > "$secret_dir/signature.log" 2>&1
security cms -D -i "$app/embedded.mobileprovision" -o "$secret_dir/embedded-profile.plist" 2> "$secret_dir/embedded-errors.log"
codesign -d --entitlements :- "$app" > "$secret_dir/entitlements.plist" 2>> "$secret_dir/signature.log"
export RIG_DEVICE_APP="$app"
export RIG_DEVICE_IPA="${ipas[0]}"
python3 scripts/device_test_support.py verify
# Only a fully verified IPA may enter the artifact staging directory.
cp "${ipas[0]}" "$output/artifact/RIG-AdHoc.ipa"
echo 'PASS: Ad Hoc IPA verified; sanitized artifact ready.'
