import SwiftUI

// MARK: - Frame chrome

/// The crop frame itself: a hairline box, a rule-of-thirds grid, and four
/// accent corner marks.
struct CropFrame: View {
    let size: CGSize

    var body: some View {
        ZStack {
            Rectangle()
                .strokeBorder(RIGTheme.text(55), lineWidth: 1)

            thirds

            ForEach(CropCorner.allCases) { corner in
                CornerMark(corner: corner)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var thirds: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(0..<3) { index in
                    Rectangle().fill(.clear)
                    if index < 2 {
                        Rectangle().fill(RIGTheme.text(16)).frame(width: 1)
                    }
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<3) { index in
                    Rectangle().fill(.clear)
                    if index < 2 {
                        Rectangle().fill(RIGTheme.text(16)).frame(height: 1)
                    }
                }
            }
        }
    }
}

struct CornerMark: View {
    let corner: CropCorner

    var body: some View {
        Path { path in
            let length: CGFloat = 22
            switch corner {
            case .topLeading:
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: .zero)
                path.addLine(to: CGPoint(x: length, y: 0))
            case .topTrailing:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
                path.addLine(to: CGPoint(x: length, y: length))
            case .bottomLeading:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: length, y: length))
            case .bottomTrailing:
                path.move(to: CGPoint(x: length, y: 0))
                path.addLine(to: CGPoint(x: length, y: length))
                path.addLine(to: CGPoint(x: 0, y: length))
            }
        }
        .stroke(RIGTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .square))
        .frame(width: 22, height: 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
        .accessibilityHidden(true)
    }
}

// MARK: - Corners

enum CropCorner: String, CaseIterable, Identifiable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var id: String { rawValue }

    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .topLeading: return "Sol üst köşeyi sürükle"
        case .topTrailing: return "Sağ üst köşeyi sürükle"
        case .bottomLeading: return "Sol alt köşeyi sürükle"
        case .bottomTrailing: return "Sağ alt köşeyi sürükle"
        }
    }

    func anchor(in frame: CGRect) -> CGPoint {
        switch self {
        case .topLeading: return CGPoint(x: frame.minX, y: frame.minY)
        case .topTrailing: return CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeading: return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomTrailing: return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    /// Moves this corner by the given unit delta, holding the opposite corner
    /// fixed and honouring the aspect ratio when one is locked.
    func resized(_ start: CGRect, dx: CGFloat, dy: CGFloat, ratio: CGFloat?, imageAspect: CGFloat) -> CGRect {
        let minimum: CGFloat = 0.12

        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY

        switch self {
        case .topLeading:
            minX += dx
            minY += dy
        case .topTrailing:
            maxX += dx
            minY += dy
        case .bottomLeading:
            minX += dx
            maxY += dy
        case .bottomTrailing:
            maxX += dx
            maxY += dy
        }

        minX = min(max(minX, 0), maxX - minimum)
        maxX = max(min(maxX, 1), minX + minimum)
        minY = min(max(minY, 0), maxY - minimum)
        maxY = max(min(maxY, 1), minY + minimum)

        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        if let ratio {
            // Width leads; height follows it, anchored at whichever edge this
            // corner is not moving.
            let unitAspect = ratio / imageAspect
            var height = rect.width / unitAspect
            if height > 1 {
                height = 1
                rect.size.width = height * unitAspect
            }
            let anchorsTop = (self == .bottomLeading || self == .bottomTrailing)
            let y = anchorsTop ? rect.minY : rect.maxY - height
            rect = CGRect(
                x: rect.minX,
                y: min(max(y, 0), max(0, 1 - height)),
                width: rect.width,
                height: min(height, 1)
            )
        }

        return rect
    }
}

// MARK: - Helpers

extension CGRect {
    func scaled(to size: CGSize) -> CGRect {
        CGRect(
            x: minX * size.width,
            y: minY * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}

extension View {
    /// Punches a hole in this view in the shape of `mask`.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack(alignment: .topLeading) {
                Rectangle()
                mask()
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
