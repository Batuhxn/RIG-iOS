import XCTest
@testable import RIG

final class ColorHarmonyTests: XCTestCase {
    private let accuracy = 1e-9

    func testEveryPairStaysInRange() {
        for lhs in ColorFamily.allCases {
            for rhs in ColorFamily.allCases {
                let score = ColorHarmony.pairScore(lhs, rhs)
                XCTAssertGreaterThanOrEqual(score, 0, "\(lhs)/\(rhs)")
                XCTAssertLessThanOrEqual(score, 1, "\(lhs)/\(rhs)")
            }
        }
    }

    func testPairScoreIsSymmetric() {
        for lhs in ColorFamily.allCases {
            for rhs in ColorFamily.allCases {
                XCTAssertEqual(
                    ColorHarmony.pairScore(lhs, rhs),
                    ColorHarmony.pairScore(rhs, lhs),
                    accuracy: accuracy,
                    "\(lhs)/\(rhs)"
                )
            }
        }
    }

    func testNeutralsCombineBroadly() {
        XCTAssertEqual(ColorHarmony.pairScore(.black, .white), ColorHarmony.bothNeutralScore, accuracy: accuracy)
        XCTAssertEqual(ColorHarmony.pairScore(.navy, .beige), ColorHarmony.bothNeutralScore, accuracy: accuracy)
        XCTAssertEqual(
            ColorHarmony.score(for: [.black, .white, .gray]),
            ColorHarmony.bothNeutralScore,
            accuracy: accuracy
        )
    }

    func testMonochromaticCombines() {
        XCTAssertEqual(ColorHarmony.pairScore(.blue, .blue), ColorHarmony.sameFamilyScore, accuracy: accuracy)
        XCTAssertEqual(
            ColorHarmony.score(for: [.blue, .blue, .blue]),
            ColorHarmony.sameFamilyScore,
            accuracy: accuracy
        )
    }

    func testNeutralAnchorsAnAccent() {
        XCTAssertEqual(ColorHarmony.pairScore(.black, .red), ColorHarmony.neutralWithAccentScore, accuracy: accuracy)
        XCTAssertEqual(ColorHarmony.pairScore(.beige, .green), ColorHarmony.neutralWithAccentScore, accuracy: accuracy)
    }

    func testAnalogousAccentsScoreAboveDistantOnes() {
        let analogous = ColorHarmony.pairScore(.red, .burgundy)
        let clashing = ColorHarmony.pairScore(.red, .green)
        XCTAssertEqual(analogous, ColorHarmony.analogousScore, accuracy: accuracy)
        XCTAssertGreaterThan(analogous, clashing)
    }

    func testComplementaryScoresAboveTheAwkwardMiddle() {
        // Blue against orange is roughly opposite; blue against green is the
        // middle distance the rules deliberately penalise.
        XCTAssertGreaterThan(
            ColorHarmony.pairScore(.blue, .orange),
            ColorHarmony.pairScore(.red, .green)
        )
    }

    func testTwoVividAccentsTakeAnExtraPenalty() {
        // Olive is muted, so the vivid multiplier must not apply to it.
        XCTAssertEqual(ColorHarmony.pairScore(.olive, .green), ColorHarmony.relatedScore, accuracy: accuracy)
        XCTAssertLessThan(
            ColorHarmony.pairScore(.yellow, .green),
            ColorHarmony.pairScore(.olive, .green)
        )
    }

    func testObviouslyClashingOutfitScoresBelowANeutralOne() {
        let clashing = ColorHarmony.score(for: [.red, .green, .orange])
        let neutral = ColorHarmony.score(for: [.black, .white, .gray])
        XCTAssertLessThan(clashing, neutral)
        XCTAssertLessThan(clashing, 0.60)
    }

    func testBusyPaletteIsDampedFurther() {
        let fourAccents = ColorHarmony.score(for: [.red, .green, .blue, .yellow])
        let threeAccents = ColorHarmony.score(for: [.red, .green, .orange])
        XCTAssertLessThan(fourAccents, threeAccents)
        XCTAssertLessThan(fourAccents, 0.40)
    }

    func testMulticolorIsNeverConfident() {
        for family in ColorFamily.allCases {
            XCTAssertEqual(
                ColorHarmony.pairScore(.multicolor, family),
                ColorHarmony.unclassifiedScore,
                accuracy: accuracy,
                "multicolor/\(family)"
            )
        }
        let score = ColorHarmony.score(for: [.multicolor, .black, .white])
        XCTAssertGreaterThan(score, 0.35)
        XCTAssertLessThan(score, 0.85)
    }

    func testSingleColorHasNoOpinion() {
        XCTAssertEqual(ColorHarmony.score(for: [.red]), ColorHarmony.insufficientDataScore, accuracy: accuracy)
        XCTAssertEqual(ColorHarmony.score(for: []), ColorHarmony.insufficientDataScore, accuracy: accuracy)
    }

    func testCircularDistanceWrapsAround() {
        XCTAssertEqual(ColorHarmony.circularDistanceDegrees(0, 350), 10, accuracy: accuracy)
        XCTAssertEqual(ColorHarmony.circularDistanceDegrees(350, 0), 10, accuracy: accuracy)
        XCTAssertEqual(ColorHarmony.circularDistanceDegrees(0, 180), 180, accuracy: accuracy)
    }
}
