# RIG iOS v0.1 — implementation report

> Historical checkpoint. Current validation supersedes the counts and "never
> compiled" statements below: Gate A run `34627340043` passed a simulator
> build and 154 XCTest tests with zero failures; Gate B1 run `34627735523`
> passed an unsigned arm64 `iphoneos` build and IPA verification. Standalone
> simulator launch (Gate A2) remains unverified.

Date: 2026-09-10

## Executive Status

# IMPLEMENTED — APPLE RUNTIME VALIDATION PENDING

The whole of the v0.1 scope is written: 48 Swift source files, 4,224 lines, plus
10 test files and 102 test functions. **None of it has been compiled or run.**
The development host is Windows with no Apple toolchain, and no attempt was made
to fake one. Everything below separates what was actually checked from what was
only written.

## Scope Completed

All twenty-one items in the definition of done exist in the workspace:

| | Item | Where |
|---|---|---|
| 1 | Native SwiftUI shell, three tabs | `Sources/App/` |
| 2 | SwiftData wardrobe persistence | `Sources/Models/`, `Sources/Persistence/` |
| 3 | File-backed garment images | `Services/ImageStorage/` |
| 4 | Photo import | `Features/GarmentEditor/AddGarmentFlow.swift` |
| 5 | Camera path | `Services/Camera/CameraPicker.swift` |
| 6 | Vision foreground removal | `Services/BackgroundRemoval/VisionBackgroundRemover.swift` |
| 7 | Graceful fallback on failure | `Services/ImageStorage/GarmentImportService.swift` |
| 8 | Garment metadata editing | `Features/GarmentEditor/` |
| 9 | Wardrobe browsing and filtering | `Features/Wardrobe/` |
| 10 | Manual outfit creation | `Features/OutfitBuilder/` |
| 11 | Bounded candidate generation | `OutfitEngine/CandidateGenerator.swift` |
| 12 | Rule-based ranking | `OutfitEngine/OutfitEngine.swift` |
| 13 | Saved looks | `Features/Looks/` |
| 14 | Like/dislike capture | `Models/OutfitFeedback.swift`, `Features/Suggestions/` |
| 15 | ML seam, disabled | `OutfitEngine/CompatibilityProvider.swift` |
| 16 | Unit tests | `Tests/` |
| 17 | Project specification | `project.yml` |
| 18 | macOS validation script | `scripts/validate_macos.sh` |
| 19 | README | `README.md` |
| 20 | Architecture and scope docs | `docs/` |
| 21 | This report | `reports/` |

## Files / Modules Added

Everything is new; `RIG-iOS/` did not previously exist. `FashionMLSpike/` was not
touched.

```
RIG-iOS/
├── project.yml                XcodeGen specification, RIG + RIGTests, iOS 17
├── Support/                   Info.plist, PrivacyInfo.xcprivacy
├── Sources/
│   ├── App/            (3)    entry point, tab shell, injected services
│   ├── Models/         (7)    category, colour, season, snapshot + 3 SwiftData entities
│   ├── Persistence/    (2)    model container, preview fixtures
│   ├── OutfitEngine/  (13)    validity, signature, rules, generation, ranking, ML seam
│   ├── Services/       (7)    image paths/store/processing/import, background removal, camera
│   ├── DesignSystem/   (3)    theme, components, garment image view
│   ├── Features/      (13)    Home, Wardrobe, GarmentEditor, Suggestions, OutfitBuilder, Looks
│   └── Resources/             asset catalogue with an accent colour
├── Tests/             (10)    106 test functions
├── docs/               (4)    scope, architecture, decisions, Apple validation checklist
├── reports/            (1)    this file
├── scripts/            (2)    validate_macos.sh, static_audit.py
└── .github/workflows/     ios-validation.yml (prepared, never run, manual trigger only)
```

Largest file: 254 lines. No file exceeds 420 lines; the static audit fails if one does.

## Outfit Engine

