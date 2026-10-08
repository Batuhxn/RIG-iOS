"""Select a balanced, title-labelled benchmark subset from the Polyvore text index.

Labels come from product titles with conservative regex rules (weak labels). Every
selected image is then visually reviewed; see data/review_overrides.json.
Classes follow the v0.3 taxonomy (RiG GarmentCategory raw values + subtype strings).
"""
import json
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PER_CLASS = int(sys.argv[1]) if len(sys.argv) > 1 else 12
FILES = set(sys.argv[2].split(",")) if len(sys.argv) > 2 else None

NOT_GARMENT = r"set|pack|bundle|socks?|lingerie|bra\b|swim|bikini|pajama|kids?|baby|girls?'|boys?'|costume|doll"

# (category, subtype, polyvore categories allowed, include regex, exclude regex)
RULES = [
    ("top", "t-shirt", {"tops"}, r"\bt-?shirt|\btee\b", r"dress|sweatshirt|tank|long sleeve"),
    ("top", "shirt", {"tops"}, r"\bshirt\b", r"t-?shirt|sweatshirt|dress|tee\b|blouse|overshirt|jacket"),
    ("top", "blouse", {"tops"}, r"\bblouse\b", r"dress|shirt"),
    ("top", "sweater", {"tops", "outerwear"}, r"\bsweater\b|\bjumper\b|\bpullover\b", r"dress|cardigan|hood|vest|sweatshirt"),
    ("top", "hoodie", {"tops", "outerwear"}, r"\bhoodie\b|\bhooded sweatshirt\b", r"dress|zip|jacket|vest"),
    ("top", "tank top", {"tops"}, r"\btank\b|\bcamisole\b|\bcami\b", r"dress|tankini"),
    ("bottom", "jeans", {"bottoms"}, r"\bjeans?\b", r"short|skirt|jacket|dress|overall"),
    ("bottom", "trousers", {"bottoms"}, r"\btrousers?\b|\bpants\b|\bchinos?\b", r"jean|denim|short|legging|jogger|sweatpant|track|culotte|skirt|pajama"),
    ("bottom", "shorts", {"bottoms"}, r"\bshorts\b", r"skort|jacket|swim|board"),
    ("bottom", "skirt:mini", {"bottoms"}, r"\bmini[- ]skirt\b|\bmini\b.*\bskirt\b", r"skort|short|dress|midi|maxi"),
    ("bottom", "skirt:midi", {"bottoms"}, r"\bmidi[- ]skirt\b|\bmidi\b.*\bskirt\b", r"skort|short|dress|mini|maxi"),
    ("bottom", "skirt:maxi", {"bottoms"}, r"\bmaxi[- ]skirt\b|\bmaxi\b.*\bskirt\b", r"skort|short|dress|mini|midi"),
    ("dress", "dress:mini", {"all-body"}, r"\bmini[- ]dress\b|\bmini\b.*\bdress\b", r"shirt|top|midi|maxi|jumpsuit|romper"),
    ("dress", "dress:midi", {"all-body"}, r"\bmidi[- ]dress\b|\bmidi\b.*\bdress\b", r"shirt|top|mini|maxi|jumpsuit|romper"),
    ("dress", "dress:maxi", {"all-body"}, r"\bmaxi[- ]dress\b|\bmaxi\b.*\bdress\b", r"shirt|top|mini|midi|jumpsuit|romper"),
    ("outerwear", "jacket", {"outerwear"}, r"\bjacket\b", r"blazer|coat|vest|gilet|dress|shirt"),
    ("outerwear", "coat", {"outerwear"}, r"\bcoat\b|\bovercoat\b|\btrench\b", r"jacket|blazer|petticoat|vest|dress|top coat|coatigan"),
    ("outerwear", "blazer", {"outerwear", "tops"}, r"\bblazer\b", r"dress|vest"),
    ("outerwear", "cardigan", {"outerwear", "tops"}, r"\bcardigan\b", r"dress|coat|vest|jacket"),
    ("shoes", "sneakers", {"shoes"}, r"\bsneakers?\b|\btrainers?\b", r"boot|sandal|slip-on loafer"),
    ("shoes", "boots", {"shoes"}, r"\bboots?\b|\bbooties?\b", r"sneaker|sandal|boot-cut|bootcut"),
    ("shoes", "heels", {"shoes"}, r"\bpumps?\b|\bheels?\b|\bstilettos?\b", r"boot|sandal|sneaker|flat|mule|slingback"),
    ("shoes", "flats", {"shoes"}, r"\bballet flats?\b|\bballerinas?\b|\bflats\b", r"boot|sandal|sneaker|heel"),
    ("shoes", "sandals", {"shoes"}, r"\bsandals?\b", r"heel|boot|sneaker|wedge|platform|stiletto"),
    ("bag", "handbag", {"bags"}, r"\bbag\b|\btote\b|\bclutch\b|\bbackpack\b", r"phone|case|cosmetic|makeup|charm"),
]

