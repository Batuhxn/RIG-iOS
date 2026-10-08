"""Core ML runtime parity on a macOS runner (GitHub Actions is RiG's remote Mac).

1. Fetch the 300 reviewed Polyvore images (pinned dataset revision, range reads) and
   compose the 17 CC0 phone-photo cutouts.
2. Re-export RIGGarmentEncoder.mlmodel from the pinned FashionCLIP revision with the
   same script used on Windows; report whether its SHA-256 equals MODEL_LOCK.json.
3. fp32 PyTorch reference embedding + app decision per item.
4. Core ML runtime (computeUnits ALL and CPU_ONLY) on the identical input tensor.
5. Report embedding deviation, per-field decision parity, suggest/abstain transitions,
   accuracy vs reviewed ground truth for both, and Mac-proxy latency.

Exit non-zero if the product-decision gate fails (see GATES).
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

FIELDS = ("category", "subtype", "length", "primaryColor", "subtypeAlternatives")
# Product gate: Core ML decisions may differ from fp32 on at most 3% of items, a
# changed item may only move between suggest and abstain (never to a different
# value), and embeddings must stay close.
GATES = {"max_changed_fraction": 0.03, "max_value_flips": 0, "min_median_cosine": 0.995, "min_cosine": 0.98}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
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


def classify_changes(ref, got):
    """Per field: same / suggest->abstain / abstain->suggest / value flip."""
    out = {}
    for f in FIELDS:
        a, b = ref.get(f), got.get(f)
        if a == b:
            continue
        out[f] = "abstained" if b is None else "newly suggested" if a is None else "VALUE FLIP"
    return out


def accuracy(rows, key):
    res = {}
    for f in ("category", "subtype", "length", "primaryColor"):
        el = [r for r in rows if f in r["expected"]]
        sug = [r for r in el if f in r[key]]
        cor = sum(r[key][f] == r["expected"][f] for r in sug)
        res[f] = {"labelled": len(el), "prefilled": len(sug), "correct": cor,
                  "precision": round(cor / len(sug), 4) if sug else None,
                  "recall": round(cor / len(el), 4) if el else None}
    return res


def main():
    os.environ.setdefault("HF_HOME", str(ROOT / ".cache/hf"))
    import torch
    import coremltools as ct
    from PIL import Image
    import bench
    from dump_parity import decide

    t0 = time.time()
    subprocess.run([sys.executable, str(HERE / "fetch_images.py")], check=True, cwd=HERE)
    compose_real()
    print(f"fixtures ready in {time.time() - t0:.0f}s", flush=True)

    subprocess.run([sys.executable, str(HERE / "export_fashionclip.py")], check=True, cwd=HERE)
    model_path = ROOT / "artifacts/RIGGarmentEncoder.mlmodel"
    manifest = json.loads((ROOT / "artifacts/RIGGarmentPrompts.json").read_text())
    lock_path = ROOT.parents[1] / "Resources/Models/MODEL_LOCK.json"
    lock = json.loads(lock_path.read_text()) if lock_path.exists() else {}
    exported_sha = sha256(model_path)

    items = []
    for which in ("catalog", "real"):
        os.environ["RIG_BENCH_SET"] = which
        items += [(which, it) for it in bench.load_benchmark()]

    enc = bench.Encoder("fashion-clip")
    tower = enc.model.eval()

    runtimes = {}
    for units in ("ALL", "CPU_ONLY"):
        t = time.perf_counter()
        m = ct.models.MLModel(str(model_path), compute_units=getattr(ct.ComputeUnit, units))
        runtimes[units] = {"model": m, "load_ms": (time.perf_counter() - t) * 1000, "times": []}

    rows = []
    for which, it in items:
        rgba = bench.cutout(it)
        x = letterbox_tensor(rgba)
        with torch.no_grad():
            ref = tower.get_image_features(pixel_values=torch.from_numpy(x))[0].numpy().astype(np.float64)
        row = {"id": it["id"], "set": which, "expected": it["expected"], "reference": decide(ref.tolist(), manifest)}
        for units, rt in runtimes.items():
            t = time.perf_counter()
            out = rt["model"].predict({"image": x})["embedding"].reshape(-1).astype(np.float64)
            rt["times"].append((time.perf_counter() - t) * 1000)
            cos = float(out @ ref / (np.linalg.norm(out) * np.linalg.norm(ref)))
            got = decide(out.tolist(), manifest)
            row[units] = {"cosine": cos, "max_abs": float(np.abs(out - ref).max()), "decision": got,
                          "changes": classify_changes(row["reference"], got)}
        rows.append(row)

    report = {"host": platform.platform(), "python": sys.version.split()[0], "coremltools": ct.__version__,
              "torch": torch.__version__, "n": len(rows),
              "model": {"bytes": model_path.stat().st_size, "sha256": exported_sha,
                        "pinned_sha256": lock.get("sha256"), "matches_lock": exported_sha == lock.get("sha256"),
                        "modelID": manifest["modelID"]},
              "gates": GATES, "reference_accuracy": accuracy(rows, "reference"), "runtimes": {}}
    ok = True
    for units, rt in runtimes.items():
        cos = np.array([r[units]["cosine"] for r in rows])
        changed = [r for r in rows if r[units]["changes"]]
        kinds = Counter(k for r in changed for k in r[units]["changes"].values())
        fields = Counter(f for r in changed for f in r[units]["changes"])
        flips = kinds.get("VALUE FLIP", 0)
        times = sorted(rt["times"])
        for r in rows:
            r[units + "_decision"] = r[units]["decision"]
        summary = {
            "cosine_median": round(float(np.median(cos)), 5), "cosine_p01": round(float(np.percentile(cos, 1)), 5),
            "cosine_min": round(float(cos.min()), 5),
            "max_abs_median": round(float(np.median([r[units]["max_abs"] for r in rows])), 5),
            "items_changed": len(changed), "changed_fraction": round(len(changed) / len(rows), 4),
            "change_kinds": dict(kinds), "changed_fields": dict(fields),
            "changed_items": [{"id": r["id"], **r[units]["changes"]} for r in changed][:40],
            "accuracy_vs_ground_truth": accuracy(rows, units + "_decision"),
            "mac_proxy_ms": {"cold_load": round(rt["load_ms"], 1), "first_predict": round(rt["times"][0], 1),
                             "p50": round(times[len(times) // 2], 1), "p95": round(times[int(0.95 * len(times)) - 1], 1)},
        }
        passed = (summary["changed_fraction"] <= GATES["max_changed_fraction"] and flips <= GATES["max_value_flips"]
                  and summary["cosine_median"] >= GATES["min_median_cosine"] and summary["cosine_min"] >= GATES["min_cosine"])
        summary["gate_passed"] = passed
        ok &= passed if units == "ALL" else True  # ALL is what the app uses; CPU_ONLY is diagnostic
        report["runtimes"][units] = summary
    out = ROOT / "results"
    out.mkdir(exist_ok=True)
    (out / "coreml_parity.json").write_text(json.dumps(report, indent=1))
    (out / "coreml_parity_rows.json").write_text(json.dumps(rows, default=str))
    print(json.dumps(report, indent=1))
    # Public annotations: job logs need a signed-in viewer, annotations do not.
    for units, s in report["runtimes"].items():
        print(f"::notice title=CoreML {units}::gate={'PASS' if s['gate_passed'] else 'FAIL'} cos_med={s['cosine_median']} "
              f"cos_min={s['cosine_min']} changed={s['items_changed']}/{len(rows)} kinds={s['change_kinds']} "
              f"fields={s['changed_fields']} proxy_ms={s['mac_proxy_ms']}")
        acc = s["accuracy_vs_ground_truth"]
        print(f"::notice title=Accuracy {units}::" + " ".join(
            f"{f}={a['correct']}/{a['prefilled']} prec={a['precision']} rec={a['recall']}" for f, a in acc.items()))
    ra = report["reference_accuracy"]
    print("::notice title=Accuracy fp32 reference::" + " ".join(
        f"{f}={a['correct']}/{a['prefilled']} prec={a['precision']}" for f, a in ra.items()))
    print(f"::notice title=Model::sha256={exported_sha} matches_lock={report['model']['matches_lock']} "
          f"bytes={report['model']['bytes']} host={report['host']}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
