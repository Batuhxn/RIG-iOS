# v0.3 Auto Metadata

Base: origin/main 2b0013f. Isolated branch: feat/v0.3-auto-metadata-main.
The local design/nocturne-ios checkout is older and is not the integration base.

Architecture: optional predictions from one on-device image embedding, fixed precomputed
text embeddings, deterministic alpha-masked colour histogram. No network inference.
Existing category raw values and required name/season validation remain unchanged.
Length is mini/midi/maxi only for skirts and dresses in this version.
Confidence is a model similarity or mask-area score, NOT a calibrated probability.
New SwiftData fields are optional; old rows have no automatic metadata.

Commit sequence:
1. Spike: taxonomy, ranking, mask colours, Core ML provider contract, benchmark harness,
   model/export evaluation and unit tests.
2. Integration: dependency injection, import predictions, editable fields, persistence,
   cancellation and regression tests.
3. Validation report and reviewable patch.

Validation: existing host audit and Python tests; XCTest for deterministic colours,
ranking, draft merge, persistence, unavailable model and cancellation. Xcode build,
legacy-store migration and device latency require macOS/iPhone and remain explicit gates.
No model may be enabled for release until a labelled garment set measures per-field
accuracy, abstention, correction rate, p50/p95, cold load, memory and bundle size.

Model decision: evaluate MIT-licensed OpenAI CLIP ViT-B/32, with image encoder only
on device and precomputed text vectors. MobileCLIP's current LICENSE_MODELS excludes
product development; older Core ML cards link a different license, so exact checkpoint
provenance cannot be inferred from the repository code license.
