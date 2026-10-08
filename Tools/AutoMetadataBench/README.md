# AutoMetadataBench — RiG v0.3 Auto Metadata

Offline benchmark, model export and CI checks for "Zero-Friction Garment Intake".
Not part of the app. Third-party images are never committed; they are fetched
from their pinned sources. Only labels, selections and the 17 CC0 photos are in git.

## Current result (app-exact decision, gate 0.7, FashionCLIP 2.0 nn-int8)

Precision / recall of what the form prefills, on visually verified labels:

| Split | Category | Kind | Length | Colour |
|---|---|---|---|---|
| Catalogue: Polyvore cutouts (294) | 99.3% / 97.6% | 96.5% / 89.4% | 93.0% / 79.1% | 96.3% / 81.4% |
| Phone: CC0, BEN2 masks (17) | 100% / 94% | 100% / 80% | — | 100% / 64% |
| Realistic: CC0 amateur photos (218) | 99.5% / 96.8% | 95.1% / 87.6% | 100% / 67% | 90.1% / 56.1% |

The realistic hard subset (40 items: dim light, mask leaks, navy/black, top vs
dress) is reported by `compare_models.py`.

## What runs where

| Check | Where | Script / workflow | Last result |
|---|---|---|---|
| Core ML runtime parity, 4 variants | GitHub macOS 15 (free) | `ci_parity.py`, `automd-coreml-parity.yml` | nn-fp32 exact (cos 1.000); nn-int8 0 value flips, cos p5 0.9932 |
| Publish gated bytes as a Release | GitHub macOS 15 | `automd-publish-model.yml` (manual) | `automd-model-v1` |
| Swift pipeline with the fetched model, simulator | GitHub macOS 15 | `e2e.py`, `automd-e2e.yml` | 311 items, 0 value flips vs Python Core ML |
| Decision logic, Swift vs Python | WSL Swift 6.3 | `swift-check` (local) | exact on 529 embeddings |
| Benchmarks and experiments | Windows CPU | `bench.py`, `compare_models.py`, `color_experiments.py`, `prompt_experiments.py` | see table above |

Proxy latency (**not iPhone**): Core ML on a CPU-only macOS VM had p50 275 ms;
the Swift `analyze()` in the simulator had cold 1.3 s and warm p50 463 ms. Real-device
p50/p95, memory and thermals need Batuhan's iPhone.

## Decisions recorded by measurement

- FashionCLIP 2.0 over CLIP B/32 and B/16, and over FashionCLIP 1.0 (see
  `docs/FASHIONCLIP_LEGAL_RISK.md`).
- Flat softmax over `category/kind` with prompt ensembles, instead of per-level
  cosine margins (34% → 99% category prefill precision).
- Colour from the embedding, not pixels (36–55% on phone photos with pixels).
  Black/navy, white/beige and black/gray need ≥ 0.95.
- nn-int8 over mlprogram-int8 (the latter made a wrong category on a phone photo).
- Gemini round 1: synonym changes adopted; hard negatives and letterbox/padding
  changes rejected (`data/gemini_round1.md`).

## Reproduce locally (Windows)

Use any Python 3.12 venv with `torch==2.5.0 transformers==4.48.3 coremltools==8.3.0
pillow numpy pyarrow`, and set `HF_HOME` to a cache directory.

```
python scripts/fetch_images.py                  # Polyvore subset (pinned revision)
python scripts/fetch_cc0.py                     # CC0 sample (alexeygrigorev/clothing-dataset)
python scripts/cutout_cc0.py                    # BEN2 masks: evaluation stand-in, never shipped
python scripts/cc0_labels.py                    # writes data/cc0_labels.json
python scripts/compare_models.py fashion-clip --sets=catalog,real,cc0
python scripts/build_prompts.py                 # Resources/Models/RIGGarmentPrompts.json
```
