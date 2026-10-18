import SwiftData
import SwiftUI

struct SuggestionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rigServices) private var services

    @Query private var items: [ClothingItem]
    @Query private var feedback: [OutfitFeedback]
    @Query private var savedOutfits: [SavedOutfit]

    @State private var model = SuggestionsModel()
    @State private var weather = WeatherModel()

    private var garmentsByID: [UUID: ClothingItem] {
        // Not `uniqueKeysWithValues`: that traps on a duplicate key, and a
        // corrupt store must not be able to crash a screen.
        items.reduce(into: [:]) { result, item in result[item.id] = item }
    }

    private var ratingsBySignature: [String: OutfitRating] {
        var result: [String: OutfitRating] = [:]
        for entry in feedback.sorted(by: { $0.createdAt < $1.createdAt }) {
            if let rating = entry.rating {
                result[entry.outfitSignature] = rating
            }
        }
        return result
    }

    private var savedSignatures: Set<String> {
        Set(savedOutfits.map(\.signature))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RIGTheme.Spacing.l) {
                WeatherCardView(
                    state: weather.state,
                    selectedCity: weather.selectedCity,
                    isRefreshing: weather.isRefreshing,
                    onSelect: { city in
                        Task { await weather.select(city, using: services.weather) }
                    },
                    onRefresh: {
                        Task { await weather.refresh(using: services.weather) }
                    }
                )

                if let errorMessage = model.errorMessage {
                    RIGErrorBanner(message: errorMessage) {
                        model.errorMessage = nil
                    }
                }

                if model.isLoading && model.suggestions.isEmpty {
                    ProgressView("Building looks…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, RIGTheme.Spacing.xl)
                } else if !model.readiness.canSuggest {
                    RIGEmptyState(
                        symbol: "square.grid.2x2",
                        title: "Not enough to work with yet",
                        message: model.emptyResultMessage
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, RIGTheme.Spacing.xl)
                } else if model.suggestions.isEmpty {
                    RIGEmptyState(
                        symbol: "sparkles",
                        title: "No looks to show",
                        message: model.emptyResultMessage
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, RIGTheme.Spacing.xl)
                } else {
                    if model.hasWrappedAround {
                        Text("You have seen everything this wardrobe can make. Starting again from the top.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text(OutfitRating.recordingExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(model.suggestions) { suggestion in
                        OutfitCardView(
                            suggestion: suggestion,
                            garments: garmentsByID,
                            recordedRating: ratingsBySignature[suggestion.signature],
                            isSaved: savedSignatures.contains(suggestion.signature),
                            onSave: { save(suggestion) },
                            onRate: { rate(suggestion, $0) },
                            weatherNotes: weatherNotes(for: suggestion)
                        )
                    }

                    Button("Show another set") {
                        Task { await generate(startOver: false) }
                    }
                    .buttonStyle(RIGSecondaryButtonStyle())
                    .disabled(model.isLoading)
                }
            }
            .padding(.horizontal, RIGTheme.Spacing.m)
            .padding(.bottom, RIGTheme.Spacing.xl)
        }
        .background(RIGTheme.pageBackground)
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await generate(startOver: true)
        }
        .task {
            await weather.start(using: services.weather)
        }
        // A new or refreshed forecast re-ranks from the top; losing the forecast
        // falls back to the ordinary ranking rather than keeping stale order.
        .onChange(of: weather.rankingContext) {
            Task { await generate(startOver: true) }
        }
    }

    @MainActor
    private func generate(startOver: Bool) async {
        await model.generate(
            wardrobe: items.map(\.snapshot),
            engine: services.engine,
            startOver: startOver,
            weather: weather.rankingContext
        )
    }

    private func weatherNotes(for suggestion: OutfitSuggestion) -> [String] {
        guard let context = weather.rankingContext, let report = weather.state.report else { return [] }
        return WeatherOutfitNote.notes(for: suggestion.items, weather: context, rainHours: report.rainHoursCovered)
    }

    private func save(_ suggestion: OutfitSuggestion) {
        let garments = suggestion.items.compactMap { garmentsByID[$0.id] }
        guard garments.count == suggestion.items.count else {
            model.errorMessage = "One of those garments is no longer in your wardrobe."
            return
        }

        let outfit = SavedOutfit(
            name: SavedOutfit.defaultName(for: Date()),
            source: .suggestion,
            items: garments
        )
        modelContext.insert(outfit)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(outfit)
            model.errorMessage = "That look could not be saved to this device."
        }
    }

    /// Feedback is an upsert: changing your mind replaces the old opinion rather
    /// than stacking a contradictory one next to it.
    private func rate(_ suggestion: OutfitSuggestion, _ rating: OutfitRating) {
        let signature = suggestion.signature
        for existing in feedback where existing.outfitSignature == signature {
            modelContext.delete(existing)
        }
        modelContext.insert(OutfitFeedback(outfitSignature: signature, rating: rating))
        do {
            try modelContext.save()
        } catch {
            model.errorMessage = "That reaction could not be saved."
        }
    }
}

#Preview {
    NavigationStack {
        SuggestionsView()
    }
    .modelContainer(PreviewData.container())
    .environment(\.rigServices, .preview())
}
