import SwiftData
import XCTest
@testable import RIG

@MainActor
final class SuggestionsModelTests: XCTestCase {
    func testTopOnlyMessageAsksForBottomOrDress() async {
        let model = SuggestionsModel()
        await model.generate(wardrobe: [Fixture.garment(1, .top)], engine: OutfitEngine())
        XCTAssertFalse(model.readiness.canSuggest)
        XCTAssertTrue(model.suggestions.isEmpty)
        XCTAssertEqual(model.emptyResultMessage, "Add a bottom — or a dress — and RIG can start building looks.")
    }

    func testBottomOnlyMessageAsksForTopOrDress() async {
        let model = SuggestionsModel()
        await model.generate(wardrobe: [Fixture.garment(1, .bottom)], engine: OutfitEngine())
        XCTAssertEqual(model.emptyResultMessage, "Add a top — or a dress — and RIG can start building looks.")
    }

    func testAccessoryOnlyMessageExplainsTheMissingBase() async {
        let model = SuggestionsModel()
        await model.generate(wardrobe: [Fixture.garment(1, .accessory)], engine: OutfitEngine())
        XCTAssertFalse(model.readiness.canSuggest)
        XCTAssertEqual(model.emptyResultMessage, "Add a top and a bottom — or a dress — and RIG can start building looks.")
    }

    func testReadyWardrobeWithNoResultsDoesNotInventMissingCategories() async {
        let model = SuggestionsModel()
        var configuration = OutfitEngineConfiguration.default
        configuration.maximumEvaluatedCandidates = 0
        await model.generate(
            wardrobe: [Fixture.garment(1, .top), Fixture.garment(2, .bottom)],
            engine: OutfitEngine(configuration: configuration)
        )
        XCTAssertTrue(model.readiness.canSuggest)
        XCTAssertTrue(model.suggestions.isEmpty)
        XCTAssertEqual(
            model.emptyResultMessage,
            "No looks are available right now. Try again after reviewing your wardrobe."
        )
    }

    func testReadySmallWardrobeProducesSuggestions() async {
        let model = SuggestionsModel()
        await model.generate(
            wardrobe: [Fixture.garment(1, .top), Fixture.garment(2, .bottom), Fixture.garment(3, .outerwear)],
            engine: OutfitEngine()
        )
        XCTAssertTrue(model.readiness.canSuggest)
        XCTAssertEqual(model.suggestions.count, 2)
        XCTAssertFalse(model.isLoading)
    }

    func testAnotherSetWrapsHonestlyWhenSmallWardrobeIsExhausted() async {
        let model = SuggestionsModel()
        let wardrobe = [Fixture.garment(1, .dress)]
        await model.generate(wardrobe: wardrobe, engine: OutfitEngine())
        let first = model.suggestions
        await model.generate(wardrobe: wardrobe, engine: OutfitEngine())
        XCTAssertTrue(model.hasWrappedAround)
        XCTAssertEqual(model.suggestions, first)
    }

    func testSavedFeedbackDoesNotChangeSuggestionRanking() async throws {
        let container = try RIGModelContainer.makeInMemoryContainer()
        let context = ModelContext(container)
        let model = SuggestionsModel()
        let wardrobe = Fixture.smallWardrobe()
        await model.generate(wardrobe: wardrobe, engine: OutfitEngine(), startOver: true)
        let before = model.suggestions
        for (index, suggestion) in before.enumerated() {
            context.insert(OutfitFeedback(
                outfitSignature: suggestion.signature,
                rating: index == 0 ? .disliked : .liked
            ))
        }
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<OutfitFeedback>()), before.count)
        await model.generate(wardrobe: wardrobe, engine: OutfitEngine(), startOver: true)
        XCTAssertEqual(model.suggestions, before)
    }

    func testFeedbackCopyDescribesRecordingWithoutLearning() {
        XCTAssertEqual(
            OutfitRating.recordingExplanation,
            "Likes and dislikes are saved on this device. They do not change your suggestions."
        )
        XCTAssertEqual(OutfitRating.liked.recordingActionLabel, "Save a like for this look")
        XCTAssertEqual(OutfitRating.disliked.recordingActionLabel, "Save a dislike for this look")
    }
}
