"""Fetch images for data/selection.json from the pinned Polyvore parquet (image column only)."""
import hashlib
import io
import json
from collections import defaultdict
from pathlib import Path

import pyarrow.parquet as pq

from index_polyvore import BASE, RangeFile

ROOT = Path(__file__).resolve().parents[1]

if __name__ == "__main__":
    selection = json.loads((ROOT / "data/selection.json").read_text(encoding="utf-8"))
    out = ROOT / "data/images"
    out.mkdir(parents=True, exist_ok=True)
    by_file = defaultdict(dict)
    for item in selection:
        if not (out / f"{item['id']}.jpg").exists():
            by_file[item["file"]][item["row"]] = item
    for name, wanted in by_file.items():
        print("reading", name, len(wanted), flush=True)
        pf = pq.ParquetFile(io.BufferedReader(RangeFile(BASE + name), buffer_size=8 << 20))
        table = pf.read_row_group(0, columns=["item_id", "image"])
        ids, images = table.column("item_id"), table.column("image")
        for row, item in wanted.items():
            assert ids[row].as_py() == item["item_id"], (row, item["item_id"])
            image = images[row].as_py()
            data = image["bytes"] if isinstance(image, dict) else image
            (out / f"{item['id']}.jpg").write_bytes(data)
            item["sha256"] = hashlib.sha256(data).hexdigest()
    print("done", len(list(out.glob("*.jpg"))), flush=True)
