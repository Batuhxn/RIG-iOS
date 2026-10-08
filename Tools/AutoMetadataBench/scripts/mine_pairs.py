"""Mine REAL same-item multi-view candidates from the full CC0 clothing dataset.

All 5,403 photos are embedded (raw photos, FashionCLIP); the most similar cross-photo pairs,
especially from the same sender, are rendered for visual verification. Only pairs a human
(Claude) confirms as the same physical garment become positives.
"""
import csv
import io
import json
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import bench
from bench import ROOT, Encoder

REPO = "https://raw.githubusercontent.com/alexeygrigorev/clothing-dataset/master"

if __name__ == "__main__":
    rows = list(csv.DictReader(io.StringIO(urllib.request.urlopen(f"{REPO}/images.csv", timeout=60).read().decode())))
    rows = [r for r in rows if r["label"] not in ("Skip", "Not sure", "Other") and r["kids"] == "False"]
    out = ROOT / "data/cc0_all"
    out.mkdir(parents=True, exist_ok=True)

    def get(r):
        p = out / f"{r['image']}.jpg"
        if not p.exists():
            try:
                p.write_bytes(urllib.request.urlopen(f"{REPO}/images/{r['image']}.jpg", timeout=60).read())
            except Exception:
                return None
        return r

    with ThreadPoolExecutor(16) as pool:
        rows = [r for r in pool.map(get, rows) if r]
    print(len(rows), "photos", flush=True)
    emb_path = ROOT / "results/cc0_all_emb.npy"
    if emb_path.exists():
        E = np.load(emb_path)
    else:
        enc = Encoder("fashion-clip")
        E = np.stack([enc.image(Image.open(out / f"{r['image']}.jpg").convert("RGBA"))[0] for r in rows])
        np.save(emb_path, E)
    S = E @ E.T
    np.fill_diagonal(S, -1)
    iu = np.triu_indices(len(rows), 1)
    sims = S[iu]
    order = np.argsort(-sims)[:400]
    cands = []
    for k in order:
        i, j = int(iu[0][k]), int(iu[1][k])
        if rows[i]["label"] != rows[j]["label"]:
            continue
        cands.append({"a": rows[i]["image"], "b": rows[j]["image"], "label": rows[i]["label"],
                      "same_sender": rows[i]["sender_id"] == rows[j]["sender_id"], "sim": round(float(S[i, j]), 4)})
        if len(cands) >= 120:
            break
    (ROOT / "data/pair_candidates.json").write_text(json.dumps(cands, indent=1))
    sheets = ROOT / "results/pair_sheets"
    sheets.mkdir(parents=True, exist_ok=True)
    W, H, per = 300, 150, 12
    for s in range(0, len(cands), per):
        sheet = Image.new("RGB", (2 * W, (H + 16) * ((min(per, len(cands) - s) + 1) // 2) * 1), "white")
        sheet = Image.new("RGB", (W * 2, (H + 16) * 6), "white")
        d = ImageDraw.Draw(sheet)
        for n, c in enumerate(cands[s:s + per]):
            x, y = (n % 2) * W, (n // 2) * (H + 16)
            for m, key in enumerate(("a", "b")):
                im = Image.open(out / f"{c[key]}.jpg").convert("RGB")
                im.thumbnail((W // 2 - 4, H - 4))
                sheet.paste(im, (x + m * (W // 2) + 2, y + 2))
            d.text((x + 2, y + H), f"{s + n} {c['label']} {c['sim']} {'S' if c['same_sender'] else ''}", fill="black")
        sheet.save(sheets / f"pairs_{s // per:02d}.jpg", quality=85)
    print(len(cands), "candidates;", sum(c["same_sender"] for c in cands), "same sender", flush=True)
