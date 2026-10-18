"""Research-only, zero-network white-balance ablation for RiG v0.3.

This does NOT replace FashionCLIP or change the shipping colour decision.
It compares pixel-only HSV votes on the 218 CC0 amateur photos using the
matching original JPG and BEN2 alpha cutout already produced for the benchmark.

Run (after the existing CC0 benchmark images have been fetched and cut out):
  python Tools/AutoMetadataBench/scripts/white_balance_ablation.py

Dependencies: Pillow, numpy (the existing benchmark already uses both).
Outputs only summary JSON under Tools/AutoMetadataBench/results/ (gitignored).
It deliberately does not trigger any API, download, ML inference or paid runner.

CAUTION: The app uses FashionCLIP embedding predictions with abstention.
Pixel-vote accuracy printed here is NOT comparable to 90.1% / 56.1% precision
and recall of the model-prefill pipeline. No model threshold is modified.
"""
from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MODES = ("original", "gray-world", "white-patch")
MIN_NEUTRAL_BACKGROUND_PIXELS = 256
MAX_RGB_GAIN = 1.30
MIN_RGB_GAIN = 1 / MAX_RGB_GAIN


def codex_family(red: float, green: float, blue: float) -> str:
    """Port of the shipping MaskedColorExtractor.family HSV boundaries."""
    maximum = max(red, green, blue)
    minimum = min(red, green, blue)
    delta = maximum - minimum
    saturation = 0 if maximum == 0 else delta / maximum
    if maximum < 0.16:
        return "black"
    if saturation < 0.12:
        return "white" if maximum > 0.85 else "gray"
    if maximum == red:
        hue = 60 * math.fmod((green - blue) / delta, 6)
    elif maximum == green:
        hue = 60 * ((blue - red) / delta + 2)
    else:
        hue = 60 * ((red - green) / delta + 4)
    if hue < 0:
        hue += 360
    if 20 <= hue < 65 and saturation < 0.4 and maximum > 0.6:
        return "beige"
    if hue < 15 or hue >= 345:
        return "burgundy" if maximum < 0.5 else ("pink" if saturation < 0.5 else "red")
    if hue < 45:
        return "brown" if maximum < 0.65 else "orange"
    if hue < 70:
        return "yellow"
    if hue < 100:
        return "olive"
    if hue < 175:
        return "green"
    if hue < 260:
        return "navy" if maximum < 0.45 else "blue"
    if hue < 310:
        return "purple"
    return "pink"


def estimate_illuminant_gain(
    rgb: np.ndarray, foreground_mask: np.ndarray, method: str
) -> np.ndarray | None:
    """Estimate bounded per-channel correction from *background* pixels only.

    Ignore highly chromatic backgrounds. This is conservative and can abstain:
    a blue sofa is not a white balance reference. When no sufficiently neutral
    pixels exist, the caller should leave the source photograph unchanged.

    No labeled examples are used for parameter fitting. Evaluate changes
    separately on even (tuning) and odd (held-out) indexed examples.
    """
    if method not in ("gray-world", "white-patch"):
        raise ValueError(f"Unknown method: {method}")
    if rgb.ndim != 3 or rgb.shape[-1] != 3 or foreground_mask.shape != rgb.shape[:2]:
        raise ValueError("Expected HxWx3 RGB and aligned HxW foreground mask")
    pixels = rgb.reshape(-1, 3).astype(np.float64) / 255.0
    background = ~foreground_mask.reshape(-1).astype(bool)
    maximum = pixels.max(axis=1)
    minimum = pixels.min(axis=1)
    saturation = np.divide(maximum - minimum, maximum,
                           out=np.zeros_like(maximum), where=maximum > 0)
    luminosity = pixels.mean(axis=1)
    neutral = background & (saturation < 0.35) & (luminosity > 0.08) & (luminosity < 0.96)
    samples = pixels[neutral]
    if len(samples) < MIN_NEUTRAL_BACKGROUND_PIXELS:
        return None
    if method == "gray-world":
        reference = np.mean(samples, axis=0)
    else:
        brightness = samples.mean(axis=1)
        bright = samples[brightness >= np.quantile(brightness, 0.8)]
        if len(bright) < 64:
            return None
        reference = np.quantile(bright, 0.95, axis=0)
    if np.any(reference <= 0) or not np.all(np.isfinite(reference)):
        return None
    neutral_target = float(np.mean(reference))
    gains = np.clip(neutral_target / reference, MIN_RGB_GAIN, MAX_RGB_GAIN)
    return gains


