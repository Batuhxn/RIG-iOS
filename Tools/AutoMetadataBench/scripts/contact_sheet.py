"""Render labelled contact sheets (one per ~30 items) for visual label review."""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
COLS, ROWS, CELL = 6, 5, 200

if __name__ == "__main__":
    manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "data/selection.json"
    items = json.loads(manifest.read_text(encoding="utf-8"))
    out = ROOT / "results/sheets"
    out.mkdir(parents=True, exist_ok=True)
    per = COLS * ROWS
    for page in range(0, len(items), per):
        sheet = Image.new("RGB", (COLS * CELL, ROWS * (CELL + 34)), "white")
        draw = ImageDraw.Draw(sheet)
        for k, item in enumerate(items[page:page + per]):
            x, y = (k % COLS) * CELL, (k // COLS) * (CELL + 34)
            img = Image.open(ROOT / item.get("image", f"data/images/{item['id']}.jpg")).convert("RGB")
            img.thumbnail((CELL - 6, CELL - 6))
            sheet.paste(img, (x + 3, y + 3))
            e = item["expected"]
            label = f"{page + k} {e.get('subtype', '')} {e.get('length', '')}".strip()
            draw.text((x + 3, y + CELL), label[:32], fill="black")
            draw.text((x + 3, y + CELL + 14), f"{e.get('primaryColor', '-')}", fill="blue")
        sheet.save(out / f"sheet_{page // per:02d}.jpg", quality=85)
    print("sheets", (len(items) + per - 1) // per)
