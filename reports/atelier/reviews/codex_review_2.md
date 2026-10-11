Reviewed through **4656977**. Workspace unchanged; no files created or edited.

- **P2 — Layer guard can move sideways or deepen penetration.** [AvatarOutfitBuilder.swift:86](https://github.com/Batuhxn/RIG-iOS/blob/4656977/Sources/AvatarLab/Core/AvatarOutfitBuilder.swift#L86): clamping `n·hitNormal` changes the denominator without correcting the direction. With perpendicular normals, a point initially 1 mm inside moves **168 mm sideways after six passes**, remaining 1 mm inside. Opposing normals push inward. Use the hit normal when alignment is small/nonpositive, then verify clearance.

- **P2 — Soft seam does not guarantee continuity at material boundaries.** [AvatarStageView.swift:174](https://github.com/Batuhxn/RIG-iOS/blob/4656977/Sources/AvatarLab/AvatarStageView.swift#L174): only the front material receives the modifier. Classification uses face normals; blending uses interpolated vertex normals. After reclassification, **27 neutral-tee boundary vertices retain 100% photo weight**, beside plain-colour back faces. This leaves hard transitions for contrasting prints. Fade using distance to the actual material boundary.

- **P3 — Extreme dress still penetrates visible skin.** [build_garment_templates.py:613](https://github.com/Batuhxn/RIG-iOS/blob/4656977/Tools/AvatarAssets/build_garment_templates.py#L613): final rest-body clearance does not ensure morphed clearance. Two dress vertices penetrate **2.043 and 2.097 mm**; their nearest body triangles are not hidden. Add a final collision correction after deformation/smoothing, or validate clearance across the supported morph envelope.

- **P3 — Snapshot background argument is ignored.** [AvatarStageView.swift:209](https://github.com/Batuhxn/RIG-iOS/blob/4656977/Sources/AvatarLab/AvatarStageView.swift#L209): the local `background` shadows the parameter, and the following assignment writes the existing background back. This invalidates requested render-matrix backgrounds. Rename the saved value and assign the parameter.

- **P3 — Photo-span filling still chooses the previous row.** [GarmentPhotoMapping.swift:54](https://github.com/Batuhxn/RIG-iOS/blob/4656977/Sources/AvatarLab/Core/GarmentPhotoMapping.swift#L54): despite the nearest-row contract, `[A, nil, nil, B]` becomes `[A, A, A, B]`. The second empty row should use B. Texture pixel padding was fixed, but projection bounds retain this bias. Apply nearest-row filling here too.

- **P3 — TriangleGrid has unbounded construction cost.** [AvatarOutfitBuilder.swift:163](https://github.com/Batuhxn/RIG-iOS/blob/4656977/Sources/AvatarLab/Core/AvatarOutfitBuilder.swift#L163): every cell in each triangle’s bounding box receives an entry. Current neutral templates require approximately **7,700–14,400 entries**; a triangle spanning 20 m on each axis would require roughly **297 million** at 3 cm resolution. Cap oversized triangles or use a BVH.

The shader expression correctly recovers garment-space normals for the current rigid/uniform transforms; nonuniform scaling would require undoing the normal transform instead. The sRGB-to-linear conversion is correct for the supplied sRGB colours. This matches [Apple’s transform contract](https://developer.apple.com/documentation/scenekit/scnprogram). **Device Metal compilation remains unverified**; I found no specific syntax defect.

Outer/back culling is complementary, so it does not itself remove both sides of a triangle. Folded patches can expose dark lining. Reclassification preserves valid indices and UV arrays, but changes projection bounds: the neutral dress loses **9.54 mm** horizontally, shifting retained UVs by up to **0.0178**. Stable projection bounds would avoid classification-driven print jumps.

Builder relaxation uses simultaneous updates and no randomness, although boundary vertices in affected fold regions also move. Hidden triangles are recomputed afterward; **3040→2966 alone does not prove incorrect occlusion**.

The existing audit was rerun against the Git-ref asset in memory. **All rows have zero NaN/inf vertices and zero degenerate triangles.** “Opposed” counts faces opposing averaged binding-body normals; it is not definitive proof of inverted winding.

| Preset | Garment | Opposed | Inside >2 mm | Max depth mm | Edge stretch min–max |
|---|---|---:|---:|---:|---:|
| S1 | Tee | 116 | 0% | 0 | 1.000–1.000 |
| S1 | Trousers | 10 | 0% | 0 | 1.000–1.000 |
| S1 | Skirt | 0 | 0% | 0 | 1.000–1.000 |
| S1 | Dress | 52 | 0% | 0 | 1.000–1.000 |
| S2 | Tee | 129 | 0% | 0 | 0.632–1.331 |
| S2 | Trousers | 13 | 0% | 0 | 0.725–1.222 |
| S2 | Skirt | 0 | 0% | 0 | 0.639–1.236 |
| S2 | Dress | 58 | 0% | 0 | 0.508–1.238 |
| S3 | Tee | 112 | 0% | 0 | 0.748–1.459 |
| S3 | Trousers | 10 | 0% | 0 | 0.923–1.041 |
| S3 | Skirt | 0 | 0% | 0 | 0.933–1.083 |
| S3 | Dress | 50 | 0% | 0 | 0.809–1.496 |
| Extreme | Tee | 121 | 0% | 0 | 0.567–2.935 |
| Extreme | Trousers | 10 | 0% | 0 | 0.697–3.034 |
| Extreme | Skirt | 0 | 0% | 0 | 0.623–1.819 |
| Extreme | Dress | 50 | 0.143% | 2.097 | 0.470–1.922 |

Extreme uses hips/bust/shoulders/overall `1`, waist `−1`, legLength `−0.6`; it is stronger than the render-matrix extreme. These are individual-garment results before layering.