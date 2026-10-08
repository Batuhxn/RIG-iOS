"""Write device-fixtures/ for Tests/AutoMetadataBenchmarkTests.swift (RIG_METADATA_FIXTURES=.../manifest.json).

Each cutout is the same RGBA PNG the offline benchmark scored, so on-device results are
directly comparable with results/ (expected labels are the reviewed ground truth).
"""
import json
import os
import shutil

from bench import ROOT, cutout, load_benchmark

if __name__ == "__main__":
    out = ROOT / "device-fixtures"
    (out / "cutouts").mkdir(parents=True, exist_ok=True)
    rows = []
    for which in ("catalog", "real"):
        os.environ["RIG_BENCH_SET"] = which
        for it in load_benchmark():
            cutout(it)  # ensures the PNG exists
            src = ROOT / "data/cutouts" / f"{it['id']}.png" if which == "catalog" else ROOT / it["image"]
            dst = out / "cutouts" / f"{it['id']}.png"
            shutil.copyfile(src, dst)
            rows.append({"id": it["id"], "cutout": f"cutouts/{it['id']}.png",
                         "expected": {k: str(v) for k, v in it["expected"].items()}})
    (out / "manifest.json").write_text(json.dumps(rows, indent=0))
    print(len(rows), "fixtures ->", out)