Pure Foundation. Every rule takes `GarmentSnapshot` values, so nothing in the
engine imports SwiftData or SwiftUI and all of it is testable without an app.

```
wardrobe → CandidateGenerator → OutfitValidator (hard gate)
        → rule scoring → optional capped signal → sort → diversify → suggestions
```

**Validity is RIG's alone.** One top and one bottom, or one dress; a dress plus
a top or bottom conflicts; accessories alone are not an outfit; duplicates are
rejected; one of each category except accessories, which cap at three. No score
from any source, now or later, can overrule this.

**Generation is bounded and deterministic.** At most 300 evaluated candidates
and 60 structural bases, no randomness anywhere, deduplicated by signature, and
profile-major so every base appears plainly before any base is decorated twice.
"Show another set" walks further down the same ranking rather than reshuffling.

**Scoring** is colour 0.45, season 0.30, structural completeness 0.20, explicit
favourites 0.05, weights summing to 1 and every component in 0...1.

- *Colour* is the mean of pairwise scores over a documented rule set: neutrals
  combine broadly, monochrome combines, a neutral anchors an accent, and two
  accents are judged by coarse hue distance with an extra penalty for two vivid
  non-analogous colours. Anything paired with `multicolor` scores flat mid-range
  — refusing to be confident about a garment with no single hue. A palette with
  more than three distinct accent families is damped further.
- *Season* is 1.0 when every garment shares a season and 0.25 when none overlap,
  with partial pairwise overlap in between. This is not weather.
- *Completeness* is base 0.60, shoes +0.20, outerwear +0.10, bag or accessory +0.10.
- *Favourites* is stated preference, not a learned style model.

The total is shown as a band — "Strong match", "Good match", "Try this",
"Something different" — and never as a number. A test asserts no generated
summary contains a digit.

**The ML seam** is `CompatibilityProvider`, wired with `nil` in v0.1. Its
constraints are enforced in code, not by convention: optional return, shortlist
only (top 12), influence hard-clamped to 15% of the final score, a throwing
provider leaves rule scores standing, and it has no input to validity at all.

## Persistence

SwiftData with three entities. Enumerations persist as raw strings and seasons
as an `Int` bitmask, so adding a case later cannot invalidate a store. Unknown
raw values degrade deliberately: an unknown category reads as `accessory`, which
has no structural authority, and an unknown colour reads as `multicolor`, which
the rules score non-committally.

`SavedOutfit` does not persist garment order — order means nothing here and
storing it would invite someone to read position as compatibility. It records
the signature at save time, which is how a look can tell that a garment was
deleted from the wardrobe underneath it.

Feedback is an upsert against an order-independent signature. Nothing reads it.
That is the point: capture now, learn later, and do not claim otherwise.

## Image Pipeline

One directory per garment UUID under Application Support, holding
`original.jpg` (≤1600 px), `cutout.png` (≤1200 px, absent on failure) and
`thumbnail.png` (≤400 px). Path arithmetic is a pure function of the UUID, so
collisions are impossible and deleting a garment is one directory removal.
Writes are atomic.

Deletion removes the row first and the files second; the reverse order could
leave a live row pointing at nothing. An orphan sweep on launch collects
anything a failed removal left behind, and only touches directories whose names
parse as UUIDs absent from the store.

## Background Removal

`VNGenerateForegroundInstanceMaskRequest` with
`generateMaskedImage(ofInstances:from:croppedToInstancesExtent:)`, both iOS 17.
The signatures were taken from Apple's Vision documentation, which was the one
thing consulted online.

The protocol deals in `Data`, not `UIImage`: image bytes are `Sendable`,
`UIImage` is not, and keeping Vision behind a `Data` interface is what lets the
whole pipeline be exercised without an Apple runtime. Three implementations
exist — Vision, passthrough, and always-failing — and the failure path is tested.

**Failure never blocks import.** A garment with only its original photograph is a
perfectly good garment, and both the detail screen and the review step say which
one is being shown.