COLOR_WORDS = {
    "black": "black", "white": "white", "grey": "gray", "gray": "gray", "charcoal": "gray",
    "beige": "beige", "camel": "beige", "sand": "beige", "nude": "beige", "brown": "brown",
    "chocolate": "brown", "navy": "navy", "blue": "blue", "cobalt": "blue", "green": "green",
    "emerald": "green", "olive": "olive", "khaki": "olive", "red": "red", "burgundy": "burgundy",
    "wine": "burgundy", "bordeaux": "burgundy", "pink": "pink", "blush": "pink", "fuchsia": "pink",
    "purple": "purple", "lilac": "purple", "lavender": "purple", "orange": "orange",
    "yellow": "yellow", "mustard": "yellow", "gold": "metallic", "silver": "metallic", "metallic": "metallic",
}
PATTERN_WORDS = r"print|stripe|floral|check|plaid|gingham|tartan|leopard|zebra|camo|polka|dot|multi|colou?r[- ]?block|tie[- ]dye|paisley|patchwork|embroider|sequin|graphic|logo"
# Ambiguous colour words make the title unusable as colour ground truth.
AMBIGUOUS = r"\b(ivory|cream|ecru|off[- ]white|stone|taupe|tan|denim|indigo|wash|rose|coral|teal|turquoise|mint|rust|tobacco|cognac|mocha|bronze|copper|light|dark|pale|neon|bright)\b"


def color_label(title):
    t = title.lower()
    if re.search(PATTERN_WORDS, t) or re.search(AMBIGUOUS, t):
        return None
    found = {COLOR_WORDS[w] for w in re.findall(r"[a-z]+", t) if w in COLOR_WORDS}
    return found.pop() if len(found) == 1 else None


def main():
    rows = [json.loads(l) for l in (ROOT / "data/polyvore_index.jsonl").open(encoding="utf-8")]
    pools = defaultdict(list)
    for row in rows:
        if FILES and row["file"] not in FILES:
            continue
        title = ((row.get("title") or "").strip() or (row.get("url_name") or "").strip())
        t = title.lower()
        if not title or re.search(NOT_GARMENT, t):
            continue
        hits = [r for r in RULES if row["category"] in r[2] and re.search(r[3], t) and not re.search(r[4], t)]
        if len(hits) != 1:  # ambiguous across classes: skip rather than guess
            continue
        pools[hits[0][1]].append((row, hits[0]))
    print({k: len(v) for k, v in sorted(pools.items())})
    rng = random.Random(20261008)
    selected = []
    for _, sub, *_ in RULES:
        pool = pools[sub]
        # Prefer items with a colour label so colour accuracy has enough support.
        rng.shuffle(pool)
        pool.sort(key=lambda p: color_label(p[0]["title"] or p[0]["url_name"]) is None)
        for row, (category, subtype, *_rest) in pool[:PER_CLASS]:
            base, _, length = subtype.partition(":")
            expected = {"category": category, "subtype": base}
            if length:
                expected["length"] = length
            color = color_label(row["title"] or row["url_name"])
            if color:
                expected["primaryColor"] = color
            selected.append({"id": f"pv-{row['item_id']}", "source": "polyvore", "item_id": row["item_id"],
                             "file": row["file"], "row": row["row"], "title": row["title"] or row["url_name"], "expected": expected})
    out = ROOT / "data/selection.json"
    out.write_text(json.dumps(selected, indent=1, ensure_ascii=False), encoding="utf-8")
    print(len(selected), "selected;", Counter(s["expected"].get("primaryColor") for s in selected))


if __name__ == "__main__":
    main()

