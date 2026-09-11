# Decisions

Only the choices that would be expensive to reverse.

## SwiftUI and SwiftData, no third-party runtime dependencies

Both ship with the platform, both are supported on the iOS 17 floor, and
neither adds a dependency to audit or a licence to clear. SwiftData's `@Model`
observation also removes an entire layer of view-model plumbing. The cost is
that SwiftData is younger than Core Data and its migration story is less proven;
the mitigation is the raw-value persistence decision below.

## Enumerations persist as raw strings and bitmasks, never as Codable enums

`categoryRaw`, `primaryColorRaw` and `seasonMask` are the stored authority.
Adding a colour family or a category later cannot invalidate an existing store,
and an unrecognised value degrades to a safe default — an unknown category reads
as `accessory`, which has no structural authority, and an unknown colour reads
as `multicolor`, which the harmony rules score non-committally.

## Garment images live in files, not in the database

Image bytes are written under Application Support in one directory per garment
UUID; the database stores relative paths. Blobs inside a SwiftData store bloat
every fetch and make the store hard to migrate. Directory-per-garment makes
deletion a single directory removal, makes collision impossible, and makes an
orphan sweep both possible and safe.

## Three fixed image sizes: 1600, 1200, 400

Retained original, cutout and thumbnail. A wardrobe of two hundred 12-megapixel
photographs would be gigabytes of the user's storage for pixels nothing ever
displays. The original is kept at 1600 specifically so a garment can be
reprocessed by a better background remover later without re-photographing it.

## Local-only, with no network code at all

There is no networking layer to disable, no endpoint to configure and no key to
protect. The static audit fails the build-adjacent check if `URLSession` or any
cloud or analytics symbol appears anywhere in the sources. The privacy claim RIG
makes is therefore narrow and true: wardrobe data is stored locally and v0.1
does not upload it.

## Rules before ML, and the ML seam stays inert

`FashionMLSpike` reached CONDITIONAL GO, not GO. Its evaluated head returned a
saturated constant through its shipped output, weighed roughly 806 MB once
converted, was never run on Apple hardware, and its checkpoint licensing is
unresolved. So v0.1 ranks with explicit rules, and `CompatibilityProvider`
exists with no implementation attached.

## A compatibility signal can never exceed 15% of a score

The cap is enforced in `OutfitEngineConfiguration.effectiveCompatibilitySignalWeight`
rather than left to a caller's discretion, and a provider has no influence at all
over `OutfitValidator`. A model may reorder near-ties. It may not decide what an
outfit is, and it may not overrule the user.

## The interface shows bands, never numbers

"Strong match", not "92% compatible". There is no calibrated probability behind
the ranking and displaying a number would claim one. A test asserts that no
generated summary contains a digit.

## iOS 17 minimum

`VNGenerateForegroundInstanceMaskRequest` and its high-resolution masked-image
output are iOS 17, and they are the whole basis of local background removal.
`@Observable` and the modern SwiftData and SwiftUI APIs come along with that
floor. Supporting iOS 16 would mean a second, worse extraction path.

## XcodeGen, with `project.yml` as the checked-in source of truth

No Apple toolchain was available on the development host. Hand-writing a
`.pbxproj` to claim the project exists would produce a large fragile file that
nobody verified. A `project.yml` is reviewable, diffable, and generates a real
project in one command on macOS.

## EdgeSAM and the Core ML exception (v0.4)

v0.1's static audit banned `CoreML`, `MLModel` and `MLMultiArray` everywhere,
and banned `.mlmodel`/`.mlpackage` anywhere in the repository. That rule
existed because v0.1 shipped no model at all: `FashionMLSpike` had reached
CONDITIONAL GO, not GO, its evaluated head returned a saturated constant, its
converted artefacts weighed roughly 806 MB, and its checkpoint licensing was
unresolved. Banning the symbols outright was the cheapest way to guarantee
that unresolved research never quietly became production code.

v0.4 Slice 2 adds a real, bounded on-device use of Core ML: EdgeSAM-3x, for
interactive garment mask proposals inside a manually drawn region. This is a
different situation on every axis that mattered above — the model runs
on-device only, nothing is uploaded, its artefact provenance, checksums and
license (NTU S-Lab License 1.0, non-commercial; verbatim text at
`Sources/Resources/Models/EdgeSAM-NOTICE/LICENSE.txt`, full provenance in
`docs/EDGESAM_PROVENANCE.md`) are recorded rather than unresolved, and its
role is capped by construction: a mask is a proposal the user must accept,
adjust or reject, never an automatic write. So the blanket ban is no longer
the correct rule, and keeping it would have blocked a change the product
now deliberately makes.

The exception the static audit now enforces is narrow and mechanical, not a
change of posture:

- `CoreML` / `MLModel` / `MLMultiArray` may appear only inside
  `Sources/Services/Segmentation/`, and only in production sources — never in
  tests, which exercise the seam through `GarmentSegmenting`, a Foundation-only
  protocol that never leaks a Core ML type outward.
- A bundled `.mlmodel` / `.mlpackage` / `.mlmodelc` artefact is permitted only
  under `Sources/Resources/Models/`.
- Every other forbidden pattern (network calls, cloud sync, third-party
  analytics, tracking, location) is checked exactly as before, everywhere.
- Nothing about this exception permits network access for the model itself:
  `GarmentSegmenting` takes and returns `Data`/`Foundation` values, runs
  encode-once/decode-many against a locally bundled package, and the "no
  networking code at all" decision above is otherwise unchanged.

If a later slice wants Core ML somewhere else in the app, that is a new
decision to write down here, not an automatic extension of this one.

## The outfit engine works on snapshots, not on models

Every rule takes `GarmentSnapshot`, a Foundation-only value type. That is why
the engine can be unit tested without SwiftData or a running app, and it is also
the exact shape a future compatibility provider receives.
