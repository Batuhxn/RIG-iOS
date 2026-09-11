import SwiftUI
import UIKit

struct GarmentCropView: View {
    let image: UIImage
    let sourcePixelSize: CGSize
    @Binding var region: NormalizedCropRect
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            CropCanvas(image: image, pixels: sourcePixelSize, size: proxy.size, region: $region)
                // Replacing the canvas cancels in-flight gestures on layout and
                // app interruption. GestureState resets on system cancellation.
                .id(proxy.size.width)
                .id(proxy.size.height)
                .id(scenePhase)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crop area")
    }

    static func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        return CropGeometry.imageRect(for: imageSize, in: container).size
    }

    static func cornerPoint(_ corner: CropCorner, in rect: CGRect) -> CGPoint {
        CropGeometry.cornerPoint(corner, in: rect)
    }
}

private struct CropCanvas: View {
    let image: UIImage
    let pixels: CGSize
    let size: CGSize
    @Binding var region: NormalizedCropRect
    @GestureState private var interaction: CropInteraction?
    @Namespace private var canvasSpace

    private var imageRect: CGRect { CropGeometry.imageRect(for: pixels, in: size) }
    private var visibleRegion: NormalizedCropRect { interaction?.region(in: imageRect) ?? region }

    var body: some View {
        let selection = CropGeometry.selectionRect(for: visibleRegion, pixels: pixels, in: imageRect)
        let handles = CropGeometry.handleRect(for: selection, in: size)
        // A fixed base owns layout. Overlays never contribute their own size.
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .accessibilityHidden(true)
            }
            .overlay {
                Canvas { context, _ in
                    var shade = Path(imageRect)
                    shade.addRect(selection)
                    context.fill(shade, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
                    context.stroke(Path(selection), with: .color(.white), lineWidth: 2)
                    for corner in CropCorner.allCases {
                        let actual = CropGeometry.cornerPoint(corner, in: selection)
                        let handle = CropGeometry.cornerPoint(corner, in: handles)
                        var connector = Path()
                        connector.move(to: actual)
                        connector.addLine(to: handle)
                        context.stroke(connector, with: .color(.white), lineWidth: 1)
                        let circle = CGRect(x: handle.x - 7, y: handle.y - 7, width: 14, height: 14)
                        context.fill(Path(ellipseIn: circle), with: .color(.white))
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if selection.width < CropGeometry.touchSize * 2 || selection.height < CropGeometry.touchSize * 2 {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1)
                        .position(x: handles.midX, y: handles.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: canvasSpace)
            .gesture(dragGesture)
            .accessibilityHint("Drag inside the selection to move it. Drag a corner handle to resize it.")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasSpace))
            .updating($interaction) { value, state, _ in
                if state == nil {
                    state = beginInteraction(at: value.startLocation)
                }
                state?.translation = value.translation
            }
            .onEnded { value in
                // The binding stays unchanged during the gesture, so the final
                // event also works if SwiftUI has already reset GestureState.
                var completed = interaction ?? beginInteraction(at: value.startLocation)
                completed.translation = value.translation
                region = completed.region(in: imageRect)
            }
    }

    private func beginInteraction(at point: CGPoint) -> CropInteraction {
        let selection = CropGeometry.selectionRect(for: region, pixels: pixels, in: imageRect)
        let handles = CropGeometry.handleRect(for: selection, in: size)
        return CropInteraction(start: region, operation: CropGeometry.operation(
            at: point, selection: selection, handles: handles))
    }
}
