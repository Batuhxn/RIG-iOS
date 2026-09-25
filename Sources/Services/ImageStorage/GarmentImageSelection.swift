import Foundation

/// Review choice. An unavailable cutout always resolves to the original photo.
enum GarmentImageChoice: Hashable, Sendable {
    case cutout
    case original

    static func initial(for result: GarmentImportResult) -> Self {
        result.isBackgroundRemoved && result.cutoutRelativePath != nil ? .cutout : .original
    }

    func resolved(for result: GarmentImportResult) -> Self {
        self == .cutout && Self.initial(for: result) == .original ? .original : self
    }

    func relativePath(in result: GarmentImportResult) -> String {
        switch resolved(for: result) {
        case .cutout: return result.cutoutRelativePath ?? result.originalRelativePath
        case .original: return result.originalRelativePath
        }
    }

    /// Finalize the one thumbnail before creating the model row. Original and
    /// cutout source files remain available under the garment's directory.
    func presentation(for result: GarmentImportResult, in store: GarmentImageStore) throws -> GarmentImagePresentation {
        let selected = resolved(for: result)
        var thumbnailPath = result.thumbnailRelativePath
        if selected == .original && result.cutoutRelativePath != nil {
            guard let source = store.data(atRelativePath: result.originalRelativePath),
                  let thumbnail = GarmentImageProcessing.pngData(
                      from: source,
                      maxDimension: GarmentImageProcessing.thumbnailMaxDimension
                  ) else {
                throw GarmentImageSelectionError.originalUnavailable
            }
            thumbnailPath = try store.write(thumbnail, for: result.garmentID, kind: .thumbnail)
        }
        return GarmentImagePresentation(
            thumbnailRelativePath: thumbnailPath,
            usesCutout: selected == .cutout
        )
    }
}

struct GarmentImagePresentation: Hashable, Sendable {
    let thumbnailRelativePath: String?
    let usesCutout: Bool
}

enum GarmentImageSelectionError: Error {
    case originalUnavailable
}

/// Bulk review keeps each photo's selection independent of its neighbours.
struct GarmentImageChoices {
    private var choices: [UUID: GarmentImageChoice] = [:]

    init() {}

    func choice(for result: GarmentImportResult) -> GarmentImageChoice {
        choices[result.garmentID] ?? .initial(for: result)
    }

    mutating func select(_ choice: GarmentImageChoice, for result: GarmentImportResult) {
        choices[result.garmentID] = choice.resolved(for: result)
    }

    mutating func remove(for id: UUID) {
        choices[id] = nil
    }
}
