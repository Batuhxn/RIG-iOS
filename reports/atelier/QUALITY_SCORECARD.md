# RiG Atelier: quality scorecard

No invented scores. Each dimension has observable acceptance criteria; the status
column says what was measured and where. Subjective dimensions are judged side by
side on the render matrix (same camera, morphs and garments; Garment Engine v1
stage style vs current) and the uncertainty is stated.

Evidence sources:
- **Matrix**: `testAtelierRenderMatrix` (Tests/AtelierRenderMatrixTests.swift): 3 outfits
  (tee+trousers, skirt+tee, dress) x 2 fabrics (stripes, plain) x 4 bodies
  (silhouettes 1-3, extreme) x 4 angles (front, 45°, side, 135°), v1 vs current.
- **Audit**: `Tools/AvatarAssets/audit_garment_geometry.py` (Codex, independent) and
  `Tools/AvatarAssets/atelier_lab.py` (Claude); both evaluate the runtime maths offline.
- **XCTest**: the full RIGTests suite on GitHub's macOS runner (simulator).

| Dimension | Importance | Acceptance criteria | Status |
|---|---|---|---|
| Clothing silhouette | Critical | No folded creases visible in the matrix; hems, necklines and sleeve openings read as lines, not steps | **met in renders**: edge zigzag p90 tee 31–42 → 3–11 mm, dress 42 → 12 mm (close-ups); folds > 90° tee 19 → 12, trousers 17 → 2, **dress 4 → 10 (open)** |
| Body morph correctness | Critical | Controls stay independent (existing tests); no NaN/degenerate faces for all bodies (audit) | audit: 0 NaN, 0 degenerate on all 16 body/template cases |
| Texture preservation | Critical | Stripes recognisably continuous on the front; no smear at the panel edge; no invented pattern on sides/back | **met**: angular mapping keeps skirt/dress stripes straight (v1 bent them into arcs); crisp side-seam edge; sides/back plain main colour |
| Mesh intersection / clipping | Critical | No garment vertex > 2 mm inside visible skin on silhouettes 1-3; extreme body reported, not hidden | **met**: 0 on all four review bodies (was tee 18 / dress 16 vertices, -17.4 / -9.1 mm); hidden-skin holes 0 on silhouettes, 2 tee triangles on the extreme body; coat over tee 0 inside (was 697) |
| Consistency across angles | High | No hard photo/colour line at 45° and side; side views have no large unexplained colour blocks | **met, subjectively**: clean seam line instead of a jagged material edge; plain sides are expected (one photo). ChatGPT has not yet judged the final version |
| Material / lighting | High | Mannequin not blown out (existing pixel tests pass); fabric not plastic; no dramatic shadows | **met**: lighting D approved by ChatGPT; pixel tests pass; lining lit as an inside |
| UI polish | Medium | Sliders reachable on a 667 pt screen; captions accurate; VoiceOver values spoken | stage height ≤ 50% of container; copy updated; accessibilityValue added (not device-tested) |
| Performance | High | Outfit build stays within ~10% of v1 in the same CI run (debug simulator; not iPhone) | **met**: 422 ms vs 487 ms (run-to-run noise is large); iPhone unmeasured |
| Asset size | Medium | Templates stay ≈ 0.32 MB; no new bundled assets | 0.322 MB (was 0.322 MB); no new assets (environment and shadow are generated) |
