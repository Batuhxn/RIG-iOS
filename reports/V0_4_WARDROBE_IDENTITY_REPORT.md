# v0.4 Duplicate Garment Detection + Wardrobe Identity

## What ships

- Each garment stores its identity: the unit-length v0.3 FashionCLIP image vector
  (512 Float32) and the ID of the model that made it (`ClothingItem.visualEmbedding`,
  `visualEmbeddingModelID`). Identities from different models are never compared.
- Adding a garment checks it against garments of the same category. At most one
  suggestion is shown, and only when cosine ≥ 0.93. The sheet shows both photos and
  two buttons, "Same item" and "Add as new", with no score.
- The Vision feature-print matcher is deleted. No second model, nothing paid, no
  photo leaves the device.
- Older garments without a current identity (saved before v0.4, or under another
  encoder) are embedded the first time a check needs them, and the identity is then
  stored on the garment (lazy backfill). A failed save is rolled back and never blocks
  adding the garment.

## Threshold: 0.93, provisional

ChatGPT approved this on 2026-10-08 as the provisional production threshold. It will be
reopened after the iPhone multi-view test. Cutouts are cropped to the garment, as the
app stores them.

| cosine | synthetic re-captures found / false prompt | real same item found | real look-alike prompted |
|---|---|---|---|
| 0.89 | 71% / 0.5% | 14/14 | 57/68 |
| 0.91 | 62% / 0% | 14/14 | 44/68 |
| 0.92 | 56% / 0% | 13/14 | 29/68 |
| **0.93** | **47% / 0%** | **10/14** | **13/68** |
| 0.94 | 35% / 0% | 7/14 | 4/68 |
| 0.95 | 23% / 0% | 6/14 | 0/68 |

- **Synthetic re-captures.** 217 CC0 garments, each with 2 augmented re-shots
  (rotation, shear, scale, edge occlusion, white balance, exposure, blur, JPEG). Run with `automd-dup-bench.yml` on a GitHub macOS
  runner, with real Apple Vision cutouts. A false prompt here means a garment's hardest
  same-category neighbour in the gallery scores ≥ t. Feature-print was worse at every
  operating point; its shipped 0.75 cutoff would prompt on about 52% of new garments.
- **Real multi-view and real look-alikes.** I took the 120 most similar cross-photo
  pairs among 4,656 CC0 photos and labelled them by hand
  (`Tools/AutoMetadataBench/data/real_pairs.json`):
  - 14 show the same garment in different photos;
  - 4 are burst shots (cosine 0.94–0.99, reported apart);
  - 68 are different garments that look alike, mostly one seller's near-identical
    shirts and jeans photographed on the same bed;
  - 34 are unsure and excluded.

  The cutouts were made with BEN2, an evaluation-only stand-in for Vision.
  `scripts/real_pairs.py` reproduces the numbers.

## Findings

- The global embedding cannot separate near-twin garments. Real same-item pairs score
  0.91–0.98 and real look-alikes score up to 0.95 (AUC 0.88). Two second stages on the
  same encoder did not help: tile-by-tile embeddings (AUC 0.78–0.88) and a mask colour
  histogram (AUC 0.61). So there is no second stage.
- The look-alike pairs are the extreme tail: 68 of about 10.8 million pairs. The rate a
  user sees is roughly P(the wardrobe already holds a near-twin) × P(the twin scores
  ≥ 0.93). People with several similar white shirts or jeans will still see occasional
  prompts. A false prompt costs one tap; a miss costs a duplicate item.
- The real positives are few (n = 14) and come from one session per seller, with the same
  light and camera. They are probably easier than a user re-photographing a garment
  months later, which is what the synthetic split approximates.

## Open

- iPhone multi-view gate: 20+ of Batuhan's own garments photographed twice on different
  days, plus his own look-alike items, to confirm 0.93 before it stops being provisional.

## Codex review (closed 2026-10-09)

The three P2 findings are fixed in `7be0db8`, and CI run 37858049418 passed:

- A truncated stored identity is no longer treated as current. Identities must
  match the encoder's dimension, and wrong-length vectors are re-embedded.
- Matching always uses the identity image (the cutout, or the original when
  there is none). The Original/Cutout choice only affects what the review sheet
  shows.
- The backfill writes through its own ModelContext, so it never commits or
  rolls back another screen's pending edits.

Codex re-reviewed the fixes and found them correct. Its follow-up check is now
an Apple-runtime test: the container's main context sees a backfilled identity
on its already-loaded object and keeps it through its own later save. CI run
37874276234 passed it (`8da9c8e`).

The temporary push triggers are removed. Both workflows are manual dispatch only.
