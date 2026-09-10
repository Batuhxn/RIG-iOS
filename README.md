# RIG — iOS

A wardrobe you actually own, on a phone that keeps it to itself.

You photograph clothes you have. RIG cuts them out of their background on the
device, keeps them in a local wardrobe, and suggests looks from what is there.
Nothing leaves the phone.

## Status

**Implemented; never compiled.** Every source file here was written on a Windows
host with no Apple toolchain. The logic has been reviewed and statically audited,
and 102 unit tests are written, but **no Xcode build and no test run has
happened**. See `reports/V0_1_IMPLEMENTATION_REPORT.md` for exactly what is
verified and what is not, and run `scripts/validate_macos.sh` on a Mac to find
out where it stands.

## v0.1 scope

In: local wardrobe, photo and camera import, on-device foreground extraction with
a graceful fallback, garment metadata and editing, rule-based suggestions, a
manual outfit builder, saved looks, like/dislike capture.

Out: accounts, backend, sync, weather, occasion, preference learning, any ML
model, virtual try-on, sharing, analytics, monetisation.

Full list, including why each exclusion holds: `docs/V0_1_SCOPE.md`.

Recurring operating cost: zero. There is no service.

## Architecture in one paragraph

SwiftUI features read SwiftData models and call into two places: `OutfitEngine/`,
which is pure Foundation and scores looks from immutable `GarmentSnapshot`
values, and `Services/`, which owns garment image files and Apple Vision
background removal behind protocols. Views never score and never touch the file
system; the engine never touches SwiftData. `docs/ARCHITECTURE.md` has the
diagrams, the score breakdown, and the concurrency rules.

## Privacy model

RIG v0.1 contains no networking code of any kind. No `URLSession`, no analytics
SDK, no crash reporter, no cloud container, no advertising identifier, no
location. `scripts/static_audit.py` fails if any of those symbols appear in the
sources, and `Support/PrivacyInfo.xcprivacy` declares no tracking and no
collected data types.

The precise claim, and the only one RIG is entitled to make: **wardrobe data is
stored locally and v0.1 does not upload it.** RIG implements no cryptography of
its own, so it does not claim encryption beyond the protection iOS gives any
app's container.

The only permission the app asks for is the camera, and only when you tap
"Take a photo". Choosing from Photos uses `PhotosPicker`, which needs no
library permission at all.

## Local data model

| Where | What |
|---|---|
| SwiftData | `ClothingItem`, `SavedOutfit`, `OutfitFeedback` |
| Application Support | `Garments/<uuid>/original.jpg`, `cutout.png`, `thumbnail.png` |

Images are files, not database blobs. Each garment owns one directory, so
deleting a garment is one directory removal and two garments can never collide.
Sizes are capped at 1600 / 1200 / 400 px on the longest side.

## Setup

Requires macOS with Xcode 15 or later (iOS 17 SDK).

```sh
brew install xcodegen
cd RIG-iOS
xcodegen generate      # produces RIG.xcodeproj from project.yml
open RIG.xcodeproj
```

`project.yml` is the source of truth; `RIG.xcodeproj` is generated and is not
checked in. There are no package dependencies to resolve.

## Build and test

Everything the script does, in one command:

```sh
bash scripts/validate_macos.sh
```

It refuses to run off macOS, checks for Xcode and XcodeGen, runs the static
audit, generates the project, builds for the simulator with code signing
disabled, picks an installed iPhone simulator, and runs the unit tests. Any
failure stops it with a non-zero status, and the last line is always
`RESULT: PASS` or `RESULT: FAIL`.

That script is Gate A. `docs/APPLE_VALIDATION_CHECKLIST.md` has all three gates:
the build, a simulator smoke pass, and the physical-iPhone pass that is the only
way to find out whether Vision produces usable cutouts.

By hand:

```sh
xcodebuild build -project RIG.xcodeproj -scheme RIG \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO

xcodebuild test -project RIG.xcodeproj -scheme RIG \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

The host-side audit needs no toolchain and runs anywhere:

```sh
python3 scripts/static_audit.py
```

## Optional: running the Apple gate on GitHub Actions

`.github/workflows/ios-validation.yml` is prepared but **not enabled**. It has
never run, and this repository has no remote. To use it later:

1. Create a **private** repository on GitHub. Do not make it public — it holds a
   personal wardrobe application, and nothing here has been reviewed for
   publication.
2. Add it as a remote and push:
   ```sh
   git remote add origin git@github.com:<you>/rig-ios.git
   git push -u origin main
   ```
3. Open the repository's **Actions** tab and enable workflows if prompted.
4. Run **iOS validation** manually from that tab (`workflow_dispatch`).

The workflow checks out the repository, prints the toolchain versions, installs
and verifies XcodeGen, and then runs `scripts/validate_macos.sh` — the same
script a developer runs locally, so there is one gate and not two. It uploads
the `.xcresult` bundle as an artifact. It uses no secrets, signs nothing,
deploys nothing and publishes nothing.

**On cost:** it is deliberately manual-only. GitHub-hosted macOS runners are
metered at a higher multiplier than Linux runners and are not free beyond an
account's included allowance, so this is not a zero-cost gate — check your
account's current billing before enabling the commented-out `push:` trigger.
A Mac you already own runs the identical script for nothing.

## Deliberately not implemented

No weather. No occasion engine. No learned personal style — feedback is captured
and nothing reads it yet, and the interface never claims otherwise. No ML
compatibility model. No virtual try-on or body rendering; a look is your own
garment cutouts, arranged plainly. No sharing, no accounts, no sync. No app icon
or store assets.

Suggestions show a band — "Strong match", "Try this" — and never a percentage.
There is no calibrated probability behind the ranking, so showing a number would
be a lie about precision. A unit test asserts that no generated summary contains
a digit.

## Relationship to FashionMLSpike

`../FashionMLSpike/` is completed, frozen research and is **not** a dependency.
No code, weight or checkpoint from it is in this app, and nothing here imports
Core ML.

Its verdict was CONDITIONAL GO, and three findings shaped this codebase:

- The evaluated pretrained head returned exactly 1.0 for every outfit through its
  shipped output. **A model's score is not a verdict**, which is why
  `OutfitValidator` is RIG's and no provider can overrule it.
- Its converted artefacts totalled roughly 806 MB and were never run on Apple
  hardware. That is not an iPhone footprint, so v0.1 ships no model at all.
- Its checkpoint licensing is unresolved, so integrating it would have been a
  legal question as well as an engineering one.

What survived into the product is the *shape*: coarse category and colour carry
most of the useful signal, so RIG asks for a category rather than a paragraph;
and `CompatibilityProvider` is the single seam where a licensed, validated model
could later contribute a capped signal without any of this being rewritten.

## Verification status

| | |
|---|---|
| Static audit (delimiters, imports, forbidden APIs, force unwraps) | PASS on the development host |
| `project.yml`, workflow YAML and `Info.plist` / privacy manifest parse | PASS |
| `scripts/validate_macos.sh` shell syntax (`bash -n`) | PASS |
| Swift compilation | **NOT RUN** — no Apple toolchain |
| Unit tests | **NOT RUN** — written, never executed |
| Simulator launch | **NOT RUN** |
| Device run, Vision cutout quality, memory behaviour | **NOT RUN** |
