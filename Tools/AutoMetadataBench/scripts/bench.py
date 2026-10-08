"""RiG v0.3 Auto Metadata offline benchmark.

Replicates the Swift pipeline in Codex's feat/v0.3-auto-metadata-main branch
(CoreMLGarmentClassifier + EmbeddingRanking + MaskedColorExtractor) on CPU, and compares
variants (prompt ensembles, flat vs hierarchical, other permissive encoders, Lab colour).

Usage: python bench.py [model ...]     (default: all)
Outputs results/summary.json, results/report.md, results/observations_<config>.json
"""
import colorsys
import json
import math
import os
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
torch.set_num_threads(min(8, os.cpu_count() or 1))

# Pinned so CI re-exports exactly the evaluated weights.
REVISIONS = {"fashion-clip": "7e3ba62ce16b379a1ab479346b66f192e76f51b7"}

MODELS = {
    "clip-b32": "openai/clip-vit-base-patch32",
    "clip-b16": "openai/clip-vit-base-patch16",
    "fashion-clip": "patrickjohncyh/fashion-clip",
    "siglip-b16": "google/siglip-base-patch16-224",
}

# ---------------------------------------------------------------- data

def load_benchmark():
    items = json.loads((ROOT / "data/selection.json").read_text(encoding="utf-8"))
    overrides = json.loads((ROOT / "data/review_overrides.json").read_text(encoding="utf-8"))
    out = []
    for i, item in enumerate(items):
        o = overrides.get(str(i), {})
        if o.get("exclude"):
            continue
        e = dict(item["expected"])
        for k, v in o.items():
            if v is None:
                e.pop(k, None)
            elif k != "exclude":
                e[k] = v
        if e["category"] == "bag":  # bag subtypes are not distinguished in v0.3 ground truth
            e.pop("subtype", None)
        if e.get("subtype") not in ("skirt", "dress"):
            e.pop("length", None)
        out.append({**item, "index": i, "expected": e})
    extra = ROOT / "data/real_photos.json"  # hand-labelled phone photos with BEN2 cutouts
    real = json.loads(extra.read_text(encoding="utf-8")) if extra.exists() else []
    which = os.environ.get("RIG_BENCH_SET", "catalog")
    return {"catalog": out, "real": real, "all": out + real}[which]


