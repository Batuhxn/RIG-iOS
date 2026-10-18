#!/usr/bin/env python3
"""Regression tests for the network rule in static_audit.py.

Run:  python3 scripts/test_static_audit.py
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import static_audit  # noqa: E402

WEATHER = "Sources/Services/Weather/OpenMeteoWeatherService.swift"
WEATHER_TEST = "Tests/WeatherForecastParsingTests.swift"

CLEAN_SERVICE = '''import Foundation
struct OpenMeteoWeatherService {
    static let host = "api.open-meteo.com"
    static let attributionURL = URL(string: "https://open-meteo.com/")
    func go(_ request: URLRequest) async throws {
        var request = request
        request.httpMethod = "GET"
        let session = URLSession(configuration: .ephemeral)
        _ = try await session.data(for: request)
    }
}
'''


def findings(relative: str, raw: str) -> list[str]:
    return static_audit.network_findings(relative, raw, static_audit.strip_swift(raw))


class NetworkRuleTests(unittest.TestCase):
    def test_clean_weather_service_passes(self) -> None:
        self.assertEqual(findings(WEATHER, CLEAN_SERVICE), [])

    def test_networking_elsewhere_still_fails(self) -> None:
        for path in ("Sources/Services/ImageStorage/GarmentImageStore.swift",
                     "Sources/Services/Weather/WeatherRepository.swift",
                     "Sources/Features/Suggestions/SuggestionsModel.swift"):
            result = findings(path, "import Foundation\nlet s = URLSession.shared\n")
            self.assertTrue(result, path)
            self.assertIn("network call", result[0])

    def test_comment_mentioning_urlsession_is_not_a_call(self) -> None:
        self.assertEqual(findings("Sources/App/RIGApp.swift", "import Foundation\n// URLSession is banned\n"), [])

    def test_other_host_fails(self) -> None:
        raw = CLEAN_SERVICE.replace("api.open-meteo.com", "api.example.com")
        self.assertTrue(any("api.example.com" in item for item in findings(WEATHER, raw)))
        raw = CLEAN_SERVICE + 'let u = URL(string: "https://tracker.example.net/x")\n'
        self.assertTrue(any("tracker.example.net" in item for item in findings(WEATHER, raw)))

    def test_garment_or_photo_reference_fails(self) -> None:
        for snippet in ("let x: GarmentSnapshot? = nil", "let d = imageData", "let i: UIImage? = nil",
                        "let p = photoLibrary"):
            raw = CLEAN_SERVICE + snippet + "\n"
            self.assertTrue(any("garment or photo" in item for item in findings(WEATHER, raw)), snippet)

    def test_post_and_body_fail(self) -> None:
        raw = CLEAN_SERVICE.replace('httpMethod = "GET"', 'httpMethod = "POST"')
        self.assertTrue(any("non-GET" in item for item in findings(WEATHER, raw)))
        raw = CLEAN_SERVICE + "func b(_ r: inout URLRequest) { r.httpBody = Data() }\n"
        self.assertTrue(any("request body" in item for item in findings(WEATHER, raw)))

    def test_persistent_session_fails(self) -> None:
        raw = CLEAN_SERVICE + "let c = URLSessionConfiguration.default\n"
        self.assertTrue(any("persistent session" in item for item in findings(WEATHER, raw)))

    def test_weather_test_may_build_requests_but_not_sessions(self) -> None:
        ok = "import XCTest\nlet r = URLRequest(url: URL(fileURLWithPath: \"/\"))\nlet b = r.httpBody\n"
        self.assertEqual(findings(WEATHER_TEST, ok), [])
        bad = ok + "let s = URLSession.shared\n"
        self.assertTrue(any("stub the transport" in item for item in findings(WEATHER_TEST, bad)))

    def test_allowlist_is_exactly_two_files(self) -> None:
        self.assertEqual(set(static_audit.NETWORK_ALLOWLIST), {WEATHER, WEATHER_TEST})

    def test_real_weather_service_passes(self) -> None:
        path = static_audit.ROOT / WEATHER
        self.assertTrue(path.is_file())
        self.assertEqual(findings(WEATHER, path.read_text(encoding="utf-8")), [])


if __name__ == "__main__":
    unittest.main()
