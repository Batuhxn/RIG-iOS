"""Measure Gemini round-1 hypotheses (data/gemini_round1.md) with the app's exact rule.

Adoption rule (ChatGPT/product): a change is kept only if category and kind precision do
not drop on any split and coverage (recall) does not fall at equal precision.
"""
import copy
import json
import os
import sys

from PIL import Image

import bench
from bench import ROOT, Encoder, load_benchmark
from color_embed import COLORS, GENERIC, color_groups
from dump_parity import decide

FIELDS = ("category", "subtype", "length", "primaryColor")


def apply_gemini(ens, hard_negatives=False):
    e = copy.deepcopy(ens)
    t, o, s = e["top"], e["outerwear"], e["shoes"]
    t["sweater"] = [x for x in t["sweater"] if x != "a sweatshirt"] + ["a chunky knit wool pullover", "a ribbed crewneck sweater"]
    o["coat"] += ["a long tailored overcoat", "an outerwear trench coat"]
    s["heels"] = [x for x in s["heels"] if x != "high heels"] + ["pointed stiletto pumps", "open high heel sandals"]
    s["boots"] += ["tall shaft boots", "ankle boots covering the ankle"]
    s["flats"] += ["flat slip-on loafers", "zero-heel ballet flats"]
    t["blouse"] = [x for x in t["blouse"] if x != "a blouse"] + ["a dressy woven buttoned blouse", "a silk work blouse"]
    t["t-shirt"] += ["a casual cotton jersey tee"]
    e["dress"]["dress"] += ["a one-piece full-body dress", "a dress with connected bodice and skirt"]
    if hard_negatives:
        s["boots"] += ["boots with an upper shaft, not low-top flats or exposed pumps"]
        s["flats"] += ["flat-soled shoes with no elevated heel"]
        e["dress"]["dress"] += ["a continuous one-piece dress, not a separate blouse or top"]
        e["bottom"]["trousers"] += ["dress pants or slacks, not denim jeans"]
    return e


def manifest(enc, ens):
    groups = {"flat": {}}
    for cat, subs in ens.items():
        for sub, syns in subs.items():
            groups["flat"][f"{cat}/{sub}"] = [t.format(x) for x in syns for t in bench.TEMPLATES]
    for noun, lens in bench.LENGTH_ENSEMBLE.items():
        cat = "bottom" if noun == "skirt" else "dress"
        groups["length." + cat] = {k: [t.format(x) for x in v for t in bench.TEMPLATES] for k, v in lens.items()}
    g = {k: [{"label": l, "vector": enc.text(p).tolist()} for l, p in v.items()] for k, v in groups.items()}
    g["color"] = [{"label": k, "vector": enc.text(v).tolist()} for k, v in color_groups()["color"].items()]
    return {"logitScale": 100.0, "threshold": 0.7, "groups": g}


def score(rows):
    out = {}
    for f in FIELDS:
        el = [r for r in rows if f in r["expected"]]
        sug = [r for r in el if f in r["pred"]]
        cor = sum(r["pred"][f] == r["expected"][f] for r in sug)
        out[f] = (cor, len(sug), len(el))
    return out


def items_for(which):
    if which == "cc0":
        p = ROOT / "data/cc0_labels.json"
        return json.loads(p.read_text()) if p.exists() else []
    os.environ["RIG_BENCH_SET"] = which
    return load_benchmark()


if __name__ == "__main__":
    enc = Encoder("fashion-clip")
    sets = [s for s in ("catalog", "real", "cc0") if items_for(s)]
    data = {s: [(it, bench.cutout(it)) for it in items_for(s)] for s in sets}
    prompt_variants = {"baseline": bench.ENSEMBLE, "gemini": apply_gemini(bench.ENSEMBLE),
                       "gemini+neg": apply_gemini(bench.ENSEMBLE, True)}
    preprocess = {"white": ("white", 1.0), "gray240": ((240, 240, 240), 1.0), "gray128": ((128, 128, 128), 1.0),
                  "pad90": ("white", 0.9)}

    def embed(rgba, bg, frac):
        canvas_bg = Image.new("RGB", rgba.size, bg)
        canvas_bg.paste(rgba, mask=rgba.split()[3])
        size = enc.size
        s = size * frac / max(canvas_bg.size)
        im = canvas_bg.resize((max(1, round(canvas_bg.width * s)), max(1, round(canvas_bg.height * s))), Image.BICUBIC)
        canvas = Image.new("RGB", (size, size), bg)
        canvas.paste(im, ((size - im.width) // 2, (size - im.height) // 2))
        x = enc.proc(images=canvas, return_tensors="pt", do_resize=False, do_center_crop=False)
        import torch
        with torch.no_grad():
            v = enc.model.get_image_features(pixel_values=x["pixel_values"])
        return torch.nn.functional.normalize(v, dim=-1)[0].numpy()

    manifests = {k: manifest(enc, v) for k, v in prompt_variants.items()}
    results = {}
    for pname, (bg, frac) in preprocess.items():
        embs = {s: [embed(rgba, bg, frac) for _, rgba in data[s]] for s in sets}
        for mname, m in manifests.items():
            if pname != "white" and mname != "baseline":
                continue  # one factor at a time
            key = f"{mname}|{pname}"
            results[key] = {}
            for s in sets:
                rows = [{"expected": it["expected"], "pred": decide(e.tolist(), m)} for (it, _), e in zip(data[s], embs[s])]
                results[key][s] = score(rows)
            line = " | ".join(f"{s}: " + " ".join(f"{f[:3]}={c}/{n}/{l}" for f, (c, n, l) in results[key][s].items()) for s in sets)
            print(f"{key:22s} {line}", flush=True)
    (ROOT / "results/prompt_experiments.json").write_text(json.dumps(results, indent=1))
