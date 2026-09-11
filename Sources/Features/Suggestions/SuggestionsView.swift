import SwiftData
import SwiftUI

struct SuggestionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rigServices) private var services

    @Query private var items: [ClothingItem]
    @Query private var feedback: [OutfitFeedback]
    @Query private var savedOutfits: [SavedOutfit]

    @State private var model = SuggestionsModel()

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
                if let errorMessage = model.errorMessage {
                    RIGErrorBanner(message: errorMessage) {
                        model.errorMessage = nil
                    }
                }

                if model.isLoading && model.suggestions.isEmpty {
                    ProgressView("Kombinler kuruluyor…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, RIGTheme.Spacing.xl)
                } else if !model.readiness.canSuggest {
                    RIGEmptyState(
                        symbol: "square.grid.2x2",
                        title: "Henüz yeterli parça yok",
                        message: model.readiness.explanation
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, RIGTheme.Spacing.xl)
                } else if model.suggestions.isEmpty {
                    RIGEmptyState(
                        symbol: "sparkles",
                        title: "Gösterilecek kombin yok",
                        message: "RIG could not assemble a valid look from this wardrobe. Adding shoes or a second bottom usually helps."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, RIGTheme.Spacing.xl)
                } else {
                    if model.hasWrappedAround {
                        Text("Bu dolabın kurabileceği her şeyi gördün. Baştan başlıyoruz.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(model.suggestions) { suggestion in
                        OutfitCardView(
                            suggestion: suggestion,
                            garments: garmentsByID,
                            recordedRating: ratingsBySignature[suggestion.signature],
                            isSaved: savedSignatures.contains(suggestion.signature),
                            onSave: { save(suggestion) },
                            onRate: { rate(suggestion, $0) }
                        )
                    }

                    Button("Başka bir set göster") {
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
        .navigationTitle("Öneriler")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await generate(startOver: true)
        }
    }

    @MainActor
    private func generate(startOver: Bool) async {
        await model.generate(
            wardrobe: items.map(\.snapshot),
            engine: services.engine,
            startOver: startOver
        )
    }

    private func save(_ suggestion: OutfitSuggestion) {
        let garments = suggestion.items.compactMap { garmentsByID[$0.id] }
        guard garments.count == suggestion.items.count else {
            model.errorMessage = "O parçalardan biri artık dolabında değil."
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
            model.errorMessage = "Bu kombin cihaza kaydedilemedi."
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
            model.errorMessage = "Bu tepki kaydedilemedi."
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
