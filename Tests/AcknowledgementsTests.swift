import XCTest
@testable import RIG

/// The MIT licences of the bundled garment encoder must ship with the app
/// (docs/FASHIONCLIP_LEGAL_RISK.md). They live in iOS Settings > RIG > Acknowledgements.
final class AcknowledgementsTests: XCTestCase {
    func testSettingsBundleCarriesTheEncoderLicences() throws {
        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "Settings", withExtension: "bundle"))
        let data = try Data(contentsOf: bundle.appendingPathComponent("Acknowledgements.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let groups = try XCTUnwrap(plist["PreferenceSpecifiers"] as? [[String: Any]])
        let text = groups.compactMap { $0["FooterText"] as? String }.joined(separator: "\n")
        XCTAssertTrue(text.contains("Copyright (c) 2023 Patrick John Chia"))
        XCTAssertTrue(text.contains("Gabriel Ilharco"))
        XCTAssertEqual(text.components(separatedBy: "Permission is hereby granted").count - 1, 2)
    }
}
