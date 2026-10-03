import Foundation
import XCTest
@testable import SunEngine

/// engine/tests/fixtures/sun-bands.json, written by the Python reference (engine/scripts/make_bands_fixture.py). The
/// grid, the disk rule, the corridor and the bands must give the same answers as `bands.py`: the same minute, the
/// same state, the same random bits. Synthetic skies; nothing here is field-validated.
final class SunBandsParityTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Place: Decodable { let lat: Double; let lon: Double; let tz: String }
        struct Region: Decodable { let state: String; let alt_min: Double?; let alt_max: Double?; let az_min: Double?; let az_max: Double? }
        struct RNG: Decodable { let seed: String; let raw: [String]; let units: [Double]; let draws: [[Double]] }
        struct Cell: Decodable { let az: Int; let alt: Int; let state: String }
        struct Probe: Decodable { let name: String; let grid: String; let set: [Cell]; let az: Double; let alt: Double; let state: String }
        struct Segment: Decodable { let from: Int; let to: Int; let state: String }
        struct Day: Decodable { let day: String; let segments: [Segment]; let minutes: [String: Int]; let daylight: Int }
        struct Options: Decodable { let samples: Int?; let boundary_jitter_deg: Double?; let step_minutes: Int?; let seed: UInt64? }
        struct BandCase: Decodable {
            let name: String; let grid: String; let place: String; let delta_deg: Double; let sigma_deg: Double
            let options: Options; let days: [Day]
        }
        struct Corridor: Decodable {
            let name: String; let question: String?; let days: [String]; let place: String; let delta_deg: Double
            let local_minutes: [Int]?; let grid: String
            let corridor_cells: Int; let unknown_cells: Int; let glass_cells: Int; let coverage_pct: Double
        }
        let version: String
        let places: [String: Place]
        let grids: [String: [Region]]
        let rng: RNG
        let classify: [Probe]
        let bands: [BandCase]
        let corridors: [Corridor]
    }

    private func fixture() throws -> Fixture {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: "engine/tests/fixtures/sun-bands.json")))
    }

    private func state(_ name: String) -> CellState {
        switch name {
        case "sky": .sky
        case "blocked": .blocked
        case "glassUncertain": .glassUncertain
        default: .unknown
        }
    }

    /// The fixture's grid language: regions in order, last one wins, half-open bounds on cell centres.
    private func grid(_ regions: [Fixture.Region], sets: [Fixture.Cell] = []) -> VisibilityGrid {
        var grid = VisibilityGrid { az, alt in
            var result = CellState.unknown
            for r in regions where az >= (r.az_min ?? -1e9) && az < (r.az_max ?? 1e9) && alt >= (r.alt_min ?? -1e9) && alt < (r.alt_max ?? 1e9) {
                result = state(r.state)
            }
            return result
        }
        for cell in sets { grid[azimuthCell: cell.az, altitudeCell: cell.alt] = state(cell.state) }
        return grid
    }

    private func day(_ text: String) -> LocalDay {
        let parts = text.split(separator: "-").map { Int($0)! }
        return LocalDay(year: parts[0], month: parts[1], day: parts[2])
    }

    func testRandomStreamMatchesBitForBit() throws {
        let f = try fixture()
        XCTAssertEqual(f.version, SunBands.version)
        var rng = SplitMix64(seed: UInt64(f.rng.seed, radix: 16)!)
        XCTAssertEqual(f.rng.raw.map { _ in String(format: "%016llx", rng.next()) }, f.rng.raw)
        rng = SplitMix64(seed: UInt64(f.rng.seed, radix: 16)!)
        for unit in f.rng.units { XCTAssertEqual(rng.nextUnit(), unit, accuracy: 1e-16) }
        rng = SplitMix64(seed: UInt64(f.rng.seed, radix: 16)!)
        for draw in f.rng.draws {
            XCTAssertEqual(rng.nextGaussian(), draw[0], accuracy: 1e-14)
            XCTAssertEqual(rng.nextUniform(-1, 1), draw[1], accuracy: 1e-15)
            XCTAssertEqual(rng.nextUniform(-1, 1), draw[2], accuracy: 1e-15)
        }
    }

    func testClassifierMatches() throws {
        let f = try fixture()
        for probe in f.classify {
            let verdict = DirectSun.classify(azimuthARDeg: probe.az, altitudeDeg: probe.alt, in: grid(f.grids[probe.grid]!, sets: probe.set))
            XCTAssertEqual(verdict.rawValue, probe.state, probe.name)
        }
    }

    func testCorridorsMatch() throws {
        let f = try fixture()
        for c in f.corridors {
            let place = f.places[c.place]!, tz = TimeZone(identifier: place.tz)!
            let days: [LocalDay] = c.question.map { LightQuestion(rawValue: $0)!.corridorDays(year: 2026, latitude: place.lat, timeZone: tz) }
                ?? c.days.map(day)
            XCTAssertEqual(days.map(\.description), c.days, c.name)
            let window = c.local_minutes.map { $0[0]..<$0[1] }
            let corridor = SunCorridor(days: days, latitude: place.lat, longitude: place.lon, timeZone: tz, yawDeg: c.delta_deg, localMinutes: window)
            let coverage = corridor.coverage(of: grid(f.grids[c.grid]!))
            XCTAssertEqual(coverage.corridorCells, c.corridor_cells, c.name)
            XCTAssertEqual(coverage.unknownCells, c.unknown_cells, c.name)
            XCTAssertEqual(coverage.glassCells, c.glass_cells, c.name)
            XCTAssertEqual(coverage.coveragePct, c.coverage_pct, accuracy: 1e-9, c.name)
        }
    }

    func testBandsMatchToTheMinute() throws {
        let f = try fixture()
        XCTAssertGreaterThan(f.bands.count, 10)
        for c in f.bands {
            let place = f.places[c.place]!, tz = TimeZone(identifier: place.tz)!
            var options = BandOptions()
            if let v = c.options.samples { options.samples = v }
            if let v = c.options.boundary_jitter_deg { options.boundaryJitterDeg = v }
            if let v = c.options.step_minutes { options.stepMinutes = v }
            if let v = c.options.seed { options.seed = v }
            let sun = SunBands(grid: grid(f.grids[c.grid]!), latitude: place.lat, longitude: place.lon, timeZone: tz,
                               yaw: YawEstimate(deltaDeg: c.delta_deg, sigmaDeg: c.sigma_deg), options: options)
            for expected in c.days {
                let bands = sun.bands(on: day(expected.day))
                let name = "\(c.name) \(expected.day)"
                XCTAssertEqual(bands.segments.count, expected.segments.count, name)
                for (got, want) in zip(bands.segments, expected.segments) {
                    XCTAssertEqual(Int(got.from.timeIntervalSince1970), want.from, name)
                    XCTAssertEqual(Int(got.to.timeIntervalSince1970), want.to, name)
                    XCTAssertEqual(got.state.rawValue, want.state, name)
                }
                for (stateName, minutes) in expected.minutes {
                    XCTAssertEqual(bands.minutes(SunState(rawValue: stateName)!), minutes, "\(name) \(stateName)")
                }
                XCTAssertEqual(bands.daylightMinutes, expected.daylight, name)
            }
        }
    }
}
