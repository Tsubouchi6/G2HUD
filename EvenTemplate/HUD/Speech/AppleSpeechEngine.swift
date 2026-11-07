// AppleSpeechEngine.swift
//
// SpeechEngine backed by Apple's on-device SpeechAnalyzer + SpeechTranscriber
// (iOS 26+). Free, offline, no API key. The language model is downloaded by
// iOS the first time a language is used.
//
// Public API:
//   AppleSpeechEngine()
//   start(languageId:onUpdate:onError:)      // see SpeechEngine
//   append(pcm16:)
//   stop()

import AVFoundation
import Speech

@MainActor
final class AppleSpeechEngine: SpeechEngine {

    // MARK: - State

    let displayName = "Apple (on-device)"

    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    /// Converts mic audio (16 kHz Int16) to the model's format. nil when the
    /// formats already match.
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var isRunning = false

    // MARK: - SpeechEngine

    func start(
        languageId: String,
        onUpdate: @escaping (SpeechUpdate) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        guard !isRunning else { return }
        try await Self.requestPermission()

        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: languageId)
        ) else {
            throw SpeechEngineError.unsupportedLanguage(languageId)
        }

        // progressiveTranscription = live, in-progress (volatile) results + fast results.
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

        // Download the language model the first time it's needed.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let modelFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        try prepareConverter(for: modelFormat)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let (sequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputBuilder = builder
        self.analyzer = analyzer

        resultsTask = Task { @MainActor in
            do {
                for try await result in transcriber.results {
                    onUpdate(SpeechUpdate(text: String(result.text.characters), isFinal: result.isFinal))
                }
            } catch {
                if !(error is CancellationError) { onError(error) }
            }
        }

        try await analyzer.start(inputSequence: sequence)
        isRunning = true
    }

    func append(pcm16: Data) {
        guard isRunning, let builder = inputBuilder,
              let micBuffer = PcmBuffers.makeBuffer(fromPcm16: pcm16)
        else { return }

        guard let converter, let analyzerFormat else {
            builder.yield(AnalyzerInput(buffer: micBuffer))
            return
        }
        if let converted = Self.convert(micBuffer, with: converter, to: analyzerFormat) {
            builder.yield(AnalyzerInput(buffer: converted))
        }
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false

        // End input, let the model finalize what it heard, then wait for the
        // results stream to close so the last phrase is delivered.
        inputBuilder?.finish()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            try? await analyzer?.cancelAndFinishNow()
        }
        await resultsTask?.value

        analyzer = nil
        inputBuilder = nil
        resultsTask = nil
        converter = nil
        analyzerFormat = nil
    }

    // MARK: - Audio conversion

    /// Picks the model's audio format and builds a converter from the mic format.
    private func prepareConverter(for modelFormat: AVAudioFormat?) throws {
        guard let modelFormat, let micFormat = PcmBuffers.micFormat else {
            throw SpeechEngineError.noAudioFormat
        }
        analyzerFormat = modelFormat
        if micFormat == modelFormat {
            converter = nil
            return
        }
        guard let converter = AVAudioConverter(from: micFormat, to: modelFormat) else {
            throw SpeechEngineError.noAudioFormat
        }
        self.converter = converter
    }

    /// Converts one buffer. The converter keeps its resampler state between
    /// calls, so chunks join seamlessly.
    private static func convert(
        _ input: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var handedOver = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if handedOver {
                inputStatus.pointee = .noDataNow
                return nil
            }
            handedOver = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, conversionError == nil, output.frameLength > 0 else { return nil }
        return output
    }

    // MARK: - Permission

    private static func requestPermission() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw SpeechEngineError.permissionDenied }
    }
}