def cutout(item):
    """Approximate the app's subject-lift cutout: flood-fill near-white background from the border.

    Polyvore images are catalogue shots on white; photos with real backgrounds yield an
    (honestly) poor mask, which is recorded as mask_coverage.
    """
    path = ROOT / "data/cutouts" / f"{item['id']}.png"
    if path.exists():
        return Image.open(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    src = ROOT / item.get("image", f"data/images/{item['id']}.jpg")
    img = Image.open(src).convert("RGB")
    if img.mode == "RGBA" or src.suffix.lower() == ".png" and Image.open(src).mode == "RGBA":
        rgba = Image.open(src).convert("RGBA")
    else:
        work = img.copy()
        sentinel = (255, 0, 254)
        w, h = work.size
        seeds = [(x, 0) for x in range(0, w, max(1, w // 20))] + [(x, h - 1) for x in range(0, w, max(1, w // 20))]
        seeds += [(0, y) for y in range(0, h, max(1, h // 20))] + [(w - 1, y) for y in range(0, h, max(1, h // 20))]
        for s in seeds:
            px = work.getpixel(s)
            if px != sentinel and min(px) >= 225:
                ImageDraw.floodfill(work, s, sentinel, thresh=18)
        arr = np.asarray(work)
        bg = np.all(arr == np.array(sentinel, dtype=np.uint8), axis=-1)
        alpha = np.where(bg, 0, 255).astype(np.uint8)
        rgba = Image.fromarray(np.dstack([np.asarray(img), alpha]), "RGBA")
    rgba.save(path)
    return rgba


# ---------------------------------------------------------------- colour

def codex_family(r, g, b):
    """Exact port of MaskedColorExtractor.family (HSV fixed boundaries)."""
    mx, mn = max(r, g, b), min(r, g, b)
    delta = mx - mn
    sat = 0 if mx == 0 else delta / mx
    if mx < 0.16:
        return "black"
    if sat < 0.12:
        return "white" if mx > 0.85 else "gray"
    if mx == r:
        hue = 60 * math.fmod((g - b) / delta, 6)
    elif mx == g:
        hue = 60 * ((b - r) / delta + 2)
    else:
        hue = 60 * ((r - g) / delta + 4)
    if hue < 0:
        hue += 360
    if 20 <= hue < 65 and sat < 0.4 and mx > 0.6:
        return "beige"
    if hue < 15 or hue >= 345:
        return "burgundy" if mx < 0.5 else ("pink" if sat < 0.5 else "red")
    if hue < 45:
        return "brown" if mx < 0.65 else "orange"
    if hue < 70:
        return "yellow"
    if hue < 100:
        return "olive"
    if hue < 175:
        return "green"
    if hue < 260:
        return "navy" if mx < 0.45 else "blue"
    if hue < 310:
        return "purple"
    return "pink"


def masked_pixels(rgba, max_dim=192):
    im = rgba.copy()
    im.thumbnail((max_dim, max_dim))
    a = np.asarray(im).reshape(-1, 4).astype(np.float64)
    keep = a[:, 3] >= 230
    return a[keep, :3] / 255.0, keep.mean()


def color_codex(rgba):
    px, _ = masked_pixels(rgba)
    if len(px) < 32:
        return None, None
    counts = Counter(codex_family(*p) for p in px)
    ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    primary = ranked[0][0]
    secondary = ranked[1][0] if len(ranked) > 1 and ranked[1][1] / len(px) >= 0.15 else None
    return primary, secondary


# Lab prototypes for RiG's palette (sRGB anchors -> CIELAB). Metallic/multicolor excluded.
PALETTE_RGB = {
    "black": [(20, 20, 22), (40, 40, 42)], "white": [(245, 245, 242), (232, 230, 225)],
    "gray": [(128, 128, 128), (180, 180, 182), (85, 85, 88)], "beige": [(225, 205, 175), (200, 175, 140)],
    "brown": [(110, 70, 40), (150, 95, 55), (80, 55, 40)], "navy": [(30, 40, 75), (25, 30, 55), (45, 55, 95)],
    "blue": [(50, 100, 200), (130, 170, 220), (70, 110, 170), (60, 70, 180), (170, 200, 230), (100, 130, 165)],
    "green": [(40, 140, 70), (120, 190, 120), (20, 90, 50)],
    "olive": [(110, 110, 50), (90, 95, 60)], "red": [(200, 30, 35), (230, 60, 50)],
    "burgundy": [(110, 25, 40), (90, 20, 35)], "pink": [(240, 160, 180), (230, 100, 150), (245, 200, 205)],
    "purple": [(110, 50, 150), (170, 140, 200), (70, 40, 110)], "orange": [(240, 120, 40), (230, 90, 50)],
    "pink_pale": [(245, 215, 220), (240, 200, 205)],
    "yellow": [(240, 210, 50), (220, 170, 50)],
}


def srgb_to_lab(rgb):
    rgb = np.asarray(rgb, dtype=np.float64)
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
    xyz = lin @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


PROTO_NAMES, PROTO_LAB = zip(*[(n, srgb_to_lab(np.array(c) / 255.0)) for n, cs in PALETTE_RGB.items() for c in cs])
PROTO_LAB = np.array(PROTO_LAB)


def kmeans(x, k, iters=20, seed=0):
    rng = np.random.default_rng(seed)
    c = x[rng.choice(len(x), size=min(k, len(x)), replace=False)]
    for _ in range(iters):
        d = ((x[:, None] - c[None]) ** 2).sum(-1)
        lab = d.argmin(1)
        c = np.array([x[lab == j].mean(0) if (lab == j).any() else c[j] for j in range(len(c))])
    return c, np.bincount(lab, minlength=len(c))


LAB_VERSION = 2


def lab_name(lab):
    L, a, b = lab
    chroma = math.hypot(a, b)
    if LAB_VERSION == 1:
        if chroma < 9:
            return "black" if L < 25 else "white" if L > 88 else "gray"
        if L < 18 and chroma < 18:
            return "black"
    else:
        # v2: black fabric with sheen sits at L 15-30 with a faint cast; light tints (baby blue,
        # blush) keep chroma ~7-12, so the achromatic cut is lower and lightness-scaled.
        if L < 24 and chroma < 12:
            return "black"
        if chroma < (5 if L > 80 else 7):
            return "black" if L < 28 else "white" if L > 86 else "gray"
    d = ((PROTO_LAB - lab) ** 2 * np.array([0.6, 1.0, 1.0])).sum(1)
    return PROTO_NAMES[int(d.argmin())].replace("_pale", "")


def color_lab(rgba, k=4):
    """Lab k-means over masked pixels, clusters named by nearest palette prototype; edge-trimmed."""
    px, _ = masked_pixels(rgba)
    if len(px) < 32:
        return None, None
    lab = srgb_to_lab(px)
    centers, counts = kmeans(lab, k)
    votes = Counter()
    for c, n in zip(centers, counts):
        if n:
            votes[lab_name(c)] += n
    ranked = votes.most_common()
    total = sum(votes.values())
    primary = ranked[0][0]
    secondary = ranked[1][0] if len(ranked) > 1 and ranked[1][1] / total >= 0.2 else None
    return primary, secondary


# ---------------------------------------------------------------- semantics

CODEX_SUBTYPES = {
    "top": ["t-shirt", "shirt", "blouse", "sweater", "hoodie", "tank top"],
    "bottom": ["skirt", "trousers", "jeans", "shorts", "leggings"],
    "dress": ["dress", "jumpsuit"],
    "outerwear": ["jacket", "coat", "blazer", "cardigan"],
    "shoes": ["sneakers", "boots", "sandals", "heels", "loafers"],
    "bag": ["handbag", "backpack", "tote bag", "clutch"],
    "accessory": ["hat", "scarf", "belt", "sunglasses", "watch"],
}
CODEX_CATEGORIES = {"top": "upper body clothing", "bottom": "lower body clothing", "dress": "a dress or jumpsuit",
                    "outerwear": "outerwear", "shoes": "footwear", "bag": "a bag", "accessory": "a fashion accessory"}


def codex_groups():
    g = {"category": {k: [f"a photo of {v}"] for k, v in CODEX_CATEGORIES.items()}}
    for cat, subs in CODEX_SUBTYPES.items():
        g["subtype." + cat] = {s: [f"a photo of {s}"] for s in subs}
    for cat, noun in [("bottom", "skirt"), ("dress", "dress")]:
        g["length." + cat] = {l: [f"a photo of {l} {noun}"] for l in ("mini", "midi", "maxi")}
    return g


TEMPLATES = ["a product photo of {}.", "a photo of {}.", "{} on a white background.",
             "an online store photo of {}.", "a cutout photo of {}, isolated."]
ENSEMBLE = {
    "top": {"t-shirt": ["a t-shirt", "a short-sleeve tee", "a graphic t-shirt", "a cotton crew-neck t-shirt"],
            "shirt": ["a button-up shirt", "a collared shirt", "a button-down shirt with cuffs"],
            "blouse": ["a blouse", "a women's blouse", "a flowy chiffon blouse", "a ruffled blouse"],
            "sweater": ["a knit sweater", "a pullover sweater", "a crewneck jumper", "a sweatshirt"],
            "hoodie": ["a hoodie", "a hooded sweatshirt", "a zip-up hoodie with drawstrings"],
            "tank top": ["a tank top", "a camisole", "a sleeveless top with thin straps", "a crop tank top"]},
    "bottom": {"jeans": ["jeans", "denim jeans", "a pair of skinny jeans", "ripped jeans"],
               "trousers": ["trousers", "a pair of pants", "tailored trousers", "wide-leg pants", "leggings"],
               "shorts": ["shorts", "a pair of shorts", "denim shorts", "high-waisted shorts"],
               "skirt": ["a skirt", "a mini skirt", "a midi skirt", "a maxi skirt", "a pencil skirt", "a pleated skirt"]},
    "dress": {"dress": ["a dress", "a mini dress", "a midi dress", "a maxi dress", "a sleeveless dress", "a long-sleeve dress"]},
    "outerwear": {"jacket": ["a jacket", "a leather jacket", "a bomber jacket", "a denim jacket", "a biker jacket"],
                  "coat": ["a coat", "a long overcoat", "a trench coat", "a wool coat", "a faux fur coat"],
                  "blazer": ["a blazer", "a tailored blazer", "a suit jacket with lapels"],
                  "cardigan": ["a cardigan", "a knit cardigan", "an open-front cardigan", "a button-up knit cardigan"]},
    "shoes": {"sneakers": ["sneakers", "trainers", "a pair of sneakers", "canvas sneakers"],
              "boots": ["boots", "ankle boots", "a pair of boots", "knee-high boots", "heeled ankle boots"],
              "heels": ["high heels", "pumps", "stiletto heels", "high heel shoes"],
              "flats": ["ballet flats", "flat shoes", "pointed flats", "loafers"],
              "sandals": ["sandals", "flat sandals", "slides", "strappy sandals"]},
    "bag": {"bag": ["a handbag", "a bag", "a clutch", "a tote bag", "a shoulder bag", "a backpack"]},
    "accessory": {"hat": ["a hat"], "scarf": ["a scarf"], "belt": ["a belt"], "sunglasses": ["sunglasses"],
                  "jewelry": ["jewelry", "a necklace"], "watch": ["a watch"]},
}
LENGTH_ENSEMBLE = {
    "skirt": {"mini": ["a mini skirt", "a short mini skirt", "a skirt well above the knee"],
              "midi": ["a midi skirt", "a mid-calf length skirt", "a below-the-knee skirt"],
              "maxi": ["a maxi skirt", "a long floor-length skirt", "an ankle-length skirt"]},
    "dress": {"mini": ["a mini dress", "a short mini dress", "a dress well above the knee"],
              "midi": ["a midi dress", "a mid-calf length dress", "a below-the-knee dress"],
              "maxi": ["a maxi dress", "a long floor-length gown", "an ankle-length dress"]},
}


class Encoder:
    def __init__(self, key):
        from transformers import AutoModel, AutoProcessor
        self.key, self.repo = key, MODELS[key]
        rev = REVISIONS.get(key)
        self.model = AutoModel.from_pretrained(self.repo, revision=rev).eval()
        self.proc = AutoProcessor.from_pretrained(self.repo, revision=rev)
        self.size = 224
        self.siglip = "siglip" in key
        self._text = {}

    def letterbox(self, rgba):
        """Codex contract: white letterbox, aspect-fit, 224 square, composited over white."""
        bg = Image.new("RGB", rgba.size, "white")
        bg.paste(rgba, mask=rgba.split()[3])
        s = self.size / max(bg.size)
        im = bg.resize((max(1, round(bg.width * s)), max(1, round(bg.height * s))), Image.BICUBIC)
        canvas = Image.new("RGB", (self.size, self.size), "white")
        canvas.paste(im, ((self.size - im.width) // 2, (self.size - im.height) // 2))
        return canvas

    @torch.no_grad()
    def image(self, rgba):
        x = self.proc(images=self.letterbox(rgba), return_tensors="pt", do_resize=False, do_center_crop=False)
        t = time.perf_counter()
        v = self.model.get_image_features(pixel_values=x["pixel_values"])
        dt = (time.perf_counter() - t) * 1000
        return torch.nn.functional.normalize(v, dim=-1)[0].numpy(), dt

    @torch.no_grad()
    def text(self, prompts):
        key = tuple(prompts)
        if key not in self._text:
            kw = {"padding": "max_length"} if self.siglip else {"padding": True}
            x = self.proc(text=list(prompts), return_tensors="pt", **kw)
            v = torch.nn.functional.normalize(self.model.get_text_features(**x), dim=-1)
            self._text[key] = v.mean(0)
            self._text[key] = torch.nn.functional.normalize(self._text[key], dim=-1).numpy()
        return self._text[key]


def build_classes(enc, groups):
    return {g: (list(entries), np.stack([enc.text(p) for p in entries.values()])) for g, entries in groups.items()}


def ensemble_groups():
    g = {"category": {}, "flat": {}}
    for cat, subs in ENSEMBLE.items():
        prompts = [t.format(s) for syns in subs.values() for s in syns for t in TEMPLATES]
        g["category"][cat] = prompts
        g["subtype." + cat] = {k: [t.format(s) for s in v for t in TEMPLATES] for k, v in subs.items()}
        for sub, syns in subs.items():
            g["flat"][f"{cat}/{sub}"] = [t.format(s) for s in syns for t in TEMPLATES]
    for noun, lens in LENGTH_ENSEMBLE.items():
        cat = "bottom" if noun == "skirt" else "dress"
        g["length." + cat] = {k: [t.format(s) for s in v for t in TEMPLATES] for k, v in lens.items()}
    return g


def codex_best(image, labels, vecs, minimum=0.2, margin=0.025):
    """Exact EmbeddingRanking.best semantics; returns (suggestion|None, ranked list)."""
    scores = vecs @ image
    order = sorted(range(len(labels)), key=lambda i: (-scores[i], labels[i]))
    ranked = [(labels[i], float(scores[i])) for i in order]
    ok = ranked[0][1] >= minimum and ranked[0][1] - ranked[1][1] >= margin
    return (ranked[0] if ok else None), ranked


def softmax_rank(image, labels, vecs, scale=100.0):
    s = vecs @ image * scale
    p = np.exp(s - s.max())
    p /= p.sum()
    order = np.argsort(-p)
    return [(labels[i], float(p[i])) for i in order]


def predict(enc, img, classes, mode, prob_threshold=0.0):
    """mode: 'codex' (hierarchical, raw cosine min/margin) or 'flat' (ensemble flat softmax)."""
    out, aux = {}, {}
    if mode == "codex":
        cat, ranked = codex_best(img, *classes["category"])
        aux["category_top1"] = ranked[0][0]
        if cat is None:
            return out, aux
        out["category"] = cat[0]
        if "subtype." + cat[0] not in classes:
            return out, aux
        sub, sranked = codex_best(img, *classes["subtype." + cat[0]])
        aux["subtype_top1"] = sranked[0][0]
        if sub:
            out["subtype"] = sub[0]
        if f"length.{cat[0]}" in classes and (cat[0] == "dress" or (sub and sub[0] == "skirt")):
            ln, lranked = codex_best(img, *classes["length." + cat[0]])
            aux["length_top1"] = lranked[0][0]
            if ln:
                out["length"] = ln[0]
        return out, aux
    ranked = softmax_rank(img, *classes["flat"])
    cat_p = defaultdict(float)
    for lab, p in ranked:
        cat_p[lab.split("/")[0]] += p
    cat, cp = max(cat_p.items(), key=lambda kv: kv[1])
    aux["category_top1"], aux["category_p"] = cat, cp
    within = [(l.split("/")[1], p / cp) for l, p in ranked if l.startswith(cat + "/")]
    aux["subtype_top1"], aux["subtype_p"] = within[0]
    aux["subtype_top2"] = [w[0] for w in within[:2]]
    if cp >= prob_threshold:
        out["category"] = cat
        if within[0][1] >= prob_threshold:
            out["subtype"] = within[0][0]
    if cat in ("bottom", "dress") and (cat == "dress" or within[0][0] == "skirt"):
        lr = softmax_rank(img, *classes["length." + cat])
        aux["length_top1"], aux["length_p"] = lr[0]
        if lr[0][1] >= prob_threshold and "category" in out:
            out["length"] = lr[0][0]
    return out, aux


# ---------------------------------------------------------------- metrics

FIELDS = ("category", "subtype", "length", "primaryColor", "secondaryColor")


def summarize(rows):
    res = {"count": len(rows), "fields": {}}
    for f in FIELDS:
        el = [r for r in rows if f in r["expected"]]
        sug = [r for r in el if r["predicted"].get(f) is not None]
        cor = sum(r["predicted"].get(f) == r["expected"][f] for r in sug)
        res["fields"][f] = {"labelled": len(el), "suggested": len(sug),
                            "accuracy_all": round(cor / len(el), 4) if el else None,
                            "accuracy_suggested": round(cor / len(sug), 4) if sug else None,
                            "coverage": round(len(sug) / len(el), 4) if el else None}
    for f in ("category", "subtype", "length"):
        el = [r for r in rows if f in r["expected"] and f + "_top1" in r["aux"]]
        if el:
            res["fields"][f]["top1_unthresholded"] = round(sum(r["aux"][f + "_top1"] == r["expected"][f] for r in el) / len(el), 4)
    t = sorted(r["milliseconds"] for r in rows)
    res["cpu_p50_ms"], res["cpu_p95_ms"] = round(t[len(t) // 2], 1), round(t[math.ceil(.95 * len(t)) - 1], 1)
    return res


def confusions(rows, field):
    c = Counter()
    for r in rows:
        e, p = r["expected"].get(field), r["aux"].get(field + "_top1")
        if e and p and e != p:
            c[f"{e} -> {p}"] += 1
    return c.most_common(12)


def main(keys):
    items = load_benchmark()
    print(len(items), "items", flush=True)
    cut = {it["id"]: cutout(it) for it in items}
    colors = {}
    for it in items:
        colors[it["id"]] = {"codex": color_codex(cut[it["id"]]), "lab": color_lab(cut[it["id"]])}
    summary, details = {}, {}
    for key in keys:
        enc = Encoder(key)
        embs, times = {}, {}
        for it in items:
            embs[it["id"]], times[it["id"]] = enc.image(cut[it["id"]])
        configs = {"codex": ("codex", codex_groups())}
        if key == "clip-b32":
            configs["codex-ensemble"] = ("codex", ensemble_groups())
        configs["flat-ensemble"] = ("flat", ensemble_groups())
        for name, (mode, groups) in configs.items():
            if mode == "codex":
                g = {k: v for k, v in groups.items() if k != "flat"}
                if name == "codex-ensemble":  # ensemble classes but Codex decision rule; bag/dress single-class guard
                    g = {k: v for k, v in g.items() if len(v) >= 2}
                classes = build_classes(enc, g)
            else:
                classes = build_classes(enc, groups)
            for thr in ([0.0, 0.5, 0.7] if mode == "flat" else [None]):
                rows = []
                for it in items:
                    pred, aux = predict(enc, embs[it["id"]], classes, mode, thr or 0.0)
                    if name == "codex-ensemble" and pred.get("category") in ("dress", "bag"):
                        pred["subtype"] = pred["category"] if pred["category"] == "dress" else None
                    if mode == "flat" and pred.get("category") == "bag":
                        pred.pop("subtype", None)
                    for cm in ("codex", "lab"):
                        pass
                    prim, sec = colors[it["id"]]["codex" if name.startswith("codex") else "lab"]
                    pred["primaryColor"], pred["secondaryColor"] = prim, sec
                    rows.append({"id": it["id"], "expected": it["expected"], "predicted": pred, "aux": aux,
                                 "milliseconds": times[it["id"]]})
                tag = f"{key}/{name}" + (f"@{thr}" if thr is not None else "")
                summary[tag] = summarize(rows)
                summary[tag]["confusions"] = {f: confusions(rows, f) for f in ("category", "subtype", "length")}
                details[tag] = rows
                fs = summary[tag]["fields"]
                print(f"{tag:38s} cat {fs['category']['accuracy_all']}/{fs['category'].get('top1_unthresholded')} "
                      f"sub {fs['subtype']['accuracy_all']}/{fs['subtype'].get('top1_unthresholded')} "
                      f"len {fs['length']['accuracy_all']}/{fs['length'].get('top1_unthresholded')} "
                      f"col {fs['primaryColor']['accuracy_all']} p50 {summary[tag]['cpu_p50_ms']}ms", flush=True)
        del enc
    # colour-only comparison, independent of model
    for cm in ("codex", "lab"):
        rows = [{"expected": it["expected"], "predicted": {"primaryColor": colors[it["id"]][cm][0],
                 "secondaryColor": colors[it["id"]][cm][1]}, "aux": {}, "milliseconds": 0} for it in items]
        s = summarize(rows)["fields"]["primaryColor"]
        conf = Counter(f"{r['expected']['primaryColor']} -> {r['predicted']['primaryColor']}" for r in rows
                       if "primaryColor" in r["expected"] and r["predicted"]["primaryColor"] != r["expected"]["primaryColor"])
        summary[f"color/{cm}"] = {"primaryColor": s, "confusions": conf.most_common(15)}
        print(f"color/{cm}: {s}", flush=True)
    mask = {it["id"]: float((np.asarray(cut[it['id']])[..., 3] > 0).mean()) for it in items}
    summary["mask_coverage_gt_0.95"] = [k for k, v in mask.items() if v > 0.95]
    out = ROOT / "results"
    tag = os.environ.get("RIG_BENCH_SET", "catalog") + "_" + "_".join(keys)
    (out / f"summary_{tag}.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    (out / f"details_{tag}.json").write_text(json.dumps(details, indent=0), encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1:] or list(MODELS))
