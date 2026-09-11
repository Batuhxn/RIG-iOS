import SwiftUI
import UIKit

/// Small main-actor cache so scrolling the wardrobe does not re-read and
/// re-decode the same thumbnails. Bounded by NSCache's own eviction.
@MainActor
final class GarmentImageCache {
    static let shared = GarmentImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 240
    }

    func image(forRelativePath path: String) -> UIImage? {
        cache.object(forKey: path as NSString)
    }

    func insert(_ image: UIImage, forRelativePath path: String) {
        cache.setObject(image, forKey: path as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Draws a garment from disk.
///
/// A missing file is a placeholder, never a crash and never a deleted row. Image
/// files and database rows can drift apart — a restore, an interrupted write —
/// and the wardrobe has to stay usable when they do.
struct GarmentImageView: View {
    let relativePath: String?
    var symbolName: String = "photo"
    var contentMode: ContentMode = .fit

    @Environment(\.rigServices) private var services
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityHidden(true)
            } else if isLoading {
                // The design's loading state, applied where RIG actually has
                // one. SwiftData queries are synchronous, so there is no
                // full-screen load to skeleton; reading an image off disk is
                // the only wait the user can see.
                RIGSkeleton(cornerRadius: RIGTheme.Radius.medium)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(RIGTheme.text(30))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: relativePath) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let relativePath else {
            image = nil
            isLoading = false
            return
        }
        if let cached = GarmentImageCache.shared.image(forRelativePath: relativePath) {
            image = cached
            isLoading = false
            return
        }

        isLoading = true
        let store = services.imageStore
        let data = await Task.detached(priority: .userInitiated) {
            store.data(atRelativePath: relativePath)
        }.value

        guard let data, let decoded = UIImage(data: data) else {
            image = nil
            isLoading = false
            return
        }
        GarmentImageCache.shared.insert(decoded, forRelativePath: relativePath)
        image = decoded
        isLoading = false
    }
}
