# Gemini adversary — round 1 (Gemini 3 Flash via Antigravity, 2026-10-08)

Hypotheses only. Each is kept or dropped by measurement (`scripts/prompt_experiments.py`).

## Synonym changes
- sweater: remove "a sweatshirt"; add "a chunky knit wool pullover", "a ribbed crewneck sweater".
- coat: add "a long tailored overcoat", "an outerwear trench coat".
- heels: remove bare "high heels"; add "pointed stiletto pumps", "open high heel sandals".
- boots: add "tall shaft boots", "ankle boots covering the ankle".
- flats: add "flat slip-on loafers", "zero-heel ballet flats".
- blouse: remove bare "a blouse"; add "a dressy woven buttoned blouse", "a silk work blouse".
- t-shirt: add "a casual cotton jersey tee".
- dress: add "a one-piece full-body dress", "a dress with connected bodice and skirt".

## Hard negatives
- boots: "boots with an upper shaft, not low-top flats or exposed pumps"
- flats: "flat-soled shoes with no elevated heel"
- dress: "a continuous one-piece dress, not a separate blouse or top"
- trousers: "dress pants or slacks, not denim jeans"

## Inherently ambiguous (abstain)
heeled booties (boots/heels); midi vs maxi (letterbox removes absolute scale);
flowy shorts vs mini skirt; black trousers vs black jeans.

## Preprocessing experiments
- letterbox colour (128,128,128) or (240,240,240) instead of white (white garments blend)
- 3:4 crop / aspect preservation instead of 1:1 letterbox
- longest edge at 90% of the canvas (margin padding)

## Colour
cream → white family; anchor blue vs navy with "light or medium royal blue" vs
"very dark navy blue"; black vs metallic: avoid specular wording for black.
