# v0.5 Avatar Lab — overnight report (2026-10-09)

Branch `feat/v0.5-avatar-lab`, cut from `main` at `2b0013f`. Not merged, no PR,
nothing spent. Design and limitations: `docs/AVATAR_LAB.md`.

## What works (verified)

| Claim | Evidence |
|---|---|
| The app builds with the Avatar tab | Avatar Lab CI (GitHub `macos-15`, Xcode 16.4): runs 37848282999 and 37849262651 green |
| Every existing RIG test still passes | the same run executes the full `RIGTests` suite via `scripts/validate_macos.sh` |
| The asset loads and carries every target the controls need | `AvatarLabTests.testBundledAssetLoadsWithEveryTargetTheControlsNeed` |
| Hips change hips only, shoulders change shoulders only (≤ 1 mm elsewhere) | `testHipsChangeHipsOnlyAndShouldersChangeShouldersOnly` |
| Every control is visible and stays human-sized (1.40–1.95 m) at both limits | `testEveryControlVisiblyChangesTheBodyAndStaysCoherentAtItsLimits` |
| All 11 garment cuts produce shells with valid UVs; long sleeves reach further; trousers reach lower | `testEveryGarmentCutProducesAShellOutsideTheSkin` |
| Trousers and skirt widen with the hips | `testGarmentsFollowTheBodyShape` |
| Profile: clamp, NaN, unknown keys, corrupt file, save/reload/delete | `testValuesAreClamped…`, `testProfileRoundTrips…`, `testProfileStoreSavesReloadsAndDeletes` |
| Simulator render: body drawn, wider hips visible in pixels, side ≠ front | `AvatarRenderingTests.testAvatarRendersAndMorphsAreVisible` |
| Simulator render: garment photo appears on the body; colour mode draws none | `testGarmentPhotoIsDrawnOnTheBody` |
| Corrupt or truncated asset is rejected, not a crash | `testCorruptAssetsAreRejectedNotCrashed` |

Foundation-only tests also run on Linux (Swift 6.3, WSL): 12/12 pass.

Simulator renders from run 37849262651 (`reports/avatar_lab/ci_simulator_renders.jpg`):

- top row: neutral front, side, wider hips, the striped test photo on a tee,
  trousers and shoes, and its side view;
- bottom row: a dress on a curvier shape, then one outfit in 2D, 3D photo,
  3D colour and 3D turned.

The 2D image in that run draws the trousers over the tee. That was a fault in
the test's compositing (the app draws in layer order) and is now fixed.

## Measurements (not iPhone)

| What | Where | Result |
|---|---|---|
| Asset load (2.1 MB) | iOS simulator, debug | 257 / 420 ms (two runs) |
| Body + 3 garments, one update | iOS simulator, debug | 189 / 309 ms (two runs) |
| Body + 2 garments, one update | Linux x86, debug / release | 46–59 ms / **4 ms** |

TestFlight builds are release builds; the debug numbers are the unoptimised
upper bound. Physical-iPhone frame time, memory and thermals are **not measured**.

## Decisions taken tonight

- **Foundation: MakeHuman CC0 assets.** Only data is used, no code (MakeHuman is
  AGPL, MPFB2 GPL). Provenance and hashes: `Support/Avatar/NOTICE.md`,
  `Tools/AvatarAssets/SOURCES.lock.json`.
- **Renderer: SceneKit behind `AvatarMesh`.** The only built-in option with
  dynamic meshes on iOS 17. RealityKit's blend-shape APIs need iOS 18.
- **Garments: MakeHuman's helper tights and skirt**, cut by landmarks. Two
  additions: a skin guard (no poke-through) and a drape (tops hang from the
  chest).
- **Product (ChatGPT):** "Silhouette 1/2/3" with thumbnails; no Frame control;
  mannequin body; 2D overlay by default, 3D photo optional; separate tab for now.
- **Adversarial review (Gemini):**
  - Accepted: 3D photo projection smears at the sides and looks "painted on";
    the anatomical mesh needed a mannequin form.
  - Not adopted tonight: GPU morphing with `SCNMorpher` (the release CPU path is
    4 ms) and authored loose garment meshes (a larger asset task).

## Not done / open

- v0.4 Codex review findings (truncated identity, original-vs-cutout identity
  image, backfill rollback scope) are recorded in
  `AutoMetadataBench/codex_v04_review.md` and deliberately not patched overnight.
- The garment cut comes from category and subtype keywords. v0.3 auto metadata
  (kind and length) is on another branch.
- No real wardrobe photo has been seen on the avatar: CI uses synthetic cutouts.
  An iPhone run with Batuhan's garments is the real test.
- The `avatar-lab.yml` push trigger is TEMPORARY. Remove it before any merge.
