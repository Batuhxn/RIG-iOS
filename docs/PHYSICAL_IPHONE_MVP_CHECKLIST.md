# RIG v0.2 RC1 — physical iPhone MVP verification

Status: NOT RUN. Blank PASS/FAIL cells do not count as success.

- TestFlight version/build:
- Tested commit SHA:
- iPhone model / iOS version:
- Tester / date:
- Installation source / previous version:

Record PASS or FAIL in the corresponding column and details in NOTES. For a
failure include steps, image characteristics, screenshot and crash time if any.
Use non-sensitive sample images. Test on an iPhone with iOS 17 or newer.

| Test | Expected result | PASS | FAIL | NOTES |
|---|---|---|---|---|
| Fresh install | Launches into usable first-run experience; no startup error or crash | | | |
| First garment import | A single import can complete with intentional category/metadata; no multi-item onboarding requirement | | | |
| PhotosPicker | Opens, selects image, supports cancel; no broad library permission prompt | | | |
| Camera capture | Permission appears when requested; allow captures; deny/cancel leaves app usable | | | |
| JPEG | Imports, previews and saves correctly | | | |
| HEIC | Imports from iPhone library; orientation and preview correct | | | |
| Portrait image | Aspect ratio/orientation preserved through preview and saved thumbnail | | | |
| White garment / light background | Inspect foreground extraction; Original remains usable if cutout is poor | | | |
| Dark garment / dark background | Inspect extraction and edges; Original fallback remains available | | | |
| Shoes | Correct category can be chosen; preview and save usable | | | |
| Bag/accessory | Correct category can be chosen; preview and save usable | | | |
| Garment worn/held by person | Inspect whether person/hands enter cutout; user can choose Original | | | |
| Cutout vs Original | Switching is responsive; selected representation is retained after save and relaunch | | | |
| Single duplicate flow | Known duplicate prompts; skip leaves count unchanged; intentional keep creates one additional item | | | |
| Bulk duplicate flow | Mixed new/duplicate imports allow item decisions; skipped items stay absent and accepted items save once | | | |
| Wardrobe filters | Categories and active filters show correct items and can be cleared | | | |
| Edit | Name/category/metadata persist; save failure remains recoverable if encountered | | | |
| Favorite | Toggle reflects in detail/list and persists after relaunch | | | |
| Delete | Confirmation/cancel correct; confirmed item disappears and stays deleted | | | |
| Suggestion generation | Minimal viable wardrobe yields useful valid suggestions; insufficient wardrobe explains what to add | | | |
| Top + bottom | One top and one bottom produce a valid look without mandatory shoes | | | |
| Dress | A dress alone produces a valid base look | | | |
| Outerwear without shoes | Outerwear can accompany a valid base; absence of shoes does not block it | | | |
| Saved look | Save suggestion/manual look; it appears in Looks and opens correctly | | | |
| Relaunch persistence | Force quit/reopen; garments, images, edits, favorites and saved looks survive | | | |
| Deleted garment / missing look | Delete garment used in a look; opening affected look handles missing garment without crash or stale image | | | |
| Crash-free completion | Entire sequence completed without crash, hang or unrecoverable state | | | |

## Acceptance record

- Overall: PASS / FAIL / NOT RUN
- Blocking failures:
- Non-blocking image-quality observations:
- Follow-up build needed:
- Evidence location:

Simulator tests do not satisfy these physical-device checks. Do not mark a
Vision quality row PASS solely because import completed; inspect the image.
