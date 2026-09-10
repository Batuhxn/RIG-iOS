import Foundation

/// The one seam through which a future machine-learning compatibility model may
/// contribute to ranking.
///
/// Deliberate constraints, all enforced by `OutfitEngine`:
///
/// - A provider returns an optional. `nil` means "no opinion", and the engine
///   carries on with rules alone. Providers are never required to answer.
/// - The returned value is a *signal* in 0...1, not a probability, not a verdict
///   and not something the interface ever displays.
/// - The signal is capped at `OutfitEngineConfiguration.maximumAllowedCompatibilitySignalWeight`
///   of the final score. It can reorder near-ties. It cannot overturn the rules.
/// - It has no say whatsoever in `OutfitValidator`. Structural validity is RIG's.
///
/// RIG v0.1 ships with no provider. See `FashionMLSpike/reports/FINAL_DECISION.md`
/// for why: the evaluated pretrained head saturated to a constant, weighed some
/// 806 MB once converted, and its checkpoint licensing is unresolved.
protocol CompatibilityProvider: Sendable {
    var isEnabled: Bool { get }
    func compatibilitySignal(for items: [GarmentSnapshot]) async throws -> Double?
}

/// The v0.1 provider: present in the type system, silent in practice.
struct DisabledCompatibilityProvider: CompatibilityProvider {
    let isEnabled = false

    func compatibilitySignal(for items: [GarmentSnapshot]) async throws -> Double? {
        nil
    }
}
