import Foundation

/// Whether direct sun reaches the target at one instant (docs/06 §4, §6).
public enum SunState: String, Sendable, Codable, CaseIterable {
    /// Stable direct sun.
    case direct
    /// On a boundary, or the direction uncertainty straddles one. Never reported as direct.
    case sensitive
    case blocked
    /// The sun is in a cell nobody saw, or behind unresolved glass. Enters the calculation as unknown, never as sky.
    case unknown
}

public enum DirectSun {
    /// One direction against the grid. The sun disk (radius 0.27°) is judged on the 3×3 cells around it: unanimous sky is
    /// direct, unanimous obstruction is blocked, anything mixed is a boundary; unknown or glass at the centre, or as the
    /// majority, is unknown (docs/06 §4).
    public static func classify(azimuthARDeg az: Double, altitudeDeg alt: Double, in grid: VisibilityGrid) -> SunState {
        guard let centre = VisibilityGrid.cell(azimuthDeg: az, altitudeDeg: alt) else { return .unknown }
        let centreState = grid[azimuthCell: centre.az, altitudeCell: centre.alt]
        guard centreState == .sky || centreState == .blocked else { return .unknown }
        var sky = 0, blocked = 0, other = 0
        for dAlt in -1...1 {
            let a = centre.alt + dAlt
            guard a >= 0, a < VisibilityGrid.altitudeCells else { continue }
            for dAz in -1...1 {
                switch grid[azimuthCell: centre.az + dAz, altitudeCell: a] {
                case .sky: sky += 1
                case .blocked: blocked += 1
                case .unknown, .glassUncertain: other += 1
                }
            }
        }
        if other > sky + blocked { return .unknown }
        if other == 0 && blocked == 0 { return .direct }
        if other == 0 && sky == 0 { return .blocked }
        return .sensitive
    }
}
