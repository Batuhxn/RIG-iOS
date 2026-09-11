import CoreML
import Foundation
import os
import UIKit

/// Metadata and aggregate statistics only; never records photographs or mask planes.
/// All logging and diagnostic scans compile out of Release builds.
struct EdgeSAMDiagnostics {
    enum ConversionFailure: String {
        case maskCount, scoreCount, scoreRead, maskRead, resizedDimensions
        case sourceDimensions, sourceImageDimensions, thresholdDimensions, emptyForeground
        case contextCreation, contextData, maskedImageCreation, imageCrop, pngEncoding
    }

    #if DEBUG
    let id = UUID().uuidString
    #endif

    func event(_ stage: String, _ values: @autoclosure () -> [String: String]) {
        #if DEBUG
        var record = values()
        record["stage"] = stage
        record["trace"] = id
        record["uptime"] = "\(ProcessInfo.processInfo.systemUptime)"
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let message = String(data: data, encoding: .utf8) else { return }
        let line = "[RIG-EdgeSAM] " + message
        EdgeSAMDiagnosticBuffer.shared.append(line)
        Logger(subsystem: "dev.rig.app", category: "EdgeSAM").debug("\(line, privacy: .public)")
        #endif
    }

    func fail<T>(_ failure: ConversionFailure) -> T? {
        event("failure", ["guard": failure.rawValue])
        return nil
    }

    func tensor(_ name: String, _ array: MLMultiArray) {
        event(name, ["shape": "\(array.shape)", "strides": "\(array.strides)",
                     "dataType": "\(array.dataType.rawValue)", "count": "\(array.count)"])
    }

    func source(_ name: String, _ image: UIImage) {
        event(name, ["size": "\(image.size)", "scale": "\(image.scale)",
                     "orientation": "\(image.imageOrientation.rawValue)",
                     "cgWidth": "\(image.cgImage?.width ?? 0)", "cgHeight": "\(image.cgImage?.height ?? 0)"])
    }

    func metadata(_ value: EdgeSAMResizeMetadata) {
        event("resize", ["sourceWidth": "\(value.sourceWidth)", "sourceHeight": "\(value.sourceHeight)",
                         "resizedWidth": "\(value.resizedWidth)", "resizedHeight": "\(value.resizedHeight)",
                         "modelWidth": "1024", "modelHeight": "1024", "scale": "\(value.scale)",
                         "padRight": "\(1024 - value.resizedWidth)", "padBottom": "\(1024 - value.resizedHeight)"])
    }

    func plane(_ name: String, _ values: [Float], width: Int, height: Int) {
        #if DEBUG
        var finiteCount = 0
        var foregroundCount = 0
        var minimum = Float.infinity
        var maximum = -Float.infinity
        for value in values {
            if value > 0 { foregroundCount += 1 }
            if value.isFinite {
                finiteCount += 1
                minimum = min(minimum, value)
                maximum = max(maximum, value)
            }
        }
        let bounds = EdgeSAMGeometry.thresholdAndBoundingBox(values, width: width, height: height)
        event(name, ["width": "\(width)", "height": "\(height)", "count": "\(values.count)",
                     "finite": "\(finiteCount)", "nonFinite": "\(values.count - finiteCount)",
                     "min": finiteCount > 0 ? String(minimum) : "none",
                     "max": finiteCount > 0 ? String(maximum) : "none",
                     "foreground": "\(foregroundCount)",
                     "boundingPixels": bounds.map { "\($0.minX),\($0.minY),\($0.maxX - $0.minX + 1),\($0.maxY - $0.minY + 1)" } ?? "empty",
                     "boundingNormalized": bounds.map { "\($0.boundingRegion)" } ?? "empty"])
        #endif
    }
}
