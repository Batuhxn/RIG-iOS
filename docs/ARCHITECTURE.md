# Architecture

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│  Features/            SwiftUI screens and their local state   │
│  Home · Wardrobe · GarmentEditor · Suggestions ·              │
│  OutfitBuilder · Looks                                        │
└───────────────┬──────────────────────────┬───────────────────┘
                │                          │
      ┌─────────▼─────────┐      ┌─────────▼──────────┐
      │  OutfitEngine/    │      │  Services/         │
      │  pure rules,      │      │  ImageStorage      │
      │  Foundation only  │      │  BackgroundRemoval │
      │                   │      │  Camera            │
      └─────────┬─────────┘      └─────────┬──────────┘
                │                          │
      ┌─────────▼──────────────────────────▼──────────┐
      │  Models/ + Persistence/                        │
      │  SwiftData entities, container, fixtures       │
      └────────────────────────────────────────────────┘
```

`DesignSystem/` sits beside the features and holds constants and shared views.
`App/` owns launch, the tab shell, and the one injected `RIGServices` value.

Two rules keep the layering real:

- **Views never score and never touch the file system.** They read models,
  present state, and call into the engine or a service.
- **The engine never touches SwiftData.** Every rule takes `GarmentSnapshot`,
  a Foundation-only value type. That is what makes the rules testable without a
  running app.

## Persistence ownership

SwiftData owns structured data, through `RIGModelContainer`:

| Entity | Owns |
|---|---|
| `ClothingItem` | one garment: metadata, favourite state, and the *relative paths* of its images |
| `SavedOutfit` | a kept look: its name, source, garment relationship, and the signature recorded at save time |
| `OutfitFeedback` | one like or dislike against an outfit signature |

Enumerations persist as raw strings, seasons as an `Int` bitmask. Unknown values
degrade safely rather than trapping — see `docs/DECISIONS.md`.

`SavedOutfit` deliberately does **not** persist garment order. Order carries no
meaning, and storing it would invite someone to read position as compatibility.
Display order is derived from category at render time.

## Image ownership

`GarmentImageStore` owns every garment byte on disk. Layout, rooted at
Application Support:

```
Garments/<GARMENT-UUID>/original.jpg     ≤ 1600 px, JPEG q0.85
Garments/<GARMENT-UUID>/cutout.png       ≤ 1200 px, transparent, absent on failure
Garments/<GARMENT-UUID>/thumbnail.png    ≤  400 px
```

Path arithmetic lives in `GarmentImagePaths` and is a pure function of the
garment UUID, so collisions are impossible and cleanup is one directory removal.
Writes are atomic. Nothing is uploaded anywhere.

### Deletion and cleanup

Deleting a garment deletes the row first, saves, and only then removes its
directory. The reverse order could leave a live row pointing at files that no
longer exist. If the file removal fails, the orphan sweep on the next launch
collects it: `orphanedGarmentIDs(knownGarmentIDs:)` reports only directories
whose names parse as UUIDs and are absent from the store, so an unexpected file
can never be swept up by accident.

## Import pipeline

```
photo Data
   │
   ├─ downscale to 1600 px, encode JPEG ──────────► write original.jpg
   │
   ├─ GarmentBackgroundRemoving.removeBackground(from:)
   │        │ success                    │ failure or no foreground
   │        ▼                            ▼
   │   downscale 1200, PNG          record a message
   │   write cutout.png             isolated = false
   │
   └─ thumbnail from the cutout when there is one, otherwise the original
```

The contract that shapes this: **a failed cutout never blocks an import.** A
garment with only its original photograph is a perfectly good garment, and the
interface says which one the user is looking at.

The protocol deals in `Data` rather than `UIImage` on purpose — image bytes are
`Sendable`, `UIImage` is not, and keeping Vision behind a protocol is what lets
the whole pipeline, failure path included, be exercised without an Apple runtime
(`PassthroughBackgroundRemover`, `FailingBackgroundRemover`).

## Outfit generation flow

```
wardrobe: [GarmentSnapshot]
   │
   ▼
