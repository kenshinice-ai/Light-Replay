import Foundation
import simd

/// Everything the Light scan knows at one instant that could change what the buyer should do next.
public struct ScanStatus: Sendable, Equatable {
    public var isRecording = false
    /// `CaptureRecorder.trackingState`: "normal", "limited:<reason>" or "not_available".
    public var trackingState = "not_available"
    public var anchorLocked = false
    public var driftM: Double?
    public var toleranceM = 0.15
    /// How fast the camera is turning, degrees per second.
    public var turnRateDegPerSec = 0.0
    /// True once a direction estimate (Δ) exists, so the sun path can be placed.
    public var directionKnown = false
    /// Share of the question's sun corridor the camera has looked at, 0…1.
    public var coverage = 0.0
    public var targetCoverage = 0.9
    /// Nearest unseen corridor cell from where the camera points: x = Δazimuth (+ right), y = Δaltitude (+ up), degrees.
    public var gap: SIMD2<Double>?
    /// Lower-case question name for the sentence, e.g. "winter sun".
    public var questionName = "winter sun"

    public init() {}
}

/// One instruction at a time (docs/04 §8; apple-design review 2026-09-30).
public struct ScanPrompt: Sendable, Equatable {
    public enum Tone: Sendable, Equatable {
        case guide
        case caution
        case done
    }

    public let text: String
    /// SF Symbol name.
    public let symbol: String
    public let tone: Tone

    public init(_ text: String, symbol: String, tone: Tone = .guide) {
        self.text = text
        self.symbol = symbol
        self.tone = tone
    }
}

/// Picks the single most useful instruction. Order: tracking, viewpoint, speed, direction, then coverage — each earlier
/// problem would make the later advice pointless.
public enum ScanCoach {
    /// Faster than this the frames blur and the anchor drifts (candidate, docs/04 §4).
    public static let fastTurnDegPerSec = 60.0
    /// A gap closer than this to the centre of view is already on screen; no arrow needed.
    public static let onScreenDeg = 12.0

    public static func prompt(for s: ScanStatus) -> ScanPrompt {
        guard s.isRecording else {
            return ScanPrompt("Stand where you'd sit. Hold the phone at eye height, then tap Start.", symbol: "figure.stand")
        }
        switch s.trackingState {
        case "normal": break
        case "limited:excessive_motion":
            return ScanPrompt("Slow down.", symbol: "tortoise", tone: .caution)
        case "limited:insufficient_features":
            return ScanPrompt("Point at the room for a moment, not a blank wall.", symbol: "viewfinder", tone: .caution)
        case "not_available":
            return ScanPrompt("Starting the camera…", symbol: "camera", tone: .caution)
        default:
            return ScanPrompt("Hold still for a moment.", symbol: "hand.raised", tone: .caution)
        }
        guard s.anchorLocked else {
            return ScanPrompt("Hold still for a moment.", symbol: "hand.raised", tone: .caution)
        }
        if let drift = s.driftM, drift > s.toleranceM {
            return ScanPrompt("Move back to where you started. Keep the dot in the circle.", symbol: "arrow.uturn.backward", tone: .caution)
        }
        if s.turnRateDegPerSec > fastTurnDegPerSec {
            return ScanPrompt("Slower. Let the camera see the sky.", symbol: "tortoise", tone: .caution)
        }
        guard s.directionKnown else {
            return ScanPrompt("Finding north. Keep the phone upright.", symbol: "location.north.line")
        }
        if s.coverage >= s.targetCoverage {
            return ScanPrompt("That's enough sky. Tap Save.", symbol: "checkmark.circle.fill", tone: .done)
        }
        guard let gap = s.gap, max(abs(gap.x), abs(gap.y)) > onScreenDeg else {
            return ScanPrompt("Sweep slowly along the sun path.", symbol: "arrow.left.and.right")
        }
        let reason = "The \(s.questionName) passes there."
        if abs(gap.x) >= abs(gap.y) {
            return gap.x < 0 ? ScanPrompt("Turn left. \(reason)", symbol: "arrow.left")
                             : ScanPrompt("Turn right. \(reason)", symbol: "arrow.right")
        }
        return gap.y > 0 ? ScanPrompt("Tilt up. \(reason)", symbol: "arrow.up")
                         : ScanPrompt("Tilt down. \(reason)", symbol: "arrow.down")
    }
}

/// A live estimate of Δ (the true azimuth of the session's −Z axis) from the compass, for placing the sun path while
/// scanning. Same rule as the magnetic candidate in `SceneRecordBuilder`: `Δ = trueHeading − az_ar(camera)`. It is an
/// on-screen guide only; the record keeps every raw heading for NorthResolver (docs/05).
public struct LiveYaw: Sendable, Equatable {
    public struct Estimate: Sendable, Equatable {
        public let deltaDeg: Double
        /// max(median reported accuracy, spread of the readings), degrees.
        public let sigmaDeg: Double
        public let samples: Int
    }

    public static let capacity = 60
    /// Steeper than this the compass axis is ambiguous (the phone is looking at the sky or the floor).
    public static let maximumPitchDeg = 50.0

    private var yaws: [Double] = []
    private var accuracies: [Double] = []

    public init() {}

    public mutating func add(_ heading: HeadingSample, cameraAzimuthARDeg: Double, cameraPitchDeg: Double) {
        guard heading.isValid, abs(cameraPitchDeg) <= Self.maximumPitchDeg else { return }
        let yaw = (heading.trueHeading - cameraAzimuthARDeg).truncatingRemainder(dividingBy: 360)
        yaws.append(yaw < 0 ? yaw + 360 : yaw)
        accuracies.append(heading.headingAccuracy)
        if yaws.count > Self.capacity {
            yaws.removeFirst()
            accuracies.removeFirst()
        }
    }

    public var estimate: Estimate? {
        guard yaws.count >= 3 else { return nil }
        var sx = 0.0, sy = 0.0
        for y in yaws {
            sx += cos(y * .pi / 180)
            sy += sin(y * .pi / 180)
        }
        let n = Double(yaws.count)
        let r = min(1, (sx * sx + sy * sy).squareRoot() / n)
        var mean = atan2(sy, sx) * 180 / .pi
        if mean < 0 { mean += 360 }
        let spread = r > 0 ? (-2 * log(r)).squareRoot() * 180 / .pi : 180
        let median = accuracies.sorted()[accuracies.count / 2]
        return Estimate(deltaDeg: mean, sigmaDeg: max(median, spread), samples: yaws.count)
    }
}
