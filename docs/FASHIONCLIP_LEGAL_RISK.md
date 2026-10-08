# FashionCLIP — licence and provenance risk review

Engineering review, 2026-10-08. **Not legal advice.** It records what primary sources
say, separates licence from provenance, and states what is unresolved. A lawyer
should confirm anything marked *unresolved* before a commercial launch.

Shipped artefact: FashionCLIP 2.0 image tower only (`patrickjohncyh/fashion-clip`
@ `7e3ba62ce16b`), converted to Core ML, 8-bit weights. No text encoder and no
training data ship. Inference is on-device; no image leaves the phone.

| Area | Finding | Rating |
|---|---|---|
| A. Code licence | MIT, "Copyright (c) 2023 Patrick John Chia" ([LICENSE](https://github.com/patrickjohncyh/fashion-clip/blob/master/LICENSE)). RiG does not ship this code; the exporter is our own. | **Clear** |
| B. Weight licence | Model card front matter `license: mit` ([HF card](https://huggingface.co/patrickjohncyh/fashion-clip)). The paper says checkpoints are released "under an open-source license" ([arXiv 2204.03972](https://arxiv.org/abs/2204.03972)). MIT requires keeping the copyright and permission notice in copies. | **Acceptable with note**: ship the MIT notice in the app's acknowledgements. |
| C1. Fine-tuning data (Farfetch) | About 700k Farfetch catalogue image/text pairs. The paper: "Farfetch made available for the first time" the dataset. Two authors are Farfetch employees (Porto). The data itself is not public ("awaiting official release"). The data owner took part in the work that released the weights. | **Acceptable with note**: no public dataset licence, but released with the data owner's participation. |
| C2. Base model (LAION) | FashionCLIP 2.0 is fine-tuned from `laion/CLIP-ViT-B-32-laion2B-s34B-b79K` (MIT). That card says "Any deployed use case of the model … is currently out of scope" and that LAION-5B is not recommended for "ready-to-go industrial products" ([card](https://huggingface.co/laion/CLIP-ViT-B-32-laion2B-s34B-b79K)). This is guidance, not a licence term. LAION-5B is web-scraped. In Dec 2023 the Stanford Internet Observatory found suspected CSAM links in it; LAION withdrew it and released Re-LAION-5B in Aug 2024 ([LAION](https://laion.ai/blog/relaion-5b/)). In Germany, *Kneschke v. LAION* found the dataset's creation lawful under the TDM/research exceptions (LG Hamburg 27 Sep 2024; OLG Hamburg 10 Dec 2025, [Bird & Bird](https://cm.twobirds.com/en/insights/2025/germany/higher-regional-court-hamburg-confirms-ai-training-was-permitted-(kneschke-v,-d-,-laion)); further appeal reportedly pending). That case concerns building the dataset, not distributing a model trained on it. | **Unresolved** (reputational and jurisdiction-dependent; not a licence breach) |
| D. Trademarks | "FashionCLIP", "Farfetch", "CLIP" and "LAION" are third-party names. RiG must not use them in marketing or imply endorsement. Naming them in the acknowledgements is fine. The model can read logos ("nike air") but RiG's taxonomy has no brand output. | **Clear** if the names stay out of marketing |
| E. App Store / commercial | MIT permits commercial redistribution, with attribution. No App Store guideline forbids bundling an MIT model. Processing is on-device, so there is no data-transfer disclosure. Size (~89 MB) is product cost, not legal. | **Acceptable with note** (add attribution) |

## What would reduce the unresolved item (C2)

1. **FashionCLIP 1.0** (`@ff0d54f09aad`, before the LAION switch) was fine-tuned from
   OpenAI CLIP ViT-B/32 (MIT). OpenAI trained on its own collected web data, which
   carries its own undisclosed-provenance question, but there is no LAION-5B
   lineage. Accuracy on our benchmark: see *Measured alternative* below.
2. OpenAI CLIP B/32 without fashion fine-tuning: measured earlier as much worse
   (kind 79.6% vs 92.7%).
3. A RiG-owned fine-tune on licensed data. Out of scope for v0.3.

## Measured alternative

Same prompts, the app's exact decision rule (gate 0.7), each model with its own text
vectors (`Tools/AutoMetadataBench`, 2026-10-08). Precision / recall of prefilled values:

| Field | 2.0 (LAION base, shipped) catalogue | 1.0 (OpenAI base) catalogue | 2.0 phone | 1.0 phone |
|---|---|---|---|---|
| Category | 99.3% / 97.6% | 95.6% / 89.1% | 100% / 94% | 100% / 82% |
| Kind | 96.4% / 88.3% | 89.7% / 73.0% | 92% / 80% | 80% / 53% |
| Length | 93.1% / 80.6% | 90.6% / 43.3% | — | — |
| Colour | 96.2% / 89.4% | 92.8% / 73.9% | 89% / 73% | 86% / 55% |

On 218 visually labelled CC0 amateur photos, 1.0 is again worse: category
precision 96.1% vs 99.5%, kind 82.8% vs 95.0%, colour 73.6% vs 83.0% (before the
ambiguous-pair rule).

Moving off the LAION lineage costs about 4–7 points of precision and 15–37 points of
recall. It would miss the kind ≥ 80% product target on phone photos, and wrong
prefills would roughly double. Recommendation: keep 2.0 with the C2 note unless a
lawyer rates C2 a blocker. In that case the clean path is a RiG-owned fine-tune
(item 3), not 1.0.

## Required actions before TestFlight

- [ ] MIT notice for FashionCLIP (and the CLIP lineage) in an in-app Acknowledgements screen / `THIRD_PARTY_NOTICES`.
- [ ] Keep model names out of marketing copy.
- [ ] Product/legal decision on C2: accept FashionCLIP 2.0 with this note, or switch to 1.0 if the measured cost is small.
