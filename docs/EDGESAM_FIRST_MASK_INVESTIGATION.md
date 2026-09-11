# First-mask investigation: awaiting device evidence

Baseline: `2564a3d`. Inspected HEAD: `2b35848455ee233b991c07d0be16b435bf75b2c7`.
Only intervening commits: `52d2051` (Slice 2.1) and `2b35848` (stride repair).

The user reports that the first mask reached review on the baseline, whereas
both later repair attempts still fail before review on a real iPhone. This is
the authoritative device evidence. Existing comments and provenance text that
claim a demonstrated embedding lifetime/stride root cause are unsupported by
that evidence and must not be treated as established findings.

No failing guard or violating runtime value has yet been demonstrated. No
production repair or repair commit is justified. This change adds temporary
diagnostics and an explicitly selected DEBUG experiment, then stops.

## Behavioral diff in the crop-to-review path

| Change | Baseline behavior | HEAD behavior | Can affect conversion on garment 1? |
|---|---|---|---|
| Initial prompt in `previewDraft` (`52d2051`) | Two box corners only | Seeds a positive point at the clamped box center | Yes: changes decoder input and therefore potentially scores/logits; failure is not demonstrated. |
| Prompt tensor packing (`52d2051`) | Float32 `[1,2,2]` coordinates and `[1,2]` labels `[2,3]` | Float32 `[1,N,2]` and `[1,N]`, initial N=3, labels `[2,3,1]`; same box-first order, center appended | Yes via prediction. No change to the original box coordinates or labels. |
| New prompt helpers (`52d2051`) | Existing box mapping only | Point coordinates clamp normalized x/y to [0,1], then multiply by source dimensions and resize scale; reject nonfinite points; reject total entries >16 | Valid center points affect prediction. Rejection throws decodingFailed before conversion, not this error. |
| Crop geometry and source inputs | `draftRegion`, sourceData, manual raster crop; upright source prepared/cached together with resize metadata | Same crop/export/sourceData calls; only center seeding inserted after crop | No changed source/crop transform found. Unchanged conversion still receives changed decoder outputs. |
| Encoding cache (`52d2051`) | Cache encoder MLMultiArray object directly | Allocate a new float32 array and flat-copy count elements | Yes: data supplied to the first decode changes storage. Actual corruption was not measured. |
| Encoding copy (`2b35848`) | Flat copy | Read via declared strides and reorder before copying to fresh array; reject unsupported type/layout | Could change tensor values. Copy rejection throws encodingFailed, not maskConversionFailed. User reports no repair of the observed failure. |
| Decoder output reads (`2b35848`) | Read masks/scores as flat Float32 pointers | Shared float32/stride-aware reader, with new read-failure exits | Yes, directly: added read exits or different values. Does not establish what failed in Slice 2.1 before these exits existed. |
| Candidate state (`52d2051`) | No refinement list | Empty default per candidate; clear on region update/recrop; center seeded before first decode | Only center seeding affects the stated first-garment reproduction. No earlier garment or point interaction required. |
| Session/protocol (`52d2051`) | Pass region and token | Forward points unchanged; convenience/default remains empty | Delivers the new center point. Hash reuse, token cache, cancellation and latest-prompt checks retain the same algorithm. |
| Initial decode task (`52d2051`) | Resolve session before creating task; call proposeMask directly | Resolve session in task and shared applyDecodeResult; read candidate points before starting | Same source and region. No evidence of a first-garment session mismatch; token rejection would occur before convert. |
| Error handling (`52d2051`) | Clear maskProposal silently on all failures | Ignore cancellation/stale/unavailable; show localized failure text for other errors | Makes failures visible; cannot itself make convert return nil. Known-good review success means visibility alone does not explain the regression. |
| Mask selection/projection | Highest of four scores; 256→1024, remove bottom/right pad, resize to source, threshold >0, composite/crop/PNG | Same algorithm and dimensions; only tensor reads changed | Can fail on changed logits even though arithmetic is unchanged. No center-dependent projection code exists. |
| Review UI (`52d2051`) | Mask overlay and accept/adjust/manual/skip | Adds +/- taps, markers, reset, busy opacity and accept disable | Runs after successful convert, so cannot cause this pre-review failure. |
| Coordinate overlay helpers (`52d2051`) | Source bounding region→local crop | Adds local tap→source and source point→local | Used after review is reached, not by initial projection. |
| Refinement/reset (`52d2051`) | Absent | Append points and re-decode; reset to center | Not executed in this reproduction. |
| View split (`52d2051`) | Screen methods in main view | Same screen methods moved to Screens extension | No crop geometry/source change. |
| Reset/error notice (`52d2051`) | No failure notice state | Clear notice on new proposal/new candidate/recrop/discard; show in raw crop preview | Presentation only, after a failure. Manual fallback remains. |

