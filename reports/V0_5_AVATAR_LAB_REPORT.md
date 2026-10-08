# v0.5 Avatar Lab — overnight report (2026-10-09)

**Status: experimental prototype.** The avatar works, its shape changes and
it shows garments. The garments are not yet realistic.

Branch `feat/v0.5-avatar-lab`, cut from `main` at `2b0013f`. Not merged, no PR,
nothing spent. Design and limitations: `docs/AVATAR_LAB.md`.

## What works (verified)

| Claim | Evidence |
|---|---|
| The app builds with the Avatar tab | Avatar Lab CI (GitHub `macos-15`, Xcode 16.4): runs 37848282999, 37849262651, 37850482922, 37853004060, 37853966508 green; the final run is listed under "Final state" |
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

## Visual review: does it look worn, or pasted on?

The review grid has four body shapes. Each is shown in the 2D preview and in
the 3D view from the front, three-quarter and side. The garments are a striped
tee with jeans, and a striped dress. Before:
`reports/avatar_lab/review_grid_run37853004060.jpg`. After: the latest run's
grid, `reports/avatar_lab/review_grid_run37855412900_after.jpg`.

- **3D, front and three-quarter: closest to "worn".** Prints wrap the body and
  sleeves sit right. But the garments hug the body like tights, with no volume
  and no drape. The side view used to show flat average-colour patches where the
  cutout was transparent. These are now edge-padded with the nearest garment
  colour. That fixed the tee's sides, but on the striped dress it extends the
  edge stripe into solid blocks of yellow or navy. The fill is still a guess.
- **2D: most faithful to the photo, but plainly a paper doll.** Horizontal
  stripes hold up well. Vertical stripes stair-stepped at the edges until the
  warp moved to 48 smoothed bands. Straight jeans read as wide-leg, because both
  legs and the gap between them are stretched together.
- **3D colour:** clean, but it reads as a painted mannequin, not clothing.

**Verdict:** this is a useful preview of colour and pattern combinations. It
is not yet a convincing "wearing it" view.

## Why the next step is real 3D garment templates (RiG Garment Engine v1)

The tights shell can only ever look sprayed on. It has no volume of its own:
a skirt or dress cannot flare, trousers lose their leg shape, and a tee cannot
hang loose. The direction (ChatGPT, 2026-10-09) is MakeHuman body + independent
morph controls + real garment meshes. No cloth physics, no photoreal fitting.

**How MakeHuman binds clothes (`.mhclo`).** Each vertex of a garment mesh stores:

- the three body vertices of a triangle it is attached to;
- barycentric weights on that triangle;
- an offset from the skin.

When the body morphs, every garment vertex is placed at the weighted point on
its triangle plus the scaled offset. So an authored loose garment follows any
body shape and keeps its own volume. A `delete_verts` list hides the body
vertices the garment covers, which removes poke-through under clothes entirely.
We would implement this binding ourselves; MPFB's GPL code is not used. The
binding data travels with each CC0 garment, or with one we author.

**First targets:**

1. Straight T-shirt (loose torso, short sleeves).
2. Straight trousers (keeps leg shape and hem).
3. A-line skirt (flares from the hips).
4. Simple shift dress.

Each needs a low-poly mesh, its binding to the base mesh, and a UV layout that a
garment photo can be projected into. The photo projection, edge padding and
category → cut mapping built tonight carry over.

**Asset licensing must be checked before any garment ships.** MakeHuman's
bundled system clothes are CC0, like its other core assets. Community clothes
vary (CC-BY, sometimes CC-BY-SA). Only verified-CC0 meshes, or meshes we author,
may enter the app.

## Codex review (read-only, `2b0013f..0e0aa3f`)

Five P2 findings, all fixed in `ec08781`:

1. A corrupt count was allocated before it was checked (~64 GiB). Counts are now
   bounded by the remaining bytes.
2. NaN coordinates passed parsing and then trapped. Non-finite and out-of-range
   values are now rejected.
3. Cancelled refreshes kept computing. The work now runs as child tasks with
   cancellation checks, and slider updates are coalesced.
4. "Delete avatar" reset the screen even when the file stayed. It now resets
   only after a real deletion, and shows an alert otherwise.
5. The current outfit was not restored after relaunch. It now is.

Codex found no data-leaving-device path and no cost risk. The temporary push
trigger was flagged and is removed in the final commit.

## Final state

- Last CI: run 37855412900, green (build, full `RIGTests`, avatar and
  rendering tests). Simulator debug: 315 ms asset load, 238 ms for body plus 3
  garments.
- The workflow is now manual dispatch only. The commit that removed the push
  trigger did not start a run.
- Branch `feat/v0.5-avatar-lab`: not merged, no PR. `main` was not touched.

## Not done / open

- v0.4 Codex review findings (truncated identity, original-vs-cutout identity
  image, backfill rollback scope) are recorded in
  `AutoMetadataBench/codex_v04_review.md` and deliberately not patched overnight.
- The garment cut comes from category and subtype keywords. v0.3 auto metadata
  (kind and length) is on another branch.
- No real wardrobe photo has been seen on the avatar: CI uses synthetic cutouts.
  An iPhone run with Batuhan's garments is the real test.
- The `avatar-lab.yml` push trigger has been removed: the workflow is manual dispatch only.
