"""Sheet of colour failures; masked-out area shown magenta so mask artefacts are visible."""
from PIL import Image, ImageDraw

from bench import ROOT, color_codex, color_lab, load_benchmark

if __name__ == "__main__":
    errs = []
    for it in load_benchmark():
        e = it["expected"].get("primaryColor")
        if not e or e == "metallic":
            continue
        im = Image.open(ROOT / "data/cutouts" / f"{it['id']}.png")
        c, l = color_codex(im)[0], color_lab(im)[0]
        if c != e or l != e:
            errs.append((it, im, e, c, l))
    print(len(errs))
    W = 170
    sheet = Image.new("RGB", (W * 8, (W + 30) * ((len(errs) + 7) // 8)), "white")
    d = ImageDraw.Draw(sheet)
    for k, (it, im, e, c, l) in enumerate(errs):
        x, y = (k % 8) * W, (k // 8) * (W + 30)
        bg = Image.new("RGBA", im.size, (255, 0, 255, 255))
        bg.alpha_composite(im.convert("RGBA"))
        t = bg.convert("RGB")
        t.thumbnail((W - 4, W - 4))
        sheet.paste(t, (x + 2, y + 2))
        d.text((x + 2, y + W), f"{it['index']} gt:{e}", fill="black")
        d.text((x + 2, y + W + 13), f"hsv:{c} lab:{l}", fill="blue")
    sheet.save(ROOT / "results/color_errors.jpg", quality=85)
