import Foundation
import XCTest
@testable import SunEngine

/// Synthetic skies with analytic answers (docs/06 §9). Coordinates are a city centre used as an arbitrary input.
final class SunBandsTests: XCTestCase {
    private let lat = -37.8136, lon = 144.9631
    private let tz = TimeZone(identifier: "Australia/Melbourne")!
    private let winter = LocalDay(year: 2026, month: 6, day: 21)
    private var exact: BandOptions { var o = BandOptions(); o.boundaryJitterDeg = 0; return o }

    private func bands(_ grid: VisibilityGrid, yaw: YawEstimate = YawEstimate(deltaDeg: 0, sigmaDeg: 0),
                       options: BandOptions? = nil, day: LocalDay? = nil) -> DayBands {
        SunBands(grid: grid, latitude: lat, longitude: lon, timeZone: tz, yaw: yaw, options: options ?? exact)
            .bands(on: day ?? winter)
    }

    /// First whole minute of the day at which `condition` holds.
    private func firstMinute(_ day: LocalDay? = nil, where condition: (SunPosition) -> Bool) -> Date? {
        let interval = (day ?? winter).interval(in: tz)
        return stride(from: interval.start, to: interval.end, by: 60).first {
            condition(SolarPosition.compute(at: $0, latitude: lat, longitude: lon))
        }
    }

    private func segment(_ b: DayBands, _ state: SunState) -> BandSegment? { b.segments.first { $0.state == state } }

    func testOpenSkyIsDirectFromSunriseToSunset() {
        let b = bands(VisibilityGrid { _, alt in alt >= 0 ? .sky : .blocked })
        XCTAssertEqual(b.minutes(.unknown), 0)
        XCTAssertEqual(b.minutes(.blocked), 0)
        XCTAssertTrue((560...575).contains(b.daylightMinutes), "winter day \(b.daylightMinutes) min")
        XCTAssertGreaterThan(b.directMinutes, b.daylightMinutes - 40, "only the disk-on-horizon minutes are sensitive")
        XCTAssertEqual(SunSampler.clock(b.segments.first!.from, in: tz).prefix(4), "07:3")
    }

    func testTenDegreeHorizonSwitchesExactlyWhereTheSunCrossesIt() throws {
        let b = bands(VisibilityGrid { _, alt in alt >= 10 ? .sky : .blocked })
        // 3×3 disk rule: blocked below 9°, sensitive between 9° and 11°, direct from 11°.
        let t9 = try XCTUnwrap(firstMinute { $0.elevationDeg >= 9 })
        let t11 = try XCTUnwrap(firstMinute { $0.elevationDeg >= 11 })
        let blocked = try XCTUnwrap(segment(b, .blocked))
        let direct = try XCTUnwrap(segment(b, .direct))
        XCTAssertEqual(blocked.to.timeIntervalSince(t9), 0, accuracy: 60)
        XCTAssertEqual(direct.from.timeIntervalSince(t11), 0, accuracy: 60)
    }

    func testAzimuthHalfSkyTurnsDirectWhenTheSunPassesNorth() throws {
        // AR azimuth 0–180 blocked (east), 180–360 open (west). Winter sun: north-east morning, north at noon, north-west afternoon.
        let grid = VisibilityGrid { az, alt in alt < 0 ? .blocked : (az < 180 ? .blocked : .sky) }
        let b = bands(grid)
        let direct = try XCTUnwrap(segment(b, .direct))
        let crosses359 = try XCTUnwrap(firstMinute { $0.elevationDeg > 0 && $0.azimuthDeg > 180 && $0.azimuthDeg < 359 })
        XCTAssertEqual(direct.from.timeIntervalSince(crosses359), 0, accuracy: 60)
        XCTAssertLessThan(b.segments.first { $0.state == .blocked }!.from, direct.from, "morning is blocked")

        // Rotating the capture 30° (Δ = 30) moves the switch to where the true azimuth crosses 29° (still morning).
        let turned = bands(grid, yaw: YawEstimate(deltaDeg: 30, sigmaDeg: 0))
        let crosses29 = try XCTUnwrap(firstMinute { $0.elevationDeg > 0 && $0.azimuthDeg < 29 })
        XCTAssertEqual(try XCTUnwrap(segment(turned, .direct)).from.timeIntervalSince(crosses29), 0, accuracy: 60)
    }

    func testDirectionUncertaintyWidensTheSensitiveBand() {
        let grid = VisibilityGrid { az, alt in alt < 0 ? .blocked : (az < 180 ? .blocked : .sky) }
        var options = BandOptions()
        options.boundaryJitterDeg = 0
        let sure = bands(grid, yaw: YawEstimate(deltaDeg: 0, sigmaDeg: 0), options: options)
        let unsure = bands(grid, yaw: YawEstimate(deltaDeg: 0, sigmaDeg: 8), options: options)
        XCTAssertGreaterThan(unsure.minutes(.sensitive), sure.minutes(.sensitive) + 30)
        XCTAssertLessThan(unsure.directMinutes, sure.directMinutes)
        XCTAssertEqual(unsure.daylightMinutes, sure.daylightMinutes)
    }

