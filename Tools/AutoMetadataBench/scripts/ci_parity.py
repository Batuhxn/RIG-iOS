"""Core ML runtime parity on a macOS runner (GitHub Actions is RiG's remote Mac).

1. Fetch the 300 reviewed Polyvore images (pinned dataset revision, range reads) and
   compose the 17 CC0 phone-photo cutouts.
2. Export every candidate variant from the pinned FashionCLIP revision (nn-int8 twice,
   to check that export is deterministic).
3. fp32 PyTorch reference embedding + app decision per item.
4. Core ML runtime (computeUnits ALL and CPU_ONLY) on the identical input tensor.
5. Report embedding deviation (median/p5/min cosine), every changed decision with its
   margins, accuracy vs reviewed ground truth per split, and Mac-proxy latency.

Gate (ChatGPT/product, 2026-10-08): zero VALUE FLIPS on prefilled fields (category,
subtype, length, primaryColor); suggest<->abstain moves are acceptable; precision on
category/subtype may drop at most 1 pp vs the fp32 reference. Alternative-chip changes
are reported, not gated. Exit non-zero if no variant passes.
"""
import hashlib
import json
import os
import platform
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

PREFILLED = ("category", "subtype", "length", "primaryColor")
VARIANTS = ["nn-int8", "nn-fp32", "mlprogram-int8", "mlprogram-fp16"]


