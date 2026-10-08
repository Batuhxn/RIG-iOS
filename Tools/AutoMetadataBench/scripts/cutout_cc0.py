"""BEN2 cutouts for the CC0 sample — evaluation stand-in for Apple Vision subject lifting.

BEN2 is an engineering-only tool here (licensing unresolved; never shipped). The app's
own cutout comes from VNGenerateForegroundInstanceMaskRequest on device.
"""
import io
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parents[0] / "web-services" / "background-removal"))
from app.ben2_engine import Ben2Engine  # noqa: E402

MODEL = ROOT.parents[0] / "web-spikes/model-memory/models/ben2-fp32.onnx"

if __name__ == "__main__":
    items = json.loads((ROOT / "data/cc0_selection.json").read_text())
    out = ROOT / "data/cc0_cut"
    out.mkdir(exist_ok=True)
    engine = Ben2Engine(MODEL)
    failed = []
    shard, shards = (int(sys.argv[1]), int(sys.argv[2])) if len(sys.argv) > 2 else (0, 1)
    for i, it in enumerate(items):
        if i % shards != shard:
            continue
        dst = out / f"{it['image_id']}.png"
        if dst.exists():
            continue
        cut = engine.remove(Image.open(ROOT / "data/cc0" / f"{it['image_id']}.jpg"))
        if cut.image is None:
            failed.append(it["id"])
            continue
        dst.write_bytes(cut.image)
        if i % 20 == 0:
            print(i, flush=True)
    print("done; no garment found for", failed, flush=True)
