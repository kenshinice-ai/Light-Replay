import ARKit
import CaptureCore
import CoreLocation
import Foundation
import PropertyModel
import RealityKit
import SunEngine
import SwiftData
import SwiftUI
import simd

/// One day's sun path in the true-north frame, ready to be placed over the camera once Δ is known.
struct SunArc: Sendable {
    enum Emphasis: Sendable { case primary, context }
    let label: String
    let emphasis: Emphasis
    /// Every 10 minutes while the sun is up.
    let samples: [SunSample]
    /// Samples that get a dot and a clock label (every third hour).
    let hourMarks: [(index: Int, text: String)]
}

/// What the overlay draws this frame, in view points. Kept apart from the model so 60 Hz updates only redraw the Canvas.
@MainActor
@Observable
final class SunPathOverlayState {
    struct Point {
        let screen: CGPoint?
        /// The camera has looked at this part of the path.
        let lit: Bool
    }

    struct Line {
        let points: [Point]
        let emphasis: SunArc.Emphasis
        let label: String
    }

    struct Mark {
        let screen: CGPoint
        let text: String
        let lit: Bool
    }

    var lines: [Line] = []
    var marks: [Mark] = []
    var sunNow: CGPoint?
    /// The horizon, for the simulator's painted sky only.
    var horizon: [CGPoint?] = []
}

struct LightScanResult: Equatable, Identifiable {
    let id = UUID()
    /// Share of the question's sun path the camera pointed at. Not a measure of sky or sunlight (review U06).
    var coveragePct: Int
    /// "winter sun" or "all-year sun".
    var questionName: String
    var direction: String
    var place: String
    /// Set when the record is safe on disk but not yet on the property.
    var pendingNote: String?
    var failure: String?
    /// True when the failed scan is still in memory and saving it can be tried again without rescanning (review U22).
    var canRetrySave = false

    /// What the saved observation says about itself.
    var note: String { "Light scan · camera covered \(coveragePct)% of the \(questionName) path · sunlight not calculated" }
}

/// The Light scan (docs/04 OneTake): camera, the question's sun path over it, one instruction at a time, and a record
/// saved to the property. It guides and records; it does not compute sunlight hours (that needs sky analysis, R1).
@MainActor
@Observable
final class LightScanModel {
    enum Phase: Equatable {
        case ready
        case scanning
        case saving
        case saved(LightScanResult)
        case unsupported(String)
    }

    static let targetCoverage = 0.9

    let property: Property?
    let roomLabel: String?
    /// True in the simulator (DEBUG): a scripted sweep stands in for ARKit so the flow can be seen and tested.
    let isSimulated: Bool
    var question: LightQuestion = .winter {
        didSet { if oldValue != question { prepareSun() } }
    }
    var toleranceM = 0.15
    var targetHeightM: Double?

    private(set) var phase: Phase
    private(set) var prompt = ScanCoach.prompt(for: ScanStatus())
    private(set) var coverage = 0.0
    private(set) var reachedTarget = false
    private(set) var anchorLocked = false
    /// Lens offset from the anchor in units of the tolerance: x to the right, y towards the top of the screen.
    private(set) var driftDot = CGPoint.zero
    private(set) var driftExceeded = false
    private(set) var directionText = "Finding north…"
    let overlay = SunPathOverlayState()

    /// Created in `appear()`, not in `init`: SwiftUI may build this model more than once while the view is being
    /// declared, and an ARSession plus a location manager per throwaway copy would be waste.
    private(set) var recorder: CaptureRecorder?
    @ObservationIgnored weak var arView: ARView?
    @ObservationIgnored var viewSize: CGSize = .zero
    @ObservationIgnored private var status = ScanStatus()
    @ObservationIgnored private var sweep = SkySweep()
    @ObservationIgnored private var progress: CorridorProgress?
    @ObservationIgnored private var arcs: [SunArc] = []
    @ObservationIgnored private var sunNow: SunPosition?
    @ObservationIgnored private var liveYaw = LiveYaw()
    @ObservationIgnored private var fixedYaw: Double?
    @ObservationIgnored private var lastHeadingAt: Date?
    @ObservationIgnored private var lastForward: SIMD3<Double>?
    @ObservationIgnored private var lastFrameTime: TimeInterval?
    @ObservationIgnored private var lastCamera: PinholeCamera?
    @ObservationIgnored private var lastSweepTime: TimeInterval = -1
    @ObservationIgnored private var lastStatusTime: TimeInterval = -1
    @ObservationIgnored private var coordinate: CLLocationCoordinate2D?
    @ObservationIgnored private var sunTask: Task<Void, Never>?
    @ObservationIgnored private var pendingCapture: PendingCapture?
    /// A finished scan whose save failed; kept so it can be saved again instead of scanned again.
    @ObservationIgnored private var unsavedLog: CaptureLog?
    #if DEBUG
    @ObservationIgnored private var synthetic: SyntheticSweep?
    @ObservationIgnored private var syntheticTask: Task<Void, Never>?
    @ObservationIgnored private var syntheticOpened = Date()
    #endif

