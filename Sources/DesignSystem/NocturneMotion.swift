import SwiftUI

/// Every animation in the design, in one place.
///
/// The prototype expresses motion as CSS transitions scattered across the
/// markup — `.34s cubic-bezier(.22,.61,.36,1)` on a screen change, `.42s` on a
/// sheet, `.2s` on a chip. Transcribing those numbers into each view would
/// spread the same four curves across a dozen files and make a retune a
/// find-and-replace. They live here instead, named for what they animate.
///
/// `cubic-bezier(.22,.61,.36,1)` is the design's standard ease-out and appears
/// on screen changes, sheets, the crop frame and the before/after cutout.
enum NocturneMotion {
    /// The design's standard ease-out curve, at an arbitrary duration.
    static func standard(_ duration: Double) -> Animation {
        .timingCurve(0.22, 0.61, 0.36, 1, duration: duration)
    }

    /// Screen-to-screen change. The prototype fades over .34s and moves over
    /// .38s; SwiftUI drives both from one animation, so the longer wins.
    static let screen = standard(0.38)

    /// A bottom sheet arriving or leaving.
    static let sheet = standard(0.42)

    /// Chips, pills, segmented controls, selection badges.
    static let control: Animation = .easeInOut(duration: 0.22)

    /// Content arriving in a list or grid ("rise": fade up over 10px).
    static let rise = standard(0.4)

    /// Per-item stagger for a rising list. The prototype uses 40-60ms.
    static let riseStagger: Double = 0.045

    /// The success check, which overshoots.
    static let pop: Animation = .spring(response: 0.5, dampingFraction: 0.62)

    /// The processing ring and its sweep, which track a numeric progress value
    /// and must not overshoot it.
    static let progress: Animation = .linear(duration: 0.16)

    /// The crop frame moving between aspect ratios.
    static let cropFrame = standard(0.35)

    /// The before/after cutout comparison.
    static let cutout = standard(0.45)

    /// One turn of an indeterminate spinner.
    static let spinPeriod: Double = 0.9

    /// One pass of a skeleton shimmer.
    static let shimmerPeriod: Double = 1.4

    /// One breath of the processing glow.
    static let glowPeriod: Double = 2.2
}
