#!/bin/bash
# Gate A2: install and launch the real app in an iPhone simulator.
# Gate A already compiles and runs XCTest; this checks the app process itself.

set -euo pipefail

cd "$(dirname "$0")/.."
RESULT_DIR="$PWD/build/simulator-smoke"
DERIVED_DIR="$PWD/build/SimulatorSmokeDerivedData"
BUNDLE_ID="dev.rig.app"
mkdir -p "$RESULT_DIR"

SIMULATOR_ID=""
capture_logs() {
  status=$?
  trap - EXIT
  if [ -n "$SIMULATOR_ID" ]; then
    if ! xcrun simctl spawn "$SIMULATOR_ID" log show \
      --last 5m --style compact \
      --predicate 'process == "RIG" OR eventMessage CONTAINS[c] "dev.rig.app"' \
      > "$RESULT_DIR/runtime.log" 2>&1; then
      echo "Could not collect simulator runtime logs; see runtime.log." >&2
    fi
  fi
  exit "$status"
}
trap capture_logs EXIT

command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is required." >&2; exit 1; }
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen is required." >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "xcrun is required." >&2; exit 1; }

echo "Generating RIG.xcodeproj"
xcodegen generate
test -d RIG.xcodeproj || { echo "RIG.xcodeproj was not generated." >&2; exit 1; }
xcodebuild -project RIG.xcodeproj -list > "$RESULT_DIR/project-list.log" 2>&1 || {
  cat "$RESULT_DIR/project-list.log" >&2
  exit 1
}

# Match the installed-iPhone selection in Gate A without assuming a device model.
SIMULATOR_LINE="$(
  xcrun simctl list devices available \
    | awk '/^-- iOS/ { ios = 1; next } /^-- / { ios = 0 } ios && /iPhone/ { print }' \
    | tail -n 1
)"
test -n "$SIMULATOR_LINE" || { echo "No available iPhone simulator." >&2; exit 1; }
SIMULATOR_ID="$(printf '%s\n' "$SIMULATOR_LINE" | sed -n 's/.*(\([0-9A-Fa-f-]\{36\}\)).*/\1/p' | head -n 1)"
test -n "$SIMULATOR_ID" || { echo "Could not parse simulator ID: $SIMULATOR_LINE" >&2; exit 1; }
echo "Simulator: $SIMULATOR_LINE"
printf '%s\n' "$SIMULATOR_LINE" > "$RESULT_DIR/simulator.txt"

if xcrun simctl list devices booted | grep -Fq "$SIMULATOR_ID"; then
  echo "Simulator is already booted."
else
  xcrun simctl boot "$SIMULATOR_ID" > "$RESULT_DIR/boot.log" 2>&1 || {
    cat "$RESULT_DIR/boot.log" >&2
    exit 1
  }
fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b >> "$RESULT_DIR/boot.log" 2>&1 || {
  cat "$RESULT_DIR/boot.log" >&2
  exit 1
}

echo "Building RIG for simulator $SIMULATOR_ID"
if ! xcodebuild build \
  -project RIG.xcodeproj \
  -scheme RIG \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  > "$RESULT_DIR/build.log" 2>&1; then
  tail -n 100 "$RESULT_DIR/build.log" >&2
  exit 1
fi

APP="$DERIVED_DIR/Build/Products/Debug-iphonesimulator/RIG.app"
test -d "$APP" || { echo "Simulator app missing: $APP" >&2; exit 1; }
xcrun simctl install "$SIMULATOR_ID" "$APP" > "$RESULT_DIR/install.log" 2>&1 || {
  cat "$RESULT_DIR/install.log" >&2
  exit 1
}

LAUNCH_OUTPUT="$(xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" 2>&1)" || {
  printf '%s\n' "$LAUNCH_OUTPUT" | tee "$RESULT_DIR/launch.log" >&2
  exit 1
}
printf '%s\n' "$LAUNCH_OUTPUT" | tee "$RESULT_DIR/launch.log"
if [[ "$LAUNCH_OUTPUT" =~ dev\.rig\.app:[[:space:]]*([0-9]+) ]]; then
  APP_PID="${BASH_REMATCH[1]}"
else
  echo "simctl launch did not report an app PID." >&2
  exit 1
fi

# The simulator app is a host process. A successful launch response alone does
# not establish that it survived startup, so check after a bounded wait.
sleep 10
kill -0 "$APP_PID" 2>/dev/null || { echo "RIG terminated shortly after launch (PID $APP_PID)." >&2; exit 1; }

xcrun simctl io "$SIMULATOR_ID" screenshot "$RESULT_DIR/RIG-home.png"
test -s "$RESULT_DIR/RIG-home.png" || { echo "Simulator screenshot is empty." >&2; exit 1; }
kill -0 "$APP_PID" 2>/dev/null || { echo "RIG terminated before smoke completion." >&2; exit 1; }

echo "PASS: RIG installed, launched, stayed alive for 10 seconds, and produced a screenshot."
echo "Inspect RIG-home.png to confirm the Home screen rather than StartupFailureView."
