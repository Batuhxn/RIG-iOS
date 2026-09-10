#!/usr/bin/env python3
"""Host-side checks for the RIG iOS sources.

This is NOT a compiler and does not pretend to be one. It catches the classes of
mistake that are cheap to catch without an Apple toolchain — unbalanced
delimiters, a stray third-party import, an accidental network call, a forgotten
force unwrap, a model checkpoint that wandered into the app — so that the real
Xcode build on macOS starts from a cleaner place.

Run:  python3 scripts/static_audit.py
Exit: 0 when every check passes, 1 otherwise.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources"
TESTS = ROOT / "Tests"

APPLE_MODULES = {
    "Foundation", "SwiftUI", "SwiftData", "UIKit", "Vision", "PhotosUI",
    "CoreImage", "CoreGraphics", "Observation", "XCTest", "Combine",
    "AVFoundation", "ImageIO", "os",
}

# Anything here would contradict the v0.1 privacy and dependency posture.
FORBIDDEN_PATTERNS = {
    "network call": r"\b(URLSession|URLRequest|NSURLConnection|CFNetwork|NWConnection|Network\.)\b",
    "cloud sync": r"\b(CloudKit|CKContainer|NSUbiquitousKeyValueStore|NSPersistentCloudKitContainer)\b",
    "third-party analytics or backend": r"\b(Firebase|Amplitude|Mixpanel|Sentry|Segment|Supabase|Crashlytics|AppsFlyer)\b",
    "tracking": r"\b(ATTrackingManager|ASIdentifierManager|AdSupport)\b",
    "location": r"\b(CLLocationManager|CoreLocation)\b",
    "machine-learning runtime": r"\b(CoreML|MLModel|MLMultiArray)\b",
}

FORCE_PATTERNS = {
    "force try": r"\btry!\s",
    "force cast": r"\bas!\s",
    "fatalError": r"\bfatalError\s*\(",
}

BINARY_SUFFIXES = {".mlmodel", ".mlpackage", ".pth", ".pt", ".ckpt", ".onnx", ".zip", ".bin", ".safetensors"}

failures: list[str] = []
notes: list[str] = []


def swift_files(base: Path) -> list[Path]:
    return sorted(base.rglob("*.swift"))


def strip_swift(source: str) -> str:
    """Blank out comments and string literals so scans do not read prose."""
    out: list[str] = []
    index = 0
    length = len(source)
    while index < length:
        char = source[index]
        pair = source[index:index + 2]
        triple = source[index:index + 3]
        if pair == "//":
            end = source.find("\n", index)
            index = length if end == -1 else end
            continue
        if pair == "/*":
            depth = 1
            index += 2
            while index < length and depth:
                if source[index:index + 2] == "/*":
                    depth += 1
                    index += 2
                elif source[index:index + 2] == "*/":
                    depth -= 1
                    index += 2
                else:
                    index += 1
            continue
        if triple == '"""':
            index += 3
            while index < length and source[index:index + 3] != '"""':
                index += 1
            index += 3
            continue
        if char == '"':
            index += 1
            while index < length and source[index] != '"':
                index += 2 if source[index] == "\\" else 1
            index += 1
            continue
        out.append(char)
        index += 1
    return "".join(out)


def check_delimiters(path: Path, code: str) -> None:
    stack: list[tuple[str, int]] = []
    pairs = {")": "(", "]": "[", "}": "{"}
    line = 1
    for char in code:
        if char == "\n":
            line += 1
        elif char in "([{":
            stack.append((char, line))
        elif char in ")]}":
            if not stack or stack[-1][0] != pairs[char]:
                failures.append(f"{path.relative_to(ROOT)}:{line}: unbalanced '{char}'")
                return
            stack.pop()
    if stack:
        opener, opened_at = stack[-1]
        failures.append(f"{path.relative_to(ROOT)}: unclosed '{opener}' opened on line {opened_at}")


