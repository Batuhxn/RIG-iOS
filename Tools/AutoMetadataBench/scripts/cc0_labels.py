"""Visual labels for the CC0 sample (Claude, 2026-10-08, from results/cc0_sheets).

Weak dataset labels were NOT copied: several were wrong (e.g. 'Blazer' on denim jackets,
'Shorts' on capri trousers, 'Hoodie' on a hoodie dress). None = not judged reliably from
the photo. H = hard case (lighting, mask leak, navy/black, top vs dress, unusual item).
X = excluded (garment identity ambiguous). Writes data/cc0_labels.json in the bench format.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
X = "exclude"
L = {  # idx: (category, subtype, length, colour, hard)
 0: ("top", "t-shirt", None, "orange", 0), 1: ("top", "t-shirt", None, None, 0), 2: ("top", "t-shirt", None, "gray", 0),
 3: ("top", "t-shirt", None, "black", 0), 4: ("top", "t-shirt", None, "pink", 0), 5: ("top", "t-shirt", None, "black", 0),
 6: ("top", "t-shirt", None, None, 1), 7: ("top", "t-shirt", None, "gray", 0), 8: ("top", "t-shirt", None, None, 0),
 9: ("top", "t-shirt", None, None, 0), 10: ("top", "t-shirt", None, None, 0), 11: ("top", "t-shirt", None, None, 0),
 12: ("top", "t-shirt", None, "blue", 0), 13: ("top", "t-shirt", None, None, 1), 14: ("top", None, None, "navy", 1),
 15: ("outerwear", "cardigan", None, None, 1), 16: ("top", None, None, "burgundy", 0), 17: ("top", None, None, "gray", 0),
 18: ("top", None, None, "navy", 1), 19: ("top", None, None, None, 0), 20: ("top", None, None, None, 0),
 21: ("top", "sweater", None, "gray", 0), 22: ("top", None, None, None, 1), 23: ("top", None, None, None, 0),
 24: ("top", "sweater", None, "gray", 1), 25: ("top", "sweater", None, "beige", 0), 26: X,
 27: ("top", "sweater", None, None, 0), 28: ("top", "shirt", None, None, 0), 29: ("top", "shirt", None, "red", 0),
 30: ("top", None, None, None, 1), 31: ("top", "shirt", None, None, 0), 32: ("top", None, None, None, 0),
 33: ("top", "shirt", None, None, 0), 34: ("top", None, None, "gray", 0), 35: ("top", "shirt", None, "blue", 0),
 36: ("top", "shirt", None, None, 0), 37: ("top", "shirt", None, None, 0), 38: ("top", "shirt", None, "blue", 0),
 39: ("top", "shirt", None, "black", 0), 40: ("top", "shirt", None, None, 0), 41: ("top", "shirt", None, None, 0),
 42: ("top", None, None, "black", 1), 43: ("top", "blouse", None, None, 0), 44: ("top", "blouse", None, None, 0),
 45: ("top", None, None, "white", 1), 46: ("top", "blouse", None, None, 0), 47: ("top", "blouse", None, None, 0),
 48: ("top", "blouse", None, "white", 0), 49: ("top", None, None, "black", 1), 50: ("top", "blouse", None, None, 0),
 51: ("top", "blouse", None, None, 0), 52: ("top", "blouse", None, None, 0), 53: ("top", "blouse", None, None, 0),
 54: ("top", "hoodie", None, "gray", 0), 55: ("top", "hoodie", None, None, 0), 56: ("top", "hoodie", None, "pink", 0),
 57: ("top", "hoodie", None, "navy", 1), 58: ("top", "hoodie", None, "burgundy", 0), 59: ("top", "hoodie", None, "black", 0),
 60: ("top", "hoodie", None, None, 1), 61: ("top", "hoodie", None, "beige", 1), 62: X, 63: X,
 64: ("top", "hoodie", None, None, 0), 65: ("top", "hoodie", None, "white", 0), 66: ("top", "hoodie", None, None, 0),
 67: ("top", None, None, None, 0), 68: ("top", "tank top", None, None, 0), 69: ("top", "tank top", None, None, 0),
 70: ("top", "tank top", None, None, 0), 71: ("top", "tank top", None, "black", 0), 72: ("top", "tank top", None, "black", 0),
 73: ("top", "tank top", None, "red", 0), 74: ("top", "tank top", None, "black", 1), 75: ("top", None, None, None, 1),
 76: ("top", "tank top", None, None, 0), 77: ("top", "tank top", None, None, 0), 78: ("top", None, None, None, 0),
 79: ("top", "shirt", None, None, 0), 80: ("top", None, None, None, 0), 81: ("top", None, None, "blue", 0),
 82: ("top", None, None, None, 0), 83: ("top", None, None, None, 0), 84: ("top", "tank top", None, "white", 0),
 85: ("top", "tank top", None, "beige", 0), 86: ("top", "tank top", None, "gray", 0), 87: ("top", "tank top", None, "blue", 0),
 88: ("top", "tank top", None, "navy", 1), 89: ("top", "tank top", None, None, 0), 90: ("top", "tank top", None, "blue", 0),
 91: ("top", "tank top", None, "beige", 1), 92: ("bottom", "jeans", None, None, 0), 93: ("bottom", "jeans", None, "blue", 0),
 94: ("bottom", "trousers", None, None, 0), 95: ("bottom", "trousers", None, None, 0), 96: ("bottom", None, None, "purple", 0),
 97: ("bottom", "jeans", None, None, 0), 98: ("bottom", "jeans", None, "blue", 0), 99: ("bottom", "trousers", None, "gray", 0),
 100: ("bottom", "trousers", None, None, 0), 101: ("bottom", "trousers", None, None, 0), 102: ("bottom", None, None, None, 1),
 103: ("bottom", "trousers", None, "navy", 1), 104: ("bottom", "trousers", None, None, 0), 105: ("bottom", "trousers", None, None, 0),
 106: ("bottom", "trousers", None, None, 1), 107: ("bottom", "trousers", None, "black", 1), 108: ("bottom", None, None, "blue", 0),
 109: ("bottom", "jeans", None, "blue", 0), 110: ("bottom", "trousers", None, "olive", 0), 111: ("bottom", "trousers", None, "white", 0),
 112: ("bottom", "trousers", None, "navy", 1), 113: ("bottom", "trousers", None, "navy", 0), 114: ("bottom", "shorts", None, None, 0),
 115: ("bottom", "shorts", None, "black", 0), 116: ("bottom", "shorts", None, "black", 0), 117: ("bottom", "shorts", None, "white", 0),
 118: ("bottom", "shorts", None, "blue", 0), 119: ("bottom", "shorts", None, "navy", 0), 120: ("bottom", None, None, "black", 1),
 121: ("bottom", "shorts", None, None, 0), 122: ("bottom", "shorts", None, "gray", 0), 123: ("bottom", "shorts", None, "gray", 0),
 124: ("bottom", "shorts", None, "olive", 0), 125: ("bottom", "shorts", None, "blue", 0), 126: ("bottom", "shorts", None, None, 0),
 127: ("bottom", "shorts", None, None, 0), 128: ("bottom", None, None, None, 1), 129: ("bottom", "shorts", None, "blue", 0),
 130: ("bottom", "skirt", "mini", None, 0), 131: ("bottom", "skirt", "mini", "blue", 0), 132: ("bottom", "skirt", None, None, 0),
 133: ("bottom", "skirt", "mini", None, 0), 134: ("bottom", "skirt", None, "olive", 0), 135: ("bottom", "skirt", "mini", None, 0),
 136: ("bottom", "skirt", None, None, 1), 137: ("bottom", "skirt", None, "white", 0), 138: ("bottom", "skirt", "maxi", None, 0),
 139: ("bottom", "skirt", "mini", None, 0), 140: ("bottom", "skirt", "mini", "pink", 0), 141: ("bottom", "skirt", "mini", "blue", 0),
 142: ("bottom", "skirt", "midi", "black", 0), 143: ("bottom", "skirt", None, None, 0), 144: ("bottom", "skirt", "mini", None, 0),
 145: ("bottom", "skirt", None, None, 0), 146: ("bottom", "skirt", "mini", "white", 0), 147: X,
 148: ("dress", "dress", "mini", "white", 0), 149: ("dress", "dress", None, "red", 0), 150: ("dress", "dress", None, "navy", 0),
 151: ("dress", "dress", None, None, 0), 152: ("dress", "dress", None, None, 1), 153: ("dress", "dress", None, None, 0),
 154: ("dress", "dress", None, None, 0), 155: X, 156: ("dress", "dress", None, None, 0), 157: ("dress", "dress", None, None, 0),
 158: ("dress", "dress", None, None, 0), 159: ("dress", "dress", None, "brown", 0), 160: ("dress", "dress", None, None, 1),
 161: ("dress", "dress", None, None, 0), 162: X, 163: ("dress", "dress", None, "blue", 1), 164: ("dress", "dress", None, None, 0),
 165: ("dress", "dress", None, None, 0), 166: ("outerwear", "jacket", None, "black", 0), 167: ("outerwear", "jacket", None, None, 0),
 168: ("outerwear", None, None, "olive", 0), 169: ("outerwear", "jacket", None, "black", 0), 170: ("outerwear", "jacket", None, "black", 0),
 171: ("outerwear", "jacket", None, "red", 0), 172: ("outerwear", "jacket", None, "black", 0), 173: ("outerwear", "jacket", None, "black", 0),
 174: ("outerwear", None, None, "white", 0), 175: ("outerwear", None, None, "pink", 0), 176: ("outerwear", "jacket", None, "black", 0),
 177: ("outerwear", "jacket", None, None, 0), 178: ("outerwear", None, None, None, 0), 179: ("outerwear", "jacket", None, None, 0),
 180: ("outerwear", "jacket", None, "green", 0), 181: ("outerwear", "jacket", None, "brown", 0), 182: ("outerwear", "jacket", None, "black", 0),
 183: ("outerwear", "jacket", None, "red", 0), 184: ("outerwear", "jacket", None, None, 0), 185: ("outerwear", "jacket", None, None, 0),
 186: ("outerwear", "jacket", None, "navy", 1), 187: ("outerwear", "blazer", None, "beige", 0), 188: ("outerwear", "jacket", None, None, 1),
 189: ("outerwear", "jacket", None, "blue", 0), 190: ("outerwear", "blazer", None, "navy", 0), 191: ("outerwear", "blazer", None, None, 0),
 192: ("outerwear", "blazer", None, "brown", 0), 193: ("outerwear", "blazer", None, "black", 0), 194: ("outerwear", "jacket", None, "blue", 1),
 195: ("outerwear", "blazer", None, "gray", 0), 196: ("outerwear", None, None, "green", 0), 197: ("outerwear", None, None, None, 1),
 198: ("shoes", "sneakers", None, "black", 0), 199: ("shoes", "boots", None, "brown", 0), 200: ("shoes", "boots", None, "purple", 0),
 201: ("shoes", "flats", None, None, 0), 202: ("shoes", "boots", None, None, 0), 203: ("shoes", "sneakers", None, "gray", 0),
 204: ("shoes", "heels", None, "black", 0), 205: ("shoes", "boots", None, None, 0), 206: ("shoes", "flats", None, "black", 0),
 207: ("shoes", "boots", None, None, 0), 208: ("shoes", "sneakers", None, "blue", 0), 209: ("shoes", "sneakers", None, "black", 0),
 210: ("shoes", None, None, None, 1), 211: ("shoes", None, None, None, 1), 212: ("shoes", "sneakers", None, None, 0),
 213: ("shoes", "boots", None, "black", 1), 214: ("shoes", "boots", None, "brown", 0), 215: ("shoes", None, None, "white", 1),
 216: ("shoes", "sandals", None, "black", 0), 217: ("shoes", None, None, None, 1), 218: ("shoes", "flats", None, None, 0),
 219: ("shoes", None, None, None, 1), 220: ("accessory", None, None, "white", 0), 221: ("accessory", None, None, None, 1),
 222: ("accessory", None, None, None, 0), 223: ("accessory", None, None, "beige", 0),
}

if __name__ == "__main__":
    sel = json.loads((ROOT / "data/cc0_selection.json").read_text())
    assert len(L) == len(sel) == 224
    out = []
    for i, it in enumerate(sel):
        lab = L[i]
        cut = ROOT / "data/cc0_cut" / f"{it['image_id']}.png"
        if lab == X or not cut.exists():
            continue
        cat, sub, length, color, hard = lab
        e = {"category": cat}
        if sub:
            e["subtype"] = sub
        if length:
            e["length"] = length
        if color:
            e["primaryColor"] = color
        out.append({"id": it["id"], "index": i, "image": f"data/cc0_cut/{it['image_id']}.png", "source": "cc0",
                    "weak_label": it["weak_label"], "hard": bool(hard), "expected": e})
    (ROOT / "data/cc0_labels.json").write_text(json.dumps(out, indent=1))
    print(len(out), "labelled with cutouts;", sum(o["hard"] for o in out), "hard")
