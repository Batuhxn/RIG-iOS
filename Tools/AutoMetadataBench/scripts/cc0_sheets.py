"""Review sheets for the CC0 sample: original | cutout (removed area magenta), weak label."""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
COLS, ROWS, W, H = 4, 5, 300, 170

if __name__ == "__main__":
    items = json.loads((ROOT / "data/cc0_selection.json").read_text())
    out = ROOT / "results/cc0_sheets"
    out.mkdir(parents=True, exist_ok=True)
    per = COLS * ROWS
    for page in range(0, len(items), per):
        sheet = Image.new("RGB", (COLS * W, ROWS * (H + 16)), "white")
        d = ImageDraw.Draw(sheet)
        for k, it in enumerate(items[page:page + per]):
            x, y = (k % COLS) * W, (k // COLS) * (H + 16)
            orig = Image.open(ROOT / "data/cc0" / f"{it['image_id']}.jpg").convert("RGB")
            orig.thumbnail((W // 2 - 4, H - 4))
            sheet.paste(orig, (x + 2, y + 2))
            cut_path = ROOT / "data/cc0_cut" / f"{it['image_id']}.png"
            if cut_path.exists():
                cut = Image.open(cut_path).convert("RGBA")
                bg = Image.new("RGBA", cut.size, (255, 0, 255, 255))
                bg.alpha_composite(cut)
                c = bg.convert("RGB")
                c.thumbnail((W // 2 - 4, H - 4))
                sheet.paste(c, (x + W // 2 + 2, y + 2))
            d.text((x + 2, y + H), f"{page + k} {it['weak_label']}", fill="black")
        sheet.save(out / f"cc0_{page // per:02d}.jpg", quality=85)
    print((len(items) + per - 1) // per, "sheets")