def main() -> int:
    if not SOURCES.is_dir():
        failures.append("Sources/ is missing")
        return report()

    sources = swift_files(SOURCES)
    tests = swift_files(TESTS) if TESTS.is_dir() else []
    notes.append(f"{len(sources)} source files, {len(tests)} test files")

    declared_types: set[str] = set()
    type_counts: dict[str, int] = {}
    test_functions = 0

    for path in sources + tests:
        raw = path.read_text(encoding="utf-8")
        code = strip_swift(raw)
        check_delimiters(path, code)

        imports = set(re.findall(r"^\s*import\s+([A-Za-z_][A-Za-z0-9_.]*)", code, re.MULTILINE))
        if not imports:
            failures.append(f"{path.relative_to(ROOT)}: no import statement")
        for module in imports - APPLE_MODULES:
            failures.append(f"{path.relative_to(ROOT)}: unexpected module import '{module}'")

        declared_types |= set(
            re.findall(
                r"^\s*(?:(?:public|internal|fileprivate|private|final|indirect)\s+|@\w+(?:\([^)]*\))?\s+)*"
                r"(?:struct|class|enum|protocol|actor)\s+([A-Za-z_]\w*)",
                code,
                re.MULTILINE,
            )
        )
        for name in re.findall(
            r"^\s*(?:(?:public|internal|fileprivate|private|final|indirect)\s+|@\w+(?:\([^)]*\))?\s+)*"
            r"(?:struct|class|enum|protocol|actor)\s+([A-Za-z_]\w*)",
            code,
            re.MULTILINE,
        ):
            type_counts[name] = type_counts.get(name, 0) + 1

        test_functions += len(re.findall(r"\bfunc\s+test[A-Z]\w*\s*\(", code))

        is_test = path in tests
        for label, pattern in FORBIDDEN_PATTERNS.items():
            for match in re.finditer(pattern, code):
                line = code[: match.start()].count("\n") + 1
                failures.append(f"{path.relative_to(ROOT)}:{line}: {label} ({match.group(0)})")

        if not is_test:
            for label, pattern in FORCE_PATTERNS.items():
                for match in re.finditer(pattern, code):
                    line = code[: match.start()].count("\n") + 1
                    failures.append(f"{path.relative_to(ROOT)}:{line}: {label} in production code")

        line_count = raw.count("\n") + 1
        if line_count > 420:
            failures.append(f"{path.relative_to(ROOT)}: {line_count} lines — split this file")

    duplicates = sorted(name for name, count in type_counts.items() if count > 1)
    for name in duplicates:
        failures.append(f"type '{name}' is declared {type_counts[name]} times")

    if test_functions < 60:
        failures.append(f"only {test_functions} test functions found")
    notes.append(f"{test_functions} test functions")
    notes.append(f"{len(declared_types)} declared types")

    # The ML seam must exist, and must be inert.
    provider = SOURCES / "OutfitEngine" / "CompatibilityProvider.swift"
    if not provider.is_file():
        failures.append("CompatibilityProvider.swift is missing — the future ML seam must exist")
    else:
        text = provider.read_text(encoding="utf-8")
        if "DisabledCompatibilityProvider" not in text:
            failures.append("No disabled compatibility provider is defined")
    app_services = (SOURCES / "App" / "RIGServices.swift").read_text(encoding="utf-8")
    if "compatibilityProvider: nil" not in app_services:
        failures.append("The live engine must be wired with no compatibility provider in v0.1")

    # Nothing resembling a model or checkpoint may be inside the app.
    for path in ROOT.rglob("*"):
        if path.is_file() and path.suffix.lower() in BINARY_SUFFIXES:
            failures.append(f"{path.relative_to(ROOT)}: model or archive artefact inside the app")

    check_configuration()

    # Privacy manifest must be present and must claim nothing.
    manifest = ROOT / "Support" / "PrivacyInfo.xcprivacy"
    if not manifest.is_file():
        failures.append("Support/PrivacyInfo.xcprivacy is missing")
    else:
        text = manifest.read_text(encoding="utf-8")
        if "NSPrivacyTracking" not in text or "<false/>" not in text:
            failures.append("Privacy manifest must declare NSPrivacyTracking false")

    info = ROOT / "Support" / "Info.plist"
    if not info.is_file():
        failures.append("Support/Info.plist is missing")
    elif "NSCameraUsageDescription" not in info.read_text(encoding="utf-8"):
        failures.append("Info.plist is missing NSCameraUsageDescription")

    return report()