Model assets, configuration (`computeUnits = .all`), preprocessing, orientation
normalization, source loading, crop mapping, score ranking and projection
arithmetic have no baseline-to-HEAD changes. Test/doc changes do not execute in
the crop pipeline. No wardrobe/similarity code was changed in this investigation.

## Every optional failure exit (HEAD before instrumentation)

The original compound guards are separated in the diagnostics without changing
their acceptance criteria. Names below are `ConversionFailure` raw values.

| Diagnostic | Exact condition that returns nil |
|---|---|
| `maskCount` | masks.count != 4 × 256 × 256 = 262144. Exact rank/shape is not checked. |
| `scoreCount` | scores.count != 4. Exact rank/shape is not checked. |
| `scoreRead` / `maskRead` | floatElements returns nil; subordinate reasons below. |
| `resizedDimensions` | resizedWidth <= 0 OR resizedHeight <= 0. |
| `sourceDimensions` | sourceWidth <= 0 OR sourceHeight <= 0. |
| `sourceImageDimensions` | CGImage.width != sourceWidth OR CGImage.height != sourceHeight. |
| `thresholdDimensions` | thresholdAndBoundingBox receives invalid dimensions or count != width × height. Positive dimensions already passed; bilinearResize normally returns exactly this count. |
| `emptyForeground` | No source-space value satisfies `value > 0`. All <=0 and/or NaN satisfies this failure; nonfinite values alone are not explicitly rejected. |
| `contextCreation` | RGBA CGContext allocation/creation returns nil. Dimensions, bytesPerRow=sourceWidth×4, bitsPerComponent=8, RGB and premultipliedLast are the arguments. Runtime allocation success cannot be inferred statically. |
| `contextData` | The created CGContext has no data pointer. |
| `maskedImageCreation` | context.makeImage() returns nil. |
| `imageCrop` | masked.cropping(to: bounding rectangle) returns nil. Rectangle is (minX,minY,maxX−minX+1,maxY−minY+1). |
| `pngEncoding` | UIImage(...).pngData() returns nil. This was an implicit propagated nil. |

The outer `guard let cutout` propagates the last five compositing failures;
it is not another independent unknown reason.

Reader subordinate exits (`tensorReadFailure`): dataType != float32; empty
shape; shape/strides rank mismatch; calculated maxOffset < 0; or reorder
validation fails. Reorder requires nonempty, positive dimensions, equal ranks,
maxOffset >=0 and source.count > maxOffset, where
maxOffset = sum((shape[d]−1)×strides[d]). The caller allocates a buffer spanning
max(maxOffset+1,array.count), so its supplied span normally satisfies that last
check. Shape, strides, count, type and failed read guard are logged.

There is no separate nil guard for selected plane/index: bestIndex starts at 0
and can only become 1, 2 or 3, yielding bases 0,65536,131072,196608. NaN first
score leaves index 0 under existing comparison semantics. There is no explicit
finite-score check. There is no orientation check in convert; only the CGImage
dimensions are compared. Square-image orientation errors would not trip it.

There is no upper-bound padding guard: malformed resized dimensions above
1024 can produce an out-of-bounds trap, not a nil. The unchanged metadata
factory bounds each resized dimension to 1...1024 for positive source sizes.
Bilinear resize returns [] on nonpositive dimensions; the actual call sites
use constants or validated positive sizes. Malformed shapes/strides or integer
overflow can also trap rather than return nil. These are distinctions in the
existing code, not new repairs.

## Device diagnostics and comparison