## UI

Three tabs. Home is a wordmark, one primary action, an honest wardrobe summary
and recent looks — no weather card, no score, no personalisation claim, because
v0.1 has none of those. Wardrobe is a photography-led grid with category, season
and favourite filters. Looks holds saved outfits.

System colours throughout, so light and dark mode both work without a second
palette; a serif wordmark is the only styling flourish. Every list has an empty
state, every failure has a recoverable banner, controls carry VoiceOver labels
and 44-point minimum targets, and text uses Dynamic Type styles.

## Tests

102 test functions across 10 files, all against deterministic logic:

| File | Covers |
|---|---|
| `OutfitValidatorTests` | valid bases, dress conflicts, duplicates, accessories-only, category caps, deterministic issue order |
| `OutfitSignatureTests` | order independence, set sensitivity, base signatures |
| `ColorHarmonyTests` | full range and symmetry over every pair, neutrals, monochrome, analogous vs clashing, vivid penalty, busy palettes, multicolor never confident |
| `SeasonCoherenceTests` | shared, disjoint, partial, empty-set normalisation, range |
| `CandidateGeneratorTests` | no invalid output, no duplicates, cap respected at two cap values, determinism, order independence, base-only wardrobes |
| `OutfitRankingTests` | strong fixture outranks weak, band thresholds, weights sum to 1, diversification, exclusion, and five tests on the ML seam including the 15% cap, clamping, nil, and a throwing provider |
| `GarmentImageStorageTests` | path stability, collision impossibility, round trips, deletion, orphan sweeps that ignore what they do not understand |
| `GarmentImportServiceTests` | failed removal still imports, cutout written on success, unreadable data rejected, downscaling, no upscaling |
| `PersistenceTests` | SwiftData round trips, unknown raw values, snapshots, look signatures, deletion marking looks incomplete, feedback queries |

## Verification Actually Executed

| Check | Result |
|---|---|
| Host inspection for an Apple toolchain | None present. Windows host; terminal apps reachable only in click-only mode, so no shell could be driven there either |
| `scripts/static_audit.py` | **PASS** — 48 source files, 10 test files, 102 test functions, 99 declared types |
| Delimiter balance across all 58 Swift files, comments and strings excluded | PASS |
| Import audit — every imported module is an Apple framework | PASS, no third-party dependency anywhere |
| Forbidden-symbol scan: `URLSession`, `URLRequest`, `NWConnection`, CloudKit, Firebase, Supabase, Sentry, Mixpanel, Amplitude, Segment, Crashlytics, `ATTrackingManager`, `AdSupport`, CoreLocation, CoreML, `MLModel` | PASS — none present in sources or tests |
| Force `try!` / `as!` / `fatalError` in production code | PASS — none |
| Model or archive artefacts (`.mlmodel`, `.pth`, `.onnx`, `.zip`, …) inside the app | PASS — none |
| ML seam present and inert (`DisabledCompatibilityProvider`, live engine wired `compatibilityProvider: nil`) | PASS |
| Privacy manifest declares no tracking; `Info.plist` carries `NSCameraUsageDescription` | PASS |
| File size ceiling (420 lines) | PASS — largest is 254 |
| `project.yml` parses as YAML, declares targets RIG + RIGTests and one scheme | PASS |
| `VNInstanceMaskObservation.generateMaskedImage(ofInstances:from:croppedToInstancesExtent:)` signature and iOS 17 availability | Confirmed against Apple's documentation |
| Manual review pass for concurrency isolation, optional flattening, trapping dictionary construction, and delete-order bugs | Ten defects found and fixed before this report |

## Verification NOT Executed

Nothing here was compiled, launched or measured. Specifically **not** done:

- **Swift compilation.** No `swiftc`, no `xcodebuild`, no type checking. Type
  errors, macro expansion failures and SwiftUI builder errors are all still
  possible. The static audit is not a compiler and does not claim to be.
