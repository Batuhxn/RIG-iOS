"""8-bit parity gate (ChatGPT/product decision 2026-10-08: ship 8-bit only if category/subtype drop <= 1pp
and no new real-photo failures).

Simulates Core ML weight-only linear int8 quantisation (per-output-channel symmetric, as
coremltools.optimize.coreml.linear_quantize_weights mode="linear_symmetric") on the IMAGE tower only
(text vectors are precomputed in fp32 offline). Activations stay float, as on device.
"""
import json
import os
import sys

import torch

import bench
from bench import Encoder, build_classes, ensemble_groups, load_benchmark, predict, summarize
from color_embed import color_groups
from bench import softmax_rank


def quantize_(module):
    n = 0
    for m in module.modules():
        if isinstance(m, (torch.nn.Linear, torch.nn.Conv2d)):
            w = m.weight.data
            flat = w.reshape(w.shape[0], -1)
            scale = flat.abs().amax(1).clamp(min=1e-12) / 127.0
            q = torch.round(flat / scale[:, None]).clamp(-127, 127)
            m.weight.data = (q * scale[:, None]).reshape(w.shape)
            n += w.numel()
    return n


def run(enc, cls, color_cls, which):
    os.environ["RIG_BENCH_SET"] = which
    rows = []
    for it in load_benchmark():
        emb, ms = enc.image(bench.cutout(it))
        pred, aux = predict(enc, emb, cls, "flat", 0.7)
        c = softmax_rank(emb, *color_cls)
        pred["primaryColor"] = c[0][0] if c[0][1] >= 0.7 else None
        aux["primaryColor_top1"] = c[0][0]
        rows.append({"id": it["id"], "expected": it["expected"], "predicted": pred, "aux": aux, "milliseconds": ms})
    return rows


if __name__ == "__main__":
    key = sys.argv[1] if len(sys.argv) > 1 else "fashion-clip"
    enc = Encoder(key)
    cls = build_classes(enc, ensemble_groups())
    color_cls = build_classes(enc, color_groups())["color"]
    base = {w: run(enc, cls, color_cls, w) for w in ("catalog", "real")}
    params = quantize_(enc.model.vision_model) + quantize_(enc.model.visual_projection)
    q = {w: run(enc, cls, color_cls, w) for w in ("catalog", "real")}
    out = {"quantized_params": params}
    for w in ("catalog", "real"):
        sb, sq = summarize(base[w]), summarize(q[w])
        flips = [(b["id"], {k: (b["predicted"].get(k), r["predicted"].get(k)) for k in ("category", "subtype", "length", "primaryColor")
                  if b["predicted"].get(k) != r["predicted"].get(k)}) for b, r in zip(base[w], q[w])]
        out[w] = {"fp32": sb["fields"], "int8": sq["fields"], "changed_predictions": [f for f in flips if f[1]]}
        for f in ("category", "subtype", "length", "primaryColor"):
            a, b = sb["fields"][f], sq["fields"][f]
            print(f"{w:8s} {f:13s} fp32 all={a['accuracy_all']} sug={a['accuracy_suggested']} cov={a['coverage']} | "
                  f"int8 all={b['accuracy_all']} sug={b['accuracy_suggested']} cov={b['coverage']}")
        print(w, "changed:", out[w]["changed_predictions"])
    (bench.ROOT / f"results/int8_parity_{key}.json").write_text(json.dumps(out, indent=1))
