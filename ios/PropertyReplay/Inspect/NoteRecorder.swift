@preconcurrency import AVFoundation
import Foundation
import Speech

/// Push-to-talk transcription with the on-device SpeechAnalyzer (ADR-0015): audio is never written to disk,
/// only the transcript survives. One recording at a time.
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
    /// True between press and release. Preparation can outlive a short press; when it finishes we honour this.
    private var pressActive = false
    /// Bumped by every start() and stop(); an in-flight start() abandons itself when it is no longer current.
    private var generation = 0

    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    var isRecording: Bool { state == .recording || state == .preparing }

    /// Preferred transcription language (UserPreferences.noteLanguage); nil follows the phone.
    var preferredLanguage: String?
    /// The supported locale actually in use for the current note, for the status bubble.
    @Published private(set) var activeLocaleName: String?

    func start() async {
        pressActive = true
        switch state {
        case .idle, .unavailable: break
        default: return
        }
        generation += 1
        let mine = generation
        state = .preparing
        transcript = ""
        /// After every await: bail out if the finger lifted or another start()/stop() superseded us.
        func stillWanted() -> Bool { mine == generation && pressActive }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .unavailable("Microphone access is off. Enable it in Settings to dictate notes.")
            return
        }
        guard stillWanted() else { state = .idle; return }
        guard let locale = await NoteLanguages.resolve(preferredLanguage) else {
            let wanted = preferredLanguage ?? Locale.current.identifier
            state = .unavailable("On-device transcription does not support \(wanted) on this phone. Pick another note language in You › Preferences.")
            return
        }
        activeLocaleName = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        guard stillWanted() else { state = .idle; return }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            state = .unavailable("Speech model is not installed: \(error.localizedDescription)")
            return
        }
        guard stillWanted() else { state = .idle; return }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            state = .unavailable("No compatible audio format for transcription.")
            return
        }
        guard stillWanted() else { state = .idle; return }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.inputContinuation = continuation

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    await MainActor.run { self?.transcript = text }
                }
            } catch {
                await MainActor.run { self?.state = .unavailable("Transcription stopped: \(error.localizedDescription)") }
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
            self.engine = engine
            try await analyzer.start(inputSequence: stream)
            guard stillWanted() else { await shutdown(); state = .idle; return }   // released while preparing
            state = .recording
        } catch {
            teardownAudio()
            state = .unavailable("Could not start the microphone: \(error.localizedDescription)")
        }
    }

    /// Returns the final transcript.
    func stop() async -> String {
        pressActive = false
        generation += 1
        switch state {
        case .recording:
            state = .finishing
            await shutdown()
            state = .idle
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        case .preparing:
            state = .idle          // the in-flight start() sees the new generation and cleans up after itself
            return ""
        default:
            return transcript
        }
    }

    /// Stops audio, drains the analyzer, releases everything. Safe to call twice.
    private func shutdown() async {
        teardownAudio()
        inputContinuation?.finish()
        inputContinuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
    }

    private func teardownAudio() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
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
