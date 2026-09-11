import CoreGraphics
import Foundation

/// The image rect is the only bridge from the stationary canvas to image space.
enum CropGeometry {
    static let touchSize: CGFloat = 48

    static func imageRect(for pixels: CGSize, in container: CGSize) -> CGRect {
        guard pixels.width > 0, pixels.height > 0, container.width > 0, container.height > 0,
              pixels.width.isFinite, pixels.height.isFinite,
              container.width.isFinite, container.height.isFinite else { return .zero }
        let scale = min(container.width / pixels.width, container.height / pixels.height)
        let size = CGSize(width: pixels.width * scale, height: pixels.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    static func viewRect(for region: NormalizedCropRect, in imageRect: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + CGFloat(region.x) * imageRect.width,
               y: imageRect.minY + CGFloat(region.y) * imageRect.height,
               width: CGFloat(region.width) * imageRect.width,
               height: CGFloat(region.height) * imageRect.height)
    }

    static func normalizedRect(from rect: CGRect, in imageRect: CGRect) -> NormalizedCropRect {
        guard imageRect.width > 0, imageRect.height > 0 else {
            return NormalizedCropRect(x: 0, y: 0, width: 0, height: 0)
        }
        return NormalizedCropRect(x: Double((rect.minX - imageRect.minX) / imageRect.width),
                                  y: Double((rect.minY - imageRect.minY) / imageRect.height),
                                  width: Double(rect.width / imageRect.width),
                                  height: Double(rect.height / imageRect.height))
    }

    static func selectionRect(for region: NormalizedCropRect, pixels: CGSize, in imageRect: CGRect) -> CGRect {
        let edges = region.pixelRect(in: pixels)
        guard !edges.isNull else { return .zero }
        let normalized = normalizedRect(from: edges, in: CGRect(origin: .zero, size: pixels))
        return viewRect(for: normalized, in: imageRect)
    }

    static func cornerPoint(_ corner: CropCorner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeading: return CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeading: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomTrailing: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    /// Spread handles for tiny regions, with connector lines, so their hit areas
    /// do not cover the entire move target. Keep full touch targets on screen.
    static func handleRect(for selection: CGRect, in canvas: CGSize) -> CGRect {
        let inset = touchSize / 2
        let width = min(max(selection.width, touchSize * 2), max(canvas.width - touchSize, 0))
        let height = min(max(selection.height, touchSize * 2), max(canvas.height - touchSize, 0))
        return CGRect(x: min(max(selection.midX - width / 2, inset), max(inset, canvas.width - inset - width)),
                      y: min(max(selection.midY - height / 2, inset), max(inset, canvas.height - inset - height)),
                      width: width, height: height)
    }

    static func operation(at point: CGPoint, selection: CGRect, handles: CGRect) -> CropOperation? {
        let nearest = CropCorner.allCases.min { a, b in
            let p = cornerPoint(a, in: handles)
            let q = cornerPoint(b, in: handles)
            return hypot(point.x - p.x, point.y - p.y) < hypot(point.x - q.x, point.y - q.y)
        }
        if let nearest {
            let center = cornerPoint(nearest, in: handles)
            if abs(point.x - center.x) <= touchSize / 2 && abs(point.y - center.y) <= touchSize / 2 {
                return .resize(nearest)
            }
        }
        let moveRect = CGRect(x: selection.midX - max(selection.width, touchSize) / 2,
                              y: selection.midY - max(selection.height, touchSize) / 2,
                              width: max(selection.width, touchSize), height: max(selection.height, touchSize))
        // The center of the spread handles remains movable even when a tiny
        // selection touches a canvas edge and its own center meets a handle.
        let moveControl = CGRect(x: handles.midX - touchSize / 2, y: handles.midY - touchSize / 2,
                                 width: touchSize, height: touchSize)
        return moveRect.contains(point) || moveControl.contains(point) ? .move : nil
    }
}

enum CropOperation: Equatable {
    case move
    case resize(CropCorner)
}

struct CropInteraction {
    let start: NormalizedCropRect
    let operation: CropOperation?
    var translation: CGSize = .zero

    func region(in imageRect: CGRect) -> NormalizedCropRect {
        guard imageRect.width > 0, imageRect.height > 0 else { return start }
        let dx = Double(translation.width / imageRect.width)
        let dy = Double(translation.height / imageRect.height)
        switch operation {
        case .move: return start.translated(dx: dx, dy: dy)
        case .resize(let corner):
            return start.resized(corner, dx: dx, dy: dy,
                                 minimumSize: CGSize(width: CropGeometry.touchSize / imageRect.width,
                                                     height: CropGeometry.touchSize / imageRect.height))
        case nil: return start
        }
    }
}
