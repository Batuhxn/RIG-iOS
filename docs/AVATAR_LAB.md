# Avatar Lab (v0.5, experimental)

"See your real clothes on a version of you." This is an **approximate outfit
preview**, not a virtual fitting room. Nothing in it claims size, fit or drape.

## What exists

- **Body.** MakeHuman's CC0 base mesh, baked to its default neutral figure
  (1.65 m, A-pose), smoothed into a dress-form "mannequin" (face, chest and
  pelvis detail removed), with 30 sparse morph targets.
- **Controls.** 15 signed sliders, five shown first: Shoulders, Upper body, Waist,
  Hips, Legs. The rest sit under "Refine": Height, Torso length, Chest, Ribcage,
  Tummy, Seat, Thighs, Arm length, Upper arms, Overall. Each slider drives
  only its own region's targets: widening the hips moves no shoulder vertex
  (a test checks this). There are no units and no measurement fields.
- **Garments.** Cut from MakeHuman's own clothing helpers (`helper-tights`, a
  full-body suit, and `helper-skirt`), which every body target also moves. So a
  garment follows the body for free. Cuts: top (no / short / long sleeve, hip or
  cropped hem), outerwear, trousers, shorts, skirt (mini / knee / midi / maxi),
  dress, shoes. Wardrobe items map to a cut by category and subtype keywords.
- **Preview modes.**
  - *3D photo*: the garment's cutout is projected flat, front to back, onto the
    shell. Transparent areas of the cutout are filled with the garment's own
    average colour.
  - *3D colour*: the same shell in that average colour.
  - *2D* (default): an orthographic front view. The cutout photo is cut into 16
    horizontal strips, collar to hem, and each strip is stretched to the shell's
    front width at that height (Approach A). The photo keeps its own pixels and
    follows shoulders, waist and hips.
  - Both 3D modes rotate (turntable).
