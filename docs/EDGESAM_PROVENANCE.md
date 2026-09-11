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
