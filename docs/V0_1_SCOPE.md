# RIG iOS v0.1 — scope

This document exists so that v0.1 stops where it says it stops. Anything in the
OUT list is a later version, not a small addition.

## In

- Native SwiftUI application, iOS 17 minimum, no third-party runtime dependencies.
- Local wardrobe stored with SwiftData on the device.
- Garment import from the Photos library and from the camera.
- Local foreground extraction with Apple Vision, and a graceful fallback to the
  original photograph when it fails.
- Garment metadata: name, optional kind, category, primary colour family,
  seasons, favourite, notes.
- Garment browsing, filtering by category and season and favourites, editing,
  and deletion including its image files.
- Rule-based outfit suggestions: bounded deterministic candidate generation, a
  hard validity gate, and ranking on colour, season, structural completeness and
  explicit favourites.
- A manual outfit builder with the same validity rules.
- Saved looks, from suggestions or built by hand.
- Like and dislike capture, stored locally against an order-independent outfit
  signature.
- A `CompatibilityProvider` seam for future ML, shipped with no provider attached.
- Unit tests for the deterministic logic.
- An Xcode project specification, a macOS validation script and a host-side
  static audit.

## Out

Not started, not stubbed, not designed around:

- Accounts, authentication, or any notion of a user identity.
- Any backend, API server, or web frontend.
- Sync of any kind: iCloud, CloudKit, or a third party.
- Weather.
- An occasion engine.
- Personal preference learning. Feedback is captured and nothing reads it.
- Any machine-learning compatibility model, on device or otherwise.
- Virtual try-on, body rendering, or generated fashion imagery.
- Social features, sharing, or export.
- Analytics, telemetry, crash reporting, advertising.
- Localisation infrastructure.
- App Store submission work, icons, screenshots, or store metadata.
- Monetisation of any kind.
- Android, iPad-specific layouts, watch or vision targets.

## Recurring cost

Zero. There is no service to pay for, because there is no service.

## The rule that keeps this honest

Every deferred item above must remain addable without rewriting the wardrobe or
the interface. That is the whole reason `OutfitEngine` scores from
`GarmentSnapshot` values behind a protocol rather than reaching into SwiftData,
and the reason weather, occasion and preference are described as future *inputs
to ranking* rather than future rewrites.
