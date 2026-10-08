"""v0.4 real multi-view split: hand-labelled CC0 photo pairs (data/real_pairs.json), on cutouts.

`python real_pairs.py cut` makes BEN2 cutouts (evaluation stand-in for Apple Vision, never
shipped); `python real_pairs.py` scores them. Like the app (croppedToInstancesExtent), each
cutout is cropped to the garment before embedding. Photos come from mine_pairs.py.

Verdicts: same_item = one garment, different photo; same_shot = burst/near-identical photo
(reported apart, too easy); look_alike = a different garment that looks alike (mostly one
seller's shirts and jeans on the same bed); unsure = excluded.
"""
import json
import sys

import numpy as np
from PIL import Image

from bench import ROOT

PHOTOS, CUT = ROOT / "data/cc0_all", ROOT / "data/pairs_cut"
THRESHOLDS = (0.89, 0.90, 0.91, 0.92, 0.93, 0.94, 0.95)


def cut(ids):
    sys.path.insert(0, str(ROOT.parents[0] / "web-services" / "background-removal"))
    from app.ben2_engine import Ben2Engine
    engine = Ben2Engine(ROOT.parents[0] / "web-spikes/model-memory/models/ben2-fp32.onnx")
    CUT.mkdir(parents=True, exist_ok=True)
    for i in ids:
        dst = CUT / f"{i}.png"
        if not dst.exists():
            out = engine.remove(Image.open(PHOTOS / f"{i}.jpg"))
            if out.image is not None:
                dst.write_bytes(out.image)


def garment(i):
    im = Image.open(CUT / f"{i}.png").convert("RGBA")
    box = im.split()[3].point(lambda a: 255 if a > 128 else 0).getbbox()
    return im.crop(box) if box else im


if __name__ == "__main__":
    pairs = [p for p in json.loads((ROOT / "data/real_pairs.json").read_text())["pairs"] if p["verdict"] != "unsure"]
    ids = list(dict.fromkeys(p[k] for p in sorted(pairs, key=lambda p: p["verdict"] == "look_alike")
                             for k in ("a", "b")))
    if sys.argv[1:] == ["cut"]:
        cut(ids)
        sys.exit()
    from bench import Encoder
    enc = Encoder("fashion-clip")
    emb = {i: enc.image(garment(i))[0] for i in ids if (CUT / f"{i}.png").exists()}
    sims = {}
    for p in pairs:
        if p["a"] in emb and p["b"] in emb:
            sims.setdefault(p["verdict"], []).append(float(emb[p["a"]] @ emb[p["b"]]))
    for v, s in sims.items():
        print(f"{v}: n={len(s)} cosine min {min(s):.3f} median {np.median(s):.3f} max {max(s):.3f}")
    pos, neg = sims["same_item"], sims["look_alike"]
    for t in THRESHOLDS:
        print(f"t={t:.2f}  same item found {sum(s >= t for s in pos)}/{len(pos)}  "
              f"look-alike prompted {sum(s >= t for s in neg)}/{len(neg)}")
