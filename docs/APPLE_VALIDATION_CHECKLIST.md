# Apple validation checklist

Three gates, in order. Nothing below has been attempted; every box is open.
Do not mark a gate passed on inspection — only on a run.

---

## GATE A — BUILD (macOS, no device needed)

One command:

```sh
bash scripts/validate_macos.sh
```

It fails closed and ends in `RESULT: PASS` or `RESULT: FAIL`.

- [ ] **XcodeGen** — `xcodegen generate` produces `RIG.xcodeproj` from `project.yml`
- [ ] **Simulator compile** — `xcodebuild build` succeeds for `generic/platform=iOS Simulator`
- [ ] **XCTest** — all tests in `RIGTests` pass on an installed iPhone simulator

Expect compile errors on the first run. Four thousand lines of never-compiled
Swift, SwiftData macros and SwiftUI result builders will not be clean first
time. That is the point of the gate, not a failure of it.

Record: Xcode version, XcodeGen version, simulator used, number of tests run.

---

## GATE B — SIMULATOR SMOKE (macOS, no device needed)

Run the app on the simulator and drive it by hand. The camera and Vision are
not meaningfully testable here; that is Gate C.

- [ ] **Launches** — reaches the Home tab, no crash, no `StartupFailureView`
- [ ] **Garment CRUD** — add a garment from Photos, see it in Wardrobe, open it,
      edit its name and category, favourite it, delete it
- [ ] **PhotosPicker** — the picker appears and returns an image with **no**
      photo-library permission prompt (RIG uses the out-of-process picker)
- [ ] **Manual outfit builder** — slots fill, an already-chosen garment cannot be
      chosen twice, validation messages appear for an incomplete look, Save is
      disabled until the look is valid
- [ ] **Suggest a Look** — with at least one top and one bottom (or one dress),
      three ranked cards appear; "Show another set" returns different looks;
      an under-stocked wardrobe shows the explanatory empty state instead
- [ ] **Save look** — a saved suggestion appears in Looks and on Home
- [ ] **Like / Dislike** — the thumb fills in; tapping the other one replaces the
      first rather than recording both
- [ ] **Relaunch persistence** — quit and relaunch: garments, looks and ratings
      are all still there, and garment images still render

Also worth watching for: any suggestion card showing a percentage (there must
be none), and any look that is structurally invalid (two bottoms, a dress with
a top, the same garment twice).

---

## GATE C — PHYSICAL IPHONE

The only gate that can retire the real product risk.

- [ ] **Camera permission** — the prompt appears once, with RIG's usage string;
      denying it does not crash and leaves Photos import working
- [ ] **Camera capture** — a photo is captured and reaches the review step
- [ ] **Real garment import** — import ten actual garments: worn, on a hanger, on
      a bed, in domestic lighting, not catalogue cut-outs
- [ ] **Vision foreground extraction** — `VNGenerateForegroundInstanceMaskRequest`
      actually returns instances for those photographs
- [ ] **Cutout quality** — judge the results by eye. This is the single largest
      unknown in RIG. If the cutouts are poor the wardrobe looks bad no matter
      how correct everything behind it is
- [ ] **Fallback when Vision fails** — force it (a busy background, a blank wall,
      a photo of nothing): the garment still saves, the original photo is used,
      and both the review step and the detail screen say so
- [ ] **Persistence after relaunch** — force-quit and relaunch with a real
      wardrobe; images still load from Application Support
- [ ] **Image deletion / orphan cleanup** — delete a garment, confirm its
      directory is gone; then kill the app mid-delete if you can and confirm the
      next launch's orphan sweep collects the leftovers
- [ ] **Memory and responsiveness** — 50+ garments: scroll the wardrobe grid,
      open Suggestions repeatedly, watch memory in Instruments. The image cache
      holds decoded 400 px thumbnails and is bounded by `NSCache`; confirm that
      is actually enough

Record: device model, iOS version, wardrobe size, peak memory, and a subjective
score for cutout quality out of ten.

---

## After the gates

Only once Gate C is done is there enough evidence to judge whether the
rule-based engine produces looks a person would actually wear — which is a
judgement question about real clothes, not a code question, and is the correct
input to any decision about revisiting the ML seam.
