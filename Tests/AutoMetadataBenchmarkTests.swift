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
        for (index, fixture) in fixtures.enumerated() {
            let image = try Data(contentsOf: manifestURL.deletingLastPathComponent().appendingPathComponent(fixture.cutout))
            let result = await service.analyze(cutout: image)
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
        }
        let attachment = XCTAttachment(data: encoded, uniformTypeIdentifier: "public.json")
        attachment.name = "auto-metadata-observations.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
