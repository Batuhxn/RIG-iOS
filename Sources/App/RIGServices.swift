import Foundation
import SwiftUI

/// The few genuinely external things the interface needs.
///
/// This is dependency injection in the plain sense: one immutable value carried
/// through the environment. No container, no framework, no registration.
struct RIGServices: Sendable {
    let imageStore: GarmentImageStore
    let backgroundRemover: any GarmentBackgroundRemoving
    let engine: OutfitEngine
    let similarityMatcher: any GarmentSimilarityMatching
    /// Manual-city forecast. The only networked service; see OpenMeteoWeatherService.
    let weather: WeatherRepository

    var importService: GarmentImportService {
        GarmentImportService(store: imageStore, backgroundRemover: backgroundRemover)
    }

    /// Production wiring. Note the compatibility provider: v0.1 passes none, so
    /// the engine runs on rules alone.
    static func live() throws -> RIGServices {
        RIGServices(
            imageStore: try GarmentImageStore.applicationSupport(),
            backgroundRemover: VisionBackgroundRemover(),
            engine: OutfitEngine(configuration: .default, compatibilityProvider: nil),
            similarityMatcher: VisionFeaturePrintSimilarityMatcher(),
            weather: WeatherRepository(
                provider: OpenMeteoWeatherService(),
                cache: WeatherCache(storage: UserDefaultsWeatherStorage())
            )
        )
    }

    /// Previews and tests. Writes into a throwaway temporary directory and never
    /// touches the user's storage.
    static func preview() -> RIGServices {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "RIGPreview", directoryHint: .isDirectory)
        return RIGServices(
            imageStore: GarmentImageStore(baseDirectory: directory),
            backgroundRemover: PassthroughBackgroundRemover(),
            engine: OutfitEngine(),
            similarityMatcher: PassthroughSimilarityMatcher(),
            weather: WeatherRepository(
                provider: PreviewWeatherProvider(),
                cache: WeatherCache(storage: InMemoryWeatherStorage())
            )
        )
    }
}

private struct RIGServicesKey: EnvironmentKey {
    static let defaultValue: RIGServices = .preview()
}

extension EnvironmentValues {
    var rigServices: RIGServices {
        get { self[RIGServicesKey.self] }
        set { self[RIGServicesKey.self] = newValue }
    }
}
