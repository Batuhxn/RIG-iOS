Committed locally as **`7c323b5`** on `polish/rig-atelier-codex`. Only the two permitted files were added; the worktree is clean. No P1 defect proven.

1. **P2 — Garments penetrate skin that remains visible.** [GarmentTemplate.swift:153](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/GarmentTemplate.swift:153), [AvatarOutfitBuilder.swift:37](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/AvatarOutfitBuilder.swift:37). Neutral tee: **18 vertices inside by >2 mm**, worst **17.35 mm**; neutral dress: **16**, worst **9.07 mm**. All nearest body faces remain unhidden. Tee witness vertex 905 already has a **−17.38 mm authored normal offset**; smoothing is not the original cause. Fix authored underarm clearance, add collision constraints after deformation/smoothing, and validate hidden skin against the resulting surface. [Regression](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tests/AtelierGeometryAuditTests.swift:15).

2. **P2 — Photo-panel classification becomes invalid after deformation.** [build_garment_templates.py:475](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tools/AvatarAssets/build_garment_templates.py:475), [GarmentTemplate.swift:175](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/GarmentTemplate.swift:175). Classification uses one triangle’s rest normal for a whole quad; runtime retains those assignments after morphing and smoothing. Extreme tee has **39 photo faces below the 0.35 facing threshold**, minimum normal z **−0.357**. This permits projection onto glancing/back-facing surfaces. Reclassify individual triangles after final deformation. [Regression](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tests/AtelierGeometryAuditTests.swift:53).

3. **P2 — Layer guard misses triangle interiors.** [AvatarOutfitBuilder.swift:78](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/AvatarOutfitBuilder.swift:78). It searches vertices within 6 cm. A reproduced fixture places outer fabric directly behind an inner triangle, while every inner vertex is ~1 m away: no correction occurs. The current nearest-vertex test cannot establish surface separation. Use accelerated closest-triangle queries and check crossing edges/faces. [Regression](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tests/AtelierGeometryAuditTests.swift:72).

4. **P2 — Layer pushes leave stale normals.** [AvatarOutfitBuilder.swift:82](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/AvatarOutfitBuilder.swift:82). Positions change, but normals do not. The fixture produces a final-face normal discrepancy of **0.178**. Recompute normals after all pushes, preserving canonical seam sharing. [Regression](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tests/AtelierGeometryAuditTests.swift:85).

5. **P2 — Selecting a different photo can retain the old texture.** [AvatarLabModel.swift:281](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/AvatarLabModel.swift:281). Cache misses depend solely on garment UUID. Rewearing the same item after switching original/cutout updates its path but reuses cached imagery, colour and spans. Include image path/revision in the cache key or invalidate on changes. [Regression](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tests/AtelierGeometryAuditTests.swift:110).

6. **P3 — Loader accepts invalid binding semantics.** [GarmentTemplate.swift:95](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/GarmentTemplate.swift:95), [GarmentTemplate.swift:108](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/GarmentTemplate.swift:108). Version `999` and barycentric weight `wb=2` pass existing guards. Validate supported versions, barycentric bounds and canonical roots. [Regressions](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tests/AtelierGeometryAuditTests.swift:142).

7. **P3 — Padding does not use the nearest occupied row.** [AvatarTexturePadding.swift:40](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/AvatarTexturePadding.swift:40). Empty interior rows always copy the previous occupied row. In a red/empty/empty/blue fixture, the second empty row incorrectly becomes red. This extends colour bands unevenly. Use a bidirectional nearest-row lookup. [Regression](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tests/AtelierGeometryAuditTests.swift:101).

Additional visual causes are supported by inspection. [GarmentPhotoMapping.swift:34](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/GarmentPhotoMapping.swift:34) reprojects against deformed bounds and compresses each photo row into its opaque span; combined with uneven geometric stretch, this explains warped prints and changing apparent print scale. [AvatarStageView.swift:123](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/AvatarStageView.swift:123) switches abruptly from photograph to solid colour, explaining sharp seams. **Normals are recomputed after smoothing and shared across duplicated seams**; those seams are principally material discontinuities.

Jagged silhouettes can persist because [smoothing freezes open-edge vertices](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/GarmentTemplate.swift:187). Fixed metre offsets, [prescribed radial flare](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tools/AvatarAssets/build_garment_templates.py:303), and the [separate bodice/skirt construction](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tools/AvatarAssets/build_garment_templates.py:610) explain inconsistent ease and rigid dress/skirt volume. Uniform roughness and strong ambient fill, without fabric-detail maps in [the material setup](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/AvatarStageView.swift:174), are plausible causes of flat lighting and a painted-on appearance.

Geometry and texture preparation run off the main actor; SceneKit mutations use the main actor. Cancellation checks are coarse, and garment-loading errors silently fall back to shells. Physical-device memory, cancellation latency and thread behaviour remain unmeasured.

The [offline audit](/C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tools/AvatarAssets/audit_garment_geometry.py) uses float32 deformation, two Taubin iterations, exact closest-triangle distances and three-ray inside classification against the full body. Body topology is closed/manifold; **zero ray disagreements**. Every case had **zero NaN/inf vertices, degenerate garment triangles and degenerate binding frames**.

| Body | Template | Opposed faces¹ | Inside >2 mm | Max depth mm | Edge stretch × |
|---|---|---:|---:|---:|---:|
| S1 | Tee | 118 | 1.47% | 17.35 | 1.000–1.000 |
| S1 | Trousers | 50 | 0% | 1.52 | 1.000–1.000 |
| S1 | Skirt | 0 | 0% | 0 | 1.000–1.000 |
| S1 | Dress | 52 | 1.15% | 9.07 | 1.000–1.000 |
| S2 | Tee | 135 | 1.47% | 17.48 | 0.566–1.331 |
| S2 | Trousers | 60 | 0% | 1.56 | 0.599–1.532 |
| S2 | Skirt | 0 | 0% | 0 | 0.639–1.236 |
| S2 | Dress | 54 | 1.15% | 9.53 | 0.508–1.238 |
| S3 | Tee | 110 | 1.47% | 17.31 | 0.748–1.435 |
| S3 | Trousers | 50 | 0% | 1.52 | 0.928–1.041 |
| S3 | Skirt | 0 | 0% | 0 | 0.933–1.083 |
| S3 | Dress | 45 | 1.29% | 9.44 | 0.803–1.651 |
| Extreme | Tee | 131 | 1.47% | 18.61 | 0.567–2.469 |
| Extreme | Trousers | 48 | 0.08% | 2.01 | 0.646–2.913 |
| Extreme | Skirt | 0 | 0% | 0 | 0.623–1.819 |
| Extreme | Dress | 48 | 1.43% | 12.05 | 0.636–1.913 |

¹ Opposed to averaged binding outward normals after runtime orientation correction; this diagnostic does **not** prove every counted face is physically inverted. Stretch compares against the smoothed neutral garment. Extreme matches the existing geometry test.

Python self-checks passed; eight actual-asset nearest queries matched exhaustive searches. `--strict` returned **1**, detecting defects as intended. Nine XCTest cases were added, including one positive seam control; **XCTest execution remains pending Apple CI**.