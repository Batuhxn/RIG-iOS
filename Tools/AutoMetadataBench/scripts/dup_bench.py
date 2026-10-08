"""v0.4 duplicate-garment benchmark.

Two scenarios per query (a re-capture of a realistic garment):
  existing  gallery contains the original -> correct iff top-1 is the original and sim >= t
  new       gallery excludes the original -> any sim >= t is a false "already in wardrobe?" prompt

Re-captures are synthetic (honest limit: same garment, same mask, so optimistic): rotation,
scale/shift, shear, white balance, exposure, blur, JPEG, edge occlusion. Hard negatives are
real, different CC0 garments; the hardest are same category + same colour (e.g. black tees).
Gallery = 235 realistic originals + 294 catalogue cutouts as distractors.
"""
import io
import json
import os
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

import bench
from bench import ROOT, Encoder, load_benchmark


def augment(rgba, rng):
    im = rgba.convert("RGBA")
    w, h = im.size
    # geometry: rotate, shear, scale and shift on a padded canvas
    im = im.rotate(rng.uniform(-12, 12), resample=Image.BICUBIC, expand=True)
    sh = rng.uniform(-0.12, 0.12)
    im = im.transform(im.size, Image.AFFINE, (1, sh, -sh * im.height / 2, 0, 1, 0), resample=Image.BICUBIC)
    s = rng.uniform(0.8, 1.1)
    im = im.resize((max(8, int(im.width * s)), max(8, int(im.height * s))), Image.BICUBIC)
    canvas = Image.new("RGBA", (int(im.width * 1.15), int(im.height * 1.15)), (0, 0, 0, 0))
    canvas.paste(im, (rng.randint(0, canvas.width - im.width), rng.randint(0, canvas.height - im.height)))
    im = canvas
    # edge occlusion: cut a strip off one side (hand, hanger, frame edge)
    if rng.random() < 0.5:
        a = np.asarray(im).copy()
        side, frac = rng.choice("lrtb"), rng.uniform(0.03, 0.12)
        if side == "l": a[:, : int(a.shape[1] * frac), 3] = 0
        if side == "r": a[:, -int(a.shape[1] * frac) - 1:, 3] = 0
        if side == "t": a[: int(a.shape[0] * frac), :, 3] = 0
        if side == "b": a[-int(a.shape[0] * frac) - 1:, :, 3] = 0
        im = Image.fromarray(a, "RGBA")
    # photometric: white balance, exposure/contrast, blur, JPEG
    rgb = np.asarray(im.convert("RGB")).astype(np.float32)
    rgb *= np.array([rng.uniform(0.85, 1.15) for _ in range(3)], dtype=np.float32)
    rgb = (rgb - 128) * rng.uniform(0.8, 1.2) + 128 + rng.uniform(-25, 25)
    out = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    if rng.random() < 0.6:
        out = out.filter(ImageFilter.GaussianBlur(rng.uniform(0.3, 1.5)))
    buf = io.BytesIO()
    out.save(buf, "JPEG", quality=rng.randint(40, 85))
    out = Image.open(io.BytesIO(buf.getvalue())).convert("RGB")
    out.putalpha(im.split()[3])
    return out


def realistic_items():
    os.environ["RIG_BENCH_SET"] = "real"
    real = load_benchmark()
    cc0 = json.loads((ROOT / "data/cc0_labels.json").read_text())
    return real + cc0


if __name__ == "__main__":
    key = sys.argv[1] if len(sys.argv) > 1 else "fashion-clip"
    enc = Encoder(key)
    rng = random.Random(20261008)
    real = realistic_items()
    os.environ["RIG_BENCH_SET"] = "catalog"
    catalog = load_benchmark()
    gallery_items = real + catalog
    gal = np.stack([enc.image(bench.cutout(it))[0] for it in gallery_items])
    meta = [(it["id"], it["expected"].get("category"), it["expected"].get("primaryColor")) for it in gallery_items]
    queries = []
    for i, it in enumerate(real):
        base = bench.cutout(it)
        for k in range(2):
            q, _ = enc.image(augment(base, rng))
            queries.append((i, q))
    pos, hardest_any, hardest_cat, hardest_catcol, top1_ok = [], [], [], [], []
    for i, q in queries:
        sims = gal @ q
        _, cat, col = meta[i]
        pos.append(float(sims[i]))
        others = np.delete(np.arange(len(meta)), i)
        hardest_any.append(float(sims[others].max()))
        same_cat = [j for j in others if meta[j][1] == cat]
        hardest_cat.append(float(sims[same_cat].max()) if same_cat else -1)
        same_cc = [j for j in same_cat if col and meta[j][2] == col]
        hardest_catcol.append(float(sims[same_cc].max()) if same_cc else np.nan)
        top1_ok.append(int(np.argmax(sims) == i))
    pos, ha, hc = np.array(pos), np.array(hardest_any), np.array(hardest_cat)
    hcc = np.array(hardest_catcol)
    print(f"{key}: {len(queries)} re-capture queries; gallery {len(meta)}")
    print(f"recall@1 (existing garment ranked first): {np.mean(top1_ok):.3f}")
    q = lambda a: " ".join(f"p{p}={np.nanpercentile(a, p):.3f}" for p in (1, 5, 25, 50))
    print("positive sim          ", q(pos))
    print("hardest negative, any ", q(ha).replace("p1=", "p99=") if False else " ".join(f"p{p}={np.nanpercentile(ha, p):.3f}" for p in (50, 75, 95, 99)))
    print("hardest same category ", " ".join(f"p{p}={np.nanpercentile(hc, p):.3f}" for p in (50, 75, 95, 99)))
    print("hardest same cat+color", " ".join(f"p{p}={np.nanpercentile(hcc, p):.3f}" for p in (50, 75, 95, 99)), f"(n={np.sum(~np.isnan(hcc))})")
    rows = []
    for t in np.arange(0.80, 0.991, 0.01):
        found = float(np.mean([(p >= t) and ok for p, ok in zip(pos, top1_ok)]))   # existing: prompt shows the right item
        false_new = float(np.mean(hc >= t))   # new garment, same-category scope: a wrong prompt
        rows.append({"t": round(float(t), 2), "duplicate_found": round(found, 3), "false_prompt_new": round(false_new, 3)})
        print(f"t={t:.2f}  duplicate found {found:.3f}   false prompt on a new garment (same-category scope) {false_new:.3f}")
    (ROOT / f"results/dup_bench_{key}.json").write_text(json.dumps({"recall@1": float(np.mean(top1_ok)), "curve": rows}, indent=1))
