Reviewed **4656977→899ec16**, read-only. Four findings; no P1.

- **P2 — Normal-ray coverage hides camera-visible skin.** [build_garment_templates.py:683](https://github.com/Batuhxn/RIG-iOS/blob/899ec16/Tools/AvatarAssets/build_garment_templates.py#L683): hitting fabric along a body normal does not establish camera occlusion. Independent rays against the complete body and deformed garment found these **hidden triangle centres visible through openings** on the neutral body:

  | Garment | Front | Side |
  |---|---:|---:|
  | Tee | 14 | 18 |
  | Trousers | 42 | 13 |
  | Skirt | 0 | 0 |
  | Dress | 30 | 17 |

  All front-view cases are newly hidden by this change. Examples: trouser triangle **11239**, centre `(-0.16116, 0.05937, 0.08662)` at the hem; dress triangle **2214**, centre `(-0.20261, 1.23197, 0.03096)` near the armhole. These counts sample centres, not entire hole areas. Preserve skin near openings unless coverage holds across the triangle and supported views/morphs.

- **P2 — Skin tuck deforms exposed skin.** [AvatarOutfitBuilder.swift:64](https://github.com/Batuhxn/RIG-iOS/blob/899ec16/Sources/AvatarLab/Core/AvatarOutfitBuilder.swift#L64): sharing a hidden triangle is insufficient evidence that a vertex lies under fabric. After applying the exact tuck, front-camera checks found **18 exposed tucked vertices on the neutral tee, 26 on trousers, and 14 on the dress**. Tee vertex **802** sits near the neckline at approximately `y=1.401 m`. These vertices move the full **8 mm**, producing exposed dents. Adjacency remains intact; I found no flipped body triangles in neutral/extreme checks. Restrict tuck to covered skin and taper its displacement.

- **P2 — Nearest-vertex clearance can undo the corrected surface push.** [AvatarOutfitBuilder.swift:116](https://github.com/Batuhxn/RIG-iOS/blob/899ec16/Sources/AvatarLab/Core/AvatarOutfitBuilder.swift#L116): this second correction still follows the outer normal even when it opposes the inner surface. For a small horizontal inner triangle, outer normal `−Z`, and starting depth `−1 mm`, the surface step reaches `+6 mm`; the vertex step returns it to **−6 mm**. Repeating all 18 passes preserves the penetration, including normal recomputation for a parallel outer triangle. Use a compatible clearance direction and verify both constraints after correction.

- **P3 — Crisp AA can restore the material-edge discontinuity.** [AvatarStageLook.swift:125](https://github.com/Batuhxn/RIG-iOS/blob/899ec16/Sources/AvatarLab/AvatarStageLook.swift#L125): at boundary weight `seam=0`, `fwidth(seam)=0.5` gives `seamAA=0.75` and **13.8% photo weight**, assuming full facing weight. The adjacent back material remains plain colour. This affects the optional crisp style at coarse screen coverage. Preserve zero boundary coverage when widening the AA band.

The roughness/channel-1 and metalness/channel-2 transport is coherent: both slots are sampled before lighting and reset afterward. CPU geometry checks confirmed zero soft-seam weights at every neutral canonical material boundary. **I have not verified the UIImage ramp’s exact sampled identity or generated shader compilation on Metal**; a GPU test reading weights `0`, `0.5`, and `1` would establish that.

`fwidth` is valid in the fragment-stage surface modifier, consistent with the [Metal language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf). Its use is appropriate for AA; the boundary leak above is a separate mathematical defect.

`angularAcross` produced **no UV foldovers, collapsed UV triangles, or atan2 branch jumps** across skirts/dresses on the three presets plus extreme. A single fitted axis remains unsuitable for arbitrary asymmetric or disconnected cross-sections; that failure was not reproduced on these assets.

The stamps are local to each build, so I found no new shared-state race. Oversized-triangle construction is bounded now. Cancellation still waits until layering finishes; the expanded rounds have no internal cancellation checks, and device performance remains unmeasured.