"""Index Polyvore item text (no image bytes) via HTTP range reads of the pinned parquet files.

Output: data/polyvore_index.jsonl with item_id, category, title, url_name, file, row_group, row.
Only the item_id/category/title/url_name column chunks are transferred.
"""
import io
import json
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pyarrow.parquet as pq

REVISION = "8d3809239c7b235db712559b590a6342af1679fd"
BASE = f"https://huggingface.co/datasets/owj0421/polyvore/resolve/{REVISION}/"
FILES = [f"data/data-0000{i}-of-00005.parquet" for i in range(6)]
ROOT = Path(__file__).resolve().parents[1]
COLUMNS = ["item_id", "category", "title", "url_name"]


class RangeFile(io.RawIOBase):
    def __init__(self, url):
        self.url, self.pos = url, 0
        req = urllib.request.Request(url, headers={"Range": "bytes=0-0"})
        with urllib.request.urlopen(req, timeout=60) as r:
            self.size = int(r.headers["Content-Range"].split("/")[-1])

    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos

    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else self.pos + offset if whence == 1 else self.size + offset
        return self.pos

    def readinto(self, buffer):
        n = min(len(buffer), self.size - self.pos)
        if n <= 0:
            return 0
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{self.pos + n - 1}"})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    data = r.read()
                break
            except Exception:
                if attempt == 3:
                    raise
        buffer[: len(data)] = data
        self.pos += len(data)
        return len(data)


def index_file(name):
    pf = pq.ParquetFile(io.BufferedReader(RangeFile(BASE + name), buffer_size=1 << 20))
    rows = []
    for g in range(pf.num_row_groups):
        table = pf.read_row_group(g, columns=COLUMNS).to_pylist()
        for i, row in enumerate(table):
            rows.append({**row, "file": name, "row_group": g, "row": i})
    print(name, pf.num_row_groups, "groups", len(rows), "rows", flush=True)
    return rows


if __name__ == "__main__":
    out = ROOT / "data" / "polyvore_index.jsonl"
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(index_file, FILES))
    with out.open("w", encoding="utf-8") as f:
        for rows in results:
            for row in rows:
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
    print("wrote", out, sum(map(len, results)), file=sys.stderr)
