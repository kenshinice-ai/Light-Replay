import Foundation
import XCTest
@testable import SunEngine

final class SolarPositionTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Point: Decodable {
            let location: String
            let unix: Double
            let lat: Double
            let lon: Double
            let azimuth_deg: Double
            let elevation_deg: Double
            let true_elevation_deg: Double
            let declination_deg: Double
            let equation_of_time_min: Double
        }
        let points: [Point]
    }

    /// engine/tests/fixtures/sun-positions.json, written by the Python reference (engine/scripts/make_sun_fixture.py).
    private func fixture() throws -> Fixture {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: "engine/tests/fixtures/sun-positions.json")))
    }

    func testMatchesThePythonReferenceExactly() throws {
        let points = try fixture().points
        XCTAssertGreaterThan(points.count, 700)
        for p in points {
            let s = SolarPosition.compute(at: Date(timeIntervalSince1970: p.unix), latitude: p.lat, longitude: p.lon)
            XCTAssertEqual(s.azimuthDeg, p.azimuth_deg, accuracy: 1e-7, "\(p.location) \(p.unix)")
            XCTAssertEqual(s.elevationDeg, p.elevation_deg, accuracy: 1e-7, "\(p.location) \(p.unix)")
            XCTAssertEqual(s.trueElevationDeg, p.true_elevation_deg, accuracy: 1e-7)
            XCTAssertEqual(s.declinationDeg, p.declination_deg, accuracy: 1e-7)
            XCTAssertEqual(s.equationOfTimeMin, p.equation_of_time_min, accuracy: 1e-6)
        }
    }

    func testNRELSPAPublishedExample() {
        // Reda & Andreas (2004) Table A5.1: 2003-10-17 12:30:30 UTC−7, 39.742476 N 105.1786 W, 820 hPa, 11 °C
        // → zenith 50.11162°, azimuth 194.34024°.
        let date = Date(timeIntervalSince1970: 1_066_419_030)
        let s = SolarPosition.compute(at: date, latitude: 39.742476, longitude: -105.1786, pressureHPa: 820, temperatureC: 11)
        XCTAssertEqual(90 - s.elevationDeg, 50.11162, accuracy: 0.01)
        XCTAssertEqual(s.azimuthDeg, 194.34024, accuracy: 0.01)
    }

    func testSolsticeNoonMatchesTheFlatFormula() {
        // docs/06 §2: Melbourne 28.8° / 75.6°.
        let tz = TimeZone(identifier: "Australia/Melbourne")!
        func noon(_ day: LocalDay) -> Double {
            SunSampler.samples(on: day, latitude: -37.8136, longitude: 144.9631, timeZone: tz, stepMinutes: 1)
                .map(\.position.elevationDeg).max() ?? 0
        }
        XCTAssertEqual(noon(LocalDay(year: 2026, month: 6, day: 21)), 28.8, accuracy: 0.15)
        XCTAssertEqual(noon(LocalDay(year: 2026, month: 12, day: 21)), 75.6, accuracy: 0.15)
    }
}