- **Unit tests.** All 102 are written; zero have run. Their assertions were
  derived by hand from the rule constants.
- **Simulator or device launch.** No screen has ever been rendered.
- **Vision foreground extraction.** `VisionBackgroundRemover` has never
  executed. Cutout quality on real garment photographs is entirely unknown.
- **SwiftData behaviour at runtime**, including the delete-nullify behaviour that
  `PersistenceTests` asserts and the `@Relationship` inverse declaration.
- **The camera bridge**, on hardware or otherwise.
- **Memory, launch time, scroll performance**, image cache behaviour.
- **Accessibility audit** with VoiceOver or Dynamic Type at accessibility sizes.
- **The macOS validation script itself**, which has also never run.

No Apple hardware or CI was obtained, and no money was spent.

## Known Risks

1. **First compile will not be clean.** Four thousand lines of unverified Swift,
   including SwiftData macros and SwiftUI result builders, will produce errors.
   Expect an hour of fixes, not a green first run.
2. **Vision cutout quality is the product risk.** If foreground extraction is
   poor on ordinary garment photographs, the wardrobe looks bad regardless of
   how correct everything behind it is. The fallback keeps the app working but
   does not make it look good.
3. **SwiftData relationship semantics.** The many-to-many between `ClothingItem`
   and `SavedOutfit` with a declared inverse is the least certain persistence
   choice here. `testDeletingAGarmentMarksItsLooksIncomplete` is where it will
   show up.
4. **Colour rules are asserted, not validated.** They are internally consistent
   and tested against themselves. Nobody has checked that their output matches
   what a person would call a good outfit. That is a judgement question and
   needs real garments and a real opinion.
5. **Strict concurrency is set to `targeted`.** Moving to `complete` will surface
   work, most likely in the UIKit camera bridge.
6. **No app icon.** The asset catalogue carries an accent colour only.
7. **Small-wardrobe experience.** With a handful of garments the same looks recur
   quickly. The interface says so plainly rather than pretending to be
   inexhaustible, but it is still a thin first-run experience.

## Deferred Work

Everything in `docs/V0_1_SCOPE.md` under OUT, unchanged: accounts, backend, sync,
weather, occasion, preference learning, any ML model, virtual try-on, sharing,
analytics, monetisation, localisation, App Store work.

Deferred within v0.1's own areas:

- App icon and store assets.
- iPad-specific layouts; the app builds universal but is designed for iPhone.
- Reprocessing an existing garment's cutout after a better remover ships. The
  1600 px original is retained precisely so this is possible later.
- Feedback is captured and never read. That is deliberate for v0.1.
- Wardrobe filtering happens in memory rather than in the query predicate, which
  is right at personal-wardrobe scale and will need revisiting at thousands.

# Pre-Apple Validation Hardening

A bounded pass performed after the implementation above, with one goal: give the
first real Apple build the best chance of being informative rather than
mechanical. No product features were added and no scope moved.

## Compile-risk fixes made

Six defects, each with specific evidence rather than a hunch:

1. **Unit tests had no host application.** `RIGTests` is a `bundle.unit-test`
   target that does `@testable import RIG`, which cannot link against an
   *application* target without a host. Added `TEST_HOST` and `BUNDLE_LOADER` to
   the target in `project.yml`. This alone would very likely have failed the
   first `xcodebuild test`.
2. **Doubly-optional image paths silently discarded the fallback.** Four call
   sites wrote `garment?.thumbnailRelativePath ?? garment?.preferredImageRelativePath`.
   Optional chaining through an optional garment produces `String??`, and `??`
   unwraps the *outer* layer — so a garment with no thumbnail rendered a
   placeholder instead of falling back to its cutout or original photograph.
   Replaced with one `ClothingItem.displayImageRelativePath` property, and
   `flatMap` at the two genuinely optional sites. A test now pins the
   thumbnail → cutout → original order.
