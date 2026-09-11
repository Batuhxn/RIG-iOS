import SwiftUI
import UIKit

/// Drag a rectangle over the photograph. That is the whole of v0.3 cropping.
///
/// Deliberately plain. A rectangle a finger can move and resize is predictable
/// on a portrait mirror photo, needs no third-party dependency, and leaves the
/// source image untouched — the rectangle is only ever fractions, and the cut
/// is taken later from the full-resolution bytes.
struct GarmentCropView: View {
    let image: UIImage
    @Binding var region: NormalizedCropRect

    /// The rectangle as it was when the current drag began. Drag translations
    /// are cumulative from the start of the gesture, so applying them to live
    /// state instead would compound and run away.
    @State private var dragOrigin: NormalizedCropRect?

    private let handleSize: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let fitted = Self.fittedSize(for: image.size, in: proxy.size)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .accessibilityHidden(true)
                overlay(in: fitted)
                    .frame(width: fitted.width, height: fitted.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crop area")
    }

    /// Aspect-fit, so the whole photograph is visible and no part of a garment
    /// can be hiding outside the frame.
    static func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return container }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    // MARK: - Overlay

    private func overlay(in fitted: CGSize) -> some View {
        let rect = CGRect(
            x: region.x * fitted.width,
            y: region.y * fitted.height,
            width: region.width * fitted.width,
            height: region.height * fitted.height
        )
        return ZStack(alignment: .topLeading) {
            dimming(around: rect, in: fitted)

            Rectangle()
                .strokeBorder(Color.white, lineWidth: 2)
                .background(Color.white.opacity(0.001))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .contentShape(Rectangle())
                .gesture(moveGesture(in: fitted))

            ForEach(CropCorner.allCases, id: \.self) { corner in
                handle(corner, rect: rect, fitted: fitted)
            }
        }
    }

    /// Four bands rather than a mask: no blend modes, nothing to render wrong
    /// on a device, and each band is trivially correct.
    private func dimming(around rect: CGRect, in fitted: CGSize) -> some View {
        let shade = Color.black.opacity(0.45)
        return ZStack(alignment: .topLeading) {
            shade
                .frame(width: fitted.width, height: max(rect.minY, 0))
            shade
                .frame(width: fitted.width, height: max(fitted.height - rect.maxY, 0))
                .offset(y: rect.maxY)
            shade
                .frame(width: max(rect.minX, 0), height: rect.height)
                .offset(y: rect.minY)
            shade
                .frame(width: max(fitted.width - rect.maxX, 0), height: rect.height)
                .offset(x: rect.maxX, y: rect.minY)
        }
        .allowsHitTesting(false)
    }

    private func handle(_ corner: CropCorner, rect: CGRect, fitted: CGSize) -> some View {
        let point = Self.cornerPoint(corner, in: rect)
        return Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            .frame(width: handleSize, height: handleSize)
            .offset(x: point.x - handleSize / 2, y: point.y - handleSize / 2)
            .gesture(resizeGesture(corner, in: fitted))
            .accessibilityLabel(corner.accessibilityLabel)
    }

    static func cornerPoint(_ corner: CropCorner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeading: return CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeading: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomTrailing: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    // MARK: - Gestures

    private func moveGesture(in fitted: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragOrigin ?? region
                if dragOrigin == nil { dragOrigin = start }
                region = start.translated(
                    dx: Double(value.translation.width / max(fitted.width, 1)),
                    dy: Double(value.translation.height / max(fitted.height, 1))
                )
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func resizeGesture(_ corner: CropCorner, in fitted: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragOrigin ?? region
                if dragOrigin == nil { dragOrigin = start }
                region = start.resized(
                    corner,
                    dx: Double(value.translation.width / max(fitted.width, 1)),
                    dy: Double(value.translation.height / max(fitted.height, 1))
                )
            }
            .onEnded { _ in dragOrigin = nil }
    }
}

extension CropCorner {
    var accessibilityLabel: String {
        switch self {
        case .topLeading: return "Top left corner"
        case .topTrailing: return "Top right corner"
        case .bottomLeading: return "Bottom left corner"
        case .bottomTrailing: return "Bottom right corner"
        }
    }
}
