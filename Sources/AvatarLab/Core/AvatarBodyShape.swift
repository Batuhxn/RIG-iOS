import Foundation

/// One body control the user can move. Every control is a signed value in
/// `range`, 0 meaning the neutral figure, and each one drives only its own
/// region's morph targets: changing hips never touches shoulders.
///
/// Labels describe a direction, never a judgement, and no control is in units:
/// the avatar is an approximate silhouette, not a measurement.
enum AvatarControl: String, CaseIterable, Codable, Sendable {
    case shoulders
    case upperBody
    case waist
    case hips
    case legLength
    // Refinements, behind "More".
    case height
    case torsoLength
    case bust
    case underbust
    case stomach
    case seat
    case thighs
    case armLength
    case upperArms
    case overall
    // MakeHuman's two sex macros are in the asset (frame-a / frame-b) but have no
    // control: relabelling them would be misleading (product decision, v0.5).

    /// The five shown first; the rest are optional refinements.
    static let primary: [AvatarControl] = [.shoulders, .upperBody, .waist, .hips, .legLength]
    static var refinements: [AvatarControl] { allCases.filter { !primary.contains($0) } }

    var title: String {
        switch self {
        case .shoulders: return "Shoulders"
        case .upperBody: return "Upper body"
        case .waist: return "Waist"
        case .hips: return "Hips"
        case .legLength: return "Legs"
        case .height: return "Height"
        case .torsoLength: return "Torso length"
        case .bust: return "Chest"
        case .underbust: return "Ribcage"
        case .stomach: return "Tummy"
        case .seat: return "Seat"
        case .thighs: return "Thighs"
        case .armLength: return "Arm length"
        case .upperArms: return "Upper arms"
        case .overall: return "Overall"
        }
    }

    /// Words for the two ends of the slider.
    var endLabels: (low: String, high: String) {
        switch self {
        case .shoulders, .waist, .hips, .underbust, .upperBody: return ("Narrower", "Wider")
        case .legLength, .torsoLength, .armLength: return ("Shorter", "Longer")
        case .height: return ("Shorter", "Taller")
        case .bust, .stomach, .seat, .thighs, .upperArms: return ("Less", "More")
        case .overall: return ("Slimmer", "Fuller")
        }
    }

    /// Allowed values. Asymmetric where a target's extreme leaves the realistic
    /// range (MakeHuman's full height target reaches 2.4 m).
    var range: ClosedRange<Float> {
        switch self {
        case .height: return -0.6...0.35
        case .legLength, .torsoLength, .armLength: return -0.6...0.6
        default: return -1...1
        }
    }

    /// Morph targets this control blends: (target, weight per unit) for each side.
    var targets: (negative: [(String, Float)], positive: [(String, Float)]) {
        func pair(_ base: String, _ weight: Float = 1) -> ([(String, Float)], [(String, Float)]) {
            ([("\(base)-decr", weight)], [("\(base)-incr", weight)])
        }
        switch self {
        case .shoulders: return pair("shoulders")
        // "Upper body" widens the ribcage and chest together; both remain separately refinable.
        case .upperBody: return ([("underbust-decr", 1), ("bust-decr", 0.5)], [("underbust-incr", 1), ("bust-incr", 0.5)])
        case .waist: return pair("waist")
        case .hips: return pair("hips")
        case .legLength: return pair("leglength")
        case .height: return pair("height")
        case .torsoLength: return pair("torsolength")
        case .bust: return pair("bust")
        case .underbust: return pair("underbust")
        case .stomach: return pair("stomach")
        case .seat: return pair("seat")
        case .thighs: return pair("thighs")
        case .armLength: return pair("armlength")
        case .upperArms: return pair("upperarms")
        case .overall: return pair("fullness")
        }
    }
}

/// The user's avatar body: one value per control. Versioned and sanitised, so a
/// stored profile from an older or newer build, or a corrupted file, always
/// decodes to something safe to render.
struct AvatarBodyShape: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = AvatarBodyShape.currentSchemaVersion
    private(set) var values: [AvatarControl: Float] = [:]

    static let neutral = AvatarBodyShape()

    init(values: [AvatarControl: Float] = [:]) {
        for (control, value) in values { self[control] = value }
    }

    subscript(control: AvatarControl) -> Float {
        get { values[control] ?? 0 }
        set {
            let clean = newValue.isFinite ? min(max(newValue, control.range.lowerBound), control.range.upperBound) : 0
            values[control] = clean == 0 ? nil : clean
        }
    }

    /// Target weights for the morph engine.
    var targetWeights: [String: Float] {
        var weights: [String: Float] = [:]
        for (control, value) in values where value != 0 {
            let side = value < 0 ? control.targets.negative : control.targets.positive
            for (name, perUnit) in side {
                weights[name, default: 0] += abs(value) * perUnit
            }
        }
        return weights
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, values }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = AvatarBodyShape.currentSchemaVersion
        // Unknown control names (a newer build) and bad numbers are dropped, not fatal.
        let raw = (try? container.decode([String: Float].self, forKey: .values)) ?? [:]
        for (key, value) in raw {
            if let control = AvatarControl(rawValue: key) { self[control] = value }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) }), forKey: .values)
    }
}

/// Neutral starting points for onboarding. Not types of people and not named:
/// "Silhouette 1 / 2 / 3", shown as pictures, all equally editable.
struct AvatarStartingSilhouette: Identifiable, Sendable {
    let id: String
    let title: String
    let shape: AvatarBodyShape

    static let all: [AvatarStartingSilhouette] = [
        AvatarStartingSilhouette(id: "silhouette-1", title: "Silhouette 1", shape: .neutral),
        AvatarStartingSilhouette(id: "silhouette-2", title: "Silhouette 2", shape: AvatarBodyShape(values: [
            .waist: -0.4, .hips: 0.5, .seat: 0.4, .bust: 0.3, .shoulders: -0.2, .thighs: 0.3,
        ])),
        AvatarStartingSilhouette(id: "silhouette-3", title: "Silhouette 3", shape: AvatarBodyShape(values: [
            .shoulders: 0.5, .upperBody: 0.4, .waist: 0.2, .hips: -0.3, .bust: -0.6, .seat: -0.3,
        ])),
    ]
}
