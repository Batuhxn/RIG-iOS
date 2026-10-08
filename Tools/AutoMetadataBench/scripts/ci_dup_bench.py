"""v0.4 duplicate benchmark on a macOS runner with Apple Vision (the app's own cutout path).

1. Fetch the 224 CC0 originals (data/cc0_selection.json; labels in data/cc0_labels.json).
2. Cut out each original with VNGenerateForegroundInstanceMaskRequest (as VisionBackgroundRemover).
3. Re-captures: augment the ORIGINAL photo (geometry, white balance, exposure, blur, JPEG,
   occlusion) and cut it out again with Vision, so the mask differs too.
4. Embed gallery and queries with (a) Vision FeaturePrint, RiG's current matcher, and
   (b) FashionCLIP 2.0 image tower, the v0.3 embedding already computed at import.
5. Same-category scope (as GarmentDuplicateCheck). For each threshold report:
   duplicate found (existing garment, top-1 correct and above threshold) and
   false prompt (new garment: original removed from gallery, anything above threshold).
Also reports v0.3 classification accuracy on Vision cutouts vs the BEN2 cutouts.
"""
import io
import json
import os
import random
import subprocess
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
REPO_IMAGES = "https://raw.githubusercontent.com/alexeygrigorev/clothing-dataset/master/images"


def vision_cutout(path, out_png):
    import Quartz
    import Vision
    from Foundation import NSURL
    src = Quartz.CGImageSourceCreateWithURL(NSURL.fileURLWithPath_(str(path)), None)
    cg = Quartz.CGImageSourceCreateImageAtIndex(src, 0, None)
    handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(cg, {})
    request = Vision.VNGenerateForegroundInstanceMaskRequest.alloc().init()
    ok, _ = handler.performRequests_error_([request], None)
    results = request.results() if ok else None
    if not results:
        return None
    obs = results[0]
    buf, _ = obs.generateMaskedImageOfInstances_fromRequestHandler_croppedToInstancesExtent_error_(
        obs.allInstances(), handler, True, None)
    if buf is None:
        return None
    ci = Quartz.CIImage.imageWithCVPixelBuffer_(buf)
    ctx = Quartz.CIContext.contextWithOptions_(None)
    cg_out = ctx.createCGImage_fromRect_(ci, ci.extent())
    dest = Quartz.CGImageDestinationCreateWithURL(NSURL.fileURLWithPath_(str(out_png)), "public.png", 1, None)
    Quartz.CGImageDestinationAddImage(dest, cg_out, None)
    Quartz.CGImageDestinationFinalize(dest)
    return Image.open(out_png).convert("RGBA")


def feature_print(png_path):
    """Vision feature print as a vector, plus the observation for API distance checks."""
    import Vision
    from Foundation import NSURL
    handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(NSURL.fileURLWithPath_(str(png_path)), {})
    request = Vision.VNGenerateImageFeaturePrintRequest.alloc().init()
    ok, _ = handler.performRequests_error_([request], None)
    if not ok or not request.results():
        return None, None
    obs = request.results()[0]
    raw = bytes(obs.data())
    dtype = np.float32 if obs.elementType() == 1 else np.float64
    return np.frombuffer(raw, dtype=dtype).astype(np.float64), obs


def curve(name, dist_or_sim, higher_is_closer, meta, queries, thresholds):
    """queries: list of (gallery_index, vector). Returns rows and recall@1."""
    gal = dist_or_sim["gallery"]
    rows, top1 = [], []
    pos, hardest = [], []
    for (i, q) in queries:
        scores = dist_or_sim["score"](gal, q)
        cat = meta[i]["category"]
        same = [j for j in range(len(meta)) if meta[j]["category"] == cat]
        best = max(same, key=lambda j: scores[j]) if higher_is_closer else min(same, key=lambda j: scores[j])
        top1.append(best == i)
        pos.append(scores[i])
        others = [j for j in same if j != i]
        hardest.append((max if higher_is_closer else min)(scores[j] for j in others) if others else None)
    for t in thresholds:
        if higher_is_closer:
            found = np.mean([ok and p >= t for ok, p in zip(top1, pos)])
            false = np.mean([h is not None and h >= t for h in hardest])
        else:
            found = np.mean([ok and p <= t for ok, p in zip(top1, pos)])
            false = np.mean([h is not None and h <= t for h in hardest])
        rows.append((round(float(t), 3), round(float(found), 3), round(float(false), 3)))
    return rows, float(np.mean(top1)), np.array(pos, dtype=float), np.array([h for h in hardest if h is not None], dtype=float)


