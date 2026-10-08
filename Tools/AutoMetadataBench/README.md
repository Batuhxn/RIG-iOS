# AutoMetadataBench — RiG v0.3 Auto Metadata

Offline benchmark and model export for RiG's "Zero-Friction Garment Intake".
Runs on Windows CPU. Not part of the app. Owner: Claude (lead), 2026-10-08.

## Bottom line

| Field (prefill at gate 0.7) | Catalogue: precision / recall (n) | Phone photos: precision / recall (n) | Target |
|---|---|---|---|
| Category | **99.3% / 97.6%** (294) | 100% / 94% (17) | ≥ 90% |
| Kind (subtype) | **96.4% / 88.3%** (274) | 92% / 80% (15) | ≥ 80% |
| Length (skirt, dress) | 93.1% / 80.6% (67) | n/a | — |
| Primary colour | **96.2% / 89.4%** (226) | 89% / 73% (11) | ≥ 95% |
| Top-2 kinds shown when unsure | contain truth 18/19 | 0/1 | — |

Model: FashionCLIP (MIT) image tower, 8-bit weights, **88.8 MB** Core ML
(`artifacts/RIGGarmentEncoder.mlmodel`), plus a 263 KB prompt manifest. No text
encoder ships. CPU (Windows) p50 ≈ 45 ms/image; **iPhone latency not measured**.

What the original Codex design would have done on the same data (CLIP B/32,
one prompt per label, raw-cosine min 0.2 / margin 0.025): category 34%, kind 16%
prefilled-and-correct, because it abstained on almost everything. Top-1 without
thresholds was 82% / 63%.

## Key findings

1. **The decision rule mattered more than the model.** A flat softmax (logit
   scale 100) over all `category/kind` labels with prompt ensembles (5 templates ×
   3–6 synonyms), category probability = sum over its kinds, beat hierarchical
   raw-cosine margins on every model: B/32 cat 91.5%, B/16 95.9%, FashionCLIP 98.6%
   (top-1, catalogue).
2. **FashionCLIP > CLIP** for fashion: kind 92.7% vs 79.6% (B/32) / 83.9% (B/16);
   length 89% vs 55–59%. Same ViT-B/32 size as B/32.
3. **Pixel colour fails on real photos.** Lab k-means v2: 90% on catalogue apparel
   but 36% on phone photos; Codex HSV 72% / 55%. White tees under indoor light read
   as grey. **Colour from the same embedding** (precomputed colour prompts, zero
   extra inference): 93% catalogue, 82% phone; 96% precision at 92% coverage when
   gated. Pixels now only supply a secondary colour that agrees.
4. **8-bit parity holds** (simulated weight-only per-channel int8 on linear/conv,
   matching the exported file): category identical, kind +0.4 pp, 7/311 predictions
   flip only between suggest/abstain, no new wrong answers.
5. **Labels from product titles are noisy**: ~1/3 of 300 needed correction or were
   ambiguous on visual review (`data/review_overrides.json`). Genuinely ambiguous
   pairs: shirt/blouse, heels/heeled sandals/heeled boots, sweater/sweatshirt,
   cream→white/beige, black/navy in shadow, camel→beige/brown.
6. **Shoes colour**: insoles/footbeds dominate pixels (pixel 72%). Embedding helps.
   Metallic is never guessed from pixels.

## Honest limits

- Catalogue set is Polyvore product cutouts — in-domain for FashionCLIP (trained on
  Farfetch catalogue). Phone set is only 17 CC0 photos with BEN2 masks (not Apple
  Vision). **Before shipping: ≥ 30 real iPhone wardrobe photos through the app.**
- Prompts were written before measuring; generic colour prompts were chosen over
  subtype-conditioned ones after measuring both (small selection effect).
- Thresholds (0.7) were picked on this data; no separate held-out split for
  classification. Colour Lab tuning used even/odd split (tune 86.0% / held-out 86.9%).
- **Unverified:** Core ML runtime parity of the exported `.mlmodel` (needs macOS),
  iPhone latency/memory/cold load, Xcode compile of SwiftUI (Gate A run pending).
