# EdgeSAM Core ML artifact provenance (v0.4 Slice 2)

Recorded once, at integration time, per the v0.4 Slice 2 requirement to pin
artifact identity/version/checksum before writing any adapter code against
these files. If the bundled `.mlpackage` files in
`Sources/Resources/Models/` ever change, this document must be updated
alongside them.

## Source

- Upstream project: [chongzhou96/EdgeSAM](https://github.com/chongzhou96/EdgeSAM)
  (`master` branch, inspected 2026-09-11).
- License: **S-Lab License 1.0** (non-commercial) — copied verbatim into
  `Sources/Resources/Models/EdgeSAM-NOTICE/LICENSE.txt`. See "License" below.
- The two Core ML artifacts (`edge_sam_3x_encoder.mlpackage`,
  `edge_sam_3x_decoder.mlpackage`) and the upstream `LICENSE.txt` were staged
  by the repository owner directly from EdgeSAM's official HuggingFace
  distribution and handed to this integration as `.mlpackage.zip` files plus
  the license text. They were not re-downloaded by this integration — this
  document instead records what was independently verified about their
  *contents* once received, which is the part that actually matters for
  writing a correct adapter.
- Both `model.mlmodel` files carry a `com.github.apple.coremltools.version`
  metadata entry of `7.1` and a `com.github.apple.coremltools.source` of
  `torch==2.0.0` (`TorchScript` dialect) — consistent with an export
  produced by EdgeSAM's own `scripts/export_coreml_model.py`, not a
  hand-modified or third-party re-export.

## Checksums (SHA-256)

Computed directly from the files staged into this integration; not copied
from any upstream listing.

| File | SHA-256 |
|---|---|
| `edge_sam_3x_encoder.mlpackage.zip` (as staged) | `9c749659493a12948937a845cc9c0578930c3532ebbdbaf64c71a32c7a3a6dec` |
| `edge_sam_3x_decoder.mlpackage.zip` (as staged) | `f8a278c28ee831e1a43e6f8e1ea5f2c9f0dd7dc4965ef6126204958217fcff7e` |
| `edge_sam_3x_encoder.mlpackage/Data/com.apple.CoreML/model.mlmodel` | `e0b7179ef64d39c8610877ee75b4bfd2405e421edc03199b1b0de13b37ff8616` |
| `edge_sam_3x_decoder.mlpackage/Data/com.apple.CoreML/model.mlmodel` | `4518e04d599e85df080eb129d61118e121118b050508bbb83fa26d7fe6eeaa48` |
| `edge_sam_3x_encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin` | `c89a70057120761ce8bd84e586cc4c5fbaad6daf24147abc77d27df7d93662c7` |
| `edge_sam_3x_decoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin` | `f2392539e4491f64b6ab29e8f4438ab118cdd21993b1613b78cd39a7c1d99774` |
| `EdgeSAM-NOTICE/LICENSE.txt` (upstream `LICENSE`, byte-identical) | `cfd654022bdc44fdd809670d50239bcb1ebf2f4a661dca7e328f93c269538246` |

Unpacked, bundled sizes: encoder `.mlpackage` ≈ 11 MB, decoder `.mlpackage`
≈ 9.7 MB (≈ 20.7 MB combined added to the app bundle).

## How the interface below was actually verified

coremltools could not be installed in the implementation sandbox (no
network route to PyPI or Apple's CDN), and no `protoc` binary was
available either. Rather than trust a README's description of the model's
inputs/outputs, `model.mlmodel`'s raw protobuf bytes were decoded directly
with a small schema-free wire-format walker
(`scripts/static_audit.py`-adjacent tooling, not shipped in the app — see
the implementation session's scratch scripts), interpreting the resulting
field numbers against the **verbatim** `Model.proto` and
`FeatureTypes.proto` schema fetched from
`raw.githubusercontent.com/apple/coremltools/main/mlmodel/format/`. This is
the same information `coremltools.models.MLModel(...).get_spec()` would
report; it was just extracted without the library being installable here.

The coordinate/label semantics below (how a box prompt becomes
`point_coords`/`point_labels`, what the four mask channels are, and what
preprocessing the encoder expects) are **not** inferred from the shapes
alone — they were cross-checked against EdgeSAM's own source at the same
commit family that produced these artifacts:
`scripts/export_coreml_model.py`, `edge_sam/utils/coreml.py`,
`edge_sam/modeling/prompt_encoder.py`, `edge_sam/modeling/sam.py`, and
`edge_sam/utils/transforms.py`. Every numeric claim in the tables below
(the 1024 image size, the 4 point-embedding slots, the `+0.5` pixel-center
shift, the bottom/right-only padding, the `postprocess_masks` upscale
chain) is quoted from that source, not guessed.

## Encoder interface (`edge_sam_3x_encoder.mlpackage`)

- Model type: ML Program (`mlprogram`), specification version 6 (Core ML 5
  / iOS 15+ — well within RIG's iOS 17 minimum).
- Input `image`: `Float32[1, 3, 1024, 1024]`.
- Output `image_embeddings`: `Float32[1, 256, 64, 64]`.

**What the adapter must feed it**, per `Sam.preprocess()`:

1. Resize the source image so its **longest side is 1024**, preserving
   aspect ratio (`ResizeLongestSide`, scale = `1024 / max(h, w)` applied to
   both dimensions equally).
2. Zero-pad on the **bottom and right only** up to exactly 1024×1024 —
   the top-left origin of the resized image is preserved unchanged
   (`F.pad(x, (0, padw, 0, padh))`).
3. Normalize per channel, RGB order:
   `pixel = (pixel - mean) / std` with
   `mean = [123.675, 116.28, 103.53]`, `std = [58.395, 57.12, 57.375]`.

The traced encoder graph (`forward_dummy_encoder`) does **not** perform
this preprocessing itself — it expects an already-normalized,
already-padded tensor. Skipping any of the three steps above, or getting
the pad side wrong, silently produces a plausible-looking but wrong
embedding.

## Decoder interface (`edge_sam_3x_decoder.mlpackage`)

- Model type: ML Program (`mlprogram`), specification version 6.
- Inputs:
  - `image_embeddings`: `Float32[1, 256, 64, 64]` — the encoder's output,
    unchanged. This is exactly the token `OutfitEmbeddingSession` caches
    and reuses across prompts.
  - `point_coords`: `Float32[1, N, 2]`, `N` flexible in the range **1–16**
    (default 1).
  - `point_labels`: `Float32[1, N]`, `N` flexible in the same range
    **1–16** (default 1), and must match `point_coords`'s `N`.
- Outputs:
  - `scores`: `Float32[1, 4]` — one quality value per mask candidate.
  - `masks`: `Float32[1, 4, 256, 256]` — four low-resolution mask logits,
    **not** yet resized to the source image and **not** yet thresholded.

### Box prompt → `point_coords` / `point_labels`

The exported decoder (`SamCoreMLModel.forward` in `edge_sam/utils/coreml.py`)
has no separate "box" input — a box prompt is expressed as exactly **two**
points with reserved label values, per `PromptEncoder.__init__`'s own
comment: `self.num_point_embeddings: int = 4  # pos/neg point + 2 box
corners`. The four label values are:

| `point_labels` value | Meaning |
|---|---|
| `0` | background (negative) point |
| `1` | foreground (positive) point |
| `2` | box **top-left** corner |
| `3` | box **bottom-right** corner |
| `-1` | padding ("not a point") — unused by this slice, see below |

v0.4 Slice 2 only ever sends a manually drawn rectangle, never a loose
point, so the adapter always sends exactly `N = 2`:

```
point_coords  = [[x0, y0], [x1, y1]]   // top-left, bottom-right
point_labels  = [2, 3]
```

which is within the model's declared 1–16 range, so no `-1` padding entry
is ever needed for this slice.

**Coordinate space**: `point_coords` are pixel coordinates in the same
1024×1024 padded space the encoder consumed — *not* normalized [0,1], and
*not* relative to the original crop before the longest-side resize.
Internally the graph applies `(coord + 0.5) / 1024` (`_embed_points` in
`edge_sam/utils/coreml.py`) to turn them into the position encoding's
[0,1] input, but the adapter must do the resize-then-pad transform itself
before handing coordinates in — dividing by 1024 is already baked into the
model. Because padding is bottom/right-only, mapping a box corner from the
original (or RIG-normalized) source into this space is a **pure scale by
the same `1024 / max(h, w)` factor used for the image, with no offset**.

### Reading the outputs

- `masks` are logits at native decoder resolution (256×256), covering the
  full 1024×1024 padded frame at 1/4 scale — **not** cropped to the box,
  **not** yet in source-image space.
- To map a mask channel back to RIG source-space
  (`Sam.postprocess_masks`):
  1. Bilinear-upsample 256×256 → 1024×1024 (the encoder's `img_size`).
  2. Crop away the bottom/right padding region back down to the
     resized-but-unpadded input size from the encoder preprocessing step.
  3. Bilinear-upsample that back to the *original* source image size.
  4. Threshold at `0` (`mask_threshold = 0.0` on `Sam`) to obtain a binary
     mask; values above zero are foreground.
- `scores[i]` corresponds to `masks[i]`. There is no documented fixed
  "best" index — the adapter picks `argmax(scores)` as the single proposed
  mask `SegmentationMaskResult` carries, exactly as
  `SamPredictor.predict` recommends ("select based on highest ... score").
  This value becomes `SegmentationMaskResult.qualityScore` and, per
  `docs/DECISIONS.md`, must never be shown to the user as garment
  confidence — it is EdgeSAM's own quality/IoU-style estimate for that
  mask candidate, nothing else.

## Point prompts and refinement (v0.4 Slice 2.1)

Real-device testing found two problems with v0.4 Slice 2's box-only prompt:
EdgeSAM's mask could bleed into unrelated regions (skin, background) around
a loosely drawn box, and — more seriously — EdgeSAM appeared to work only
for the *first* garment cropped out of an outfit photo, silently falling
back to the legacy background remover for every garment after it.

### Order-independence: verified against the real upstream source

Slice 2.1 needed to know whether appending refinement points *after* the
box's two corners in `point_coords`/`point_labels` — rather than, say,
interleaving them, or requiring a fixed position per point — would change
the decoder's output. Rather than guess, the actual `SamCoreMLModel`
class was fetched from
`https://raw.githubusercontent.com/chongzhou96/EdgeSAM/master/edge_sam/utils/coreml.py`
(the project's default branch is `master`, not `main`). Its
`_embed_points` method computes each row of `point_coords`/`point_labels`
independently:

```python
for i in range(self.num_point_embeddings):
    point_embedding = point_embedding + point_embeddings[i].weight * (point_labels == i).float()
```

There is no positional or sequence encoding layered on top of this — each
row contributes to the prompt embedding purely by its own coordinate and
label, summed, regardless of where it sits in the array. **The order of
entries within `point_coords`/`point_labels` does not affect the decoder's
output.** This is what let Slice 2.1 fix a stable, simple convention —
`EdgeSAMGeometry.promptEntries`: the box's two corners first (labels `2`,
`3`), then every refinement point in the order the user added them (label
`1` positive / `0` negative) — without that convention being load-bearing
for correctness. It also means the box-only case (`N = 2`, no refinement
points) is byte-identical to what v0.4 Slice 2 already shipped.

### The 16-entry cap

The decoder's declared `point_coords`/`point_labels` range is **1–16**
(see above). The box's two corners are always present in this slice, so
at most **14** refinement points can ever be sent alongside one —
enforced defensively by `EdgeSAMGeometry.promptEntries` (`points.count + 2
<= maxPromptEntryCount`), which returns `nil` rather than building an
out-of-spec tensor if that is ever exceeded. `MaskReviewSheet`'s UI does
not otherwise limit how many points a user can tap, so this guard is the
backstop, not the primary constraint.

### Root-cause hypothesis: why only the first garment worked

The most defensible explanation for "EdgeSAM worked once per session,
then silently degraded" is that `EdgeSAMSegmenter.encodeSource` was
caching the encoder's *output* `MLMultiArray` (`image_embeddings`) by
reference, rather than copying it. `MLModel.prediction(from:)` does not
guarantee an output `MLMultiArray`'s backing memory stays valid, or
unmodified, once the model runs any further prediction — including every
subsequent decoder call that same cached embedding is fed into, once per
garment, for the rest of the sitting. A cached reference to Core ML's own
output buffer is exactly the shape of bug that "works once" and then
fails quietly: the first garment's decode ran before any other prediction
had touched that memory; the second garment's decode read from a buffer
Core ML may already have reused underneath it, and the resulting failure
(or corrupted mask) fell back to the manual crop path silently, matching
the reported symptom exactly.

The fix is a defensive deep copy — `EdgeSAMSegmenter.copied(_:)` — made
at the moment the embedding is cached, so the adapter owns memory Core ML
never touches again. **This is a well-reasoned hypothesis, not a verified
root cause**: this environment cannot execute Core ML code, so the fix
could not be confirmed against the real failure. It is paired,
deliberately, with an explicit on-screen failure notice (v0.4 Slice 2.1
Goal C — see `OutfitPhotoSessionView+Segmentation.swift`) as defense in
depth: even if this hypothesis turns out to be wrong or incomplete, a
future segmentation failure will surface as a visible message rather than
silently reading as "the AI feature isn't there."

## Regression: the deep-copy strides bug (v0.4 Slice 2.1 repair)

Real-device testing after the fix above shipped found a *new*, worse
failure: mask conversion now failed outright — `"RIG could not convert
that mask back onto the photo"` — on the very first garment of a session,
before any refinement interaction. Since `EdgeSAMMaskConversion.swift`
itself was untouched by that commit, and the failure reproduced on the
first garment (so `OutfitEmbeddingSession`'s encode-once/decode-many
reuse across *garments* cannot be the cause — only one encode and one
decode had run at all), the regression had to be in what the deep-copy
fix itself changed: `EdgeSAMSegmenter.copied(_:)`.

That function copied `array.count` `Float32` elements from
`array.dataPointer` in a single flat linear pass — which silently assumes
`array`'s own backing memory is laid out contiguously (row-major) for its
declared shape. **Core ML does not guarantee that for an output
`MLMultiArray`.** Outputs computed on the Neural Engine in particular are
commonly padded per dimension for alignment, meaning `array.strides` can
legitimately differ from the shape's default contiguous strides. Before
this fix existed, the encoder's raw output object was handed directly
into the decoder's `MLDictionaryFeatureProvider` input — Core ML reads
its own `MLMultiArray` via its declared strides internally, so a
non-contiguous buffer was never a problem. The deep copy introduced a
second place reading that same buffer, this time by hand, and did so
without consulting `strides` at all: on a device where the encoder's
`image_embeddings` output is not contiguous, this reads (and therefore
copies) the wrong bytes for every row after the first, corrupting the
cached embedding before the very first decode ever runs. This is a
distinct failure from the one-garment-only bug the deep copy was written
to fix — it is entirely plausible both were real: the original reference-
caching bug on encode #2+, and this stride-blind copy corrupting encode
#1's result outright once introduced.

The same unchecked-contiguity assumption was already present, independent
of the deep copy, in `EdgeSAMMaskConversion.convert`'s reads of the
decoder's own `masks` and `scores` outputs (`scores.dataPointer... `,
`masks.dataPointer...`) — both are Core ML *output* arrays too, and nothing
about them is any more guaranteed to be contiguous than the encoder's
output. This was flagged as a suspect during the repair investigation and
fixed at the same time, on the reasoning that it is the identical bug
pattern sitting on the exact same "decoder output → selected mask plane"
step of the pipeline, even though `EdgeSAMMaskConversion.swift` had not
been touched by the Slice 2.1 commit that introduced the encoder-side
version of this bug.

**The fix**: `EdgeSAMGeometry.reorderToContiguous` (pure, no Core ML
import, exercised directly by `Tests/EdgeSAMGeometryTests.swift` with
synthetic padded buffers) walks a possibly-strided buffer by its own
multi-dimensional index and re-lays it out row-major; the common
contiguous case is fast-pathed with a single copy. `EdgeSAMMultiArraySupport
.floatElements(of:)` is the one place in the adapter that binds a Core ML
output array's `dataPointer` and hands it to that function — both
`EdgeSAMSegmenter.copied(_:)` and `EdgeSAMMaskConversion.convert` now read
every output array through it, so "always honour `strides`" is a fact
about the adapter rather than a rule each call site has to separately
remember.

**This is, again, a well-reasoned hypothesis, not a verified root
cause** — this environment cannot execute Core ML code, and non-
contiguous Neural Engine output strides could not be directly observed
without running on the real device. It is the most defensible explanation
given: (a) the exact symptom (first-garment, hard failure, appeared only
after the deep-copy commit), (b) `EdgeSAMMaskConversion.swift` being
provably unchanged, narrowing the cause to what that commit actually
touched, and (c) non-contiguous Core ML output strides being a
well-documented, real phenomenon rather than a speculative one. As
before, this is paired with — not a replacement for — the explicit
on-screen failure notice (Goal C): if this hypothesis is also incomplete,
the failure still surfaces visibly rather than silently.

## Known limitation

Whether this specific export was produced with `--use-stability-score`
(which would make `scores` a stability score rather than a predicted IoU)
could not be determined from the artifact alone without running the MIL
program body through a full interpreter — both are "higher is better"
quality signals and `qualityScore` is treated identically either way, so
this does not affect the adapter's behaviour, but it is recorded here as
an open question rather than asserted either way.

## License

EdgeSAM is distributed under the **S-Lab License 1.0**, a non-commercial
license. The verbatim text is bundled at
`Sources/Resources/Models/EdgeSAM-NOTICE/LICENSE.txt` and must ship with
the app. See `docs/DECISIONS.md`, "EdgeSAM and the Core ML exception
(v0.4)", for the product decision this implies: RIG remains a free,
non-commercial personal app for as long as this model is bundled.
