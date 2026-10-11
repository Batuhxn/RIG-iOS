Reviewed **512c58f**, read-only. No P1; two P2 issues remain.

Independent Python results:

| Neutral coat check | Failures / checked | Minimum |
|---|---:|---:|
| Compatible nearest vertex | 0 / 1,203 | **6.49 mm** |
| Closest surface within 3 cm | 0 / 1,155 | **8.00 mm** |

Final stored normals match recomputation exactly. The **36-direction sweep found zero visible hidden triangle centres** across all four templates and five review bodies.

Both findings below reference `C:/Users/bkara/Documents/ChatGPT/RIG/RIG-iOS-atelier-codex/Sources/AvatarLab/Core/AvatarOutfitBuilder.swift` at **512c58f**:

- **P2 — The 3 cm surface cutoff loses deeper collision coverage, line 95.** A valid fixture with inner triangle `(-1,-1,0), (1,-1,0), (0,1,0)` and an outer vertex at `(0,0,-0.04)` receives **no correction**: surface distance is 40 mm and every inner vertex is over 1 m away. The previous 6 cm surface query detected it. The comment that nearest vertices catch deeper penetration is therefore false. Restore the wider surface coverage, using a coarser grid or another bounded index if needed.

- **P2 — Tapered tuck still exposes previously covered skin, line 80.** In neutral side view at elevation −10°, tee vertex **8390** and trouser vertices **6237/6238** are occluded before tuck and exposed afterward. Their nearest open-edge vertices are **49.19, 47.97 and 51.97 mm** away, so all still receive the full **8 mm** displacement. Tee vertex **8383** remains exposed after a tapered **6.16 mm** move. Distance-based taper alone does not ensure coverage; constrain displacement using post-move occlusion.

The amended test is **partly a legitimate correction**: restricting the nearest-vertex assertion to compatible normals removes an invalid constraint, and adding triangle checks improves coverage. However, its 3 cm cutoff is a **weakening of deep-penetration coverage** and skips the fixture above. Add that regression case alongside the corrected assertions.

These are offline numerical checks; Swift CI was not run locally. No files were changed.