"""macOS export spike: MIT OpenAI CLIP ViT-B/32, image-only Core ML and fixed prompts.

Requires torch, coremltools, numpy and OpenAI's `clip` package in an isolated env.
This script downloads the official checkpoint to the specified workspace cache.
It does not install or activate assets in the app. Retain the MIT notice when shipping.
Run on macOS: python scripts/export_metadata_clip.py --output build/metadata-model
"""
import argparse
import hashlib
import json
from pathlib import Path

SUBTYPES = {
    "top": ["t-shirt", "shirt", "blouse", "sweater", "hoodie", "tank top"],
    "bottom": ["skirt", "trousers", "jeans", "shorts", "leggings"],
    "dress": ["dress", "jumpsuit"],
    "outerwear": ["jacket", "coat", "blazer", "cardigan"],
    "shoes": ["sneakers", "boots", "sandals", "heels", "loafers"],
    "bag": ["handbag", "backpack", "tote bag", "clutch"],
    "accessory": ["hat", "scarf", "belt", "sunglasses", "watch"],
}
CATEGORIES = {"top": "upper body clothing", "bottom": "lower body clothing",
              "dress": "a dress or jumpsuit", "outerwear": "outerwear",
              "shoes": "footwear", "bag": "a bag", "accessory": "a fashion accessory"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    import clip
    import coremltools as ct
    import numpy as np
    import torch

    args.output.mkdir(parents=True, exist_ok=True)
    model, _ = clip.load("ViT-B/32", device="cpu", jit=False, download_root=str(args.output / "cache"))
    model = model.float().eval()
    groups = {"category": CATEGORIES}
    groups.update({"subtype." + key: {label: label for label in labels} for key, labels in SUBTYPES.items()})
    for category, noun in [("bottom", "skirt"), ("dress", "dress")]:
        groups["length." + category] = {label: f"{label} {noun}" for label in ("mini", "midi", "maxi")}
    embeddings = {}
    with torch.no_grad():
        for group, entries in groups.items():
            vectors = model.encode_text(clip.tokenize([f"a photo of {text}" for text in entries.values()]))
            vectors /= vectors.norm(dim=-1, keepdim=True)
            embeddings[group] = [{"label": label, "vector": vector.tolist()} for label, vector in zip(entries, vectors)]

    class ImageEncoder(torch.nn.Module):
        def __init__(self, inner):
            super().__init__()
            self.inner = inner

        def forward(self, image):
            return self.inner.encode_image(image)

    example = torch.zeros(1, 3, 224, 224)
    with torch.no_grad():
        traced = torch.jit.trace(ImageEncoder(model).eval(), example)
    exported = ct.convert(traced, inputs=[ct.TensorType(name="image", shape=example.shape, dtype=np.float32)],
                          outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
                          minimum_deployment_target=ct.target.iOS17, convert_to="mlprogram")
    checkpoint = args.output / "cache" / "ViT-B-32.pt"
    with checkpoint.open("rb") as stream:
        checkpoint_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    prompt_sha = hashlib.sha256(json.dumps(embeddings, sort_keys=True).encode()).hexdigest()
    model_id = f"openai-clip-vit-b32:{checkpoint_sha}:{prompt_sha}:letterbox-v1"
    exported.user_defined_metadata["rigModelID"] = model_id
    exported.save(str(args.output / "RIGGarmentEncoder.mlpackage"))
    (args.output / "RIGGarmentPrompts.json").write_text(json.dumps({"modelID": model_id, "groups": embeddings}))
    # Conversion parity is a required gate and uses the actual Core ML runtime.
    rng = np.random.default_rng(42)
    sample = rng.normal(size=(1, 3, 224, 224)).astype(np.float32)
    with torch.no_grad():
        expected = traced(torch.from_numpy(sample)).numpy().reshape(-1)
    actual = exported.predict({"image": sample})["embedding"].reshape(-1)
    cosine = float(np.dot(expected, actual) / (np.linalg.norm(expected) * np.linalg.norm(actual)))
    (args.output / "export-validation.json").write_text(json.dumps({"modelID": model_id, "cosine_parity": cosine,
        "torch": torch.__version__, "coremltools": ct.__version__}, indent=2))
    if not np.isfinite(cosine) or cosine < .999:
        raise RuntimeError(f"Export parity failed: {cosine}")
    print(f"Export parity {cosine:.6f}; garment accuracy and device measurements still required.")


if __name__ == "__main__":
    main()