def corrected_pixels(rgb: np.ndarray, foreground_mask: np.ndarray, method: str):
    source = rgb[foreground_mask]
    if len(source) < 32:
        return None, False
    if method == "original":
        return source, False
    gains = estimate_illuminant_gain(rgb, foreground_mask, method)
    if gains is None:
        return source, False
    return np.clip(source.astype(np.float64) * gains, 0, 255).astype(np.uint8), True


def majority_family(rgb_pixels: np.ndarray) -> str | None:
    if rgb_pixels is None or len(rgb_pixels) < 32:
        return None
    # Deterministic bounded sampling, independent of image size or iteration order.
    stride = max(1, math.ceil(len(rgb_pixels) / 20_000))
    sample = rgb_pixels[::stride].astype(np.float64) / 255.0
    votes = Counter(codex_family(*pixel) for pixel in sample)
    return sorted(votes.items(), key=lambda item: (-item[1], item[0]))[0][0]


def load_example(item: dict):
    cutout = ROOT / item["image"]
    source = ROOT / "data/cc0" / (cutout.stem + ".jpg")
    if not source.is_file() or not cutout.is_file():
        return None
    with Image.open(source) as original, Image.open(cutout) as mask_image:
        original = original.convert("RGB")
        original.thumbnail((384, 384))
        rgb = np.asarray(original)
        alpha = mask_image.convert("RGBA").getchannel("A").resize(original.size, Image.Resampling.BILINEAR)
        foreground = np.asarray(alpha) >= 230
    return rgb, foreground


def metrics(rows: list[dict], variant: str, split: str) -> dict:
    chosen = [r for r in rows if split == "all" or r["index"] % 2 == (0 if split == "even" else 1)]
    correct = sum(r["predictions"][variant] == r["truth"] for r in chosen)
    valid = sum(r["predictions"][variant] is not None for r in chosen)
    black_as_navy = sum(r["truth"] == "black" and r["predictions"][variant] == "navy" for r in chosen)
    navy_as_black = sum(r["truth"] == "navy" and r["predictions"][variant] == "black" for r in chosen)
    return {
        "n": len(chosen),
        "pixel_accuracy": round(correct / len(chosen), 4) if chosen else None,
        "classified": valid,
        "corrections_applied": sum(r["corrected"][variant] for r in chosen),
        "black_as_navy": black_as_navy,
        "navy_as_black": navy_as_black,
        "changed_from_baseline": sum(
            r["predictions"][variant] != r["predictions"]["original"] for r in chosen
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--labels", type=Path, default=ROOT / "data/cc0_labels.json")
    parser.add_argument("--output", type=Path, default=ROOT / "results/white_balance_ablation.json")
    args = parser.parse_args()
    labels = json.loads(args.labels.read_text(encoding="utf-8"))
    rows = []
    missing = 0
    for item in labels:
        truth = item.get("expected", {}).get("primaryColor")
        if not truth or truth == "metallic":
            continue
        example = load_example(item)
        if example is None:
            missing += 1
            continue
        rgb, mask = example
        predictions: dict[str, str | None] = {}
        applied: dict[str, bool] = {}
        for variant in MODES:
            colors, did_correct = corrected_pixels(rgb, mask, variant)
            predictions[variant] = majority_family(colors)
            applied[variant] = did_correct
        rows.append({
            "id": item["id"], "index": item["index"], "truth": truth,
            "predictions": predictions, "corrected": applied,
        })
    if not rows:
        print("No local paired CC0 original photos + BEN2 cutouts found. Fetch the existing dataset first.")
        return 2

    result = {
        "description": "Offline pixel-vote white balance ablation, NOT FashionCLIP model-prefill recall",
        "labeled_pairs_processed": len(rows),
        "missing_pairs": missing,
        "variants": {
            variant: {split: metrics(rows, variant, split) for split in ("even", "odd", "all")}
            for variant in MODES
        },
        "warnings": [
            "Thresholds are not trained or tuned; even and odd partitions are diagnostics, not a statistical validation.",
            "Colorful or sparse backgrounds cause a no-correction fallback.",
            "An HSV pixel vote is not an embedding probability and has no abstention; never compare its accuracy with model-prefill precision/recall.",
            "Only enable a shipping change after comparing model-prefill precision/recall at >=90% precision on a separate held-out set.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
