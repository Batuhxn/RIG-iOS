# RIG iOS v0.1 — implementation report

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
├── Tests/             (10)    102 test functions
├── docs/               (3)    scope, architecture, decisions
├── reports/            (1)    this file
└── scripts/            (2)    validate_macos.sh, static_audit.py
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

## Recommended Next Step

Open this on a Mac and run one command:

```sh
cd RIG-iOS && sh scripts/validate_macos.sh
```

That generates the project, builds for the simulator, and runs the 102 tests. Fix
the compile errors it finds — that is the expected outcome of the first run, not
a failure of the design. Once it is green, the single most valuable thing after
that is to photograph ten real garments on a device and look at the cutouts,
because Vision extraction quality is the one risk that no amount of further code
review can retire.
