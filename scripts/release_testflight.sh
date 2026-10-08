#!/bin/bash
set -euo pipefail
set +x
umask 077

fail() { echo "ERROR: $1" >&2; exit 1; }
echo '[1/13] Validate environment and secrets'
[[ "${RUNNER_OS:-}" == macOS && "${GITHUB_REF:-}" == refs/heads/main ]] || fail 'macOS main release required'
[[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]] || fail 'Invalid run environment'
[[ -n "${RUNNER_TEMP:-}" && -n "${GITHUB_WORKSPACE:-}" ]] || fail 'Runner paths missing'

secret_dir="$RUNNER_TEMP/rig-release-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
artifact_dir="$GITHUB_WORKSPACE/build/rc1/artifact"
keychain="$secret_dir/release.keychain-db"
export RIG_SECRET_DIR="$secret_dir" RIG_ARTIFACT_DIR="$artifact_dir"

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
  rm -rf "$secret_dir" 2>/dev/null || true
}
if [[ "${1:-}" == --cleanup ]]; then cleanup; exit 0; fi
[[ "${RC_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]] || fail 'Invalid build number'
[[ "${RC_UPLOAD:-}" == true || "${RC_UPLOAD:-}" == false ]] || fail 'Invalid upload selection'
[[ "${GITHUB_SHA:-}" =~ ^[0-9a-fA-F]{40}$ ]] || fail 'Invalid commit identifier'
for name in APPLE_TEAM_ID IOS_DISTRIBUTION_P12_BASE64 IOS_DISTRIBUTION_P12_PASSWORD IOS_APP_STORE_PROFILE_BASE64 ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_BASE64; do
  [[ -n "${!name:-}" ]] || fail "Missing required secret: $name"
done
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ && "$ASC_KEY_ID" =~ ^[A-Z0-9]{10}$ ]] || fail 'Invalid signing identifier format'
[[ "$ASC_ISSUER_ID" =~ ^[a-fA-F0-9-]{36}$ ]] || fail 'Invalid issuer format'
[[ ! -e "$secret_dir" && ! -e "$artifact_dir" ]] || fail 'Private or artifact directory already exists'
mkdir -p "$secret_dir" "$artifact_dir" || fail 'Failed to create private directories'
finish() {
  local status=$?
  trap - EXIT INT TERM ERR
  echo '[13/13] Prepare safe artifacts and clean up'
  if ! python3 scripts/release_support.py sanitize || ! python3 scripts/release_support.py manifest; then
    echo 'ERROR: Artifact preparation failed' >&2
    rm -rf "$artifact_dir"
    status=1
  fi
  cleanup
  exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

security list-keychains -d user > "$secret_dir/keychain-list.txt" 2> "$secret_dir/setup-errors.log" || fail 'Failed to query keychains'
while IFS= read -r entry; do
  entry="${entry#*\"}"; entry="${entry%\"*}"
  printf '%s\n' "$entry" >> "$secret_dir/original-keychains"
done < "$secret_dir/keychain-list.txt"

echo '[2/13] Decode signing material'
python3 scripts/release_support.py decode 2> "$secret_dir/decode-errors.log" || fail 'Failed to decode signing material'
echo '[3/13] Create temporary keychain'
keychain_password=$(openssl rand -hex 32 2> "$secret_dir/keychain.log") || fail 'Failed to generate keychain password'
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$keychain" > "$secret_dir/keychain.log" 2>&1 || fail 'Failed to create keychain'
security set-keychain-settings -lut 21600 "$keychain" >> "$secret_dir/keychain.log" 2>&1 || fail 'Failed to configure keychain'
security unlock-keychain -p "$keychain_password" "$keychain" >> "$secret_dir/keychain.log" 2>&1 || fail 'Failed to unlock keychain'
echo '[4/13] Import Apple Distribution certificate'
security import "$secret_dir/certificate.p12" -k "$keychain" -P "$IOS_DISTRIBUTION_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >> "$secret_dir/keychain.log" 2>&1 || fail 'Failed to import Apple Distribution P12'
original_keychains=()
while IFS= read -r entry; do original_keychains+=("$entry"); done < "$secret_dir/original-keychains"
security list-keychains -d user -s "$keychain" "${original_keychains[@]}" >> "$secret_dir/keychain.log" 2>&1 || fail 'Failed to set keychain search list'
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >> "$secret_dir/keychain.log" 2>&1 || fail 'Failed to set codesign access'

echo '[5/13] Validate App Store provisioning profile'
security find-identity -v -p codesigning "$keychain" > "$secret_dir/identities.txt" 2> "$secret_dir/identity-errors.log" || fail 'Failed to query signing identity'
security cms -D -i "$secret_dir/profile.mobileprovision" > "$secret_dir/profile.plist" 2> "$secret_dir/profile-errors.log" || fail 'Failed to decode provisioning profile'
python3 scripts/release_support.py prepare 2> "$secret_dir/prepare-errors.log" || fail 'Profile and certificate validation failed'
profile_uuid=$(cat "$secret_dir/uuid" 2> "$secret_dir/metadata-errors.log") || fail 'Failed to read profile metadata'
certificate_sha=$(cat "$secret_dir/certificate-sha" 2>> "$secret_dir/metadata-errors.log") || fail 'Failed to read certificate metadata'
for value in "$profile_uuid" "$certificate_sha"; do echo "::add-mask::$value"; done
echo '[6/13] Install provisioning profile'
for directory in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$directory" 2>> "$secret_dir/profile-errors.log" || fail 'Failed to create profile directory'
  target="$directory/$profile_uuid.mobileprovision"
  [[ ! -e "$target" ]] || fail 'Refusing to overwrite an existing profile'
  printf '%s\n' "$target" >> "$secret_dir/installed-profiles"
  cp "$secret_dir/profile.mobileprovision" "$target" 2>> "$secret_dir/profile-errors.log" || fail 'Failed to install profile'
done

# Fetch before XcodeGen enumerates resources. Signed Auto Metadata releases may
# not silently degrade to the model-absent validation build.
bash scripts/fetch_metadata_model.sh --require-model > "$secret_dir/model.log" 2>&1 \
  || fail 'Pinned garment encoder is required for the Auto Metadata release'
python3 scripts/static_audit.py > "$secret_dir/model-audit.log" 2>&1 \
  || fail 'Static audit failed before archive'

echo '[7/13] Generate Xcode project'
xcodegen generate > "$secret_dir/generation.log" 2>&1 || fail 'Failed to generate Xcode project'
echo generation >> "$secret_dir/completed"
echo '[8/13] Archive Release app'
xcodebuild archive -project RIG.xcodeproj -scheme RIG -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$secret_dir/RIG.xcarchive" \
  -derivedDataPath "$secret_dir/DerivedData" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_IDENTITY="$certificate_sha" \
  PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" MARKETING_VERSION=0.2 \
  CURRENT_PROJECT_VERSION="$RC_BUILD_NUMBER" OTHER_CODE_SIGN_FLAGS="--keychain $keychain" \
  > "$secret_dir/archive.log" 2>&1 || fail 'Release archive failed'
echo archive >> "$secret_dir/completed"
echo '[9/13] Export App Store IPA'
xcodebuild -exportArchive -archivePath "$secret_dir/RIG.xcarchive" \
  -exportOptionsPlist "$secret_dir/ExportOptions.plist" -exportPath "$secret_dir/export" \
  > "$secret_dir/export.log" 2>&1 || fail 'App Store IPA export failed'
echo export >> "$secret_dir/completed"
shopt -s nullglob
ipas=("$secret_dir/export/"*.ipa)
[[ ${#ipas[@]} -eq 1 && -s "${ipas[0]}" ]] || fail 'Expected one nonempty IPA'
ipa="${ipas[0]}"
echo '[10/13] Validate IPA, architecture and signature'
unzip -tqq "$ipa" > "$secret_dir/zip.log" 2>&1 || fail 'IPA integrity check failed'
unzip -q "$ipa" -d "$secret_dir/ipa" >> "$secret_dir/zip.log" 2>&1 || fail 'IPA extraction failed'
app="$secret_dir/ipa/Payload/RIG.app"
codesign --verify --deep --strict --verbose=2 "$app" > "$secret_dir/signature.log" 2>&1 || fail 'IPA signature verification failed'
echo signature >> "$secret_dir/completed"
security cms -D -i "$app/embedded.mobileprovision" > "$secret_dir/export-profile.plist" 2> "$secret_dir/cms-errors.log" || fail 'Embedded profile decode failed'
codesign -d --entitlements :- "$app" > "$secret_dir/export-entitlements.plist" 2>> "$secret_dir/signature.log" || fail 'Entitlements extraction failed'
python3 scripts/release_support.py verify > "$secret_dir/ipa-validation.log" 2>&1 || fail 'Exported IPA validation failed'
echo ipa-validation >> "$secret_dir/completed"
echo architectures >> "$secret_dir/completed"

echo '[11/13] Validate with Apple'
export API_PRIVATE_KEYS_DIR="$secret_dir"
xcrun altool --validate-app -f "$ipa" --type ios --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" > "$secret_dir/apple-validation.log" 2>&1 || fail 'Apple validation failed'
echo apple-validation >> "$secret_dir/completed"
echo '[12/13] Upload only when explicitly enabled'
if [[ "$RC_UPLOAD" == true ]]; then
  xcrun altool --upload-app -f "$ipa" --type ios --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" > "$secret_dir/upload.log" 2>&1 || fail 'TestFlight upload failed'
  echo upload >> "$secret_dir/completed"
  echo 'Upload accepted by Apple; processing and tester access remain pending.'
else
  echo 'Upload disabled; no build was sent to TestFlight.'
fi
