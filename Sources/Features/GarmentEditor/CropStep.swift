import SwiftUI
import UIKit

/// The optional crop, between choosing a photograph and processing it.
///
/// Optional is the whole point, and the design says so twice — in the title
/// ("Kırp · isteğe bağlı") and in the pair of actions at the bottom, where
/// cropping is the primary and skipping is the quiet one beneath it. Both lead
/// to the same processing step; the only difference is which bytes go into it.
///
/// Nothing here writes to disk. The step hands its caller either the original
/// data untouched or freshly encoded cropped data, and the import pipeline
/// downstream cannot tell the difference — which is exactly why background
/// removal operates on the crop without knowing the crop exists.
struct CropStep: View {
    enum Ratio: String, CaseIterable, Identifiable {
        case free
        case square
        case portrait

        var id: String { rawValue }

        var label: String {
            switch self {
            case .free: return "Serbest"
            case .square: return "1:1"
            case .portrait: return "3:4"
            }
        }

        /// Width over height, or nil when the frame is unconstrained.
        var value: CGFloat? {
            switch self {
            case .free: return nil
            case .square: return 1
            case .portrait: return 3.0 / 4.0
            }
        }
    }

    let imageData: Data
    let onBack: () -> Void
    /// Cropped bytes, or nil when the user chose to skip.
    let onContinue: (Data?) -> Void

    @State private var ratio: Ratio = .portrait
    @State private var crop = CGRect(x: 0.08, y: 0.10, width: 0.84, height: 0.80)
    @State private var dragStart: CGRect?
    @State private var isWorking = false

    private var image: UIImage? { UIImage(data: imageData) }

    private var imageAspect: CGFloat {
        guard let image, image.size.height > 0 else { return 3.0 / 4.0 }
        return image.size.width / image.size.height
    }

    var body: some View {
        VStack(spacing: 0) {
            RIGFlowHeader(title: "Kırp", detail: "isteğe bağlı", onBack: onBack)

            Spacer(minLength: 0)

            cropCanvas
                .padding(.horizontal, RIGTheme.Spacing.xl)
                .padding(.vertical, 18)

            Spacer(minLength: 0)

            ratioPicker
                .padding(.horizontal, RIGTheme.Spacing.xl)
                .padding(.bottom, RIGTheme.Spacing.s)

            actions
                .padding(.horizontal, RIGTheme.Spacing.xl)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RIGTheme.pageBackground)
    }

    // MARK: - Canvas

    private var cropCanvas: some View {
        GeometryReader { proxy in
            let frame = crop.scaled(to: proxy.size)

            ZStack(alignment: .topLeading) {
                photograph

                // Everything outside the frame is dimmed. Drawn as one shape
                // with the frame punched out so there is a single even wash
                // rather than four overlapping rectangles.
                Rectangle()
                    .fill(Color(nocturne: 0x05060C).opacity(0.55))
                    .reverseMask {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                    .allowsHitTesting(false)

                CropFrame(size: frame.size)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false)

                // Move.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .gesture(moveGesture(in: proxy.size))

                // Resize, one handle per corner.
                ForEach(CropCorner.allCases) { corner in
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 44, height: 44)
                        .offset(
                            x: corner.anchor(in: frame).x - 22,
                            y: corner.anchor(in: frame).y - 22
                        )
                        .gesture(resizeGesture(corner, in: proxy.size))
                        .accessibilityLabel(corner.accessibilityLabel)
                }
            }
            .animation(NocturneMotion.cropFrame, value: ratio)
        }
        .aspectRatio(imageAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: RIGTheme.Radius.medium, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kırpma alanı")
    }

    @ViewBuilder
    private var photograph: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .accessibilityHidden(true)
        } else {
            RIGTheme.Neutral.n900
        }
    }

    // MARK: - Ratio

    private var ratioPicker: some View {
        HStack(spacing: 7) {
            Spacer(minLength: 0)
            ForEach(Ratio.allCases) { option in
                RIGChip(title: option.label, isOn: ratio == option, size: 12) {
                    ratio = option
                    applyRatio(option)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Re-fits the frame to a new aspect ratio, keeping its centre and staying
    /// inside the image.
    private func applyRatio(_ option: Ratio) {
        guard let target = option.value else { return }
        let centre = CGPoint(x: crop.midX, y: crop.midY)

        // The unit space is square, so the image's own aspect has to be folded
        // in before the frame's ratio means anything on screen.
        let unitAspect = target / imageAspect
        var width = crop.width
        var height = width / unitAspect
        if height > 1 {
            height = 1
            width = height * unitAspect
        }
        if width > 1 {
            width = 1
            height = width / unitAspect
        }

        crop = CGRect(
            x: min(max(centre.x - width / 2, 0), 1 - width),
            y: min(max(centre.y - height / 2, 0), 1 - height),
            width: width,
            height: height
        )
    }

    // MARK: - Gestures

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? crop
                if dragStart == nil { dragStart = crop }
                guard size.width > 0, size.height > 0 else { return }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                crop = CGRect(
                    x: min(max(start.minX + dx, 0), 1 - start.width),
                    y: min(max(start.minY + dy, 0), 1 - start.height),
                    width: start.width,
                    height: start.height
                )
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(_ corner: CropCorner, in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? crop
                if dragStart == nil { dragStart = crop }
                guard size.width > 0, size.height > 0 else { return }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                crop = corner.resized(start, dx: dx, dy: dy, ratio: ratio.value, imageAspect: imageAspect)
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: RIGTheme.Spacing.s) {
            Button {
                applyCrop()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "crop")
                    Text("Kırp ve devam et")
                }
            }
            .buttonStyle(RIGPrimaryButtonStyle())
            .disabled(isWorking)

            Button("Kırpmadan devam et") {
                onContinue(nil)
            }
            .buttonStyle(RIGQuietButtonStyle())
            .disabled(isWorking)
        }
        .padding(.bottom, RIGTheme.Spacing.l)
    }

    private func applyCrop() {
        isWorking = true
        // A crop that cannot be computed must never lose the photograph, so a
        // nil result falls through to the original bytes rather than failing.
        let cropped = GarmentImageProcessing.croppedJPEGData(from: imageData, unitRect: crop)
        isWorking = false
        onContinue(cropped)
    }
}
