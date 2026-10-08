"""Colour from the already-computed image embedding (zero extra inference) vs pixel extractors.

Variants: generic colour prompts; subtype-conditioned prompts ("a navy blazer") using the
predicted subtype; and a hybrid that trusts pixels only for confident achromatic/dominant cases.
"""
import json
import os
import sys
from collections import Counter

import numpy as np
from PIL import Image

import bench
from bench import ROOT, ENSEMBLE, Encoder, build_classes, color_lab, ensemble_groups, load_benchmark, predict, softmax_rank

COLORS = {
    "black": ["black"], "white": ["white", "off-white"], "gray": ["gray", "grey", "charcoal gray"],
    "beige": ["beige", "camel", "cream", "tan"], "brown": ["brown", "chocolate brown"],
    "navy": ["navy blue", "dark navy"], "blue": ["blue", "light blue", "denim blue"],
    "green": ["green", "emerald green"], "olive": ["olive green", "khaki green"], "red": ["red"],
    "burgundy": ["burgundy", "wine red", "maroon"], "pink": ["pink", "blush pink", "hot pink"],
    "purple": ["purple", "lilac"], "orange": ["orange"], "yellow": ["yellow", "mustard yellow"],
    "metallic": ["metallic gold", "metallic silver", "shiny metallic"],
}
GENERIC = ["a photo of a {} garment.", "a product photo of {} clothing.", "a {} piece of clothing.", "something {}-colored."]
NOUN = {sub: syns[0] for cat in ENSEMBLE.values() for sub, syns in cat.items()}


def color_groups(noun=None):
    t = [f"a photo of {{}} {noun}.", f"a product photo of {{}} {noun}.", f"{{}} {noun} on a white background."] if noun else GENERIC
    return {"color": {c: [tpl.format(s) for s in syns for tpl in t] for c, syns in COLORS.items()}}


if __name__ == "__main__":
    key = sys.argv[1] if len(sys.argv) > 1 else "fashion-clip"
    enc = Encoder(key)
    groups = ensemble_groups()
    cls = build_classes(enc, groups)
    generic = build_classes(enc, color_groups())["color"]
    per_noun = {}
    report = {}
    for which in ("catalog", "real"):
        os.environ["RIG_BENCH_SET"] = which
        items = [it for it in load_benchmark() if it["expected"].get("primaryColor")]
        rows = Counter()
        conf = Counter()
        for it in items:
            rgba = bench.cutout(it)
            emb, _ = enc.image(rgba)
            pred, aux = predict(enc, emb, cls, "flat")
            noun = NOUN.get(aux["subtype_top1"], "clothing")
            if noun not in per_noun:
                per_noun[noun] = build_classes(enc, color_groups(noun))["color"]
            g = softmax_rank(emb, *generic)
            s = softmax_rank(emb, *per_noun[noun])
            px = color_lab(rgba)[0]
            exp = it["expected"]["primaryColor"]
            # hybrid: embedding decides, except pixels win when they agree with the embedding's top-2
            top2 = [s[0][0], s[1][0]]
            hyb = px if px in top2 and s[0][1] < 0.6 else s[0][0]
            for name, p in (("pixel-lab", px), ("embed-generic", g[0][0]), ("embed-subtype", s[0][0]), ("hybrid", hyb)):
                rows[name] += p == exp
                rows[name + " (non-metallic)"] += p == exp if exp != "metallic" else 0
                if name == "embed-subtype" and p != exp:
                    conf[f"{exp}->{p}"] += 1
            # confidence gating for embed-subtype
            for thr in (0.5, 0.7):
                if s[0][1] >= thr:
                    rows[f"embed-subtype@{thr} suggested"] += 1
                    rows[f"embed-subtype@{thr} correct"] += s[0][0] == exp
        n = len(items)
        nm = sum(it["expected"]["primaryColor"] != "metallic" for it in items)
        report[which] = {k: round(v / (nm if "non-metallic" in k else n), 3) for k, v in rows.items() if "@" not in k}
        for thr in (0.5, 0.7):
            sug, cor = rows[f"embed-subtype@{thr} suggested"], rows[f"embed-subtype@{thr} correct"]
            report[which][f"embed-subtype@{thr}"] = {"coverage": round(sug / n, 3), "accuracy_suggested": round(cor / max(sug, 1), 3)}
        report[which]["n"] = n
        report[which]["confusions"] = conf.most_common(10)
        print(which, json.dumps(report[which]), flush=True)
    (ROOT / f"results/color_embed_{key}.json").write_text(json.dumps(report, indent=1))
