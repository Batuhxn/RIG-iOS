import SwiftUI

/// One line on the home screen: the cached forecast for the saved city.
///
/// Read-only and offline: it shows only what the Suggestions screen already
/// fetched, so opening RIG makes no request. With no city or no recent
/// forecast it renders nothing at all.
struct WeatherGlanceView: View {
    let report: WeatherReport
    let isStale: Bool

    var body: some View {
        HStack(spacing: RIGTheme.Spacing.s) {
            Image(systemName: report.condition.symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(report.city.name) · Feels like \(WeatherOutfitNote.formattedTemperature(report.apparentTemperatureC))")
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(RIGTheme.Spacing.m)
        .frame(minHeight: 44)
        .background(RIGTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.tile, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens looks ranked for this weather")
    }

    private var detail: String {
        let rain = "Highest hourly rain \(report.precipitationProbability)%, next \(report.rainHoursCovered) h"
        return isStale ? "\(rain) · may be out of date" : rain
    }
}
