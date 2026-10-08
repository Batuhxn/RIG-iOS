# RiG v0.3 Auto Metadata — status report

Date: 8 October 2026. Branch `feat/v0.3-auto-metadata-fashionclip` on Batuhxn/RIG-iOS
(no PR, `main` untouched). Built by Claude (lead) on Codex's scaffold (`e6cd4bd`,
`c9198d8`). Codex reviewed twice; all of its findings were fixed. Product decisions came
from ChatGPT acting for Batuhan.

## Status

**Remote-verifiable work is done.** Only measurements that need Batuhan's physical
iPhone remain, plus the TestFlight upload itself.

- The real Core ML runtime was validated on GitHub macOS runners against the fp32
  reference, at product-decision level.
- The model is published as Release `automd-model-v1`: the exact bytes that passed
  the gate. It is fetched and SHA-256 verified at build time; Release builds fail
  without it.
- End to end, the app's own Swift pipeline ran with the fetched model in the
  simulator on 311 labelled items: 0 value flips against Python Core ML.
- The Xcode build and the full XCTest suite are green.

## What the user experiences

Photo → background removal → analysis (model prewarmed when Add Item opens) → the
form opens prefilled with a one-line summary such as "Skirt · Mini · Black" and an
auto-name ("Black mini skirt"). Season defaults to All year. When the kind is
uncertain: "Is it [Skirt] [Shorts]". Every field stays editable. A typed name is
never overwritten. There is no confidence number and no confirmation screen.
Without the model (development builds) the form is simply manual.

## How it works

- `GarmentSemanticClassifying` / `GarmentMetadataAnalyzing`: the UI never sees the model.
- `CoreMLGarmentClassifier` (actor, loads once): white letterbox 224 → FashionCLIP 2.0
  image tower (Core ML NN, 8-bit weights, 88.8 MB) → embedding.
- `GarmentEmbeddingDecision` (Foundation-only): a softmax over prompt-ensemble text
  vectors. Category = sum over its kinds. Prefill at ≥ 0.7, else abstain. Uncertain
  kinds offer their top 2.
- Colour comes from the same embedding. Black/navy, white/beige and black/gray need
  ≥ 0.95. Pixels supply a secondary colour only when they agree with the primary.
- Prompts are versioned separately (`promptsID`). `modelID` must equal the encoder's
  `rigModelID` or the classifier refuses to run.

## Measured accuracy (precision / recall of what is prefilled)

| Split | Category | Kind | Length | Colour |
|---|---|---|---|---|
| Catalogue, 294 verified Polyvore cutouts | 99.3 / 97.6 | 96.5 / 89.4 | 93.0 / 79.1 | 96.3 / 81.4 |
| Phone, 17 CC0 photos | 100 / 94 | 100 / 80 | — | 100 / 64 |
| Realistic, 218 CC0 amateur photos (verified) | 99.5 / 96.8 | 95.1 / 87.6 | 100 / 67 | 90.1 / 56.1 |
| Realistic hard subset (40) | 39/40 | 19/20 | — | 14/17 |
| Swift app in simulator, catalogue (CI e2e) | 99.0 | 95.7 | 94.9 | 96.4 |

Targets: category ≥ 90% and kind ≥ 80% are met on every split. Colour ≥ 95% is met
on catalogue photos. On amateur photos colour reaches 90% precision. The remaining
gap is mostly black vs navy under cool indoor light, and the ambiguous-pair rule
leaves those cases for the user (a product decision).

## Gates and where they run

| Gate | Result |
|---|---|
| Core ML runtime parity (`automd-coreml-parity.yml`, macOS 15) | nn-fp32 identical to torch (cos 1.000). nn-int8: 0 prefill value flips, cos median 0.9954 / p5 0.9932 / min 0.9912, precision drop ≤ 0.74 pp. mlprogram-int8 rejected (one wrong category on a phone photo). |
| Publish gated bytes (`automd-publish-model.yml`) | `automd-model-v1`; refuses an existing tag or Release; atomic tag creation |
| Swift end to end with the fetched model (`automd-e2e.yml`) | 0 value flips, worst precision drop 0.77 pp, complete coverage enforced |
| Release-configuration packaging | encoder, prompts and acknowledgements in the app; MODEL_LOCK.json kept out |
| Gate A (Xcode build + XCTest) | green (run as part of e2e) |
| Swift = Python decision logic (WSL Swift 6.3) | exact on 529 embeddings |
| Static audit | allows only the pinned, untracked model file |

## Proxy performance (not iPhone)

- Core ML on a CPU-only macOS VM: p50 275 ms, p95 300 ms.
- Swift `analyze()` in the simulator: cold 1.4 s (now hidden by prewarm), warm p50 385 ms.
- Simulator memory: see the e2e annotation "simulator memory proxy".

The iPhone has a Neural Engine; these numbers say nothing reliable about it.

## Privacy and licences

- Everything runs on device; the static audit forbids networking APIs in app sources.
  The model is fetched at build time, never at run time.
- FashionCLIP weights and code are MIT. The training-data provenance (Farfetch, and
  the LAION base model) is reviewed in `docs/FASHIONCLIP_LEGAL_RISK.md`: one item is
  rated *unresolved* and none a *blocker*. The measured alternative (FashionCLIP 1.0)
  is clearly worse.
- MIT notices ship in iOS Settings → RIG → Acknowledgements (tested).

## Open items

1. **Needs Batuhan's iPhone:** real-device p50/p95, peak memory, thermal behaviour,
   Vision cutout quality on his wardrobe, 30+ of his own photos.
2. **Before merging:** remove the temporary branch push triggers in
   `automd-coreml-parity.yml` and `automd-e2e.yml` (manual dispatch stays).
3. **TestFlight:** `scripts/release_testflight.sh` now requires the pinned model; the
   rest of the release flow is unchanged.
4. **Later (not v0.3):** colour beyond 90% on amateur photos needs a dedicated colour
   head or fine-tune. Strings are English on `main`; the Turkish pass lives on
   `design/nocturne-ios`.