3. **`PhotosPicker` asked for a permission RIG does not need.** It was
   constructed with `photoLibrary: .shared()`, which gives the picker in-process
   library access and therefore requires photo library authorisation and an
   `NSPhotoLibraryUsageDescription` — a key the app deliberately does not
   declare. RIG only ever reads the chosen image's bytes via
   `loadTransferable(type: Data.self)` and never touches a `PHAsset`, so the
   argument was removed. The permission surface is now camera-only, matching
   what the README claims.
4. **Actor isolation across the UIKit camera bridge was implicit.** The
   `CameraPicker` callbacks arrive from a `UIImagePickerController` delegate and
   mutated `@State` and called a `@MainActor` method. The hop is now explicit
   (`Task { @MainActor in … }`) at all three call sites rather than inherited
   from an ambiguous context.
5. **`SuggestionsModel` is `@MainActor` but is created as a `@State` default
   value** inside a view struct that is not itself isolated. Added a
   `nonisolated init()`; every stored property starts from a `Sendable`
   constant, so there is nothing isolated to touch.
6. **`UILaunchScreen` carried an empty `UIColorName`.** An empty string is not a
   valid colour reference; replaced with an empty dictionary so the system
   default applies.

Verified against Apple's documentation during the pass rather than assumed:
`VNGenerateForegroundInstanceMaskRequest.results` is `[VNInstanceMaskObservation]?`,
`generateMaskedImage(ofInstances:from:croppedToInstancesExtent:)` takes an
`IndexSet` and throws returning `CVPixelBuffer`, and the `@Relationship` macro's
`deleteRule` defaults to `.nullify`. All are iOS 17.0, at RIG's deployment floor,
so no `@available` annotations are needed anywhere — and a scan confirms none are
present or missing.

## SwiftData review result

The many-to-many between `ClothingItem` and `SavedOutfit` was the largest
residual risk in the previous report. The review found the shape correct but
under-specified, and made the smallest defensible correction rather than
redesigning persistence:

- Both sides are now annotated, matching the pattern in Apple's own
  `@Relationship` documentation, which annotates the inverse-bearing side and
  the collection side.
- `deleteRule: .nullify` is now stated explicitly on both sides. It was already
  the default, but writing it down means no later edit can quietly introduce a
  cascade — and a cascade here would be severe in either direction: deleting one
  garment would destroy every look it appeared in, or deleting a look would
  destroy the garments.
- `inverse:` remains declared once, on `SavedOutfit.items`. There is exactly one
  relationship between these two types, so inference on the other side is
  unambiguous.

Four tests were added: deleting a look must not delete its garments; a garment
may belong to several looks and the inverse must populate from the other side;
deleting one look leaves the other intact; and the image-path fallback order.

**Remaining runtime-only uncertainty.** Whether SwiftData actually honours
nullify in both directions, whether the inverse populates without an explicit
fetch, and whether `@Attribute(.unique)` behaves alongside a many-to-many
relationship are all questions only a simulator run answers. `PersistenceTests`
is where they will surface.

## Validation script changes

`scripts/validate_macos.sh` was rewritten as the canonical first gate:

- `bash` with `set -euo pipefail`; every required step ends the run non-zero on
  failure, and the final line is always `RESULT: PASS` or `RESULT: FAIL`.
- Eight numbered steps: host, Xcode, XcodeGen, static audit, generate, build,
  simulator selection, test.
- Prints `sw_vers`, `xcodebuild -version`, `xcode-select -p`, `swift --version`
  and `xcodegen --version`, so a failing log identifies the toolchain that
  produced it.
- Installs nothing. A missing XcodeGen prints exactly `brew install xcodegen`
  and stops.
- Simulator selection no longer depends on `python3` and hard-codes no device
  model: it parses `xcrun simctl list devices available`, restricts to the iOS
  section so a watchOS device can never be picked, and takes the last iPhone
  listed. The parser was exercised against sample `simctl` output.
- Writes `build/RIGTests.xcresult`, which is gitignored and is what the optional
  CI job uploads.

