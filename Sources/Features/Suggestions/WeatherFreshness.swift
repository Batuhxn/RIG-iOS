import Foundation

/// How old a forecast is, in words, for the card's freshness line.
///
/// Found in a real simulator screenshot: a forecast stored a few milliseconds
/// "after" the render time read "Updated in 0 seconds". Anything under a
/// minute, or apparently in the future (clock skew), is "just now"; older
/// readings use the platform's relative formatter, injected so this stays
/// testable without it.
enum WeatherFreshness {
    static let justNowThreshold: TimeInterval = 60

    static func age(
        of fetchedAt: Date,
        now: Date,
        relative: (Date, Date) -> String
    ) -> String {
        let elapsed = now.timeIntervalSince(fetchedAt)
        guard elapsed >= justNowThreshold else { return "just now" }
        return relative(fetchedAt, now)
    }
}