def check_configuration() -> None:
    """Parse the files that gate the build: project spec, plists, workflow, shell."""
    try:
        import plistlib
    except ImportError:  # pragma: no cover - stdlib
        plistlib = None

    project = ROOT / "project.yml"
    if not project.is_file():
        failures.append("project.yml is missing")
    else:
        try:
            import yaml
        except ImportError:
            notes.append("PyYAML not installed; project.yml parsed only for required keys")
            text = project.read_text(encoding="utf-8")
            for key in ("targets:", "RIGTests:", "TEST_HOST:", "schemes:"):
                if key not in text:
                    failures.append(f"project.yml is missing '{key}'")
        else:
            spec = yaml.safe_load(project.read_text(encoding="utf-8"))
            targets = spec.get("targets", {})
            for name in ("RIG", "RIGTests"):
                if name not in targets:
                    failures.append(f"project.yml declares no '{name}' target")
            tests = targets.get("RIGTests", {}).get("settings", {}).get("base", {})
            # Without a host application, `@testable import RIG` cannot link.
            if "TEST_HOST" not in tests or "BUNDLE_LOADER" not in tests:
                failures.append("RIGTests needs TEST_HOST and BUNDLE_LOADER to host an app target")
            if "RIG" not in spec.get("schemes", {}):
                failures.append("project.yml declares no RIG scheme")
            app = targets.get("RIG", {}).get("settings", {}).get("base", {})
            if app.get("GENERATE_INFOPLIST_FILE") not in (False, "NO"):
                failures.append("The app target must use the checked-in Info.plist")
            notes.append("project.yml parsed: targets " + ", ".join(sorted(targets)))

    if plistlib is not None:
        for relative in ("Support/Info.plist", "Support/PrivacyInfo.xcprivacy"):
            path = ROOT / relative
            if not path.is_file():
                continue
            try:
                with path.open("rb") as handle:
                    plistlib.load(handle)
            except Exception as error:  # noqa: BLE001 - report any malformed plist
                failures.append(f"{relative}: not a valid property list ({error})")
        notes.append("Info.plist and privacy manifest parse as property lists")

    workflow = ROOT / ".github" / "workflows" / "ios-validation.yml"
    if workflow.is_file():
        text = workflow.read_text(encoding="utf-8")
        try:
            import yaml
        except ImportError:
            notes.append("PyYAML not installed; workflow checked textually only")
        else:
            try:
                data = yaml.safe_load(text)
            except Exception as error:  # noqa: BLE001
                failures.append(f"workflow YAML does not parse ({error})")
                data = None
            if isinstance(data, dict):
                jobs = data.get("jobs", {})
                if not jobs:
                    failures.append("workflow declares no jobs")
                for job in jobs.values():
                    runner = str(job.get("runs-on", ""))
                    if not runner.startswith("macos"):
                        failures.append(f"workflow job must run on macOS, got '{runner}'")
                notes.append("workflow YAML parsed: " + ", ".join(sorted(jobs)))
        for banned in ("secrets.", "APP_STORE", "altool", "xcrun notarytool", "fastlane"):
            if banned in text:
                failures.append(f"workflow references '{banned}' — this gate must not sign or publish")

    for script in sorted((ROOT / "scripts").glob("*.sh")):
        text = script.read_text(encoding="utf-8")
        if not text.startswith("#!"):
            failures.append(f"{script.relative_to(ROOT)}: no shebang")
        if "set -e" not in text:
            failures.append(f"{script.relative_to(ROOT)}: does not fail closed (no 'set -e')")
        # Cheap unbalanced-quote detection; `bash -n` is the real check and runs
        # in validate_macos.sh's own CI step.
        if text.count("'") % 2 or text.count('"') % 2:
            failures.append(f"{script.relative_to(ROOT)}: unbalanced quotes")


def report() -> int:
    for note in notes:
        print(f"  note: {note}")
    if failures:
        print(f"\nFAIL — {len(failures)} finding(s):")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print("\nPASS — static audit clean. This is not a compile; Xcode on macOS is still required.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
