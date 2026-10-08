"""App-exact comparison of encoders: each model gets its own prompt manifest (same prompts),
the same GarmentEmbeddingDecision rule (dump_parity.decide), per split.

Usage: python compare_models.py fashion-clip fashion-clip-v1 [--sets catalog,real,cc0]
"""
import json
import os
import sys

import bench
from bench import ROOT, Encoder, ensemble_groups, load_benchmark
from color_embed import color_groups
from dump_parity import decide

FIELDS = ("category", "subtype", "length", "primaryColor")


def manifest_for(enc):
    groups = ensemble_groups()
    g = {name: [{"label": k, "vector": enc.text(v).tolist()} for k, v in groups[name].items()]
         for name in ("flat", "length.bottom", "length.dress")}
    g["color"] = [{"label": k, "vector": enc.text(v).tolist()} for k, v in color_groups()["color"].items()]
    return {"logitScale": 100.0, "threshold": 0.7, "groups": g}


def load_cc0():
    p = ROOT / "data/cc0_labels.json"
    return json.loads(p.read_text()) if p.exists() else []


def score(rows):
    out = {}
    for f in FIELDS:
        el = [r for r in rows if f in r["expected"]]
        sug = [r for r in el if f in r["pred"]]
        cor = sum(r["pred"][f] == r["expected"][f] for r in sug)
        out[f] = f"{cor}/{len(sug)} of {len(el)} (prec {cor / max(1, len(sug)):.3f}, rec {cor / max(1, len(el)):.3f})"
    return out


if __name__ == "__main__":
    keys = [a for a in sys.argv[1:] if not a.startswith("--")]
    sets = next((a.split("=")[1] for a in sys.argv if a.startswith("--sets=")), "catalog,real").split(",")
    report = {}
    for key in keys:
        enc = Encoder(key)
        m = manifest_for(enc)
        report[key] = {}
        for which in sets:
            if which == "cc0":
                items = load_cc0()
            else:
                os.environ["RIG_BENCH_SET"] = which
                items = load_benchmark()
            rows = []
            for it in items:
                emb, _ = enc.image(bench.cutout(it))
                rows.append({"id": it["id"], "expected": it["expected"], "pred": decide(emb.tolist(), m)})
            report[key][which] = score(rows)
            report[key][which + "_rows"] = rows
            print(key, which, json.dumps(report[key][which]), flush=True)
    (ROOT / f"results/compare_{'_'.join(keys)}.json").write_text(json.dumps(report, indent=1))