def main():
    import torch
    import bench
    from dup_bench import augment
    from dump_parity import decide

    sel = json.loads((ROOT / "data/cc0_selection.json").read_text())
    labels = {x["id"]: x for x in json.loads((ROOT / "data/cc0_labels.json").read_text())}
    work = ROOT / "data/vision"
    (work / "orig").mkdir(parents=True, exist_ok=True)
    (work / "cut").mkdir(exist_ok=True)
    (work / "aug").mkdir(exist_ok=True)
    meta, gallery_png = [], []
    for it in sel:
        if it["id"] not in labels:
            continue
        p = work / "orig" / f"{it['image_id']}.jpg"
        if not p.exists():
            p.write_bytes(urllib.request.urlopen(f"{REPO_IMAGES}/{it['image_id']}.jpg", timeout=60).read())
        cut = vision_cutout(p, work / "cut" / f"{it['image_id']}.png")
        if cut is None:
            continue
        meta.append({**labels[it["id"]], "orig": p})
        gallery_png.append(work / "cut" / f"{it['image_id']}.png")
    print(f"vision cut out {len(meta)} of {len(labels)} labelled CC0 photos", flush=True)

    rng = random.Random(20261008)
    queries_png = []
    for i, m in enumerate(meta):
        photo = Image.open(m["orig"]).convert("RGBA")
        for k in range(2):
            aug = augment(photo, rng).convert("RGB")
            ap = work / "aug" / f"{i}-{k}.jpg"
            aug.save(ap, quality=90)
            c = vision_cutout(ap, work / "aug" / f"{i}-{k}.png")
            if c is not None:
                queries_png.append((i, work / "aug" / f"{i}-{k}.png"))
    print(f"{len(queries_png)} re-capture queries cut out by Vision", flush=True)

    # (a) Vision FeaturePrint
    fp_gal, fp_obs = zip(*[feature_print(p) for p in gallery_png])
    missing = sum(v is None for v in fp_gal)
    if missing:
        raise RuntimeError(f"FeaturePrint failed for {missing} gallery cutouts")
    fp_q = [(i, feature_print(p)) for i, p in queries_png]
    # check that Euclidean distance on the raw vectors equals Vision's computeDistance
    try:
        res = fp_obs[0].computeDistance_toFeaturePrintObservation_error_(None, fp_obs[1], None)
        # pyobjc returns (ok, distance) on some versions and (ok, distance, error) on others.
        floats = [x for x in (res if isinstance(res, tuple) else (res,)) if isinstance(x, float)]
        d_api = floats[0] if floats else float("nan")
    except Exception as exc:  # pyobjc out-pointer bridging differs across versions
        print(f"::warning title=computeDistance unavailable::{exc!r}")
        d_api = float("nan")
    d_np = float(np.linalg.norm(fp_gal[0] - fp_gal[1]))
    print(f"FeaturePrint distance check: API {d_api:.4f} vs numpy {d_np:.4f}", flush=True)
    fpg = np.stack(fp_gal)
    fp_queries = [(i, v[0]) for i, v in fp_q if v[0] is not None]
    fp = {"gallery": fpg, "score": lambda g, q: np.linalg.norm(g - q, axis=1)}
    fp_rows, fp_r1, fp_pos, fp_hard = curve("featureprint", fp, False, meta, fp_queries,
                                            np.round(np.arange(0.2, 1.21, 0.05), 2))

    # (b) FashionCLIP (v0.3 embedding)
    enc = bench.Encoder("fashion-clip")
    fc_gal = np.stack([enc.image(Image.open(p).convert("RGBA"))[0] for p in gallery_png])
    fc_queries = [(i, enc.image(Image.open(p).convert("RGBA"))[0]) for i, p in queries_png]
    fc = {"gallery": fc_gal, "score": lambda g, q: g @ q}
    fc_rows, fc_r1, fc_pos, fc_hard = curve("fashionclip", fc, True, meta, fc_queries,
                                            np.round(np.arange(0.80, 0.991, 0.01), 2))

    # v0.3 classification on Vision cutouts (vs BEN2 numbers in the report)
    manifest = json.loads((ROOT.parents[1] / "Resources/Models/RIGGarmentPrompts.json").read_text())
    acc = {}
    for f in ("category", "subtype", "primaryColor"):
        el = [(m, fc_gal[k]) for k, m in enumerate(meta) if f in m["expected"]]
        preds = [(m["expected"][f], decide(e.tolist(), manifest).get(f)) for m, e in el]
        sug = [(t, p) for t, p in preds if p is not None]
        acc[f] = (sum(t == p for t, p in sug), len(sug), len(preds))

    def summary(rows):
        return " ".join(f"t{t}:{f}/{x}" for t, f, x in rows)

    print(f"::notice title=Dup FeaturePrint (current matcher)::recall@1 {fp_r1:.3f}; pos dist p50 {np.median(fp_pos):.3f} p95 {np.percentile(fp_pos, 95):.3f}; hardest-neg dist p5 {np.percentile(fp_hard, 5):.3f} p50 {np.median(fp_hard):.3f}; API-vs-numpy {d_api:.3f}/{d_np:.3f}")
    print(f"::notice title=Dup FeaturePrint curve (t:found/false)::{summary(fp_rows)}")
    print(f"::notice title=Dup FashionCLIP (v0.3 embedding)::recall@1 {fc_r1:.3f}; pos sim p5 {np.percentile(fc_pos, 5):.3f} p50 {np.median(fc_pos):.3f}; hardest-neg sim p50 {np.median(fc_hard):.3f} p95 {np.percentile(fc_hard, 95):.3f}")
    print(f"::notice title=Dup FashionCLIP curve (t:found/false)::{summary(fc_rows)}")
    print(f"::notice title=v0.3 on Vision cutouts (CC0)::" + " ".join(f"{f}={c}/{n} of {l}" for f, (c, n, l) in acc.items())
          + f"; Vision cut out {len(meta)}/{len(labels)}; queries {len(queries_png)}")
    out = ROOT / "results"
    out.mkdir(exist_ok=True)
    (out / "dup_bench_vision.json").write_text(json.dumps({
        "featureprint": {"recall@1": fp_r1, "curve": fp_rows}, "fashionclip": {"recall@1": fc_r1, "curve": fc_rows},
        "v03_on_vision_cutouts": acc, "n_gallery": len(meta), "n_queries": len(queries_png)}, indent=1))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        # Job logs need a signed-in viewer; annotations are public.
        tb = traceback.format_exc().strip().splitlines()
        print("::error title=ci_dup_bench crashed::" + " | ".join(tb[-8:]))
        raise
