import Foundation
import NorthResolver
import SceneRecord
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
    /// False while the question's sun path is still being worked out (first load, or after switching question).
    public var pathReady = true
    /// False until there is a place to compute the sun for (the property's pin or a location fix).
    public var locationKnown = true
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

/// Picks the single most useful instruction. Order: tracking, viewpoint, speed, sun path, direction, then coverage —
/// each earlier problem would make the later advice pointless.
public enum ScanCoach {
    /// Faster than this the frames blur and the anchor drifts (candidate, docs/04 §4).
    public static let fastTurnDegPerSec = 60.0
    /// A frame taken further than this from the viewpoint cannot go into the result (docs/04 §4), so it does not
    /// count as looking either. Between the tolerance and this the frame counts and the buyer is asked back.
    public static let driftLimitM = QualityEvaluator.driftLimitM
    /// A gap closer than this to the centre of view is already on screen; no arrow needed.
    public static let onScreenDeg = 12.0

    public static func prompt(for s: ScanStatus) -> ScanPrompt {
        guard s.isRecording else {
            return ScanPrompt(String(localized: "Stand where you'd sit. Hold the phone at eye height, then tap Start.", bundle: .module), symbol: "figure.stand")
        }
        switch s.trackingState {
        case "normal": break
        case "limited:excessive_motion":
            return ScanPrompt(String(localized: "Slow down.", bundle: .module), symbol: "tortoise", tone: .caution)
        case "limited:insufficient_features":
            return ScanPrompt(String(localized: "Point at the room for a moment, not a blank wall.", bundle: .module), symbol: "viewfinder", tone: .caution)
        case "not_available":
            return ScanPrompt(String(localized: "Starting the camera…", bundle: .module), symbol: "camera", tone: .caution)
        default:
            return ScanPrompt(String(localized: "Hold still for a moment.", bundle: .module), symbol: "hand.raised", tone: .caution)
        }
        guard s.anchorLocked else {
            return ScanPrompt(String(localized: "Hold still for a moment.", bundle: .module), symbol: "hand.raised", tone: .caution)
        }
        if let drift = s.driftM, drift > s.toleranceM {
            return ScanPrompt(String(localized: "Move back to where you started. Keep the dot in the circle.", bundle: .module), symbol: "arrow.uturn.backward", tone: .caution)
        }
        if s.turnRateDegPerSec > fastTurnDegPerSec {
            return ScanPrompt(String(localized: "Slower. Let the camera see the sky.", bundle: .module), symbol: "tortoise", tone: .caution)
        }
        guard s.locationKnown else {
            return ScanPrompt(String(localized: "Finding where you are, to place the sun…", bundle: .module), symbol: "location")
        }
        guard s.pathReady else {
            return ScanPrompt(String(localized: "Working out the sun path…", bundle: .module), symbol: "sun.max")
        }
        guard s.directionKnown else {
            return ScanPrompt(String(localized: "Finding north. Aim the phone level for a moment.", bundle: .module), symbol: "location.north.line")
        }
        if s.coverage >= s.targetCoverage {
            // "Covered" is about where the camera looked, not about what it saw there (review U06).
            return ScanPrompt(String(localized: "Sun path covered. Tap Save.", bundle: .module), symbol: "checkmark.circle.fill", tone: .done)
        }
        guard let gap = s.gap, max(abs(gap.x), abs(gap.y)) > onScreenDeg else {
            return ScanPrompt(String(localized: "Sweep slowly along the sun path.", bundle: .module), symbol: "arrow.left.and.right")
        }
        let reason = String(localized: "The \(s.questionName) passes there.", bundle: .module)
        if abs(gap.x) >= abs(gap.y) {
            return gap.x < 0 ? ScanPrompt(String(localized: "Turn left. \(reason)", bundle: .module), symbol: "arrow.left")
                             : ScanPrompt(String(localized: "Turn right. \(reason)", bundle: .module), symbol: "arrow.right")
        }
        return gap.y > 0 ? ScanPrompt(String(localized: "Tilt up. \(reason)", bundle: .module), symbol: "arrow.up")
                         : ScanPrompt(String(localized: "Tilt down. \(reason)", bundle: .module), symbol: "arrow.down")
    }
}

/// A live estimate of Δ (the true azimuth of the session's −Z axis) from the compass, for placing the sun path while
/// scanning. Same rule as the magnetic candidate in `SceneRecordBuilder`: `Δ = trueHeading − az_ar(camera)`, merged
/// over every usable reading of the session so far. It is an on-screen guide only; the record keeps every raw heading
/// for NorthResolver (docs/05).
///
/// The whole session, not a recent window: a window follows whatever the compass did last, and the sun path slid
/// across the sky by 56–204° inside single scans (PR-20261005-01…09, docs/spike/2026-10-05-scan-coverage.md).
public struct LiveYaw: Sendable, Equatable {
    public struct Estimate: Sendable, Equatable {
        public let deltaDeg: Double
        /// max(median reported accuracy, spread of the readings), degrees.
        public let sigmaDeg: Double
        public let samples: Int
    }

    /// Steeper than this the reading is not about the camera's direction any more: Core Location switches the heading
    /// to the device's top edge, which points behind a camera aimed at the sky. Measured on an iPhone 17 Pro: flipped
    /// by about 180° in 20–75% of readings at 40–50° and in nearly all above 50°, in a few at 30–40°, in none below
    /// (same field note).
    public static let maximumPitchDeg = 30.0
    /// Beyond this many readings every second one is dropped, oldest to newest alike.
    public static let capacity = 2400

    private var yaws: [Double] = []
    private var accuracies: [Double] = []
    public private(set) var estimate: Estimate?

    public init() {}

    public mutating func add(_ heading: HeadingSample, cameraAzimuthARDeg: Double, cameraPitchDeg: Double) {
        guard heading.isValid, abs(cameraPitchDeg) <= Self.maximumPitchDeg else { return }
        yaws.append(NorthResolver.mod360(heading.trueHeading - cameraAzimuthARDeg))
        accuracies.append(heading.headingAccuracy)
        if yaws.count > Self.capacity {
            yaws = stride(from: 0, to: yaws.count, by: 2).map { yaws[$0] }
            accuracies = stride(from: 0, to: accuracies.count, by: 2).map { accuracies[$0] }
        }
        guard yaws.count >= 3 else { return }
        let merged = NorthResolver.merge(zip(yaws, accuracies).map { (yawDeg: $0, sigmaDeg: $1) })
        estimate = Estimate(deltaDeg: merged.yawDeg, sigmaDeg: merged.sigmaDeg, samples: yaws.count)
    }
}