def sha256(path):
    path = Path(path)
    h = hashlib.sha256()
    files = [path] if path.is_file() else sorted(p for p in path.rglob("*") if p.is_file())
    for f in files:
        with open(f, "rb") as s:
            for chunk in iter(lambda: s.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()


def compose_real():
    from PIL import Image
    out = ROOT / "data/real/cut"
    out.mkdir(parents=True, exist_ok=True)
    for jpg in sorted((ROOT / "data/real").glob("*.jpg")):
        rgb = Image.open(jpg).convert("RGB")
        mask = Image.open(jpg.with_suffix(".png")).convert("L").resize(rgb.size)
        rgb.putalpha(mask)
        rgb.save(out / f"{jpg.stem}.png")


def letterbox_tensor(rgba):
    from PIL import Image
    mean = np.array([0.48145466, 0.4578275, 0.40821073], dtype=np.float32)
    std = np.array([0.26862954, 0.26130258, 0.27577711], dtype=np.float32)
    bg = Image.new("RGB", rgba.size, "white")
    bg.paste(rgba, mask=rgba.split()[3])
    s = 224 / max(bg.size)
    im = bg.resize((max(1, round(bg.width * s)), max(1, round(bg.height * s))), Image.BICUBIC)
    canvas = Image.new("RGB", (224, 224), "white")
    canvas.paste(im, ((224 - im.width) // 2, (224 - im.height) // 2))
    x = (np.asarray(canvas, dtype=np.float32) / 255.0 - mean) / std
    return x.transpose(2, 0, 1)[None].copy()


def margins(image, manifest):
    """Top-1 probability per decision group (the quantity the 0.7 gate thresholds)."""
    from dump_parity import softmax
    g, s = manifest["groups"], manifest["logitScale"]
    flat = softmax(image, g["flat"], s)
    cat = Counter()
    for lab, p in flat:
        cat[lab.split("/")[0]] += p
    out = {"category": round(max(cat.values()), 4), "color": round(softmax(image, g["color"], s)[0][1], 4)}
    return out


def changes(ref, got):
    out = {}
    for f in PREFILLED + ("subtypeAlternatives",):
        a, b = ref.get(f), got.get(f)
        if a == b:
            continue
        if f == "subtypeAlternatives":
            out[f] = "alternatives changed"
        else:
            out[f] = "abstained" if b is None else "newly suggested" if a is None else f"VALUE FLIP {a}->{b}"
    return out


def accuracy(rows, key, split=None):
    res = {}
    rows = [r for r in rows if split is None or r["set"] == split]
    for f in PREFILLED:
        el = [r for r in rows if f in r["expected"]]
        sug = [r for r in el if f in r[key]]
        cor = sum(r[key][f] == r["expected"][f] for r in sug)
        res[f] = {"labelled": len(el), "prefilled": len(sug), "correct": cor,
                  "precision": round(cor / len(sug), 4) if sug else None,
                  "recall": round(cor / len(el), 4) if el else None}
    return res


def export(variant):
    subprocess.run([sys.executable, str(HERE / "export_fashionclip.py"), f"--variant={variant}"], check=True, cwd=HERE)
    base = ROOT / "artifacts" if variant == "nn-int8" else ROOT / "artifacts/variants" / variant
    path = next(base.glob("RIGGarmentEncoder.*"))
    return path, json.loads((base / "RIGGarmentPrompts.json").read_text())


def main():
    os.environ.setdefault("HF_HOME", str(ROOT / ".cache/hf"))
    import torch
    import coremltools as ct
    import bench
    from dump_parity import decide

    subprocess.run([sys.executable, str(HERE / "fetch_images.py")], check=True, cwd=HERE)
    compose_real()

    exported = {v: export(v) for v in VARIANTS}
    first_sha = sha256(exported["nn-int8"][0])
    exported["nn-int8"] = export("nn-int8")
    deterministic = first_sha == sha256(exported["nn-int8"][0])
    manifest = exported["nn-int8"][1]  # text vectors are identical across variants
    lock_path = ROOT.parents[1] / "Resources/Models/MODEL_LOCK.json"
    lock = json.loads(lock_path.read_text()) if lock_path.exists() else {}

    items = []
    for which in ("catalog", "real"):
        os.environ["RIG_BENCH_SET"] = which
        items += [(which, it) for it in bench.load_benchmark()]
    tower = bench.Encoder("fashion-clip").model.eval()

    rows = []
    for which, it in items:
        x = letterbox_tensor(bench.cutout(it))
        with torch.no_grad():
            ref = tower.get_image_features(pixel_values=torch.from_numpy(x))[0].numpy().astype(np.float64)
        rows.append({"id": it["id"], "set": which, "expected": it["expected"], "x": x, "ref": ref,
                     "reference": decide(ref.tolist(), manifest), "ref_margin": margins(ref.tolist(), manifest)})

    report = {"host": platform.platform(), "coremltools": ct.__version__, "torch": torch.__version__,
              "n": len(rows), "export_deterministic": deterministic, "pinned_sha256": lock.get("sha256"),
              "reference_accuracy": {s: accuracy(rows, "reference", s) for s in ("catalog", "real")},
              "variants": {}}
    passing = []
    for variant, (path, _) in exported.items():
        for units in ("ALL", "CPU_ONLY"):
            t = time.perf_counter()
            model = ct.models.MLModel(str(path), compute_units=getattr(ct.ComputeUnit, units))
            load_ms = (time.perf_counter() - t) * 1000
            times, cos, flips = [], [], []
            key = f"{variant}/{units}"
            kinds, alt_changes, changed = Counter(), 0, 0
            for r in rows:
                t = time.perf_counter()
                out = model.predict({"image": r["x"]})["embedding"].reshape(-1).astype(np.float64)
                times.append((time.perf_counter() - t) * 1000)
                cos.append(float(out @ r["ref"] / (np.linalg.norm(out) * np.linalg.norm(r["ref"]))))
                got = decide(out.tolist(), manifest)
                r[key] = got
                ch = changes(r["reference"], got)
                if ch:
                    changed += 1
                for f, kind in ch.items():
                    if f == "subtypeAlternatives":
                        alt_changes += 1
                        continue
                    kinds[kind.split(" ")[0] if kind.startswith("VALUE") else kind] += 1
                    if kind.startswith("VALUE"):
                        flips.append({"id": r["id"], "set": r["set"], "field": f, "change": kind,
                                      "expected": r["expected"].get(f), "ref_margin": r["ref_margin"],
                                      "coreml_margin": margins(out.tolist(), manifest)})
            cos = np.array(cos)
            ts = sorted(times)
            acc = {s: accuracy(rows, key, s) for s in ("catalog", "real")}
            drops = {s: {f: round((report["reference_accuracy"][s][f]["precision"] or 0) - (acc[s][f]["precision"] or 0), 4)
                         for f in ("category", "subtype")} for s in acc}
            passed = not flips and all(d <= 0.01 for s in drops.values() for d in s.values())
            if passed:
                passing.append(key)
            report["variants"][key] = {
                "bytes": sum(p.stat().st_size for p in ([path] if path.is_file() else path.rglob("*")) if p.is_file()),
                "sha256": sha256(path), "cosine_median": round(float(np.median(cos)), 5),
                "cosine_p5": round(float(np.percentile(cos, 5)), 5), "cosine_min": round(float(cos.min()), 5),
                "items_changed": changed, "prefill_change_kinds": dict(kinds), "alternatives_changed": alt_changes,
                "value_flips": flips, "precision_drop_vs_fp32": drops, "accuracy": acc, "gate_passed": passed,
                "mac_proxy_ms": {"load": round(load_ms, 1), "first": round(times[0], 1),
                                 "p50": round(ts[len(ts) // 2], 1), "p95": round(ts[int(0.95 * len(ts)) - 1], 1)},
            }
    report["passing"] = passing
    out = ROOT / "results"
    out.mkdir(exist_ok=True)
    (out / "coreml_parity.json").write_text(json.dumps(report, indent=1))
    print(json.dumps(report, indent=1))
    # Public annotations (job logs need a signed-in viewer; annotations do not).
    print(f"::notice title=Export::deterministic={deterministic} pinned_lock={lock.get('sha256', '')[:12]}")
    for key, v in report["variants"].items():
        a = v["accuracy"]
        print(f"::notice title={key}::gate={'PASS' if v['gate_passed'] else 'FAIL'} MB={v['bytes'] / 1e6:.1f} "
              f"cos med/p5/min={v['cosine_median']}/{v['cosine_p5']}/{v['cosine_min']} changed={v['items_changed']} "
              f"kinds={v['prefill_change_kinds']} alt={v['alternatives_changed']} drop={v['precision_drop_vs_fp32']} "
              f"proxy_ms={v['mac_proxy_ms']} sha={v['sha256'][:12]}")
        print(f"::notice title={key} accuracy::" + " | ".join(
            f"{s}: " + " ".join(f"{f}={x['correct']}/{x['prefilled']}" for f, x in a[s].items()) for s in a))
        for fl in v["value_flips"][:10]:
            print(f"::warning title={key} flip::{fl['id']} {fl['field']} {fl['change']} truth={fl['expected']} "
                  f"margin ref={fl['ref_margin']} coreml={fl['coreml_margin']}")
    ra = report["reference_accuracy"]
    print("::notice title=fp32 reference accuracy::" + " | ".join(
        f"{s}: " + " ".join(f"{f}={x['correct']}/{x['prefilled']}" for f, x in ra[s].items()) for s in ra))
    sys.exit(0 if passing else 1)


if __name__ == "__main__":
    main()
