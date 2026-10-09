# Garment Engine v1: second-watch report (2026-10-09)

Branch `feat/v0.5-avatar-lab`. Not merged, no PR, no TestFlight, nothing spent.
Design: `docs/AVATAR_LAB.md` ("Garment Engine v1"). Previous night:
`V0_5_AVATAR_LAB_REPORT.md`.

**Status: experimental prototype.** The garments now have volume of their own.
This is still an approximate preview, not a fit or size guide.

## 1. v0.4 technical debt: closed

The three P2 findings from Codex's v0.4 review were fixed in `7be0db8` on
`feat/v0.4-wardrobe-identity`. Xcode CI run 37858049418 passed.

| Finding | Root cause | Fix | Regression test |
|---|---|---|---|
| A truncated identity counted as current | the check compared only the model ID | identities must also have the encoder's dimension; the matcher never compares vectors of different lengths | `testTruncatedStoredIdentityIsReembeddedFromItsPhoto`, `testTruncatedStoredIdentityIsRecomputedAndReported` |
| "Original" was compared against cutout identities | matching used the display choice | matching always uses the identity image (the cutout, or the original when there is none); the choice only changes the review photo | `testImageChoiceDoesNotChangeTheIdentityImage` |
| Backfill could commit or roll back other screens' edits | it saved and rolled back the shared context | it writes through its own `ModelContext` | `testBackfillStoresIdentitiesWithoutCommittingOtherPendingChanges` |

Codex re-reviewed the fixes and found them correct by inspection. It asked for
one more Apple-runtime test: the main context sees the backfilled identity and
keeps it after its own later save. That test is added in `8da9c8e` and passed
in CI run 37874276234. The v0.4 workflows are back to manual dispatch.

## 2. Architecture

| Component | Role |
|---|---|
| `Tools/AvatarAssets/build_garment_templates.py` | Authors four templates offline from the body asset's CC0 helper topology: cut, shape, straighten hems, split panels, bind, list hidden skin |
| `GarmentTemplate` / `GarmentTemplateLibrary` | Versioned binary templates; bounds-checked loader |
| `GarmentDeformer` | Evaluates the binding on the morphed body; 2 Taubin smoothing steps |
| `AvatarOutfitBuilder` | Body minus covered skin, garments in layer order, layer guard; falls back to the old shells for cuts without a template |
| `GarmentPhotoMapping` | Planar u across the front panel; each photo row is read only within its garment pixels |
| `AvatarStageView` | Two materials per garment: the photo on the front panel, the unknown region on the rest; "Approximate back view" label |

The binding is MakeHuman's `.mhclo` idea, implemented independently: a
barycentric point on the nearest body triangle plus an offset in that
triangle's local frame. The rest pose is reproduced to 1e-11 m.

## 3. The four templates

| Template | Shape at rest | Body-morph behaviour (tests) |
|---|---|---|
| Relaxed tee | convexified torso + 22 mm ease, hangs from the chest (slope 0.12); elbow sleeves 16–28 mm ease; straight hem, neckline and sleeve openings | stands >10 mm further off the stomach than the old shell; widens with the shoulders |
| Straight-leg trousers | pelvis + 14 mm ease; below the knee every ring keeps at least the knee's section along the leg axis | two separate leg openings; hem ≥1.4× the bare ankle's width |
| A-line skirt (knee) | 12 mm ease at the hips, flares 0.30 m per metre below them | hem ≥5 cm wider than the hips; widens with the hips |
| Simple dress (knee) | sleeveless bodice (10 mm ease) + A-line skirt (0.22) | at bust +1, waist −1, shoulders +1, overall +1 and legs −0.6: 2.0% of vertices are >5 mm inside the skin, and that skin is hidden under the dress |

Midi lengths, long sleeves, shorts, coats and shoes keep the earlier shells.

## 4. Real garment photos

- **Front panel:** only faces that turn less than ~69° from the camera get the
  photo. Each photo row is read within its own garment pixels, so a
  trapezoid skirt photo no longer drops padding colour onto the panel's edges.
- **Unknown region:** the back, and the sides beyond ~69°, show the fabric's
  dominant colour from the garment's outline, shaded slightly. A
  red-and-white stripe gives red or white (tested), not pink. Nothing is
  mirrored or invented.
