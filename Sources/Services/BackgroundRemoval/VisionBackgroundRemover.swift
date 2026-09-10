import CoreImage
import Foundation
import UIKit
import Vision

/// Local, on-device foreground extraction.
///
/// Uses `VNGenerateForegroundInstanceMaskRequest` (iOS 17+) and asks the
/// observation for a high-resolution masked image of every instance it found.
/// No image ever leaves the device, and no network call is made anywhere in
/// this file.
///
/// UNVERIFIED: this implementation has never executed. It was written on a
/// Windows host with no Apple runtime available. The API signatures were taken
/// from Apple's Vision documentation; behaviour on real photographs, and the
/// quality of the resulting cutouts, still needs a device run.
struct VisionBackgroundRemover: GarmentBackgroundRemoving {
    /// Shared so repeated imports do not each build a rendering context.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func removeBackground(from imageData: Data) async throws -> BackgroundRemovalResult {
        guard let uiImage = UIImage(data: imageData), let cgImage = uiImage.cgImage else {
            throw BackgroundRemovalError.unreadableImage
        }

        let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()

        do {
            try handler.perform([request])
        } catch {
            throw BackgroundRemovalError.maskGenerationFailed
        }

        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw BackgroundRemovalError.noForegroundFound
        }

        let maskedBuffer: CVPixelBuffer
        do {
            maskedBuffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
        } catch {
            throw BackgroundRemovalError.maskGenerationFailed
        }

        let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
        guard let rendered = Self.ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw BackgroundRemovalError.renderingFailed
        }
        guard let pngData = UIImage(cgImage: rendered).pngData() else {
            throw BackgroundRemovalError.renderingFailed
        }

        return BackgroundRemovalResult(imageData: pngData, isolated: true)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
