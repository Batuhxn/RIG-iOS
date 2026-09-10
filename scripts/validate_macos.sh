#!/bin/sh
# RIG iOS — the Apple-side validation this project cannot run anywhere else.
#
# UNVERIFIED: this script has never been executed. It was written on a Windows
# host with no Apple toolchain. Treat a green run here as the first real
# evidence that RIG builds; nothing before it is.
#
# Requirements: macOS, Xcode 15 or later (iOS 17 SDK), XcodeGen.
#   brew install xcodegen
#   sh scripts/validate_macos.sh
#
# Fails closed: any step that fails stops the script with a non-zero status.
set -eu

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"

echo "==> Host check"
if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script requires macOS. iOS targets cannot be built anywhere else." >&2
  exit 1
fi
command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild not found. Install Xcode and run xcode-select --install." >&2; exit 1; }
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not found. Run: brew install xcodegen" >&2; exit 1; }
xcodebuild -version

echo "==> Static audit (no toolchain required)"
if command -v python3 >/dev/null 2>&1; then
  python3 scripts/static_audit.py
else
  echo "python3 not found; skipping the static audit." >&2
fi

echo "==> Generating the Xcode project from project.yml"
xcodegen generate
test -d "$PROJECT_DIR/RIG.xcodeproj" || { echo "RIG.xcodeproj was not generated." >&2; exit 1; }

echo "==> Building for the iOS Simulator (code signing disabled)"
xcodebuild build \
  -project RIG.xcodeproj \
  -scheme RIG \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

echo "==> Selecting an installed iOS simulator for the test run"
# Tests need a real simulator runtime, unlike the build above. Pick whatever
# this machine actually has rather than hard-coding a device that may not exist.
SIMULATOR_ID="$(
  xcrun simctl list devices available -j 2>/dev/null \
  | /usr/bin/python3 -c '
import json,sys
data = json.load(sys.stdin).get("devices", {})
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if not device.get("isAvailable"):
            continue
        if "iPhone" in device.get("name", ""):
            best = device["udid"]
if best:
    print(best)
'
)"

if [ -z "${SIMULATOR_ID:-}" ]; then
  echo "No available iPhone simulator runtime was found." >&2
  echo "Install one in Xcode > Settings > Platforms, then re-run this script." >&2
  echo "The build above still passed; only the test run was skipped." >&2
  exit 1
fi
echo "Using simulator $SIMULATOR_ID"

echo "==> Running unit tests"
xcodebuild test \
  -project RIG.xcodeproj \
  -scheme RIG \
  -configuration Debug \
  -destination "id=$SIMULATOR_ID" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

echo
echo "==> PASS: project generated, app built for the simulator, unit tests ran."
echo "    Still unverified by this script: behaviour on real hardware, Vision"
echo "    foreground extraction quality, and memory or thermal behaviour."
