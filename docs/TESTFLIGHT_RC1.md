# RIG v0.2 RC1 distribution preparation

Product Steps 1–6 are complete. The last pre-preparation Gate A checkpoint is
`ce8f1267b24066e841a71c9b671b49052e6b4454`, run `36393292492`: 213 tests, zero
failures. Physical-device acceptance remains open. No TestFlight upload has
been performed by this preparation. The signed release workflow has not yet run.

## Version and identity

- Bundle ID: `dev.rig.app`. Confirm ownership in the intended Apple team before
  registering the identifier or creating the app record.
- RC1 proposal adopted in project.yml: marketing version `0.2`, build `1`.
  RC1 is a release label in documentation, not a suffix in the numeric version.
- Info.plist uses MARKETING_VERSION and CURRENT_PROJECT_VERSION so CI overrides
  reach the app. Subsequent uploaded candidates use `0.2 (2)`, `0.2 (3)`, etc.
  Verify that the chosen build number is unused in App Store Connect first.
- Deployment target remains iOS 17; both iPhone and iPad remain configured.

## Apple prerequisites

An active paid Apple Developer membership, accepted agreements, a registered
explicit App ID, and an App Store Connect iOS app record matching `dev.rig.app`
are required. Their existence is unverified; repository access proves none of
these. Create the app record before validation/upload.

Apple requires Xcode 26 / iOS 26 SDK or newer for App Store Connect uploads
since April 28, 2026. Gate A stays on Xcode 16.4. The release workflow selects
Xcode 26.3 on macOS 26 explicitly, with no beta fallback. Its first archive will
also establish release compiler compatibility; the simulator gate does not.

Sources: [Apple SDK requirement](https://developer.apple.com/news/upcoming-requirements/?id=02032026a),
[upload requirements](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[create app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/),
[runner toolchain inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md).

## Secure setup

Create a GitHub environment named `testflight`, restricted to main with required
reviewers where the account supports that protection. Do not put credentials in
files tracked by Git. At inspection there were zero repository Actions secrets,
zero environments, and no local release credential environment variables.

Set these environment secrets (names only; never paste values into logs):

| Secret | Contents |
|---|---|
| APPLE_TEAM_ID | Ten-character Apple Developer team ID |
| IOS_DISTRIBUTION_P12_BASE64 | Base64 Apple Distribution certificate and private key exported as password-protected P12 |
| IOS_DISTRIBUTION_P12_PASSWORD | P12 export password |
| IOS_APP_STORE_PROFILE_BASE64 | Base64 App Store Connect distribution profile for the exact bundle ID and certificate |
| ASC_KEY_ID | App Store Connect team API key ID |
| ASC_ISSUER_ID | API issuer UUID |
| ASC_PRIVATE_KEY_BASE64 | Base64 AuthKey private P8 key |

Use an App Store Connect team API key with access sufficient to validate/upload
this app (Developer or higher according to Apple role requirements). App record
creation and certificate/profile creation may require a different authorized
account role. Prefer the API key over an Apple ID/password. This workflow uses
manual signing assets; an upload API key alone does not supply signing assets.
Base64 is encoding, not encryption. Store values only in secure secret storage.

The repository keeps Automatic signing for developer builds, without a team ID.
CI overrides to Manual with a temporary keychain and matching App Store profile.
It rejects development/ad hoc/enterprise/expired/mismatched profiles. Credentials
are removed on exit and never selected as artifacts. Job termination destroys
the ephemeral runner. The signed IPA, dSYMs, archive, decoded credentials, and
raw tool logs stay in runner temporary storage. Only sanitized diagnostics and
a credential-free manifest are retained for 14 days.

## Release workflow operation

`iOS release candidate (TestFlight)` in `.github/workflows/ios-release.yml` is
manual only, accepts an explicit build number, requires main and a successful
Gate A for the exact commit, and serializes release jobs. It installs Homebrew
XcodeGen and logs the resolved version (not pinned; an upstream change can
affect generation). It generates the project before archiving.

It builds a signed Release archive for generic iphoneos, exports with
`method=app-store-connect`, and checks signature, arm64, bundle/version, SDK,
distribution entitlements, embedded profile, and privacy manifest. It then
uses `xcrun altool` with API authentication for Apple validation. Validation
contacts Apple and requires the app record/API key even with upload disabled.
All pipes preserve failures through `set -euo pipefail`.

`upload_to_testflight` defaults to false. First dispatch with false to inspect
the IPA and logs. A later **explicitly authorized** dispatch with true uploads
only after all validation succeeds. Do not dispatch either mode until secrets
and Apple prerequisites are ready. This preparation dispatches only Gate A.
Apple processing, export-compliance review, TestFlight test information and
tester invitation remain separate. External testers may require beta review.

Artifacts: sanitized stage diagnostics and a manifest containing commit, bundle,
version, build, architecture, validation results and upload status. The sanitizer
publishes only fixed status words and source locations for compiler errors; raw
messages remain private. A sanitizer failure removes the artifact directory.
The job has a 45-minute timeout; failures stop further release operations and
artifact collection runs even on failure. No retry automatically uploads another
build. An IPA for distribution is sent directly to App Store Connect only when
upload is explicitly enabled.

Artifact policy for this public repository: the allowlisted manifest and
sanitized status/source-location logs may be shared. A signed IPA, dSYMs and
archive are restricted to authorized developers and are not uploaded as Actions
artifacts. Private keys, P12 files, profiles, temporary keychains, decoded
entitlements, raw tool logs and authentication output must never be published.

## Compliance and privacy before upload

`ITSAppUsesNonExemptEncryption=false` reflects the current source: no custom
cryptography, network service or third-party SDK. The Apple account holder must
confirm that classification; amend it if a later dependency changes the facts.
The privacy manifest declares no tracking/collected data/required-reason APIs.
Camera usage text and a 1024px app icon exist; PhotosPicker requires no blanket
photo-library permission. Verify archive validation and App Store Connect
privacy answers against actual behavior. No claim of Apple approval is made.

Set accurate App Privacy answers, a reachable privacy policy/support contact,
TestFlight beta description, feedback email and review contact/instructions.
No login credentials should be required because the app has no accounts.
Review any Apple encryption questionnaire/required-reason API diagnostics
before inviting testers. Store screenshots/production metadata are separate
from this physical MVP verification.

## Device acceptance

Use [the physical iPhone checklist](PHYSICAL_IPHONE_MVP_CHECKLIST.md), record the
actual TestFlight build/device/iOS, and attach failure reproduction details.
All rows remain unexecuted until a tester completes them on a real iPhone.
