import Foundation

/// What the camera saw in one 1°×1° cell of the sky around the target point (docs/03 §5).
public enum CellState: UInt8, Sendable, CaseIterable {
    case unknown = 0
    case sky = 1
    case blocked = 2
    /// Seen through glass and not resolved as sky or obstruction. Counts as covered but never as sky.
    case glassUncertain = 3
}

/// 360 × 100 cells in the AR world frame: azimuth 0..<360 (1° steps), altitude −10..<90 (1° steps). The AR frame is
/// what the capture measured; true azimuth reaches it only through NorthResolver's Δ (`az_ar = az_true − Δ`).
public struct VisibilityGrid: Sendable, Equatable {
    public static let azimuthCells = 360
    public static let altitudeCells = 100
    public static let minimumAltitudeDeg = -10.0

    public private(set) var states: [CellState]

    public init(filledWith state: CellState = .unknown) {
        states = Array(repeating: state, count: Self.azimuthCells * Self.altitudeCells)
    }

    /// Builds a grid from a rule on cell centres; for synthetic scenes and tests.
    public init(_ rule: (_ azimuthDeg: Double, _ altitudeDeg: Double) -> CellState) {
        self.init()
        for alt in 0..<Self.altitudeCells {
            for az in 0..<Self.azimuthCells {
                states[alt * Self.azimuthCells + az] = rule(Double(az) + 0.5, Self.minimumAltitudeDeg + Double(alt) + 0.5)
            }
        }
    }

    public subscript(azimuthCell az: Int, altitudeCell alt: Int) -> CellState {
        get { states[alt * Self.azimuthCells + Self.wrap(az)] }
        set { states[alt * Self.azimuthCells + Self.wrap(az)] = newValue }
    }

    /// The cell holding a direction, or nil below −10° / at or above 90°.
    public static func cell(azimuthDeg: Double, altitudeDeg: Double) -> (az: Int, alt: Int)? {
        let alt = Int((altitudeDeg - minimumAltitudeDeg).rounded(.down))
        guard alt >= 0 else { return nil }
        let az = wrap(Int(wrap360(azimuthDeg).rounded(.down)))
        return (az, min(alt, altitudeCells - 1))
    }

    public func state(azimuthDeg: Double, altitudeDeg: Double) -> CellState {
        guard let c = Self.cell(azimuthDeg: azimuthDeg, altitudeDeg: altitudeDeg) else { return .unknown }
        return self[azimuthCell: c.az, altitudeCell: c.alt]
    }

    static func wrap(_ az: Int) -> Int { ((az % azimuthCells) + azimuthCells) % azimuthCells }
}
