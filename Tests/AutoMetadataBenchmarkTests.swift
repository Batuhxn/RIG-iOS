import XCTest
@testable import RIG

final class AutoMetadataBenchmarkTests: XCTestCase {
    struct MetadataBenchmarkFixture: Decodable {
        let id: String
        let cutout: String
        let expected: [String: String]
    }

    struct Observation: Encodable {
        let id: String
        let expected: [String: String]
        let predicted: [String: String]
        let milliseconds: Double
        let modelID: String?
        let semanticStatus: String
        let cold: Bool
    }

    /// Explicit opt-in, never claims synthetic colour swatches are garment accuracy.
    /// RIG_METADATA_FIXTURES points to JSON and sibling consented, masked PNGs.
    func testLabelledDeviceBenchmark() async throws {
        guard let path = ProcessInfo.processInfo.environment["RIG_METADATA_FIXTURES"] else {
            throw XCTSkip("Labelled garment fixtures and model assets have not been supplied")
        }
        let manifestURL = URL(fileURLWithPath: path)
        let fixtures = try JSONDecoder().decode([MetadataBenchmarkFixture].self, from: Data(contentsOf: manifestURL))
        XCTAssertFalse(fixtures.isEmpty)
        let service = AutoMetadataService(classifier: CoreMLGarmentClassifier())
        var rows: [Observation] = []
        let baseline = Self.footprintMB()
        var afterFirst = baseline, peak = baseline
        for (index, fixture) in fixtures.enumerated() {
            let image = try Data(contentsOf: manifestURL.deletingLastPathComponent().appendingPathComponent(fixture.cutout))
            let result = await service.analyze(cutout: image)
            let now = Self.footprintMB()
            if index == 0 { afterFirst = now }
            peak = max(peak, now)
            XCTAssertNotEqual(result.semanticStatus, "unavailable", "Benchmark requires the real model")
            let values: [String: String?] = ["category": result.category?.value.rawValue,
                "subtype": result.subtype?.value, "length": result.length?.value.rawValue,
                "primaryColor": result.primaryColor?.value.rawValue, "secondaryColor": result.secondaryColor?.value.rawValue,
                "subtypeAlternatives": result.subtypeAlternatives?.joined(separator: ",")]
            rows.append(Observation(id: fixture.id, expected: fixture.expected,
                predicted: values.compactMapValues { $0 }, milliseconds: result.elapsedMilliseconds,
                modelID: result.modelID, semanticStatus: result.semanticStatus, cold: index == 0))
        }
        let encoded = try JSONEncoder().encode(rows)
        // CI reads observations from the host file system; the attachment stays for Xcode.
        if let output = ProcessInfo.processInfo.environment["RIG_METADATA_OUTPUT"] {
            try encoded.write(to: URL(fileURLWithPath: output))
            // Simulator process footprint: a proxy, not iPhone memory.
            let memory = ["baselineMB": baseline, "afterFirstGarmentMB": afterFirst, "peakMB": peak]
            try JSONEncoder().encode(memory).write(to: URL(fileURLWithPath: output + ".memory.json"))
        }
        let attachment = XCTAttachment(data: encoded, uniformTypeIdentifier: "public.json")
        attachment.name = "auto-metadata-observations.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The process's physical footprint, as Xcode's memory gauge reports it.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}