Build configuration must be **Debug**. The existing Gate B1 workflow already
builds Debug; no workflow change is needed. Gate A must validate this modified
tree, not just the original HEAD. No build or test execution is claimed here.

1. Install the Debug IPA and open Outfit photo. Tap **Diagnostics** in its
   navigation bar. Keep **2564a3d first prompt (box only)** OFF, then Clear/Done.
2. Draw the failing first-garment crop and confirm. After the failure, open
   Diagnostics and **Copy diagnostics**. Save the complete text externally.
3. For the optional comparison, switch the box-only toggle ON. Close Outfit
   photo, reopen the same photo, clear the previous records, and reproduce the
   same first-garment crop. Copy the second run. Avoid changing the box; verify
   the recorded normalized coordinates match before interpreting the comparison.
4. Switch the toggle OFF afterward. It is process-memory only and resets on
   app relaunch. It affects only the first prompt after encoding a source.

The alternative launch argument `-EdgeSAMKnownGoodFirstPrompt` enables the same
experiment for an Xcode runner. The in-app switch requires no Xcode or Console.
The old function reproduces the baseline's allocation, box coordinate mapping,
Float conversion, write order and [2,3] labels directly, independently of the
new promptEntries helper. The current embedding and conversion remain in use.
There is no automatic retry or automatic fallback. Refinement is unchanged.

Console and buffer receive the same `[RIG-EdgeSAM]` JSON record strings. Each
record includes a trace UUID and process uptime. Encoder/decoder traces are
linked by the source token. Records cover crop confirmation, decoded/upright
UIImage size/scale/orientation/CG size, metadata, raw/copied embedding layout,
actual prompt tensor values, prediction boundaries, masks/scores layouts,
scores and selected plane, per-candidate summaries, and selected-plane
statistics/bounds at decoder, model, unpadded and source resolutions. Exact
failure stage and review readiness are recorded. No pixels, raw mask planes,
image bytes, file names or photo metadata are recorded.

The buffer is protected by a lock, bounded to 512 records and 262144 UTF-8 bytes
of records (plus a small snapshot header), and reports dropped records. A single
pipeline is far below the limits. Clear removes records without changing the
experiment setting. Copy takes a fresh complete snapshot, even if the displayed
text has not been refreshed. Storage, view, switch and actual logging/scans are
DEBUG-only; no persistent production telemetry is introduced.

The comparison deliberately does not dump complete masks: they contain spatial
image information and would violate the diagnostic privacy/buffer constraints.
Scores and prompt coordinates are exact Float text; masks are aggregate
statistics. Separate fresh-source runs avoid an extra prediction changing the
state of the primary run, but may introduce ordinary model/crop variability.

## Evidence gate before any repair

1. Every optional exit: enumerated above.
2. Demonstrated failing exit: **unknown, awaiting copied device records**.
3. Actual violating values: **unknown**.
4. Responsible post-baseline change: **not confirmed**.
5. Why previous copies did not solve it: the user demonstrates they were
   insufficient; the actual reason cannot be determined without the failing
   invariant. A passing synthetic stride test does not establish device cause.

If the original prompt succeeds and current prompt fails with matching source
and crop, inspect the corresponding decoder records to isolate the changed
prompt. That alone must not be reported as proof of a specific decoder internal
mechanism. If both fail, use the exact recorded guard and values to choose the
next bounded experiment. Do not change production projection speculatively.

Added buffer tests cover bounded eviction, UTF-8 size accounting, oversized
records, clear/setting behavior and concurrent writes. They are diagnostic
infrastructure tests, **not** a first-mask regression test. The actual regression
test must wait for the demonstrated invariant and exercise the production seam.

## Local verification

Host is Windows; Swift, xcodebuild and an Apple runtime are unavailable.
The repository's full available host check is scripts/static_audit.py; Apple
build and XCTest execution must run through Gate A. All existing tests remain.
GitHub CLI is unauthenticated. The connected GitHub tool's commit-workflow query
returned no PR-triggered runs; that filtered result cannot establish whether
manual Gate A runs exist. The user will run Gate A and the Debug device build.
No push, production repair, or repair commit has been made.
