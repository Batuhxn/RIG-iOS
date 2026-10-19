"""Black vs navy (and friends) on catalog / real / cc0, app-exact colour decision.

Variants (measured, not assumed):
  base         current colour prompts, gate 0.7
  pairabstain  if top-2 are an ambiguous pair (black/navy, white/beige, black/gray) and p1 < T: abstain
  pixel        if the embedding says navy, use the masked pixels' dark-region b* (CIELAB) to decide black vs navy
  prompts      navy anchored as "very dark navy blue"/"navy blue" only; black adds "jet black", "black fabric"
"""
import json
import os

import numpy as np

import bench
from bench import ROOT, Encoder, load_benchmark, masked_pixels, srgb_to_lab
from color_embed import COLORS, GENERIC
from dump_parity import softmax

PAIRS = [{"black", "navy"}, {"white", "beige"}, {"black", "gray"}]


def color_entries(enc, colors):
    return [{"label": c, "vector": enc.text([t.format(s) for s in syns for t in GENERIC]).tolist()} for c, syns in colors.items()]


def dark_b(rgba):
    px, _ = masked_pixels(rgba)
    if len(px) < 32:
        return None
    lab = srgb_to_lab(px)
    dark = lab[lab[:, 0] <= np.percentile(lab[:, 0], 50)]
    return float(np.median(dark[:, 2])), float(np.median(dark[:, 0]))


def items_for(which):
    if which == "cc0":
        return json.loads((ROOT / "data/cc0_labels.json").read_text())
    os.environ["RIG_BENCH_SET"] = which
    return load_benchmark()


if __name__ == "__main__":
    enc = Encoder("fashion-clip")
    base_entries = color_entries(enc, COLORS)
    alt = dict(COLORS)
    alt["navy"] = ["navy blue", "very dark navy blue"]
    alt["black"] = ["black", "jet black", "black fabric"]
    prompt_entries = color_entries(enc, alt)
    data = {}
    for s in ("catalog", "real", "cc0"):
        rows = []
        for it in items_for(s):
            if "primaryColor" not in it["expected"]:
                continue
            rgba = bench.cutout(it)
            emb, _ = enc.image(rgba)
            rows.append({"id": it["id"], "truth": it["expected"]["primaryColor"], "emb": emb.tolist(),
                         "dark": dark_b(rgba)})
        data[s] = rows

    def predict(row, variant, thr=0.7, pair_t=0.9, b_t=-4.0):
        entries = prompt_entries if variant == "prompts" else base_entries
        ranked = softmax(row["emb"], entries, 100.0)
        (c1, p1), (c2, _) = ranked[0], ranked[1]
        if p1 < thr:
            return None
        if variant == "pairabstain" and {c1, c2} in PAIRS and p1 < pair_t:
            return None
        if variant == "pixel" and c1 == "navy" and row["dark"] is not None:
            b, L = row["dark"]
            if b > b_t:  # dark pixels not blue enough to be navy
                return "black"
        return c1

    results = {}
    for variant, kw in [("base", {}), ("pairabstain", {"pair_t": 0.9}), ("pairabstain95", {"pair_t": 0.95}),
                        ("pixel", {"b_t": -4.0}), ("pixel-2", {"b_t": -2.0}), ("pixel-6", {"b_t": -6.0}),
                        ("prompts", {})]:
        name = variant.split("-")[0].replace("95", "")
        line = []
        for s, rows in data.items():
            preds = [(r["truth"], predict(r, name, **kw)) for r in rows]
            sug = [(t, p) for t, p in preds if p is not None]
            cor = sum(t == p for t, p in sug)
            line.append(f"{s}: {cor}/{len(sug)} of {len(preds)} prec {cor / max(1, len(sug)):.3f} rec {cor / max(1, len(preds)):.3f}")
            results.setdefault(variant, {})[s] = (cor, len(sug), len(preds))
        print(f"{variant:14s} " + " | ".join(line), flush=True)
    # How separable is black vs navy by pixels on these sets?
    for s, rows in data.items():
        bn = [(r["truth"], r["dark"][0]) for r in rows if r["truth"] in ("black", "navy") and r["dark"]]
        for t in ("black", "navy"):
            v = sorted(b for tt, b in bn if tt == t)
            if v:
                print(f"{s} {t}: dark b* median {np.median(v):.1f} range {v[0]:.1f}..{v[-1]:.1f} n={len(v)}")
    (ROOT / "results/color_experiments.json").write_text(json.dumps(results, indent=1))
