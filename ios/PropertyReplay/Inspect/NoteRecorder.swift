@preconcurrency import AVFoundation
import Foundation
import Speech

/// Push-to-talk transcription with the on-device SpeechAnalyzer (ADR-0015): audio is never written to disk,
/// only the transcript survives. One recording at a time.
///
/// Every press is a generation (reaudit R05). A start() owns the audio resources it creates until it hands them to
/// `live`; after each await it checks it is still current, and a superseded start() releases only its own resources
/// and never writes `state` or `transcript`. Results from an older generation are dropped.
@MainActor
final class NoteRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case recording
        case finishing
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    /// The supported locale actually in use for the current note, for the status bubble.
    @Published private(set) var activeLocaleName: String?
    /// Preferred transcription language (UserPreferences.noteLanguage); nil follows the phone.
    var preferredLanguage: String?

    /// True between press and release. Preparation can outlive a short press; when it finishes we honour this.
    private var pressActive = false
    /// Bumped by every start() and stop().
    private var generation = 0
    /// The generation whose transcript is on screen; results from any other generation are ignored.
    private var transcriptOwner = 0
    /// The recording in progress, owned by the generation that started it.
    private var live: Session?

    var isRecording: Bool { state == .recording || state == .preparing }

    func start() async {
        pressActive = true
        switch state {
        case .idle, .unavailable: break
        default: return
        }
        generation += 1
        let mine = generation
        transcriptOwner = mine
        state = .preparing
        transcript = ""
        activeLocaleName = nil
        func current() -> Bool { mine == generation && pressActive }
        /// State is only ever written by the current generation.
        func finish(_ newState: State) { if mine == generation { state = newState } }

        guard await AVAudioApplication.requestRecordPermission() else {
            return finish(.unavailable(String(localized: "Microphone access is off. Enable it in Settings to dictate notes.")))
        }
        guard current() else { return finish(.idle) }
        guard let locale = await NoteLanguages.resolve(preferredLanguage) else {
            let wanted = preferredLanguage ?? Locale.current.identifier
            return finish(.unavailable(String(localized: "On-device transcription does not support \(wanted) on this phone. Pick another note language in You › Preferences.")))
        }
        guard current() else { return finish(.idle) }
        activeLocaleName = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            return finish(.unavailable(String(localized: "Speech model is not installed: \(error.localizedDescription)")))
        }
        guard current() else { return finish(.idle) }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            return finish(.unavailable(String(localized: "No compatible audio format for transcription.")))
        }
        guard current() else { return finish(.idle) }

        let session = Session(generation: mine, analyzer: SpeechAnalyzer(modules: [transcriber]))
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        session.continuation = continuation
        session.resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    await MainActor.run { if self?.transcriptOwner == mine { self?.transcript = text } }
                }
            } catch {
                await MainActor.run {
                    guard let self, self.transcriptOwner == mine, self.generation == mine else { return }
                    self.state = .unavailable(String(localized: "Transcription stopped: \(error.localizedDescription)"))
                }
            }
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: [])
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            let converter = BufferConverter(from: inputFormat, to: format)
            // @Sendable: the tap runs on the audio thread; an actor-isolated closure would trap there (device crash 2026-09-30).
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, _ in
                guard let converted = converter.convert(buffer) else { return }
                continuation.yield(AnalyzerInput(buffer: converted))
            }
            engine.prepare()
            try engine.start()
            session.engine = engine
            try await session.analyzer.start(inputSequence: stream)
        } catch {
            await release(session)
            return finish(.unavailable(String(localized: "Could not start the microphone: \(error.localizedDescription)")))
        }
        guard current() else {                       // released or superseded while preparing
            await release(session)
            return finish(.idle)
        }
        live = session
        state = .recording
    }

    /// Ends the note and returns the final transcript. Also used when leaving the screen or going to the background.
    func stop() async -> String {
        pressActive = false
        generation += 1
        let stopping = generation
        switch state {
        case .recording:
            state = .finishing
            if let session = live {
                live = nil
                await release(session)            // drains the analyzer; the owner's last results still land
            }
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if generation == stopping { state = .idle }
            return text
        case .preparing:
            state = .idle                         // the in-flight start() sees it is stale and releases its own session
            return ""
        default:
            return transcript
        }
    }

    /// Stops one session's audio and analyzer. The shared audio session is deactivated only when nothing else is
    /// recording or preparing, so releasing a stale session never silences a newer one.
    private func release(_ session: Session) async {
        await session.shutdown()
        if live == nil && state != .preparing {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    /// Audio engine, analyzer and results task that belong to one generation.
    @MainActor
    private final class Session {
        let generation: Int
        let analyzer: SpeechAnalyzer
        var engine: AVAudioEngine?
        var continuation: AsyncStream<AnalyzerInput>.Continuation?
        var resultsTask: Task<Void, Never>?

        init(generation: Int, analyzer: SpeechAnalyzer) {
            self.generation = generation
            self.analyzer = analyzer
        }

        /// Safe to call twice.
        func shutdown() async {
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            engine = nil
            continuation?.finish()
            continuation = nil
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
            resultsTask?.cancel()
            resultsTask = nil
        }
    }
}

/// Converts microphone buffers to the analyzer's format on the audio thread.
private final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let target: AVAudioFormat

    init(from source: AVAudioFormat, to target: AVAudioFormat) {
        self.target = target
        converter = source == target ? nil : AVAudioConverter(from: source, to: target)
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : output
    }
}