- **Label:** in 3D, turning past ~100° shows "Approximate back view"
  (ChatGPT's decision; an optional back photo may come later).

## 5. Visual comparison (failures kept)

All grids in `reports/avatar_lab/` show, left to right: old 2D | old 3D photo |
new front | new three-quarter | new side. Rows are Silhouettes 1–3 and one
extreme body (hips +1, waist −1, bust +1, shoulders +1, overall 0.8).

| File | What it shows |
|---|---|
| `engine_v1_separates_run37859120287.jpg` | first engine run: relaxed tee and straight trousers vs the old shells |
| `engine_v1_skirt_dress_run37859120287_before_mapping.jpg` | skirt flares and the dress keeps its shape; colour blocks at the edges of three-quarter and side views (photo corners) |
| `engine_v1_skirt_dress_run37860027772_rejected_outline_mapping.jpg` | **rejected experiment:** matching the panel's per-row outline made stripes wave |
| `engine_v1_separates_run37874251806_final.jpg`, `engine_v1_skirt_dress_run37874251806_final.jpg` | final: camera-facing photo panel, dominant-colour unknown region, straight hems, smoothing, layer guard |

What improved is the garment volume itself, not the lighting or camera: the
camera, lights and morphs are identical across the columns of a row.

Remaining visible problems:
- Stripes still curve near the front panel's edge at three-quarter views.
- At the extreme body, stripes bend over the bust. Smoothing reduced the
  ripple, but it is not gone.
- The seam between the photo and the unknown region is a visible line.
- Garments still hold the A-pose: no cloth physics.

## 6. Gemini review: measured before adoption

| Claim | Measurement | Decision |
|---|---|---|
| Nearest-triangle binding will bind across limbs (crotch, armpit) | 0 cross-limb bindings across sleeves and both legs, all four templates | not adopted (no defect found) |
| A skirt bound to the legs tears or pinches when the legs change | gap between neighbouring hem points stays 2 cm under thighs +1, legs −0.6, hips +1 and all combined | not adopted |
| The back should use the fabric's mode colour, not the mean | the mean of the striped dress is tan; of the striped tee, pink | **adopted** |
| Photo on glancing faces smears | seen in run 37861422390 at three-quarter views | **adopted** (camera-facing front panel) |
| Scale offsets by local triangle area | Gemini marks it unverified | not tried |

## 7. Codex reviews

- **Engine review** of `02033d8..509653a`: three P2 findings, all fixed in `db33998`.
  1. The tee showed through the coat shell (up to 26 mm). A layer guard now
     keeps outer layers outside inner ones (tested).
  2. Midi cuts were drawn at knee length. Midi now keeps its shell.
  3. The texture cache grew while browsing (~8 MB per garment). It now keeps
     only worn garments.
- Codex probed the library loader with five corrupt inputs: all rejected. It
  found no exposed hidden skin in front views of the neutral and extreme
  shapes.

## 8. Performance (not iPhone)

| What | Where | Result |
|---|---|---|
| Body + tee + trousers + shoes, incl. layer guard | Linux x86, release | 21 ms |
| Same | Linux x86, debug | ~400 ms |
| Body + 3 garments (engine) | iOS simulator, debug (CI) | 82–182 ms before the layer guard, 344 ms with it (run 37874251806) |
| Asset load | iOS simulator, debug (CI) | 0.25–0.42 s |
| Template file | `RIGGarments.rigarm` | 0.32 MB |

Repeated outfit swaps produce identical meshes (tested), and the texture cache
is bounded. Physical-iPhone timing and memory are **not measured**.

## 9. Provenance

`RIGGarments.rigarm` is generated only from `RIGAvatarBody.rigavatar`, which is
built from MakeHuman CC0 assets. No MakeHuman or community clothing asset and
no MPFB or MakeHuman code is used (`Support/Avatar/NOTICE.md`).

## Final state

- **Avatar branch** `feat/v0.5-avatar-lab`: the last verified CI is run
  37874251806, green (build, the full RIGTests suite, avatar, Garment Engine and
  rendering tests). Linux core tests: 27/27. The `avatar-lab` workflow is
  manual dispatch only again.
- **v0.4 branch** `feat/v0.4-wardrobe-identity`: CI run 37874276234 green (XCTest
  plus the Auto Metadata end-to-end checks). Workflows are manual dispatch only.
- Neither branch is merged, no PR, `main` untouched, no TestFlight, 0 TRY.

## Next

1. Try it on an iPhone with real wardrobe photos. All evidence so far uses
   synthetic striped cutouts.
2. Midi templates and long sleeves (the shells still cover them).
3. Soften the seam between the photo and the unknown region; an optional back
   photo (product decision C).
4. Draping beyond the A-pose would need posing or cloth simulation: out of
   v1's scope.
