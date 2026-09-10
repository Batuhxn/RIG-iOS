#!/bin/bash
# RIG iOS — the first Apple gate.
#
# This is the canonical build/test gate for RIG. It fails closed: any required
# step that fails stops the script with a non-zero status, and the last line of
# output is always either "RESULT: PASS" or "RESULT: FAIL".
#
# NEVER EXECUTED. This script was authored on a Windows host with no Apple
# toolchain. A green run here is the first real evidence that RIG compiles;
# nothing before it is.
#
# Requirements: macOS, Xcode 15 or later (iOS 17 SDK), XcodeGen.
#   brew install xcodegen
#   bash scripts/validate_macos.sh
#
# It installs nothing. If a required tool is missing it prints the exact
# command to install it and stops.

set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
PROJECT="RIG.xcodeproj"
SCHEME="RIG"
RESULT_DIR="$PROJECT_ROOT/build"

fail() {
  echo ""
  echo "RESULT: FAIL — $1"
  exit 1
}

step() {
  echo ""
  echo "==> $1"
}

# ---------------------------------------------------------------- 1. host ----
step "1/8 Host"
if [ "$(uname -s)" != "Darwin" ]; then
  fail "this script requires macOS; iOS targets cannot be built anywhere else"
fi
sw_vers || true

# --------------------------------------------------------------- 2. Xcode ----
step "2/8 Xcode"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild was not found." >&2
  echo "Install Xcode from the App Store, then run: sudo xcode-select --switch /Applications/Xcode.app" >&2
  fail "xcodebuild missing"
fi
xcodebuild -version
xcode-select --print-path
swift --version 2>/dev/null || true

# ------------------------------------------------------------ 3. XcodeGen ----
step "3/8 XcodeGen"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen was not found." >&2
  echo "Install it with exactly this command:" >&2
  echo "" >&2
  echo "    brew install xcodegen" >&2
  echo "" >&2
  echo "Nothing has been installed automatically." >&2
  fail "xcodegen missing"
fi
xcodegen --version

# --------------------------------------------------------- 4. static audit ----
step "4/8 Static audit (no toolchain required)"
if command -v python3 >/dev/null 2>&1; then
  python3 scripts/static_audit.py || fail "static audit reported findings"
else
  echo "python3 not found; skipping the static audit (not a required step)."
fi

# ------------------------------------------------------ 5. generate project ----
step "5/8 Generating $PROJECT from project.yml"
xcodegen generate
[ -d "$PROJECT_ROOT/$PROJECT" ] || fail "$PROJECT was not generated"

# ---------------------------------------------------------------- 6. build ----
step "6/8 Building for the iOS Simulator (code signing disabled)"
mkdir -p "$RESULT_DIR"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  || fail "the app did not compile for the simulator"

# ------------------------------------------------------------ 7. simulator ----
step "7/8 Selecting an installed iPhone simulator"
# Tests need a real simulator runtime, unlike the build above. No device model
# is hard-coded: whatever iPhone this machine actually has is used, and the last
# one listed is taken so a newer runtime wins on a machine with several.
SIMULATOR_LINE="$(
  xcrun simctl list devices available \
    | awk '/^-- iOS/ { ios = 1; next } /^-- / { ios = 0 } ios && /iPhone/ { print }' \
    | tail -n 1
)"

if [ -z "${SIMULATOR_LINE}" ]; then
  echo "No available iPhone simulator runtime was found." >&2
  echo "Install one in Xcode > Settings > Platforms, then re-run this script." >&2
  echo "The build in step 6 still passed; only the test run was not attempted." >&2
  fail "no iOS simulator runtime available"
fi

SIMULATOR_ID="$(printf '%s\n' "$SIMULATOR_LINE" | sed -n 's/.*(\([0-9A-Fa-f-]\{36\}\)).*/\1/p' | head -n 1)"
[ -n "${SIMULATOR_ID}" ] || fail "could not parse a simulator identifier from: $SIMULATOR_LINE"
echo "Using:$SIMULATOR_LINE"
echo "Simulator id: $SIMULATOR_ID"

# ---------------------------------------------------------------- 8. tests ----
step "8/8 Running RIGTests"
rm -rf "$RESULT_DIR/RIGTests.xcresult"
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$SIMULATOR_ID" \
  -resultBundlePath "$RESULT_DIR/RIGTests.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  || fail "unit tests did not pass"

echo ""
echo "Gate A complete: project generated, app compiled for the simulator, unit tests passed."
echo "Still unverified by this script, and only reachable on real hardware:"
echo "  - Vision foreground extraction quality on real garment photographs"
echo "  - camera capture and its permission prompt"
echo "  - memory, thermal and scrolling behaviour with a realistic wardrobe"
echo "See docs/APPLE_VALIDATION_CHECKLIST.md for gates B and C."
echo ""
echo "RESULT: PASS"
