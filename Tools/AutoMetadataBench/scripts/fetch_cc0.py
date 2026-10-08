"""Stratified sample of the CC0 clothing dataset (alexeygrigorev/clothing-dataset): amateur
photos of real garments on beds, floors, hangers. Weak labels -> category only where the
mapping is unambiguous; subtype/colour/length come from visual review (cc0_review.json).
"""
import csv
import io
import json
import random
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = "https://raw.githubusercontent.com/alexeygrigorev/clothing-dataset/master"
WEAK = {  # dataset label -> (category, subtype or None)
    "T-Shirt": ("top", "t-shirt"), "Longsleeve": ("top", None), "Shirt": ("top", "shirt"),
    "Blouse": ("top", "blouse"), "Hoodie": ("top", "hoodie"), "Top": ("top", None), "Polo": ("top", None),
    "Undershirt": ("top", None), "Pants": ("bottom", None), "Shorts": ("bottom", "shorts"),
    "Skirt": ("bottom", "skirt"), "Dress": ("dress", "dress"), "Outwear": ("outerwear", None),
    "Blazer": ("outerwear", "blazer"), "Shoes": ("shoes", None), "Hat": ("accessory", None),
}
PER = {"T-Shirt": 14, "Longsleeve": 14, "Shirt": 14, "Blouse": 12, "Hoodie": 14, "Top": 10, "Polo": 6,
       "Undershirt": 8, "Pants": 22, "Shorts": 16, "Skirt": 18, "Dress": 18, "Outwear": 20, "Blazer": 12,
       "Shoes": 22, "Hat": 4}

if __name__ == "__main__":
    rows = list(csv.DictReader(io.StringIO(urllib.request.urlopen(f"{REPO}/images.csv", timeout=60).read().decode())))
    rng = random.Random(20261008)
    picked = []
    for label, n in PER.items():
        pool = [r for r in rows if r["label"] == label and r["kids"] == "False"]
        rng.shuffle(pool)
        picked += [(r, label) for r in pool[:n]]
    out = ROOT / "data/cc0"
    out.mkdir(parents=True, exist_ok=True)

    def get(item):
        r, label = item
        p = out / f"{r['image']}.jpg"
        if not p.exists():
            p.write_bytes(urllib.request.urlopen(f"{REPO}/images/{r['image']}.jpg", timeout=60).read())
        cat, sub = WEAK[label]
        e = {"category": cat}
        if sub:
            e["subtype"] = sub
        return {"id": f"cc0-{r['image'][:8]}", "image_id": r["image"], "source": "cc0-clothing-dataset",
                "weak_label": label, "weak_expected": e}

    with ThreadPoolExecutor(8) as pool:
        items = list(pool.map(get, picked))
    (ROOT / "data/cc0_selection.json").write_text(json.dumps(items, indent=1))
    print(len(items), "images", file=sys.stderr)
