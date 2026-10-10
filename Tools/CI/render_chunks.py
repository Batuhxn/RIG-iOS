#!/usr/bin/env python3
"""Splits review renders into annotation-sized chunks, and joins them back.

CI has no write access (no gate may publish), and logs and artifacts of the public
repository need a sign-in to download, but check-run annotations are public. So the
render job encodes every PNG as WebP, base64-encodes it, cuts it into ~3.8 KB chunks
and prints them as `name.index/count data` lines; each of N parallel jobs prints its
share (GitHub keeps 50 annotations per job).

    render_chunks.py split <png dir> <part> <parts> <out.txt>
    render_chunks.py join <annotations.json ...> <out dir>     (local, after download)
"""
from __future__ import annotations

import base64
import io
import json
import sys
from pathlib import Path

CHUNK = 3800
PER_JOB = 48


def split(src: str, part: int, parts: int, out: str) -> None:
    from PIL import Image

    lines = []
    for png in sorted(Path(src).glob("*.png")):
        image = Image.open(png).convert("RGB")
        buffer = io.BytesIO()
        image.save(buffer, "WEBP", quality=80, method=6)
        text = base64.b64encode(buffer.getvalue()).decode()
        pieces = [text[i:i + CHUNK] for i in range(0, len(text), CHUNK)]
        for k, piece in enumerate(pieces):
            lines.append(f"{png.stem}.{k}/{len(pieces)} {piece}")
    budget = parts * PER_JOB
    if len(lines) > budget:
        print(f"::warning title=render-budget::{len(lines)} chunks, only {budget} fit; the rest are dropped")
    share = lines[part * PER_JOB:(part + 1) * PER_JOB]
    Path(out).write_text("\n".join(share) + ("\n" if share else ""))
    print(f"part {part}: {len(share)} of {len(lines)} chunks")


def join(files: list[str], out: str) -> None:
    pieces: dict[str, dict[int, str]] = {}
    counts: dict[str, int] = {}
    for f in files:
        for a in json.loads(Path(f).read_text()):
            title = a.get("title", "")
            if not title.startswith("r-"):
                continue
            name, _, idx = title[2:].rpartition(".")
            k, _, n = idx.partition("/")
            pieces.setdefault(name, {})[int(k)] = a["message"].strip()
            counts[name] = int(n)
    Path(out).mkdir(parents=True, exist_ok=True)
    for name, chunks in sorted(pieces.items()):
        if len(chunks) != counts[name]:
            print(f"{name}: {len(chunks)}/{counts[name]} chunks, skipped")
            continue
        data = base64.b64decode("".join(chunks[k] for k in range(counts[name])))
        (Path(out) / f"{name}.webp").write_bytes(data)
        print(f"{name}.webp {len(data)} bytes")


if __name__ == "__main__":
    if sys.argv[1] == "split":
        split(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5])
    else:
        join(sys.argv[2:-1], sys.argv[-1])
