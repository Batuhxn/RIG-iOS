# RiG v0.3 Auto Metadata — implementation and remaining gates

Date: 8 October 2026

Status: source implementation and measurement tooling prepared; **not a validated,
working end-to-end classifier or a TestFlight-ready release**. No model weights are
bundled. Colours are wired to run after successful background removal; category,
subtype and length fall back to manual entry until a validated model is installed.
Swift/iOS code has not been compiled or executed on this Windows host.

## Repository and baseline

- Repository: Batuhxn/RIG-iOS.
- Current upstream main inspected: `2b0013f` (TestFlight release diagnostics).
- Local original checkout was `design/nocturne-ios`, `8eef6b6`. It is a different,
  older design branch. Its files were not overwritten.
- Work is in an isolated checkout under this chat's `work/RIG-iOS` directory.
- Branch: `feat/v0.3-auto-metadata-main`, based on upstream main.
- Commits: `e6cd4bd` spike/export/measurement tools; `c9198d8` editable integration.
- No remote branch push, PR, TestFlight upload, signing or deployment performed.

## Existing architecture inspected

SwiftUI screens, SwiftData persistence and XcodeGen (`project.yml`). iOS deployment
target remains **17.0**, Swift language mode 5, targeted strict concurrency.

On current main, AddGarmentFlow receives camera or Photos bytes, runs
GarmentImportService, and displays image review with the metadata form. Unlike the
older design branch, current main has no crop step in this flow. BulkImportFlow
processes one queue item at a time and shares GarmentMetadataForm. Duplicate checks
run before saving. Original/cutout choice remains independent of metadata analysis.

ClothingItem already persisted category, free-text subtype, primary colour and
season, with image paths instead of image bytes. GarmentSnapshot supplies category
and primary colour to the outfit engine. No ranking changes were made.

GarmentImageProcessing normalizes orientation and caps originals/cutouts/thumbnails
at 1600/1200/400 pixels. VisionBackgroundRemover uses the iOS 17 foreground instance
mask request, combines all detected foreground instances, and emits an alpha PNG.
That is a foreground mask, not a clothes-only semantic segmentation mask. The v0.3
scope assumes one garment; worn outfits, skin, hangers and multiple garments remain
important evaluation cases. Removal failure continues with the original image.

## Implemented behaviour

- Optional category, subtype, mini/midi/maxi length, primary/secondary colour,
  per-field score, model identifier, availability state and duration.
- Length only for `bottom/skirt` and `dress/dress`; no skirt length for trousers,
  footwear or jumpsuits. Changing category clears dependent subtype and length.
- Fixed, independent category/subtype/length prompt groups. Existing category raw
  values remain stable. Subtype remains editable free text for compatibility.
- Semantic ranking normalizes image/text vectors, uses cosine similarity, rejects
  nonfinite/zero/dimension-mismatched embeddings, and abstains on insufficient
  score or top-two separation. Provisional thresholds: cosine 0.20, margin 0.025.
  These have **not** been calibrated on garment data.
- Colour extraction reads only a successful cutout, samples at <=192 pixels,
  converts to sRGB RGBA8, ignores alpha <230/255 and unpremultiplies retained RGB.
  Fixed HSV bins produce a deterministic histogram; fewer than 32 valid pixels
  abstain. Secondary colour requires >=15% of accepted mask area. Metallic remains
  manual. Colour score is pixel area share, not probability of correctness.
- Existing required name/category/primary-colour/season validation remains. No
  season or garment name is invented. All predicted values remain editable.
- Explicitly cleared fields remain cleared on a later merge. Manual edits discard
  that field's stale confidence. Incompatible length and repeated primary/secondary
  colours cannot be persisted by the metadata writer.
- Optional SwiftData `lengthRaw`, `secondaryColorRaw`, `autoMetadataJSON` preserve
  old rows' absence of metadata. Failed edits restore these fields too. A real
  v0.2 on-disk store migration is still an unexecuted validation gate.
- Model failure does not discard deterministic colours or block manual saving.
  A generation guard rejects late single-import results; cancellation/cursor checks
  prevent applying bulk results to another item.

## Backend and licensing assessment

