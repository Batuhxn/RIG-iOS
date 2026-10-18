#!/usr/bin/env bash
# Runs the framework-free logic tests with a Linux Swift toolchain.
#
# This is NOT the iOS build. It compiles only the source files whose sole
# import is Foundation, from Models, OutfitEngine, Services/Weather and
# Features/Suggestions, into a throwaway SwiftPM package named RIG, so `@testable import RIG`
# in the selected test files resolves unchanged. SwiftUI, SwiftData, Vision and
# the app target are never compiled here; Xcode on macOS is still required.
#
# Run:  bash scripts/linux_logic_tests.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/Sources/RIG" "$work/Tests/RIGTests"

# Linux Foundation keeps URLSession in a separate module.
shim='#if canImport(FoundationNetworking)
import FoundationNetworking
#endif'

copied=0
while IFS= read -r -d '' file; do
    imports="$(grep -E '^[[:space:]]*import[[:space:]]+' "$file" | awk '{print $2}' | sort -u)"
    if [ "$imports" = "Foundation" ]; then
        name="$(echo "${file#"$root/Sources/"}" | tr '/' '_')"
        { echo "$shim"; cat "$file"; } > "$work/Sources/RIG/$name"
        copied=$((copied + 1))
    fi
done < <(find "$root/Sources/Models" "$root/Sources/OutfitEngine" "$root/Sources/Services/Weather" \
    "$root/Sources/Features/Suggestions" -name '*.swift' -print0 2>/dev/null)

tests=(
    TestFixtures.swift
    CandidateGeneratorTests.swift
    ColorHarmonyTests.swift
    OutfitRankingTests.swift
    OutfitSignatureTests.swift
    OutfitValidatorTests.swift
    SeasonCoherenceTests.swift
    WeatherComfortTests.swift
    WeatherForecastParsingTests.swift
    WeatherCacheTests.swift
    WeatherSuggestionTests.swift
)
for test in "${tests[@]}"; do
    if [ -f "$root/Tests/$test" ]; then
        { echo "$shim"; cat "$root/Tests/$test"; } > "$work/Tests/RIGTests/$test"
    fi
done

cat > "$work/Package.swift" <<'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RIG",
    targets: [
        .target(name: "RIG", path: "Sources/RIG"),
        .testTarget(name: "RIGTests", dependencies: ["RIG"], path: "Tests/RIGTests"),
    ]
)
EOF

echo "Compiling $copied Foundation-only source files and ${#tests[@]} candidate test files"
cd "$work"
swift test 2>&1
