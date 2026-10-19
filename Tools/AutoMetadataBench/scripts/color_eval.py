"""Colour-only evaluation: Codex HSV vs Lab v1/v2, split by index parity (even=tune, odd=held out).

Metallic is reported separately: pixel statistics cannot see specularity, so RiG treats it as manual-only.
Shoes are reported separately because insoles/footbeds dominate the visible pixels.
"""
import json
from collections import Counter

from PIL import Image

import bench
from bench import ROOT, color_codex, color_lab, load_benchmark


def acc(rows):
    return f"{sum(p == e for e, p in rows) / len(rows):.3f} (n={len(rows)})" if rows else "-"


if __name__ == "__main__":
    items = [it for it in load_benchmark() if it["expected"].get("primaryColor")]
    cut = {it["id"]: Image.open(ROOT / "data/cutouts" / f"{it['id']}.png") for it in items}
    report = {}
    for name in ("codex-hsv", "lab-v1", "lab-v2"):
        if name.startswith("lab"):
            bench.LAB_VERSION = int(name[-1])
        fn = color_codex if name == "codex-hsv" else color_lab
        preds = {it["id"]: fn(cut[it["id"]])[0] for it in items}
        groups = {
            "all": items,
            "non-metallic": [i for i in items if i["expected"]["primaryColor"] != "metallic"],
            "non-metallic even (tune)": [i for i in items if i["expected"]["primaryColor"] != "metallic" and i["index"] % 2 == 0],
            "non-metallic odd (held-out)": [i for i in items if i["expected"]["primaryColor"] != "metallic" and i["index"] % 2 == 1],
            "non-metallic apparel": [i for i in items if i["expected"]["primaryColor"] != "metallic" and i["expected"]["category"] != "shoes"],
            "non-metallic shoes": [i for i in items if i["expected"]["primaryColor"] != "metallic" and i["expected"]["category"] == "shoes"],
        }
        report[name] = {g: acc([(i["expected"]["primaryColor"], preds[i["id"]]) for i in rows]) for g, rows in groups.items()}
        report[name]["confusions"] = Counter(f"{i['expected']['primaryColor']}->{preds[i['id']]}" for i in groups["non-metallic"]
                                             if preds[i["id"]] != i["expected"]["primaryColor"]).most_common(10)
        print(name, json.dumps(report[name]))
    (ROOT / "results/color_eval.json").write_text(json.dumps(report, indent=1))
