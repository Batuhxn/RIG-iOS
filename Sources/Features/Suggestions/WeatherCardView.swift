import SwiftUI

/// The forecast that suggestions are ranked against, and where it came from.
///
/// Every state is spelled out: no city yet, loading, current, stale with its
/// age, or unavailable. Old numbers are never shown as if they were current,
/// and the card never claims an outfit will keep anyone warm or dry.
struct WeatherCardView: View {
    let state: WeatherState
    let selectedCity: WeatherCity?
    let isRefreshing: Bool
    let onSelect: (WeatherCity) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.m) {
            header
            content
            if state.report != nil {
                attribution
            }
        }
        .padding(RIGTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RIGTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.card, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Weather")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            cityMenu
        }
    }

    private var cityMenu: some View {
        Menu {
            ForEach(WeatherCity.presets) { city in
                Button {
                    onSelect(city)
                } label: {
                    if city == selectedCity {
                        Label(city.name, systemImage: "checkmark")
                    } else {
                        Text(city.name)
                    }
                }
            }
        } label: {
            HStack(spacing: RIGTheme.Spacing.xs) {
                Text(selectedCity?.name ?? "Choose city")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 44)
        }
        .accessibilityLabel(selectedCity.map { "City, \($0.name)" } ?? "Choose a city for the forecast")
        .accessibilityHint("Suggestions are ranked for this city's weather")
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        switch state {
        case .noCity:
            Text("Pick a city to rank looks for today's weather. RIG uses no location access; only the chosen city's coordinates are sent to Open-Meteo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .loading(let city):
            HStack(spacing: RIGTheme.Spacing.s) {
                ProgressView()
                Text("Loading the forecast for \(city.name)…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)

        case .ready(let report, let age):
            forecast(report)
            freshnessLine(report, isStale: age == .stale, failure: nil)

        case .staleAfterFailure(let report, let failure):
            forecast(report)
            freshnessLine(report, isStale: true, failure: failure)

        case .unavailable(let city, let failure):
            VStack(alignment: .leading, spacing: RIGTheme.Spacing.s) {
                Label(unavailableMessage(city, failure), systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Looks below are ranked without weather.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                retryButton
            }
        }
    }

    private func forecast(_ report: WeatherReport) -> some View {
        VStack(alignment: .leading, spacing: RIGTheme.Spacing.s) {
            HStack(alignment: .center, spacing: RIGTheme.Spacing.m) {
                Image(systemName: report.condition.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(.largeTitle, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Feels like \(WeatherOutfitNote.formattedTemperature(report.apparentTemperatureC))")
                        .font(.system(.title2, design: .serif))
                    Text("\(report.condition.label) · Air \(WeatherOutfitNote.formattedTemperature(report.airTemperatureC))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            // Equal-height tiles: the rain caption wraps to two lines while the
            // wind caption does not (seen in the Gate A2 simulator screenshot).
            HStack(alignment: .top, spacing: RIGTheme.Spacing.s) {
                metric(
                    symbol: "umbrella",
                    value: "\(report.precipitationProbability)%",
                    caption: "Highest hourly rain chance, next \(report.rainHoursCovered) h"
                )
                metric(
                    symbol: "wind",
                    value: "\(Int(report.windSpeedKPH.rounded())) km/h",
                    caption: "Wind"
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metric(symbol: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(value, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(RIGTheme.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RIGTheme.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(value)")
    }

    private func freshnessLine(_ report: WeatherReport, isStale: Bool, failure: WeatherFailure?) -> some View {
        HStack(spacing: RIGTheme.Spacing.s) {
            if isStale {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            Text(freshnessText(report, isStale: isStale, failure: failure))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else if isStale {
                retryButton
            }
        }
    }

    private var retryButton: some View {
        Button("Retry", action: onRefresh)
            .font(.caption.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .disabled(isRefreshing)
    }

    private var attribution: some View {
        Group {
            if let url = OpenMeteoWeatherService.attributionURL {
                Link("Weather data by Open-Meteo.com", destination: url)
            } else {
                Text("Weather data by Open-Meteo.com")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(minHeight: 44, alignment: .leading)
    }

    // MARK: - Copy

    private func freshnessText(_ report: WeatherReport, isStale: Bool, failure: WeatherFailure?) -> String {
        let age = Self.relativeAge(since: report.fetchedAt)
        guard isStale else { return "Updated \(age)" }
        switch failure {
        case .offline: return "Offline. Showing the forecast from \(age)."
        case .unusableResponse: return "Couldn't refresh. Showing the forecast from \(age)."
        case nil: return "Forecast from \(age), may be out of date."
        }
    }

    private func unavailableMessage(_ city: WeatherCity, _ failure: WeatherFailure) -> String {
        switch failure {
        case .offline: return "No connection, so there is no forecast for \(city.name)."
        case .unusableResponse: return "The forecast for \(city.name) couldn't be read."
        }
    }

    private static func relativeAge(since date: Date) -> String {
        WeatherFreshness.age(of: date, now: Date()) { fetchedAt, now in
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: fetchedAt, relativeTo: now)
        }
    }
}

/// Every card state side by side. A struct rather than statements inside the
/// preview closure, so the preview is a single expression in any Xcode.
private struct WeatherCardPreviewGallery: View {
    let city = WeatherCity.presets[0]
    let report = WeatherReport(
        city: WeatherCity.presets[0], observedLocalTime: "2026-10-19T08:00", observedAt: Date(),
        airTemperatureC: 11, apparentTemperatureC: 9, precipitationProbability: 65, rainHoursCovered: 6,
        windSpeedKPH: 14, weatherCode: 80, fetchedAt: Date().addingTimeInterval(-600)
    )

    var body: some View {
        ScrollView {
            VStack(spacing: RIGTheme.Spacing.m) {
                card(.noCity, hasCity: false)
                card(.loading(city), refreshing: true)
                card(.ready(report, .fresh))
                card(.ready(report, .stale), refreshing: true)
                card(.staleAfterFailure(report, .offline))
                card(.unavailable(city, .offline))
            }
            .padding()
        }
        .background(RIGTheme.pageBackground)
    }

    private func card(_ state: WeatherState, hasCity: Bool = true, refreshing: Bool = false) -> some View {
        WeatherCardView(
            state: state,
            selectedCity: hasCity ? city : nil,
            isRefreshing: refreshing,
            onSelect: { _ in },
            onRefresh: {}
        )
    }
}

#Preview("States") {
    WeatherCardPreviewGallery()
}
