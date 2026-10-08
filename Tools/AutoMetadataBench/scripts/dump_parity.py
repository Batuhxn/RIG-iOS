"""Dump FashionCLIP image embeddings + Python reference decisions for the Swift parity test.

The reference re-implements GarmentEmbeddingDecision.decide in Python using the *manifest*
vectors (so the comparison checks decision logic, not export rounding).
"""
import json
import math
import os

import numpy as np


def softmax(image, entries, scale):
    img = np.asarray(image) / np.linalg.norm(image)
    vecs = np.array([e["vector"] for e in entries])
    vecs = vecs / np.linalg.norm(vecs, axis=1, keepdims=True)
    logits = scale * vecs @ img
    p = np.exp(logits - logits.max())
    p /= p.sum()
    ranked = sorted(zip([e["label"] for e in entries], p.tolist()), key=lambda kv: (-kv[1], kv[0]))
    return ranked


def decide(image, m):
    thr, s, g = m["threshold"], m["logitScale"], m["groups"]
    out = {}
    c = softmax(image, g["color"], s)
    if c[0][1] >= thr:
        out["primaryColor"] = c[0][0]
    flat = softmax(image, g["flat"], s)
    cat_p, order = {}, []
    for lab, p in flat:
        k = lab.split("/")[0]
        if k not in cat_p:
            order.append(k)
        cat_p[k] = cat_p.get(k, 0) + p
    best = max(order, key=lambda k: cat_p[k])  # first maximal in rank order, like Swift's max(by:)? see note
    within = [(lab.split("/")[1], p / cat_p[best]) for lab, p in flat if lab.split("/")[0] == best]
    if cat_p[best] < thr:
        return out
    out["category"] = best
    if best == "bag":
        return out
    if within[0][1] >= thr:
        out["subtype"] = within[0][0]
    elif len(within) >= 2:
        out["subtypeAlternatives"] = [w[0] for w in within[:2]]
        return out
    if out.get("subtype") in ("skirt", "dress") and (best == "dress" and out["subtype"] == "dress" or best == "bottom" and out["subtype"] == "skirt"):
        l = softmax(image, g["length." + best], s)
        if l[0][1] >= thr:
            out["length"] = l[0][0]
    return out


if __name__ == "__main__":
    import bench  # torch; kept out of module scope so decide() is importable on macOS without it
    from bench import ROOT, Encoder, load_benchmark

    manifest = json.loads((ROOT / "artifacts/RIGGarmentPrompts.json").read_text())
    enc = Encoder("fashion-clip")
    rows = []
    for which in ("catalog", "real"):
        os.environ["RIG_BENCH_SET"] = which
        for it in load_benchmark():
            emb, _ = enc.image(bench.cutout(it))
            rows.append({"id": it["id"], "embedding": [float(x) for x in emb], "expected": it["expected"],
                         "reference": decide(emb.tolist(), manifest)})
    (ROOT / "swift-check/Tests/Fixtures").mkdir(parents=True, exist_ok=True)
    (ROOT / "swift-check/Tests/Fixtures/parity.json").write_text(json.dumps(rows))
    # Accuracy of exactly what the app would prefill, against ground truth.
    for which, pref in (("catalog", "pv-"), ("real", "real-")):
        sub = [r for r in rows if r["id"].startswith(pref)]
        for f in ("category", "subtype", "length", "primaryColor"):
            el = [r for r in sub if f in r["expected"]]
            sug = [r for r in el if f in r["reference"]]
            cor = sum(r["reference"][f] == r["expected"][f] for r in sug)
            print(f"{which:8s} {f:13s} prefilled {len(sug)}/{len(el)} correct {cor} -> precision {cor / max(1, len(sug)):.3f} recall {cor / max(1, len(el)):.3f}")
        alts = [r for r in sub if "subtypeAlternatives" in r["reference"] and "subtype" in r["expected"]]
        hit = sum(r["expected"]["subtype"] in r["reference"]["subtypeAlternatives"] for r in alts)
        print(f"{which:8s} alternatives shown {len(alts)}, contain truth {hit}")
