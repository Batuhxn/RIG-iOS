import Foundation

/// Builds a bounded, deterministic set of structurally valid outfits.
///
/// Two properties matter more than cleverness here:
///
/// - **Bounded.** A wardrobe of 200 garments has millions of combinations. The
///   generator stops at `maximumEvaluatedCandidates` (300 by default) and never
///   materialises more than that.
/// - **Deterministic.** No randomness anywhere. The same wardrobe always yields
///   the same candidates in the same order, which is what makes the engine
///   testable and what makes "show me another set" honest rather than a shuffle.
///
/// Generation is profile-major: every base gets its plain form before any base
/// gets a second pair of shoes, so a truncated run still covers the wardrobe
/// broadly instead of exhausting variations of the first trouser it found.
struct CandidateGenerator: Sendable {
    let configuration: OutfitEngineConfiguration

    init(configuration: OutfitEngineConfiguration = .default) {
        self.configuration = configuration
    }

    private struct DecorationProfile: Hashable {
        var shoeIndex: Int?
        var outerwearIndex: Int?
        var extraIndex: Int?
    }

    func candidates(from wardrobe: [GarmentSnapshot]) -> [OutfitCandidate] {
        let ordered = wardrobe.inDisplayOrder
        let tops = ordered.filter { $0.category == .top }
        let bottoms = ordered.filter { $0.category == .bottom }
        let dresses = ordered.filter { $0.category == .dress }
        let shoes = ordered.filter { $0.category == .shoes }
        let outerwear = ordered.filter { $0.category == .outerwear }
        let extras = ordered.filter { $0.category == .bag || $0.category == .accessory }

        let bases = makeBases(tops: tops, bottoms: bottoms, dresses: dresses)
        guard !bases.isEmpty else { return [] }

        let profiles = makeProfiles(
            shoeCount: shoes.count,
            outerwearCount: outerwear.count,
            extraCount: extras.count
        )

        var results: [OutfitCandidate] = []
        var seenSignatures = Set<String>()
        results.reserveCapacity(min(configuration.maximumEvaluatedCandidates, bases.count * profiles.count))

        for profile in profiles {
            for base in bases {
                var items = base
                if let shoeIndex = profile.shoeIndex { items.append(shoes[shoeIndex]) }
                if let outerwearIndex = profile.outerwearIndex { items.append(outerwear[outerwearIndex]) }
                if let extraIndex = profile.extraIndex { items.append(extras[extraIndex]) }

                let candidate = OutfitCandidate(items: items)
                guard seenSignatures.insert(candidate.signature).inserted else { continue }
                guard OutfitValidator.isValid(candidate.items) else { continue }

                results.append(candidate)
                if results.count >= configuration.maximumEvaluatedCandidates {
                    return results
                }
            }
        }

        return results
    }

    /// Dresses first, then top/bottom pairings interleaved so that one top does
    /// not consume the whole base budget before the next top is reached.
    private func makeBases(
        tops: [GarmentSnapshot],
        bottoms: [GarmentSnapshot],
        dresses: [GarmentSnapshot]
    ) -> [[GarmentSnapshot]] {
        var bases: [[GarmentSnapshot]] = dresses.map { [$0] }

        if !tops.isEmpty && !bottoms.isEmpty {
            for offset in 0..<bottoms.count {
                for (topIndex, top) in tops.enumerated() {
                    let bottomIndex = (topIndex + offset) % bottoms.count
                    bases.append([top, bottoms[bottomIndex]])
                }
            }
        }

        var seen = Set<String>()
        var deduplicated: [[GarmentSnapshot]] = []
        for base in bases {
            let key = OutfitSignature.signature(for: base)
            guard seen.insert(key).inserted else { continue }
            deduplicated.append(base)
            if deduplicated.count >= configuration.maximumBaseCombinations { break }
        }
        return deduplicated
    }

    /// Fixed decoration order: bare base, then shoes, then shoes plus outerwear,
    /// then shoes plus one carried or worn extra.
    private func makeProfiles(shoeCount: Int, outerwearCount: Int, extraCount: Int) -> [DecorationProfile] {
        let shoeLimit = min(configuration.shoeFanout, shoeCount)
        let outerwearLimit = min(configuration.outerwearFanout, outerwearCount)
        let extraLimit = min(configuration.accessoryFanout, extraCount)

        var profiles: [DecorationProfile] = [DecorationProfile()]

        for shoeIndex in 0..<max(shoeLimit, 0) {
            profiles.append(DecorationProfile(shoeIndex: shoeIndex))
        }
        for shoeIndex in 0..<max(shoeLimit, 0) {
            for outerwearIndex in 0..<max(outerwearLimit, 0) {
                profiles.append(DecorationProfile(shoeIndex: shoeIndex, outerwearIndex: outerwearIndex))
            }
        }
        for shoeIndex in 0..<max(shoeLimit, 0) {
            for extraIndex in 0..<max(extraLimit, 0) {
                profiles.append(DecorationProfile(shoeIndex: shoeIndex, extraIndex: extraIndex))
            }
        }
        for shoeIndex in 0..<max(shoeLimit, 0) {
            for outerwearIndex in 0..<max(outerwearLimit, 0) {
                for extraIndex in 0..<max(extraLimit, 0) {
                    profiles.append(
                        DecorationProfile(
                            shoeIndex: shoeIndex,
                            outerwearIndex: outerwearIndex,
                            extraIndex: extraIndex
                        )
                    )
                }
            }
        }
        return profiles
    }
}