- Licence: weights tagged MIT; base is LAION CLIP B/32, fine-tuned on Farfetch
  product data. Training-data provenance not independently reviewed.

## Reproduce

```powershell
$py = "..\FashionMLSpike\.venv\Scripts\python.exe"; $env:HF_HOME = ".cache\hf"
& $py scripts\index_polyvore.py            # text-only range reads, 251k items
& $py scripts\select_items.py 12 data/data-00000-of-00005.parquet
& $py scripts\fetch_images.py               # 300 images, ~370 MB range read
& $py scripts\contact_sheet.py              # visual review -> data/review_overrides.json
cd scripts
& $py bench.py clip-b32 clip-b16 fashion-clip           # RIG_BENCH_SET=catalog|real|all
& $py color_eval.py; & $py color_embed.py fashion-clip
& $py int8_parity.py fashion-clip
& $py export_fashionclip.py                 # artifacts/: .mlmodel, prompts, validation
& $py dump_parity.py                        # swift-check fixtures + app-exact metrics
wsl -d Ubuntu-24.04 -- bash -lc "cd .../swift-check && bash sync.sh && swift test"
```

## App integration (branch `feat/v0.3-auto-metadata-fashionclip`, pushed, no PR)

On top of Codex's `feat/v0.3-auto-metadata-main` (e6cd4bd, c9198d8, 62c47f1, 24651c4):

- `7d6e347` `GarmentEmbeddingDecision` (Foundation-only), manifest v2, embedding
  colour, top-2 alternatives. Swift = Python on all 311 embeddings.
- `0d8ddd2` auto-name ("Black mini skirt", never overwrites typed text), season
  defaults to all year and never blocks Save, summary line "Skirt · Mini · Black",
  one-tap "Is it [Skirt] [Shorts]".
- `18117ab` model outside git: `Resources/Models/MODEL_LOCK.json` pins SHA-256
  `b2cbfb44…8dfa`; `scripts/fetch_metadata_model.sh` fails the build on mismatch;
  static audit allows only that untracked file. DECISIONS.md updated.
- `e402423`, `987117f` TEMPORARY: Gate A runs on pushes to this branch and echoes
  failures as public annotations. **Revert both before merge.**
- `172ca28` fix (Codex code): `try await model.prediction(from:)`. iOS 17 SDK picks
  the async overload in an async context; the app did not compile without it.
- `d7e1c35` fix (Codex test): explicit `[UInt8]`; `flatMap` inferred `[Any]`.

**Gate A (Xcode, simulator, full XCTest): PASS**, run 37702086288 on `55452ef`
(same tree as `d7e1c35` except line endings). CI has no model file, so
classifier paths run model-absent; the device benchmark test skips by design.

Product decisions (ChatGPT as Batuhan's proxy, 2026-10-08): bundle 8-bit if parity
holds (it did); model delivery local-only now, versioned GitHub Release asset with
pinned SHA before TestFlight, no LFS; auto-name yes; season not required.

## Next actions

1. DONE. Codex reviewed `d7e1c35` (read-only). 4 findings were applied in `339ba9c`:
   release fails without the model, colour abstention is final, stale alternatives
   are cleared, length trims the kind. Gate A passed again (run 37710140439).
   The temporary CI was removed in `0223a61`; the workflow is byte-identical to the
   original. (Codex's cleanup patch garbled em dashes; I restored from git instead.)
2. On a Mac: `python scripts/validate_coreml_parity_macos.py` (Core ML runtime vs
   fp32 torch on 311 cutouts; gates median cosine ≥ 0.995, min ≥ 0.98, ≤ 3% decision
   changes). Then iPhone p50/p95, cold load, memory via `AutoMetadataBenchmarkTests`
   with `RIG_METADATA_FIXTURES=device-fixtures/manifest.json` (311 cutouts, 20.8 MB).
3. ≥ 30 real iPhone wardrobe photos through the same test.
4. Publish the model as a versioned Release asset, pin `url` in MODEL_LOCK.json.
5. Turkish strings for the new UI when merging with `design/nocturne-ios`.
6. Open a PR only when Batuhan/ChatGPT asks (branch head `0223a61`).