    func testUnknownSkyIsNeverReportedAsDirect() {
        // Afternoon quadrant unseen, glass over the zenith: the false-valid guard at band level.
        let grid = VisibilityGrid { az, alt in
            if alt < 0 { return .blocked }
            if az >= 270 && az < 330 { return .unknown }
            if alt >= 60 { return .glassUncertain }
            return .sky
        }
        let sun = SunBands(grid: grid, latitude: lat, longitude: lon, timeZone: tz, yaw: YawEstimate(deltaDeg: 0, sigmaDeg: 3))
        for day in [winter, LocalDay(year: 2026, month: 12, day: 21)] {
            let interval = day.interval(in: tz)
            for t in stride(from: interval.start, to: interval.end, by: 300) {
                let p = SolarPosition.compute(at: t, latitude: lat, longitude: lon)
                guard p.elevationDeg > 0, grid.state(azimuthDeg: p.azimuthDeg, altitudeDeg: p.elevationDeg) != .sky else { continue }
                XCTAssertNotEqual(sun.state(at: t), .direct, "sun on a \(grid.state(azimuthDeg: p.azimuthDeg, altitudeDeg: p.elevationDeg)) cell at \(t)")
            }
        }
        let b = sun.bands(on: winter)
        XCTAssertGreaterThan(b.minutes(.unknown), 60)
        XCTAssertGreaterThan(b.upperBoundMinutes, b.directMinutes, "unknown counts toward the upper bound only")
    }

    func testBandsAreReproducible() {
        let grid = VisibilityGrid { az, alt in alt < 0 ? .blocked : (az < 180 ? .blocked : .sky) }
        let yaw = YawEstimate(deltaDeg: 5, sigmaDeg: 6)
        XCTAssertEqual(bands(grid, yaw: yaw, options: BandOptions()), bands(grid, yaw: yaw, options: BandOptions()))
    }

    func testClassifierDiskRule() {
        var grid = VisibilityGrid(filledWith: .sky)
        XCTAssertEqual(DirectSun.classify(azimuthARDeg: 100.5, altitudeDeg: 30.5, in: grid), .direct)
        grid[azimuthCell: 101, altitudeCell: 40] = .blocked      // neighbour of (100, 30°) = cell (100, 40)
        XCTAssertEqual(DirectSun.classify(azimuthARDeg: 100.5, altitudeDeg: 30.5, in: grid), .sensitive)
        grid[azimuthCell: 100, altitudeCell: 40] = .glassUncertain
        XCTAssertEqual(DirectSun.classify(azimuthARDeg: 100.5, altitudeDeg: 30.5, in: grid), .unknown, "glass at the centre")
        XCTAssertEqual(DirectSun.classify(azimuthARDeg: 359.5, altitudeDeg: 30.5, in: VisibilityGrid(filledWith: .blocked)), .blocked)
        XCTAssertEqual(DirectSun.classify(azimuthARDeg: 10, altitudeDeg: 30, in: VisibilityGrid()), .unknown)
    }

    func testDaylightSavingDayHas23HoursAndShiftsTheClock() throws {
        // Melbourne daylight saving starts 2026-10-04 02:00.
        let before = LocalDay(year: 2026, month: 10, day: 3), change = LocalDay(year: 2026, month: 10, day: 4)
        XCTAssertEqual(change.interval(in: tz).duration, 23 * 3600)
        XCTAssertEqual(before.interval(in: tz).duration, 24 * 3600)
        let open = VisibilityGrid { _, alt in alt >= 0 ? .sky : .blocked }
        // Clock minutes of sunrise, read the way a buyer reads them.
        let rise = { (d: LocalDay) -> Double in
            let clock = SunSampler.clock(self.bands(open, day: d).segments.first!.from, in: self.tz).split(separator: ":")
            return Double(Int(clock[0])! * 60 + Int(clock[1])!)
        }
        XCTAssertEqual(rise(change) - rise(before), 60, accuracy: 3, "sunrise clock time jumps by an hour")
    }

    func testLeapDayAndYearBoundaries() {
        let days = LocalDay(year: 2028, month: 2, day: 28).through(LocalDay(year: 2028, month: 3, day: 1), in: tz)
        XCTAssertEqual(days.map(\.description), ["2028-02-28", "2028-02-29", "2028-03-01"])
        XCTAssertEqual(LocalDay(year: 2026, month: 12, day: 31).adding(days: 1, in: tz).description, "2027-01-01")
    }

    func testCorridorCoverage() {
        let days = [winter]
        let corridor = SunCorridor(days: days, latitude: lat, longitude: lon, timeZone: tz, yawDeg: 0)
        let open = corridor.coverage(of: VisibilityGrid { _, alt in alt >= 0 ? .sky : .blocked })
        XCTAssertGreaterThan(open.corridorCells, 100)
        XCTAssertEqual(open.coveragePct, 100)
        XCTAssertEqual(corridor.coverage(of: VisibilityGrid()).coveragePct, 0)
        let halfSeen = corridor.coverage(of: VisibilityGrid { az, _ in az < 180 ? .unknown : .sky })
        XCTAssertTrue(halfSeen.coveragePct > 20 && halfSeen.coveragePct < 80, "\(halfSeen)")
        let glass = corridor.coverage(of: VisibilityGrid(filledWith: .glassUncertain))
        XCTAssertEqual(glass.coveragePct, 100, "glass counts as covered; the segmentation gate limits it (docs/03 §5)")
        XCTAssertEqual(glass.glassCells, glass.corridorCells)

        let breakfast = SunCorridor(days: days, latitude: lat, longitude: lon, timeZone: tz, yawDeg: 0, localMinutes: 420..<600)
        let inBreakfast = breakfast.cells.enumerated().filter(\.element).map(\.offset)
        XCTAssertFalse(inBreakfast.isEmpty)
        XCTAssertTrue(inBreakfast.allSatisfy { corridor.cells[$0] }, "a time window is a subset of the whole day")
    }
}
