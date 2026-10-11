Codex round 6 (codex-cli exec, read-only, model gpt-6-astra; the app session could not be driven any more), reviewing 512c58f..e3ebc58:

No P1/P2/P3 findings. Both round-5 P2 findings are resolved.
- Sphere early-out (AvatarOutfitBuilder.swift 240-244, 277-280): the sphere contains the whole triangle, so max(0, |p-c| - r) is a lower bound on triangle distance; it cannot reject a strictly closer triangle.
- Bounds filter (91-103): outside the bounds expanded by reach, a vertex is more than reach from every inner triangle and vertex, so neither query could trigger a push; eligibility is rebuilt per inner garment per round.
- Coverage and tuck (52, 63, 77, 103): 6 cm surface reach restored; visible skin uses the original positions; AtelierFixTests 56-65 reproduces the deep-penetration fixture.
Read-only source review; git diff --check passed; XCTests not rerun locally (CI run 38100707061 reported 263/0).
