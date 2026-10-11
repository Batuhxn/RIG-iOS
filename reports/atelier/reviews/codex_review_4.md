Reviewed through **6c27689**. Workspace unchanged. Line references below are for that Git revision; numerical checks used in-memory Python probes.

- **P2 — Final layer normals remain stale after substantial movement.** `C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/AvatarOutfitBuilder.swift:135`

  The last round skips normal recomputation on the assumption that its moves are sub-millimetre. My neutral tee/coat port measured **20.03 mm maximum last-round movement**, with 29 vertices moving over 1 mm. Stored normals differed from freshly computed normals by up to **76.9°**. This can materially distort lighting. Recompute final normals and iterate clearance/normal updates until convergence, rather than stopping by round number alone.

  **Yes, the nearest-vertex XCTest can still fail:** the port found **44 failures among 1,245 checked coat vertices**, worst signed depth **−33.0 mm**. No queried closest-surface clearance was below 5 mm. The test’s unconditional nearest-vertex criterion conflicts with the new compatibility rule; make that assertion conditional on compatible normals and retain an unconditional surface-clearance check. Swift CI must confirm the exact count.

- **P2 — Tuck still exposes previously covered vertices.** `C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/AvatarOutfitBuilder.swift:64`

  In neutral side view, tee vertices **8383, 8407 and 8411** are garment-occluded before tuck and exposed afterward, with no visible-body occluder. Vertex 8383 moves from approximately `(0.29388, 1.23685, 0.03243)` to `(0.28802, 1.23179, 0.03039)`. Across the 36 review directions, some views expose up to **six tucked tee vertices** or **eight tucked trouser vertices**. **It should taper:** limit displacement to what remains covered after movement, and fade toward openings.

- **P3 — Hidden-skin coverage still misses some review directions.** `C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Tools/AvatarAssets/build_garment_templates.py:686`

  The front/side regression is fixed: **zero exposed hidden triangle centres in all 40 template/body/view combinations**, including both extremes. However, the 36-direction sweep still finds isolated misses.

  Neutral trouser triangle **8018** is exposed at azimuth **60°**, elevation **25°**. Its geometric face normal has camera dot product **0.1842**, but the averaged vertex normal used for the centre check gives **0.0208**, so the `>0.05` filter skips it. The actual centre’s garment ray misses; the displaced centre’s ray hits. Use geometric face normals for triangle visibility and sample the actual surface point with a tiny offset along the camera ray.

The **opposed-normal fixture now holds**, ending at **+8 mm**; the nearest-vertex step no longer undoes it.

For edge smoothing, all **20 template/body cases** had finite vertices, zero triangles below **10⁻⁸ m²**, and matching authoring UVs at canonical duplicates. I confirmed **12 tee folds over 90° at rest**; the stronger extreme still has 18 tee and 21 dress folds. I found no additional smoothing defect in this matrix.

The **crisp-AA clamp fixes the demonstrated boundary leak**: its lower smoothstep threshold stays at least `0.01`, so `seam=0` produces zero photo weight. Device Metal compilation remains unverified locally.