CandidateGenerator          bounded (≤ 300 evaluated, ≤ 60 bases), deterministic,
   │                        profile-major so every base is seen before any base
   │                        is decorated twice
   ▼
OutfitValidator             HARD GATE. RIG owns this. No score overrules it.
   │
   ▼
OutfitEngine.score          colour 0.45 · season 0.30 · completeness 0.20 ·
   │                        favourites 0.05   →   0...1
   ▼
CompatibilityProvider?      optional, top 12 only, capped at 15%, may return nil
   │
   ▼
sorted → diversified        highest first, signature breaks ties, one suggestion
   │                        per structural base before backfilling
   ▼
[OutfitSuggestion]
```

### Score breakdown

| Component | Weight | What it measures |
|---|---:|---|
| `ColorHarmony` | 0.45 | mean pairwise colour agreement, damped for busy palettes |
| `SeasonCoherence` | 0.30 | 1.0 when every garment shares a season, 0.25 when none overlap |
| `OutfitCompleteness` | 0.20 | base 0.60, shoes +0.20, outerwear +0.10, bag or accessory +0.10 |
| `PreferenceWeighting` | 0.05 | share of the look the user marked favourite — stated, not learned |

The total is banded for display (`Strong match` / `Good match` / `Try this` /
`Something different`) and the number is never shown.

## Future ML seam

```swift
protocol CompatibilityProvider: Sendable {
    var isEnabled: Bool { get }
    func compatibilitySignal(for items: [GarmentSnapshot]) async throws -> Double?
}
```

v0.1 wires `compatibilityProvider: nil`. The constraints are structural, not
conventions: a provider may return `nil` and the engine carries on; it sees only
the top `compatibilityRescoreDepth` candidates; its influence is clamped to 15%
of the final score; a throwing provider leaves rule scores standing; and it has
no input at all to `OutfitValidator`. Tests assert each of these.

Weather, occasion and learned preference are intended to enter as *additional
scoring components alongside these*, not as replacements for them.

## Concurrency assumptions

- The engine, the image store, the import service and every background remover
  are `Sendable` value types with no shared mutable state, so they are safe to
  call from any task.
- Anything that mutates SwiftUI state is on the main actor: `SuggestionsModel`
  is `@MainActor @Observable`, and the async helpers inside views that touch
  `@State` are annotated `@MainActor`.
- Work that should not block the interface is explicitly off-main: image decode
  in `GarmentImageView`, the orphan sweep, and the whole import pipeline, which
  runs as a nonisolated async call.
- The build sets `SWIFT_STRICT_CONCURRENCY: targeted`. Moving to `complete` is
  expected to surface work in the UIKit camera bridge first.

## Privacy boundary

There is no boundary to police, because there is no network code. No
`URLSession`, no analytics SDK, no cloud container, no advertising identifier,
no location. `scripts/static_audit.py` fails if any of those symbols appear.
`Support/PrivacyInfo.xcprivacy` declares no tracking and no collected data
types, which is accurate rather than aspirational.

The claim RIG is entitled to make is exactly: *wardrobe data is stored locally
and v0.1 does not upload it.* Not that it is encrypted beyond what iOS provides
for any app's container, because RIG implements no cryptography of its own.

## Components unverified on an Apple runtime

Nothing in this repository has been compiled or run. The following carry more
risk than the rest and should be the first things looked at on a Mac:

1. `VisionBackgroundRemover` — written from Apple's documented iOS 17 API
   signatures, never executed. Cutout quality on real garment photographs is
   entirely unknown.
2. SwiftData relationship behaviour on delete — `PersistenceTests` asserts that
   deleting a garment leaves its saved look marked incomplete.
3. `CameraPicker` — the only UIKit bridge in the app.
4. Memory behaviour when decoding several 1200 px cutouts into the image cache.
