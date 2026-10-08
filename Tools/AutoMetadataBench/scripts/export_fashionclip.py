"""Export RiG's garment encoder (FashionCLIP image tower) + prompt manifest on Windows.

Produces in artifacts/:
  RIGGarmentEncoder.mlmodel  legacy neural-network Core ML, 8-bit linear weights (Xcode compiles to .mlmodelc)
  RIGGarmentPrompts.json     manifest v2 consumed by CoreMLGarmentClassifier (flat/length/color groups)
  export-validation.json     provenance + Windows-side checks

Contract (unchanged from feat/v0.3-auto-metadata-main): input "image" float32 [1,3,224,224], white letterbox,
CLIP mean/std; output "embedding" (unnormalised, 512); metadata rigModelID must equal manifest modelID.
Core ML *runtime* parity cannot be checked on Windows (no libcoremlpython); run validate on macOS.
"""
import hashlib
import json
import os
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).parent))
from bench import ENSEMBLE, LENGTH_ENSEMBLE, MODELS, ROOT, TEMPLATES, Encoder, ensemble_groups  # noqa: E402
from color_embed import color_groups  # noqa: E402

LOGIT_SCALE = 100.0
THRESHOLD = 0.7

if __name__ == "__main__":
    out = ROOT / "artifacts"
    out.mkdir(exist_ok=True)
    enc = Encoder("fashion-clip")
    groups = ensemble_groups()
    manifest_groups = {}
    for name in ("flat", "length.bottom", "length.dress"):
        manifest_groups[name] = [{"label": k, "vector": [round(float(x), 7) for x in enc.text(v)]} for k, v in groups[name].items()]
    manifest_groups["color"] = [{"label": k, "vector": [round(float(x), 7) for x in enc.text(v)]}
                                for k, v in color_groups()["color"].items()]
    prompts_sha = hashlib.sha256(json.dumps({"templates": TEMPLATES, "ensemble": ENSEMBLE, "length": LENGTH_ENSEMBLE,
                                             "color": color_groups()}, sort_keys=True).encode()).hexdigest()[:16]
    snap = next((ROOT / ".cache/hf/hub/models--patrickjohncyh--fashion-clip/snapshots").iterdir()).name
    model_id = f"fashion-clip:{snap[:12]}:prompts-{prompts_sha}:letterbox-v1:int8"
    manifest = {"version": 2, "modelID": model_id, "logitScale": LOGIT_SCALE, "threshold": THRESHOLD,
                "groups": manifest_groups}
    (out / "RIGGarmentPrompts.json").write_text(json.dumps(manifest, separators=(",", ":")))

    class ImageTower(torch.nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model

        def forward(self, image):
            return self.model.get_image_features(pixel_values=image)

    tower = ImageTower(enc.model).eval()
    example = torch.zeros(1, 3, 224, 224)
    with torch.no_grad():
        traced = torch.jit.trace(tower, example)
        ref = traced(torch.randn(1, 3, 224, 224, generator=torch.Generator().manual_seed(7)))
    import coremltools as ct

    variant = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--variant=")), "nn-int8")
    inputs = [ct.TensorType(name="image", shape=(1, 3, 224, 224), dtype=np.float32)]
    outputs = [ct.TensorType(name="embedding")]
    if variant.startswith("nn-"):
        from coremltools.models.neural_network import quantization_utils

        q = ct.convert(traced, inputs=inputs, outputs=outputs, convert_to="neuralnetwork",
                       minimum_deployment_target=ct.target.iOS14, skip_model_load=True)
        if variant == "nn-int8":
            class LinearOnly(quantization_utils.QuantizedLayerSelector):
                """Quantise only fully-connected/conv weights, matching int8_parity.py; norms stay float."""
                def do_quantize(self, layer, **kwargs):
                    return layer.WhichOneof("layer") in ("innerProduct", "convolution") and super().do_quantize(layer, **kwargs)

            q = quantization_utils.quantize_weights(q, nbits=8, quantization_mode="linear", selector=LinearOnly())
        suffix = "mlmodel"
    elif variant in ("mlprogram-int8", "mlprogram-fp16"):
        # ML Program (iOS 17 floor): fp16 compute like the Neural Engine; optional
        # per-channel symmetric int8 weights. Requires macOS (BlobWriter).
        q = ct.convert(traced, inputs=inputs, outputs=outputs, convert_to="mlprogram",
                       minimum_deployment_target=ct.target.iOS17, compute_precision=ct.precision.FLOAT16,
                       skip_model_load=True)
        if variant == "mlprogram-int8":
            import coremltools.optimize.coreml as cto
            config = cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(
                mode="linear_symmetric", granularity="per_channel", weight_threshold=2048))
            q = cto.linear_quantize_weights(q, config=config)
        suffix = "mlpackage"
    else:
        raise SystemExit(f"unknown variant {variant}")
    model_id = model_id.rsplit(":", 1)[0] + f":{variant}"
    manifest["modelID"] = model_id
    if variant != "nn-int8":
        out = out / "variants" / variant
        out.mkdir(parents=True, exist_ok=True)
    (out / "RIGGarmentPrompts.json").write_text(json.dumps(manifest, separators=(",", ":")))
    q.user_defined_metadata["rigModelID"] = model_id
    q.short_description = f"RiG garment encoder: FashionCLIP (MIT) image tower, {variant}."
    q.license = "MIT (patrickjohncyh/fashion-clip; OpenAI CLIP). See THIRD_PARTY_NOTICES."
    path = out / f"RIGGarmentEncoder.{suffix}"
    q.save(str(path))
    spec = q.get_spec()
    size = path.stat().st_size if path.is_file() else sum(p.stat().st_size for p in path.rglob("*") if p.is_file())
    report = {"modelID": model_id, "variant": variant, "bytes": size, "hf_snapshot": snap,
              "inputs": [i.name for i in spec.description.input], "outputs": [o.name for o in spec.description.output],
              "torch_reference_norm": float(ref.norm()), "coreml_runtime_parity": "UNVERIFIED on Windows; run on macOS",
              "manifest_bytes": (out / "RIGGarmentPrompts.json").stat().st_size,
              "classes": {k: [e["label"] for e in v] for k, v in manifest_groups.items()}}
    (out / "export-validation.json").write_text(json.dumps(report, indent=1))
    print(json.dumps({k: v for k, v in report.items() if k != "classes"}, indent=1))

