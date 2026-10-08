"""End-to-end Auto Metadata check on a macOS runner, with the app's own Swift pipeline.

  python e2e.py prepare OUT     fixtures (311 cutouts + ground truth) for
                                Tests/AutoMetadataBenchmarkTests.swift, plus the decisions of
                                the SAME bundled model run from Python (PIL letterbox ->
                                Core ML -> decide), which isolates Swift preprocessing.
  python e2e.py summarize OUT   compare Swift observations with that reference and with
                                ground truth; print public annotations; fail on a gate breach.

Gate: zero prefilled VALUE FLIPS between Swift and the Python Core ML reference; Swift
category/subtype precision on catalogue within 1 pp of the reference.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
REPO = ROOT.parents[1]
sys.path.insert(0, str(HERE))
PREFILLED = ("category", "subtype", "length", "primaryColor")


def prepare(out):
    import coremltools as ct
    import bench
    from ci_parity import compose_real, letterbox_tensor
    from dump_parity import decide

    subprocess.run([sys.executable, str(HERE / "fetch_images.py")], check=True, cwd=HERE)
    compose_real()
    model = ct.models.MLModel(str(REPO / "Resources/Models/RIGGarmentEncoder.mlmodel"))
    manifest = json.loads((REPO / "Resources/Models/RIGGarmentPrompts.json").read_text())
    (out / "cutouts").mkdir(parents=True, exist_ok=True)
    fixtures, reference = [], {}
    for which in ("catalog", "real"):
        os.environ["RIG_BENCH_SET"] = which
        for it in bench.load_benchmark():
            rgba = bench.cutout(it)
            dst = out / "cutouts" / f"{it['id']}.png"
            rgba.save(dst)
            fixtures.append({"id": it["id"], "cutout": f"cutouts/{it['id']}.png",
                             "expected": {k: str(v) for k, v in it["expected"].items()}, "set": which})
            emb = model.predict({"image": letterbox_tensor(rgba)})["embedding"].reshape(-1)
            reference[it["id"]] = decide([float(x) for x in emb], manifest)
    (out / "manifest.json").write_text(json.dumps(fixtures))
    (out / "python_coreml_reference.json").write_text(json.dumps(reference))
    print(f"prepared {len(fixtures)} fixtures; modelID {manifest['modelID']}")


def precision(rows, key, field):
    el = [r for r in rows if field in r["expected"]]
    sug = [r for r in el if field in r[key]]
    cor = sum(r[key][field] == r["expected"][field] for r in sug)
    return cor, len(sug), len(el)


def summarize(out):
    fixture_list = json.loads((out / "manifest.json").read_text())
    fixtures = {f["id"]: f for f in fixture_list}
    if len(fixtures) < 2 or len(fixtures) != len(fixture_list):
        raise ValueError("E2E requires nonempty, unique cold and warm fixtures")
    reference = json.loads((out / "python_coreml_reference.json").read_text())
    obs = json.loads((out / "observations.json").read_text())
    ids = [o["id"] for o in obs]
    if len(ids) != len(set(ids)) or set(ids) != set(fixtures) or set(reference) != set(fixtures):
        raise ValueError("E2E observations/reference must cover every fixture exactly once")
    if sum(bool(o["cold"]) for o in obs) != 1:
        raise ValueError("E2E requires exactly one cold observation")
    for o in obs:
        if o["expected"] != fixtures[o["id"]]["expected"]:
            raise ValueError("E2E observation ground truth differs from its fixture")
        if o.get("semanticStatus") not in ("suggested", "abstained"):
            raise ValueError("E2E requires a successful classifier for every fixture")
    rows, flips, moves, ms = [], [], 0, []
    for o in obs:
        swift = dict(o["predicted"])
        swift.pop("secondaryColor", None)
        alts = swift.pop("subtypeAlternatives", None)
        ref = dict(reference[o["id"]])
        ref.pop("subtypeAlternatives", None)
        for f in PREFILLED:
            a, b = ref.get(f), swift.get(f)
            if a != b:
                if a is not None and b is not None:
                    flips.append(f"{o['id']} {f} {a}->{b} truth={o['expected'].get(f)}")
                else:
                    moves += 1
        rows.append({"set": fixtures[o["id"]]["set"], "expected": o["expected"], "swift": swift, "ref": ref})
        if not o["cold"]:
            ms.append(o["milliseconds"])
    ms.sort()
    worst_drop = 0.0
    for split in ("catalog", "real"):
        part = [r for r in rows if r["set"] == split]
        line = []
        for f in PREFILLED:
            c, n, l = precision(part, "swift", f)
            rc, rn, _ = precision(part, "ref", f)
            if f in ("category", "subtype") and split == "catalog" and rn:
                # A total loss of suggestions cannot establish retained precision.
                worst_drop = max(worst_drop, rc / rn - (c / n if n else 0.0))
            line.append(f"{f}={c}/{n} of {l} (ref {rc}/{rn})")
        print(f"::notice title=E2E Swift {split}::" + " | ".join(line))
    cold = next(o["milliseconds"] for o in obs if o["cold"])
    print(f"::notice title=E2E simulator proxy (not iPhone)::cold first garment {cold:.0f} ms; warm p50 "
          f"{ms[len(ms) // 2]:.0f} ms p95 {ms[int(0.95 * len(ms)) - 1]:.0f} ms (bg-removal excluded; analyze() only)")
    print(f"::notice title=E2E Swift vs Python Core ML::{len(obs)} items, value flips {len(flips)}, "
          f"suggest/abstain moves {moves}, worst catalog precision drop {worst_drop:.4f}")
    for f in flips[:10]:
        print(f"::warning title=E2E flip::{f}")
    ok = not flips and worst_drop <= 0.01
    print(f"E2E gate {'PASS' if ok else 'FAIL'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    cmd, out = sys.argv[1], Path(sys.argv[2]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    {"prepare": prepare, "summarize": summarize}[cmd](out)