    init(property: Property?, roomLabel: String?) {
        self.property = property
        self.roomLabel = roomLabel
        coordinate = property?.coordinate
        if ARWorldTrackingConfiguration.isSupported {
            isSimulated = false
            phase = .ready
        } else {
            #if DEBUG
            isSimulated = true
            phase = .ready
            #else
            isSimulated = false
            phase = .unsupported("Light scan needs an iPhone or iPad with ARKit world tracking.")
            #endif
        }
    }

    /// The session the camera view shows (nil in the simulator).
    var arSession: ARSession? { recorder?.arSession }

    // MARK: - Lifecycle

    func appear() {
        if recorder == nil, !isSimulated, ARWorldTrackingConfiguration.isSupported { recorder = CaptureRecorder() }
        if let recorder {
            recorder.viewpointToleranceM = toleranceM
            recorder.frameObserver = { [weak self] frame in self?.handle(frame) }
            recorder.startPreview()
        }
        #if DEBUG
        if isSimulated {
            if coordinate == nil { coordinate = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631) }   // simulator only
            startSynthetic()
        }
        #endif
        prepareSun()
    }

    func disappear() {
        recorder?.frameObserver = nil
        recorder?.endPreview()
        sunTask?.cancel()
        #if DEBUG
        syntheticTask?.cancel()
        #endif
    }

    func start() {
        guard phase == .ready else { return }
        sweep = SkySweep()
        coverage = 0
        reachedTarget = false
        recorder?.viewpointToleranceM = toleranceM
        recorder?.start()
        #if DEBUG
        synthetic?.beginRecording(at: Date().timeIntervalSince(syntheticOpened))
        #endif
        phase = .scanning
        status.isRecording = true
        refreshStatus()
        #if DEBUG
        runSynthetic()
        #endif
    }

    /// Back to the camera after a result, keeping the question.
    func scanAgain() {
        guard case .saved = phase else { return }
        phase = .ready
        unsavedLog = nil
        coverage = 0
        reachedTarget = false
        status = ScanStatus()
        status.pathReady = progress != nil
        anchorLocked = false
        driftDot = .zero
        // A new session resets the AR world frame, so the old Δ and everything measured against it no longer apply.
        if !isSimulated {
            liveYaw = LiveYaw()
            lastHeadingAt = nil
        }
        sweep = SkySweep()
        lastForward = nil
        lastFrameTime = nil
        recorder?.startPreview()
        #if DEBUG
        synthetic?.reset()
        runSynthetic()
        #endif
        refreshStatus()
    }

    /// Stops the scan without keeping anything.
    func discard() {
        _ = recorder?.stop()
        #if DEBUG
        synthetic?.reset()
        #endif
        phase = .ready
    }

    func save(in context: ModelContext) {
        guard phase == .scanning else { return }
        phase = .saving
        let place = property.map { "\($0.shortAddress)\(roomLabel.map { " · \($0)" } ?? "")" } ?? "Unbound scan"
        var log = recorder?.stop(targetLabel: place, targetHeightM: targetHeightM)
        #if DEBUG
        if isSimulated, let coordinate {
            log = synthetic?.makeLog(label: "Synthetic scan (simulator) · \(place)", coordinate: coordinate, targetHeightM: targetHeightM)
            synthetic?.reset()
        }
        #endif
        var result = LightScanResult(coveragePct: Int((coverage * 100).rounded()), questionName: question.title.lowercased(),
                                     direction: directionText, place: place)
        guard let log else {
            result.failure = "Nothing was recorded. Try the scan again."
            phase = .saved(result)
            return
        }
        unsavedLog = log
        persist(log, result: result, in: context)
    }

    /// Saves the scan that failed to save, without scanning again.
    func retrySave(in context: ModelContext) {
        guard let log = unsavedLog, case .saved(let result) = phase else { return }
        persist(log, result: result, in: context)
    }

    private func persist(_ log: CaptureLog, result: LightScanResult, in context: ModelContext) {
        var result = result
        result.failure = nil
        result.canRetrySave = false
        result.pendingNote = nil
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-failFirstLightSave"), !Self.failedOnce {
                Self.failedOnce = true
                throw CocoaError(.fileWriteOutOfSpace)   // UI tests: the first save fails, the retry succeeds
            }
            #endif
            let outcome = try LightCaptureSaver.save(log, property: property, roomLabel: roomLabel, note: result.note, in: context)
            unsavedLog = nil
            pendingCapture = outcome.pending
            if let error = outcome.attachError {
                result.pendingNote = "Couldn't add it to the property yet (\(error)). It's kept on this device and is added the next time the app opens."
            }
        } catch {
            result.failure = "Couldn't save the scan: \(error.localizedDescription)"
            result.canRetrySave = true
        }
        phase = .saved(result)
    }

    #if DEBUG
    private static var failedOnce = false
    #endif

    func retryAttach(in context: ModelContext) {
        guard let capture = pendingCapture, let property, case .saved(var result) = phase else { return }
        do {
            try LightCaptureSaver.attach(capture, to: property, in: context)
            pendingCapture = nil
            result.pendingNote = nil
        } catch {
            result.pendingNote = "Still couldn't add it (\(error.localizedDescription)). It stays on this device and is added next launch."
        }
        phase = .saved(result)
    }

    // MARK: - Sun

    private func prepareSun() {
        // Until the new question's path exists nothing may look covered or done (review U23).
        progress = nil
        arcs = []
        status.pathReady = false
        refreshStatus()
        guard let coordinate else { return }
        let question = question, lat = coordinate.latitude, lon = coordinate.longitude
        sunTask?.cancel()
        sunTask = Task { [weak self] in
            let built = await Task.detached(priority: .userInitiated) {
                LightScanModel.buildSun(question: question, latitude: lat, longitude: lon, timeZone: .current, now: Date())
            }.value
            guard !Task.isCancelled, let self, self.question == question else { return }
            self.progress = built.progress
            self.arcs = built.arcs
            self.sunNow = built.sunNow
            self.status.pathReady = true
            self.refreshStatus()
            #if DEBUG
            if self.isSimulated { self.syntheticTick(Date().timeIntervalSince(self.syntheticOpened)) }
            #endif
        }
    }

    nonisolated static func buildSun(question: LightQuestion, latitude: Double, longitude: Double, timeZone: TimeZone,
                                     now: Date) -> (progress: CorridorProgress, arcs: [SunArc], sunNow: SunPosition?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let year = calendar.component(.year, from: now)
        let corridor = SunCorridor(days: question.corridorDays(year: year, latitude: latitude, timeZone: timeZone),
                                   latitude: latitude, longitude: longitude, timeZone: timeZone, yawDeg: 0)
        let winter = LightQuestion.winterSolstice(year: year, latitude: latitude)
        let summer = LightQuestion.summerSolstice(year: year, latitude: latitude)
        let equinox = LocalDay(year: year, month: 3, day: 20)
        let hourStyle = Date.FormatStyle(timeZone: timeZone).hour(.defaultDigits(amPM: .abbreviated))
        let dayStyle = Date.FormatStyle(timeZone: timeZone).day().month(.abbreviated)
        let arcs = [winter, equinox, summer].map { day -> SunArc in
            let samples = SunSampler.samples(on: day, latitude: latitude, longitude: longitude, timeZone: timeZone, stepMinutes: 10)
            let marks = samples.enumerated().compactMap { index, sample -> (index: Int, text: String)? in
                let c = calendar.dateComponents([.hour, .minute], from: sample.date)
                guard c.minute == 0, let hour = c.hour, hour % 3 == 0 else { return nil }
                return (index, sample.date.formatted(hourStyle))
            }
            let emphasis: SunArc.Emphasis = question == .allYear || day == winter ? .primary : .context
            return SunArc(label: day.interval(in: timeZone).start.formatted(dayStyle), emphasis: emphasis, samples: samples, hourMarks: marks)
        }
        let current = SolarPosition.compute(at: now, latitude: latitude, longitude: longitude)
        return (CorridorProgress(corridor: corridor), arcs, current.elevationDeg > 0 ? current : nil)
    }

    private var currentYaw: Double? { fixedYaw ?? liveYaw.estimate?.deltaDeg }

    // MARK: - Frames

    private func handle(_ frame: ARFrame) {
        let t = frame.camera.transform
        func v3(_ c: SIMD4<Float>) -> SIMD3<Double> { SIMD3(Double(c.x), Double(c.y), Double(c.z)) }
        let k = frame.camera.intrinsics
        let camera = PinholeCamera(rotation: simd_double3x3(columns: (v3(t.columns.0), v3(t.columns.1), v3(t.columns.2))),
                                   fx: Double(k[0][0]), fy: Double(k[1][1]), cx: Double(k[2][0]), cy: Double(k[2][1]),
                                   imageWidth: Double(frame.camera.imageResolution.width),
                                   imageHeight: Double(frame.camera.imageResolution.height))
        let position = v3(t.columns.3)
        let normal: Bool
        if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
        guard let recorder else { return }
        if coordinate == nil, let fix = recorder.location {
            coordinate = CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
            prepareSun()
        }
        if normal, let heading = recorder.latestHeading, heading.sampledAt != lastHeadingAt {
            lastHeadingAt = heading.sampledAt
            let angles = SkyDirection.angles(of: camera.forward)
            liveYaw.add(heading, cameraAzimuthARDeg: angles.azimuthDeg, cameraPitchDeg: angles.altitudeDeg)
        }
        step(camera: camera, time: frame.timestamp, trackingState: recorder.trackingState,
             offset: recorder.currentOffset, anchorLocked: recorder.anchorLocked, recording: recorder.isRunning) { [weak self] direction in
            guard let view = self?.arView else { return nil }
            let p = position + direction * 30
            return view.project(SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)))
        }
    }

    /// Shared by the device and the simulator: coverage, overlay and guidance for one frame.
    private func step(camera: PinholeCamera, time: TimeInterval, trackingState: String, offset: SIMD3<Double>?,
                      anchorLocked locked: Bool, recording: Bool, project: (SIMD3<Double>) -> CGPoint?) {
        let forward = camera.forward
        if let last = lastForward, let lastTime = lastFrameTime, time > lastTime {
            let angle = acos(max(-1, min(1, simd_dot(last, forward)))) * 180 / .pi
            status.turnRateDegPerSec = 0.8 * status.turnRateDegPerSec + 0.2 * angle / (time - lastTime)
        }
        lastForward = forward
        lastFrameTime = time
        lastCamera = camera
        status.trackingState = trackingState
        status.isRecording = recording && phase == .scanning
        status.anchorLocked = locked
        status.driftM = offset.map { simd_length($0) }

        if status.isRecording, trackingState == "normal", (status.driftM ?? 0) <= toleranceM,
           status.turnRateDegPerSec <= ScanCoach.fastTurnDegPerSec, time - lastSweepTime >= 0.1 {
            lastSweepTime = time
            sweep.add(camera)
        }
        drawOverlay(camera: camera, project: project)

        if time - lastStatusTime >= 0.12 {
            lastStatusTime = time
            if anchorLocked != locked { anchorLocked = locked }
            updateDriftDot(offset: offset, forward: forward)
            refreshStatus()
        }
    }

    private func updateDriftDot(offset: SIMD3<Double>?, forward: SIMD3<Double>) {
        guard let offset, toleranceM > 0 else {
            if driftDot != .zero { driftDot = .zero }
            return
        }
        let horizontal = SIMD3(forward.x, 0, forward.z)
        guard simd_length(horizontal) > 1e-6 else { return }
        let ahead = simd_normalize(horizontal)
        let right = simd_cross(ahead, SIMD3(0, 1, 0))
        driftDot = CGPoint(x: simd_dot(offset, right) / toleranceM, y: -simd_dot(offset, ahead) / toleranceM)
        let exceeded = simd_length(offset) > toleranceM
        if exceeded != driftExceeded { driftExceeded = exceeded }
    }

    private func drawOverlay(camera: PinholeCamera, project: (SIMD3<Double>) -> CGPoint?) {
        guard let yaw = currentYaw, !arcs.isEmpty else {
            if !overlay.lines.isEmpty { overlay.lines = []; overlay.marks = []; overlay.sunNow = nil }
            return
        }
        func place(_ p: SunPosition) -> (screen: CGPoint?, lit: Bool) {
            let azAR = p.azimuthDeg - yaw
            let d = SkyDirection.vector(azimuthDeg: azAR, altitudeDeg: p.elevationDeg)
            let screen = camera.pixel(of: d) == nil ? nil : project(d)
            return (screen, sweep.isSeen(azimuthDeg: azAR, altitudeDeg: p.elevationDeg))
        }
        var lines: [SunPathOverlayState.Line] = []
        var marks: [SunPathOverlayState.Mark] = []
        for arc in arcs {
            let points = arc.samples.map { sample -> SunPathOverlayState.Point in
                let placed = place(sample.position)
                return .init(screen: placed.screen, lit: placed.lit)
            }
            lines.append(.init(points: points, emphasis: arc.emphasis, label: arc.label))
            guard arc.emphasis == .primary else { continue }
            for mark in arc.hourMarks {
                if let screen = points[mark.index].screen {
                    marks.append(.init(screen: screen, text: mark.text, lit: points[mark.index].lit))
                }
            }
        }
        overlay.lines = lines
        overlay.marks = marks
        overlay.sunNow = sunNow.flatMap { place($0).screen }
    }

    private func refreshStatus() {
        var s = status
        s.toleranceM = toleranceM
        s.targetCoverage = Self.targetCoverage
        s.questionName = question.title.lowercased()
        s.directionKnown = currentYaw != nil
        s.locationKnown = coordinate != nil
        s.coverage = 0
        s.gap = nil
        if let progress, let yaw = currentYaw {
            s.coverage = progress.coverage(of: sweep, yawDeg: yaw)
            if let camera = lastCamera {
                let a = SkyDirection.angles(of: camera.forward)
                s.gap = progress.nearestGap(from: a.azimuthDeg, altitudeDeg: a.altitudeDeg, sweep: sweep, yawDeg: yaw)
            }
        }
        status = s
        let next = ScanCoach.prompt(for: s)
        if next != prompt { prompt = next }
        if abs(s.coverage - coverage) >= 0.005 || (s.coverage == 0 && coverage != 0) { coverage = s.coverage }
        // Recomputed every time, so switching question (or a better Δ) can take "covered" away again (review U23).
        let reached = phase == .scanning && s.pathReady && s.coverage >= Self.targetCoverage
        if reached != reachedTarget { reachedTarget = reached }
        let text: String
        if fixedYaw != nil {
            text = "Simulated north"
        } else if let estimate = liveYaw.estimate {
            text = "Compass ±\(Int(estimate.sigmaDeg.rounded()))°"
        } else {
            text = "Finding north…"
        }
        if text != directionText { directionText = text }
    }

    // MARK: - Simulator

    #if DEBUG
    private func startSynthetic() {
        synthetic = SyntheticSweep()
        fixedYaw = 0
        syntheticOpened = Date()
        runSynthetic()
    }

    /// Ticks at 30 Hz only while the pretend camera moves, then stops, so the app goes idle (UI tests wait for idle).
    private func runSynthetic() {
        syntheticTask?.cancel()
        syntheticTask = Task { [weak self] in
            var rendered = false
            while !Task.isCancelled, let self {
                let t = Date().timeIntervalSince(self.syntheticOpened)
                if self.syntheticTick(t) { rendered = true }
                if rendered, self.synthetic?.isFinished(at: t) ?? true { break }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    /// Returns false while there is no view to draw into yet.
    @discardableResult
    private func syntheticTick(_ t: TimeInterval) -> Bool {
        guard var sweeper = synthetic, viewSize.width > 0, viewSize.height > 0 else { return false }
        let pose = sweeper.pose(at: t)
        let camera = SyntheticSweep.camera(azimuthDeg: pose.az, altitudeDeg: pose.alt, viewSize: viewSize)
        let recording = phase == .scanning
        if recording { sweeper.record(camera, at: t) }
        synthetic = sweeper
        step(camera: camera, time: t, trackingState: "normal", offset: recording ? .zero : nil,
             anchorLocked: recording, recording: recording) { direction in
            camera.pixel(of: direction).map { CGPoint(x: $0.x, y: $0.y) }
        }
        overlay.horizon = stride(from: 0.0, through: 360.0, by: 4).map { az in
            camera.pixel(of: SkyDirection.vector(azimuthDeg: az, altitudeDeg: 0)).map { CGPoint(x: $0.x, y: $0.y) }
        }
        return true
    }
    #endif
}
