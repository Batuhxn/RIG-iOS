# RiG Atelier: open-source comparison

Date: 2026-10-11. Scope: what existing projects could fix the visible defects of the
Garment Engine v1 3D preview, under RiG's constraints (proprietary iOS app, on-device,
no GPL/AGPL code in the runtime, zero spending, one front photo per garment).

Licences and activity were checked against the GitHub API and the projects' licence
files on 2026-10-11 ("pushed" = last push to the default branch). Gemini's research
pass (Antigravity CLI, read-only) proposed the list; every licence below was
re-checked, and two of Gemini's licence claims were corrected (libigl, PyTorch3D).

## Defects the candidates are measured against

| # | Defect (render matrix, v1 style) |
|---|---|
| D1 | Hard line between the photo front and the plain unknown region |
| D2 | Flat, plastic lighting (ambient fill, no environment) |
| D3 | Garment edges read as paper (double-sided, no inside) |
| D4 | Stripes compress and bend near the panel edge at three-quarter views |
| D5 | Skin poking through garments on some bodies (Codex audit) |

## Candidates

| Project | Licence (code / assets) | Activity | iOS runtime? | Role for RiG | Fixes |
|---|---|---|---|---|---|
| [MakeHuman](https://github.com/makehumancommunity/makehuman) | AGPL-3.0 code; CC0 base mesh, targets, proxies | pushed 2024-08 (1.x legacy) | no | **asset source** (already used: CC0 body + morphs + helper topology) | none new |
| [MPFB2](https://github.com/makehumancommunity/mpfb2) | GPL-3.0 code; CC0 assets | pushed 2026-10 | no (Blender add-on) | **reference only**; its `.mhclo` handling inspired our binding, re-implemented independently | none new |
| [Blender](https://github.com/blender/blender) | GPL-2.0+ | active | no | **offline tool** at most (cloth sim to bake drape); its output is ours, but adds a heavy offline step | D3/D4 partially, offline |
| [Google Filament](https://github.com/google/filament) | Apache-2.0 | active | yes (Metal) | redistributable renderer; better PBR (cloth BRDF with sheen) | D2, but replacing SceneKit is a large change for a preview screen |
| [libigl](https://github.com/libigl/libigl) | MPL-2.0 core, some modules GPL-3.0 (GitHub reports GPL-3.0 because of `LICENSE.GPL`) | active | possible (header-only C++) | **reference**: harmonic/LSCM parameterisation, signed distance | D4/D5 ideas; we need ~50 lines, not the library |
| [Open3D](https://github.com/isl-org/Open3D) | MIT | active | impractical | offline mesh processing | none we need |
| [NVIDIA Kaolin](https://github.com/NVIDIAGameWorks/kaolin) | Apache-2.0 | active | no (PyTorch/CUDA) | research only | none |
| [PyTorch3D](https://github.com/facebookresearch/pytorch3d) | BSD-3-Clause | active | no | research only | none |
| [GarmentCode](https://github.com/maria-korosteleva/GarmentCode) | MIT | pushed 2025-06 | no (Python) | **inspiration**: garments as 2D sewing patterns, so UVs are the flat pattern | D4 (the idea: a flat-lay photo is the front pattern piece) |
| [TailorNet](https://github.com/chaitanya100100/TailorNet) | no licence file; depends on SMPL (non-commercial) | inactive since 2022 | no | **excluded** (licence) | — |
| [trimesh](https://github.com/mikedh/trimesh) | MIT | active | no | offline checks (proximity, signed distance) | D5 checks; numpy suffices for ours |
| [pyrender](https://github.com/mmatl/pyrender) | MIT | low activity | no | offline previews | none |
| [MeshLab](https://github.com/cnr-isti-vclab/meshlab) | GPL-3.0 | active | no | manual inspection only | none |
| Apple SceneKit PBR + `lightingEnvironment`, shader modifiers | Apple SDK | SceneKit maintained, not developed | yes, already in use | **adopted**: image-based light, single-sided materials, surface shader | D1, D2, D3 |

## Decisions

1. **No new dependency.** Every defect we can see has a small in-house fix in SceneKit
   or in the offline template builder. Filament is the only serious runtime candidate;
   it would replace the whole stage for a gain (cloth sheen) that the render matrix
   does not show to be the bottleneck. Revisit only if the preview becomes a
   flagship feature.
2. **Adopted ideas, implemented independently:**
   - image-based studio light and PBR fabric (Filament/Apple documentation);
   - photo-to-unknown fade by garment-space surface angle (our own; a shader modifier);
   - the flat-lay photo as the front pattern piece (GarmentCode's framing) for the
     horizontal photo coordinate, evaluated as an experiment (see the quality report);
   - closest-triangle penetration checks (libigl/trimesh's signed-distance idea, in numpy).
3. **Copyleft:** nothing from MakeHuman's or MPFB2's code, libigl's GPL modules,
   Blender or MeshLab is in the app. MakeHuman assets used are CC0
   (`Support/Avatar/NOTICE.md`).
4. **Excluded:** SMPL-based projects (TailorNet and most garment-learning research):
   non-commercial body model licences.