MobileCLIP is technically relevant: Apple's example performs on-device zero-shot
classification and offers Core ML models. However its demo requires iOS 17.2,
whereas RiG targets 17.0. Demo requirements do not prove the minimum requirement
of every exported model; inspect the chosen artifact's specification instead.
[Official iOS demo](https://github.com/apple-aiml-research/ml-mobileclip/tree/main/ios_app)

The currently published LICENSE_MODELS grants research-only use and explicitly
excludes product development/commercial products. The older Core ML model card
points to a differently named weight/data license. Do not infer checkpoint rights
from the code license or apply one version's license to all older artifacts.
No MobileCLIP weights were downloaded or redistributed.
[Current model terms](https://raw.githubusercontent.com/apple/ml-mobileclip/main/LICENSE_MODELS),
[Core ML model card](https://huggingface.co/apple/coreml-mobileclip)

At the user's request, the alternative evaluated is **OpenAI CLIP ViT-B/32** using
the official distribution and its MIT license. Preserve the MIT notice with any
redistribution and archive the exact checkpoint/source provenance. The model card
also warns that deployment needs task-specific evaluation and fine-grained classes
can be unreliable; this is not a claim of garment accuracy or vendor endorsement.
[MIT license](https://github.com/openai/CLIP/blob/main/LICENSE),
[Model card](https://github.com/openai/CLIP/blob/main/model-card.md)

The exporter prepares a Core ML image encoder plus precomputed text vectors,
avoiding an on-device text encoder/tokenizer. It records checkpoint and prompt
hashes in a shared identifier checked at runtime. Input is float32 RGB CHW
1x3x224x224 with a white aspect-fit canvas and CLIP mean/std; this differs from
CLIP's usual image crop and requires garment validation. Export requests iOS 17.

ViT-B/32 is expected to have a larger device footprint than MobileCLIP-S0; no local
device size, memory or latency measurements justify a stronger comparison.
Conversion/runtime compatibility remains unverified. Export parity checks one
synthetic tensor; this is only a conversion smoke test, not image preprocessing or
accuracy validation. Real-photo parity must be added before activation.

## Files changed

| Area | Files |
|---|---|
| Analysis | `Sources/Services/AutoMetadata/AutoMetadata.swift`, `CoreMLGarmentClassifier.swift`, `MaskedColorExtractor.swift` |
| Import wiring | `Sources/App/RIGServices.swift`, `Sources/Services/ImageStorage/GarmentImportService.swift` |
| Form and flows | `GarmentMetadataForm.swift`, new `GarmentMetadataForm+AutoMetadata.swift`, `AddGarmentFlow.swift`, `AddGarmentFlow+Duplicates.swift`, `BulkImportFlow.swift` under `Sources/Features/GarmentEditor` |
| Persistence | `Sources/Models/ClothingItem.swift`, `Sources/Features/GarmentEditor/GarmentMutations.swift` |
| Tests | `Tests/AutoMetadataTests.swift`, `AutoMetadataServiceTests.swift`, `AutoMetadataPersistenceTests.swift`, `AutoMetadataBenchmarkTests.swift` |
| Tooling | `scripts/export_metadata_clip.py`, `metadata_metrics.py`, `test_metadata_metrics.py`, narrowly scoped Core ML permission in `static_audit.py` |
| Documentation | `docs/AUTO_METADATA_PLAN.md`, this report |

## Test evidence and benchmark results

| Check | Result |
|---|---|
| Existing static audit, including new Swift sources | PASS: 67 source files, 22 test files, 229 test functions discovered |
| New Python measurement tests | PASS: 6/6 |
| Python export/metrics syntax compilation | PASS |
| Git whitespace check | PASS |
| Added Swift tests | 15 unit tests + 1 opt-in benchmark authored; NOT RUN |
| Existing general Python suite | NOT GREEN on Windows: 22 tests, 19 error records and 1 failure; unavailable bash executable and POSIX-vs-Windows path assertion; initial temp permission issue resolved by using workspace temp |
| Xcode build / Swift unit suite / UI / store migration | NOT RUN: no Apple runtime or Swift compiler available |
| Core ML conversion parity | NOT RUN: no macOS Core ML runtime, torch/clip/coremltools absent |
| Garment accuracy / coverage / correction rate | NO RESULT: no model and no labelled garment evaluation set |
| iPhone cold/warm p50/p95, peak memory, bundle size | NO RESULT: no iPhone run |

Static audit is not compilation. Test discovery is not test execution. Synthetic
ranking/colour cases are not a garment benchmark. No vendor latency numbers are
reported as RiG measurements.

## Completing validation and activation

1. On a Mac, use the delivered source or apply the patch on `2b0013f`; run the
   existing `scripts/validate_macos.sh` to compile and execute the tests first.
2. In an isolated Python environment install OpenAI CLIP from a pinned source
   revision plus compatible pinned torch/coremltools; retain dependency versions
   and MIT notice. Run `python scripts/export_metadata_clip.py --output build/metadata-model`.
   The exporter records versions and the checkpoint hash but dependencies have not
   been resolved/pinned in this session.
3. Validate real-photo tensor orientation, colour space, aspect-fit and conversion
   parity. The proposed exported assets are **not installed in Sources automatically**.
4. For a development benchmark, add the generated model package and prompt JSON
   as resources so the app contains `RIGGarmentEncoder.mlmodelc` and
   `RIGGarmentPrompts.json`. The existing static audit intentionally still rejects
   model binaries: activation requires a targeted checksum/provenance allowlist,
   not removing the general binary guard. This gate remains unfinished.
5. Supply a consented, labelled set with train/validation/test separation by garment,
   not photo. Cover all category/subtype classes, colours, skirt/dress lengths,
   backgrounds, lighting, partial views and difficult masks. Tune thresholds only
   on validation; freeze taxonomy/thresholds before held-out evaluation.
6. Benchmark fixture JSON format:

   ```json
   [{"id":"skirt-001","cutout":"skirt-001.png","expected":{
     "category":"bottom","subtype":"skirt","length":"mini","primaryColor":"black"
   }}]
   ```

   Set `RIG_METADATA_FIXTURES` in the test host environment to the device/simulator-
   accessible fixture manifest. Absent expected keys are unlabelled, not correct
   abstentions. The harness attaches `auto-metadata-observations.json` to xcresult;
   run `python scripts/metadata_metrics.py <observations.json>` after extraction.
   It reports all-sample accuracy, suggested-only accuracy, coverage, correction
   proxy, and cold versus warm timing. It rejects missing-model observations.
   This times metadata only, not the full Vision/import pipeline. Profile total
   import latency and peak memory separately with Instruments on the oldest
   supported device. Benchmarking is skipped explicitly when fixtures are absent.
7. Check live UI overrides, cancellation, duplicate checks, failed removal,
   original/cutout choice, multi-import and reopening an actual v0.2 store.
   Check no-confidence/low-confidence cases and secondary-colour false positives.
8. Only after results justify activation, permit the exact model artifacts and
   update release metadata to v0.3. Marketing version remains 0.2 in this patch
   because a verified v0.3 release was not produced.

The pending work needs a Mac/iPhone execution environment and representative labelled
photos. It cannot be replaced by host static checks or fabricated benchmark numbers.
