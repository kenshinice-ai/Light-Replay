import Foundation

/// The cells the sun passes through for a question, widened by 3° (docs/06 §5), and how much of it the capture saw.
public struct CorridorCoverage: Sendable, Equatable {
    public let corridorCells: Int
    public let unknownCells: Int
    public let glassCells: Int
    /// `corridorCells − unknownCells`; glass counts as covered and is gated separately (docs/03 §5).
    public var coveredCells: Int { corridorCells - unknownCells }
    public var coveragePct: Double { corridorCells == 0 ? 0 : 100 * Double(coveredCells) / Double(corridorCells) }
}

public struct SunCorridor: Sendable {
    public static let marginDeg = 3
    /// Row-major like `VisibilityGrid.states`.
    public let cells: [Bool]

    /// `yawDeg` is NorthResolver's Δ: `az_ar = az_true − Δ`. `localMinutes` limits the question to part of the day,
    /// for example 7:00–10:00 for winter breakfast.
    public init(days: [LocalDay], latitude: Double, longitude: Double, timeZone: TimeZone, yawDeg: Double,
                localMinutes: Range<Int>? = nil, stepMinutes: Int = SunSampler.defaultStepMinutes) {
        var cells = Array(repeating: false, count: VisibilityGrid.azimuthCells * VisibilityGrid.altitudeCells)
        let calendar = LocalDay.calendar(timeZone)
        for day in days {
            for sample in SunSampler.samples(on: day, latitude: latitude, longitude: longitude, timeZone: timeZone, stepMinutes: stepMinutes) {
                if let window = localMinutes {
                    let c = calendar.dateComponents([.hour, .minute], from: sample.date)
                    guard window.contains(c.hour! * 60 + c.minute!) else { continue }
                }
                guard let centre = VisibilityGrid.cell(azimuthDeg: sample.position.azimuthDeg - yawDeg,
                                                       altitudeDeg: sample.position.elevationDeg) else { continue }
                let m = Self.marginDeg
                for alt in max(0, centre.alt - m)...min(VisibilityGrid.altitudeCells - 1, centre.alt + m) {
                    for az in (centre.az - m)...(centre.az + m) {
                        cells[alt * VisibilityGrid.azimuthCells + VisibilityGrid.wrap(az)] = true
                    }
                }
            }
        }
        self.cells = cells
    }

    public func coverage(of grid: VisibilityGrid) -> CorridorCoverage {
        var total = 0, unknown = 0, glass = 0
        for (index, inCorridor) in cells.enumerated() where inCorridor {
            total += 1
            switch grid.states[index] {
            case .unknown: unknown += 1
            case .glassUncertain: glass += 1
            case .sky, .blocked: break
            }
        }
        return CorridorCoverage(corridorCells: total, unknownCells: unknown, glassCells: glass)
    }
}
