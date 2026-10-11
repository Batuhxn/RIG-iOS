# RiG Atelier: visual quality report

Branch `polish/rig-atelier` (from `feat/v0.5-avatar-lab` @ `ccdb984`). Not merged, no
PR, no TestFlight, nothing spent (0 TRY: GitHub's standard macOS runners are free for
this public repository; ChatGPT, Codex and Gemini were used through existing access).
No new features: every change is visual quality, geometry, correctness, tests or
accessibility of the existing Avatar screen.

**Status: remote quality gate complete; device acceptance pending.** The 3D preview is visibly better and measurably cleaner, but it
is still an approximate, A-posed preview built from one front photo. ChatGPT's verdict
at the last checkpoint: "not yet release-ready"; nobody has looked at it on an iPhone
with real wardrobe photos.

## 1. What changed, and the evidence

| Defect (how we saw it) | Cause found | Fix | Evidence |
|---|---|---|---|
| Hard line where the photo ends (ChatGPT P0) | front and back panels are separate materials, split per face | photo ends in a clean, anti-aliased side-seam line along a smooth curve of constant surface angle, never past the real material boundary (`AvatarStageLook.crispPhoto`); a soft fade was built first and rejected after close-ups (it read as a blur) | close-ups, matrix `*_atelier` vs `*_atelier-soft`; Codex verified zero photo weight at the boundary |
| Vertical stripes bent into arcs on skirts (found in the matrix) | planar photo mapping on a cone: a line of constant x is a hyperbola | skirts and dresses map by angle around one fitted straight axis (`GarmentPhotoMapping.angularAcross`) | matrix `skirt/dress_stripes`: v1 vs current; extreme-body hip kink found and fixed (per-height axis → fitted line); Codex: no UV foldovers or branch jumps |
| Sawtooth along necklines and sleeve openings (close-ups; present since v1) | the template cut follows whole quads, so every open edge was a staircase; straightening its height turned it into a horizontal zigzag | builder smooths every open-edge loop (Taubin) and re-straightens | neighbour-to-neighbour bend p90: tee 31–42 → 3–11 mm, dress 42 → 12 mm, trousers 18 → 11 mm; close-ups |
| Skin through the tee/dress armholes (Codex P2) | armholes authored up to 17 mm inside the arm root | builder moves garment vertices < 3 mm from skin to 7 mm above it, alternating with crease relaxation | visible-skin penetration > 2 mm (atelier_lab + Codex audit): tee 18 → 0 vertices, dress 16 → 0, all review bodies |
| Fabric folded over itself at armpits/crotch (found while fixing the above) | the same authored geometry | crease relaxation in the builder | dihedral > 90° at rest: tee 19 → 12, trousers 17 → 2; dress 4 → 10 (open item) |
| Skin poking along the neckline band | hidden-skin margins of 3–6 cm left skin under the fabric unhidden | skin is hidden where the fabric occludes it from every review camera direction on the rest body and five review bodies; rim skin tucked 8 mm, tapered to zero near openings | hole probe: 0 hidden triangles visible on silhouettes 1–3, 2 on the extreme body (was 26 for the dress before the multi-body rule) |
| White garments vanished on the white mannequin (Gemini #1) | near-white dress form | light warm-grey mannequin (ChatGPT: approved) | lighting study A–F |
| Flat, plastic light (Gemini) | flat ambient fill, no environment | studio environment (generated), clearer key light, soft key shadows (study D, approved); ambient occlusion and hem shading tested, no visible gain at preview scale → off | lighting study |
| Garment insides rendered black (Gemini) | lining drawn with outward normals | the inside is its own inward-facing surface | close-ups |
| Coat could pass through a relaxed tee (v1 Codex) and the guard's own defects (Codex rounds 1–4) | nearest-vertex only; stale normals; opposed normals pushed inward | closest-triangle clearance + compatible nearest-vertex clearance, normals recomputed until nothing moves | offline port of the shell and guard: coat vertices > 1 mm inside the tee 697 → 0, minimum clearance 8.0 mm; XCTests below |
| Re-wearing a garment kept its old photo; padding took the wrong row; loader accepted invalid templates (Codex) | cache keyed by ID only; previous-row fill; no semantic checks | path-keyed cache; nearest-row fill (texture and spans); version, barycentric and seam-twin validation | Codex's XCTests (passing in CI) |
| Avatar screen on small phones | fixed 380 pt stage left ~50 pt for the sliders on an iPhone SE | stage at most half the screen; accurate captions; VoiceOver slider values | code review only (no device) |

Rejected or not adopted, with reasons: soft fade (blur on side views), ambient
occlusion and hem shading (no visible benefit at preview scale), extending the
print onto the sides (ChatGPT: invents product information), any new library
(`OPEN_SOURCE_COMPARISON.md`).

## 2. Review process

- **Codex** (new session "RiG Atelier", own worktree, read-only after round 1): six
  rounds. Round 1: 7 findings + 9 regression tests (merged). Round 2: 6. Round 3: 4.
  Round 4: 3. Round 5: 2 (and a judgement on the changed test, §5). Round 6 (run with
  the Codex CLI after desktop control ended): **no findings**. No P1 in any round;
  every P2 was fixed. Full text: `reviews/codex_review_*.md`.
- **Gemini** (Antigravity CLI, read-only): research pass and an adversarial
  critique of the first renders; 3 of its 5 visual claims were confirmed and fixed,
  its licence claims for libigl and PyTorch3D were corrected.
- **ChatGPT** (new conversation): ranked the defects, approved lighting D and the
  angular mapping, rejected pattern extension, judged "not yet release-ready".

## 3. Validation system

- `Tests/AtelierRenderMatrixTests.swift`: 3 outfits × 2 fabrics × 4 bodies (incl. an
  extreme) × 4 angles (front, 45°, side, 135° back), v1 vs current (+ soft-seam
  variant); close-ups at full resolution. Renders leave CI as public annotations
  (`Tools/CI/render_chunks.py`); the repo's static audit forbids secrets and non-macOS
  jobs, so nothing is pushed from CI.
- `Tools/AvatarAssets/atelier_lab.py`: the runtime maths offline (morphs, binding,
  smoothing, coat shell, layer guard) with probes: `penetration`, `holes`, `check`,
  `winding`, `coat`. Codex's independent `audit_garment_geometry.py`.
- New XCTests: `AtelierGeometryAuditTests` (Codex), `AtelierFixTests`, plus the
  amended coat test (see §5).

## 4. Performance (debug simulator, CI — not iPhone)

| Metric | v1 run | final run |
|---|---|---|
| `engine_outfit_ms` (trousers + tee + shoes, incl. layer guard) | 487 | 422 |
| `body_plus_3_garments_ms` (older shells) | 263 | 200 |
| `asset_load_ms` | 390 | 239 |
| Template asset | 0.322 MB | 0.322 MB |

Runner timings vary run to run (the same metric ranged 461–1106 ms while the guard
was being reworked). Two intermediate versions of the guard were 2× slower; the final
one (bounded to the inner garment's reach, sphere-culled surface queries) is not.

## 5. A test that was changed, and why

`GarmentEngineTests.testOuterLayersStayOutsideInnerGarments` measured clearance from
each coat vertex to the nearest tee vertex *along the coat's normal*. Under the arm the
coat sleeve faces the tee's side; there that metric is only satisfied by pushing the
sleeve through the tee (the behaviour Codex flagged in round 2). The test now applies
that check only where the two surfaces face the same way, and adds an unconditional
closest-surface clearance (≥ 5 mm within 3 cm). Codex judged it "partly a legitimate
correction", but called the 3 cm surface cut-off then used by the guard a weakening.
The cut-off was reverted to 6 cm and Codex's deep-penetration fixture added as a test
(`AtelierFixTests`). Offline port of the coat shell and guard: 0 of 1203 compatible
vertices and 0 of 1155 surface checks fail; minimum clearance 8.0 mm (Codex reproduced
these numbers independently).

## 6. Remaining limitations (honest)

- A-pose only, no cloth simulation; fit is approximate, not a size guide.
- One front photo: sides and back show the garment's main colour, by design.
- Dress folds at the armhole under the arm (10 at rest), stronger on extreme bodies;
  tee 12 at rest (v1: 19).
- On the extreme review body 2 tee triangles of hidden skin can be seen from one of
  36 camera directions (my probe; Codex's sweep found none).
- The skin "tuck" tried during the session was removed (it could expose skin); skin
  under fabric is handled by the hidden-skin rule alone.
- A second ChatGPT checkpoint (before/after grids) was prepared but not posted: desktop
  control ended. ChatGPT's last verdict ("not yet release-ready") predates the
  edge smoothing, crisp seam and hidden-skin rule.
- Debug-simulator timings only; iPhone performance, memory and Metal shader
  compilation on device are unmeasured.
- All evidence uses synthetic striped/plain cutouts; real wardrobe photos untested.

## Reproduce

```
python scripts/static_audit.py
python Tools/AvatarAssets/build_garment_templates.py Support/Avatar/RIGAvatarBody.rigavatar Support/Avatar/RIGGarments.rigarm
python Tools/AvatarAssets/atelier_lab.py penetration|holes|check|coat
python -B Tools/AvatarAssets/audit_garment_geometry.py
```
CI: `.github/workflows/avatar-lab.yml` (manual dispatch; see Final state for the
temporary push trigger).

## Final state

- Branch `polish/rig-atelier` on GitHub; last code commit `e3ebc58`.
- **CI run 38100707061 (`e3ebc58`): green** — build, all 263 RIGTests (incl. the
  Atelier matrix and close-ups, Codex's audit tests and `AtelierFixTests`), 0 failures.
  The commits after it change only reports and the workflow trigger.
- The workflow's temporary push trigger is removed again (manual dispatch only).
- Codex's worktree branch `polish/rig-atelier-codex` is local only; its one commit
  (`7c323b5`, the audit tests) is cherry-picked into this branch.
- Not merged, no PR, `main` untouched, no TestFlight, 0 TRY.
- Images: `images/before_after_*.jpg` (before = run 38089021727 Garment Engine v1,
  after = run 38099901135), `images/closeups_run38099901135.jpg`.
- Next for Batuhan: open the Avatar tab on an iPhone with real wardrobe photos;
  decide whether the 3D preview is good enough to leave "experimental".