- **Onboarding.** "Make it feel like you": pick one of three unnamed starting
  points ("Silhouette 1 / 2 / 3", shown as rendered thumbnails), then adjust.
  Nothing is required. The Frame control (MakeHuman's sex macros) is hidden.
- **Storage.** One JSON file, `Application Support/Avatar/avatar-profile.json`:
  the slider values, the current outfit (garment IDs) and saved outfits. It is
  not a SwiftData model, so no store migration. "Delete avatar" removes the file.
  No photo, measurement or profile ever leaves the device. There is no network
  code; the static audit enforces that.

## Architecture

```
Support/Avatar/RIGAvatarBody.rigavatar   binary asset (2.1 MB), built offline
Sources/AvatarLab/Core/                  Foundation only, tested on Linux too
  AvatarBodyAsset          parse the asset (rest positions, submeshes, targets)
  AvatarBodyShape          versioned, clamped, NaN-safe control values; presets
  AvatarMorphEngine        linear blend shapes on the CPU, normals, compaction
  AvatarGarmentShell       garment cuts, rest-pose face selection, skin guard, UVs
  AvatarFrontProjection    2D overlay math (matches the orthographic camera)
  AvatarProfile(+Store)    profile JSON, outfit selection, category → cut
Sources/AvatarLab/
  AvatarLabModel           @Observable; off-main recompute, textures, persistence
  AvatarStageView          SceneKit renderer (replaceable: it only reads AvatarMesh)
  AvatarLabView            tab UI: onboarding, sliders, outfit picker, modes
```

- Body parameters (`AvatarBodyShape`) are independent of rendering. The renderer
  receives plain `AvatarMesh` values. The garment fitter is one type,
  `AvatarGarmentShellBuilder`.
- **Garment faces** are selected on the *rest* mesh by landmarks, keeping each
  triangle pair from a quad together. Selecting on the rest mesh means a T-shirt
  covers the same part of the body however it is shaped.
- **Skin guard.** Each helper vertex is paired with its nearest rest-pose body
  vertex. After a morph, any shell vertex closer to the skin than its layer
  offset is pushed out along the body normal. This removed the hip/seat
  poke-through that MakeHuman's helpers show at extreme shapes.
- **Layers.** Each layer sits a fixed offset off the skin: shoes 12 mm, bottoms
  4 mm, skirt 5 mm, tops and dresses 8 mm, outerwear 18 mm. A dress hides the
  bottom.

### Asset format (`RIGAVTR1`, little-endian)

```
"RIGAVTR1" | u32 V | f32 xyz × V (metres, y up, feet at 0)
u32 S | S × (32-byte name, u32 n, u32 indices × n)          triangles
u32 T | T × (32-byte name, f32 scale, u32 n, u32 vertex × n, i16 xyz × n)
```

`python3 -I Tools/AvatarAssets/build_avatar_asset.py <download-dir> Support/Avatar/RIGAvatarBody.rigavatar`
rebuilds it from a pinned MakeHuman commit. Each source file's SHA-256 is locked
in `Tools/AvatarAssets/SOURCES.lock.json`, so a changed upstream file fails the
build. `Tools/AvatarAssets/preview_avatar.py` renders front and side views of the
asset or of OBJ files with numpy and Pillow, for checks without a Mac.

## Technology comparison (why this foundation)

| Option | Licence for a closed commercial app | Body control | Clothing | iOS effort | Verdict |
|---|---|---|---|---|---|
| **MakeHuman assets** (base mesh + targets) | **CC0**; code is AGPL, not used | ~1,000 local targets, independent regions | helper tights/skirt follow all targets; `.mhclo` binding | small: we parse text, ship a 2 MB binary | **chosen** |
| MPFB2 (Blender add-on) | code GPL-3.0, assets CC0 like MakeHuman | same targets | best clothes fitting (mhclo) | Blender pipeline, not runtime | reuse concepts, not code |
| makehuman.js | MakeHuman licence (AGPL code) | runtime `.target` blending (the same idea we use) | — | web | idea only |
| SMPL / SMPL-X / STAR (MPI) | research licence; commercial use needs a paid licence | PCA shape space, very good | needs separate garment work | moderate | rejected (cost, licence) |
| Hand-made or CC0 game rigs (e.g. Quaternius) | CC0 | uniform scaling or bones only | none | small | rejected (no independent proportions) |
| Google Filament | Apache-2.0 | morph targets, glTF | — | adds a C++ engine and several MB | not needed yet |
| RealityKit | Apple | `BlendShapeWeightsComponent` and `LowLevelMesh` need iOS 18; iOS 17 can only regenerate a `MeshResource` | — | good later | migration target |
| **SceneKit** | Apple | any mesh; we regenerate geometry | — | smallest on iOS 17 | **prototype renderer** (deprecated for new work, still functional) |

## Approach A vs B (honest)

| | A: 2D overlay | B: 3D shell + photo |
|---|---|---|
| Garment recognisability | best from the front: the real photo, undistorted | good from the front; side and back show the front photo stretched |
| Body-shape compatibility | per-strip widths follow the outline; no depth | follows every slider |
| Rotation | none | full turntable |
| Runtime | trivial | ~50 ms per update for body + 2 garments (Linux CPU, debug); CI measures the simulator |
| Complexity | low | moderate, already built |
| Licensing | none | CC0 helpers only |

The likely product answer is a hybrid: 3D shell with the photo for the turntable,
plus a front-on 2D check. Both share the shells, so they always agree on where a
garment sits.

### Known limitations

- Shells hug the body: no drape, no loose fit, no wrinkles. Skirts follow
  MakeHuman's straight skirt helper.
- Front planar projection: the back of a garment shows the mirrored front photo,
  and sleeves take the photo's side columns. Flat-lay photos with spread sleeves
  map better than folded ones.
- Garment cut comes from category and subtype keywords. There is no per-garment
  length or sleeve detection yet; v0.3's auto metadata (kind and length) could
  supply it.
- A-pose only: no posing or animation.
- Hems follow the quad grid, so they are stepped rather than perfectly straight.
- Not measured on a physical iPhone: frame time, memory and thermals are unknown.
