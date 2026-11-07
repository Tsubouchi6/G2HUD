// CaptionController.swift
//
// Live captions: G2 mic -> speech engine -> text on the lens.
// Turns the glasses mic on/off, feeds every mic frame to the active speech
// engine (and the raw recorder), keeps the transcript, and pushes the newest
// text to the glasses at a throttled rate.
//
// Public API:
//   CaptionController(session:)
//   @Published isRunning, isStarting: Bool
//   @Published phrases: [String]        // finished phrases, oldest first
//   @Published livePhrase: String       // in-progress phrase (may still change)
//   @Published errorMessage: String?
//   @Published languageId: String       // "ja-JP" / "en-US", saved between launches
//   engineName: String
//   recorder: RawAudioRecorder
//   start() async / stop() async / clearTranscript()

import Combine
import Foundation

@MainActor
final class CaptionController: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var phrases: [String] = []
    @Published private(set) var livePhrase = ""
    @Published private(set) var errorMessage: String?
    @Published var languageId: String {
        didSet { UserDefaults.standard.set(languageId, forKey: Self.languageDefaultsKey) }
    }

    let recorder = RawAudioRecorder()
    private(set) var engineName = "Apple (on-device)"

    // MARK: - Dependencies

    private static let languageDefaultsKey = "g2hud_caption_language"

    private let session: BluetoothSession
    private var engine: SpeechEngine?
    private var subscriptions = Set<AnyCancellable>()

    // Lens push throttling.
    private var pushTask: Task<Void, Never>?
    private var lastPushedText = ""
    private var lastPushDate = Date.distantPast

    // MARK: - Lifecycle

    init(session: BluetoothSession) {
        self.session = session
        languageId = UserDefaults.standard.string(forKey: Self.languageDefaultsKey)
            ?? HudConstants.defaultCaptionLanguageId
        session.micPcm
            .sink { [weak self] event in self?.handleMic(event.pcm) }
            .store(in: &subscriptions)
    }

    // MARK: - Start / stop

    /// Loads the speech model, turns on the glasses mic, and starts captions.
    func start() async {
        guard !isRunning, !isStarting else { return }
        errorMessage = nil

        // The glasses mic lives inside our display page, which the firmware
        // won't create while its own dashboard is showing.
        if session.sdk.glassesScreenOccupied {
            errorMessage = "The glasses dashboard is open. Look down or wait for it to close, then try again."
            return
        }
        isStarting = true
        defer { isStarting = false }

        let engine = AppleSpeechEngine()
        do {
            try await engine.start(
                languageId: languageId,
                onUpdate: { [weak self] update in self?.handleSpeech(update) },
                onError: { [weak self] error in self?.handleEngineFailure(error) }
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        self.engine = engine
        engineName = engine.displayName
        session.sdk.setMicState(enabled: true, useGlassesMic: true)
        isRunning = true
        pushNow()
    }

    /// Turns the mic off, lets the engine finish the last phrase, clears the lens.
    func stop() async {
        guard isRunning else { return }
        isRunning = false
        recorder.stop()
        session.sdk.setMicState(enabled: false)
        await engine?.stop()
        engine = nil
        if !livePhrase.isEmpty {
            appendPhrase(livePhrase)
            livePhrase = ""
        }
        pushTask?.cancel()
        pushTask = nil
        lastPushedText = ""
        let sdk = session.sdk
        Task { try? await sdk.clearDisplay() }
    }

    func clearTranscript() {
        phrases = []
        livePhrase = ""
        if isRunning { schedulePush() }
    }

    // MARK: - Input handling

    private func handleMic(_ pcm: Data) {
        guard isRunning else { return }
        engine?.append(pcm16: pcm)
        recorder.append(pcm16: pcm)
    }

    private func handleSpeech(_ update: SpeechUpdate) {
        if update.isFinal {
            appendPhrase(update.text)
            livePhrase = ""
        } else {
            livePhrase = update.text
        }
        schedulePush()
    }

    private func handleEngineFailure(_ error: Error) {
        errorMessage = "Speech engine stopped: \(error.localizedDescription)"
        Task { await stop() }
    }

    private func appendPhrase(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phrases.append(trimmed)
        if phrases.count > HudConstants.captionHistoryLimit {
            phrases.removeFirst(phrases.count - HudConstants.captionHistoryLimit)
        }
    }

    // MARK: - Lens output

    /// Newest phrases (one per line) that fit the lens; oldest dropped first.
    private func lensText() -> String {
        var lines = Array(phrases.suffix(20))
        if !livePhrase.isEmpty { lines.append(livePhrase) }
        guard !lines.isEmpty else { return "Listening..." }

        let limit = HudConstants.captionMaxCharsOnLens
        var text = lines.joined(separator: "\n")
        while text.count > limit, lines.count > 1 {
            lines.removeFirst()
            text = lines.joined(separator: "\n")
        }
        return text.count > limit ? String(text.suffix(limit)) : text
    }

    /// Pushes at most once per `captionPushIntervalMs`; extra calls in between
    /// are merged into the next push.
    private func schedulePush() {
        guard isRunning, pushTask == nil else { return }
        let elapsedMs = Int(Date().timeIntervalSince(lastPushDate) * 1000)
        let waitMs = max(0, HudConstants.captionPushIntervalMs - elapsedMs)
        pushTask = Task { [weak self] in
            if waitMs > 0 { try? await Task.sleep(nanoseconds: UInt64(waitMs) * 1_000_000) }
            guard let self, !Task.isCancelled else { return }
            self.pushTask = nil
            self.pushNow()
        }
    }

    private func pushNow() {
        guard isRunning else { return }
        let text = lensText()
        guard text != lastPushedText else { return }
        lastPushedText = text
        lastPushDate = Date()
        let sdk = session.sdk
        Task { try? await sdk.displayText(text) }
    }
}