## Optional GitHub Actions preparation

`.github/workflows/ios-validation.yml` is **prepared and not enabled**. It has
never run and this repository has no remote.

- `runs-on: macos-14`, `workflow_dispatch` only. The `push:` and `pull_request:`
  triggers are present but commented out, deliberately: GitHub-hosted macOS
  runners are metered at a higher multiplier than Linux and are not free beyond
  an account's included allowance. This is not a zero-cost gate, and the README
  says so.
- It checks out, prints the toolchain, installs and verifies XcodeGen, runs the
  static audit, then calls `scripts/validate_macos.sh` — the same script a
  developer runs locally, so there is one gate rather than two that drift apart.
- It uploads the `.xcresult` bundle as an artifact.
- No secrets, no signing, no notarisation, no upload of the app, no release, no
  App Store step. The static audit fails if any of those appear in the workflow.

The README explains how to enable it after pushing to a **private** repository.

## Static checks actually executed

All on the Windows host. None of this is a compile.

| Check | Result |
|---|---|
| `scripts/static_audit.py` (extended this pass) | **PASS** — 48 source files, 10 test files, 106 test functions, 102 declared types |
| Duplicate type declarations across all 58 Swift files | PASS — none |
| Project-symbol cross-reference (every `RIG*`/`Garment*`/`Outfit*`-family type used is declared) | PASS |
| Extensions on types that do not exist | PASS — none |
| `@available` audit against the iOS 17 floor | PASS — no iOS-18+ API used, none needed |
| `project.yml` parses; declares both targets, the scheme, `TEST_HOST`/`BUNDLE_LOADER`, and a checked-in Info.plist | PASS |
| `Info.plist` and `PrivacyInfo.xcprivacy` parse as property lists | PASS |
| `.github/workflows/ios-validation.yml` parses; job runs on macOS; contains no secret, signing or publishing step | PASS |
| `bash -n scripts/validate_macos.sh` | PASS |
| Shell scripts have a shebang, fail closed, and balanced quotes | PASS |
| Simulator-selection parser against sample `simctl` output | PASS — picks an iPhone, ignores the watchOS section |
| Forbidden networking, cloud, analytics, tracking, location and CoreML symbols | PASS — none |
| Force `try!` / `as!` / `fatalError` in production code | PASS — none |
| Model or archive artefacts inside the app | PASS — none |
| Git checkpoint created and repository readable | PASS — first commit `987d9ed`, 71 files tracked |

**STATIC PASS is not APPLE BUILD PASS.** Nothing here type-checks Swift, expands
a macro, or runs a test. The audit is a lint, and it says so on every run.

## Remaining Apple-only uncertainty

Unchanged in kind from the previous report, and now the entire remaining risk:

1. **First compile will still not be clean.** Six defects were removed; four
   thousand lines of never-compiled Swift remain.
2. **SwiftData at runtime** — relationship nullify in both directions, inverse
   population, and `@Attribute(.unique)` alongside the relationship.
3. **Vision cutout quality on real garment photographs.** Still the product
   risk, and still untouchable without a device.
4. **The camera bridge**, its permission prompt, and capture on hardware.
5. **Memory and scrolling** with a realistic wardrobe.
6. **The validation script and the CI workflow themselves**, neither of which
   has ever executed.

`docs/APPLE_VALIDATION_CHECKLIST.md` turns all of the above into three ordered
gates with concrete boxes to tick.

## Recommended Next Step

Open this on a Mac and run one command:

```sh
cd RIG-iOS && bash scripts/validate_macos.sh
```

That is Gate A: it generates the project, builds for the simulator, and runs the
106 tests. Fix the compile errors it finds — that is the expected outcome of a
first run, not a failure of the design. Then work down
`docs/APPLE_VALIDATION_CHECKLIST.md`.

The single most valuable thing after Gate A is Gate C's first item: photograph
ten real garments on a device and look at the cutouts. Vision extraction quality
is the one risk that no further code review can retire.
