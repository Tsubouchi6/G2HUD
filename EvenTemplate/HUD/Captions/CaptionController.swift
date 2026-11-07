// CaptionController.swift
//
// Listening: turns the mic on/off, feeds every mic frame to the active speech
// engine (and the raw recorder), and keeps the transcript. It does not draw on
// the lens; CaptionsTab shows the transcript and VoiceCommandRouter reads
// finished phrases through `onFinalPhrase`.
//
// Public API:
//   CaptionController(session:settings:)
//   @Published isRunning, isStarting: Bool
//   @Published phrases: [String]        // finished phrases, oldest first
//   @Published livePhrase: String       // in-progress phrase (may still change)
//   @Published errorMessage: String?
//   @Published languageId: String       // "ja-JP" / "en-US", saved between launches
//   onFinalPhrase: ((String) -> Void)?
//   engineName: String
//   recorder: RawAudioRecorder
//   start() async / stop() async / clearTranscript()

import AVFoundation
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

    var onFinalPhrase: ((String) -> Void)?
    let recorder = RawAudioRecorder()
    private(set) var engineName = "Apple (on-device)"

    // MARK: - Dependencies

    private static let languageDefaultsKey = "g2hud_caption_language"

    private let session: BluetoothSession
    private let settings: HudSettings
    private var engine: SpeechEngine?
    private var subscriptions = Set<AnyCancellable>()

    // MARK: - Lifecycle

    init(session: BluetoothSession, settings: HudSettings) {
        self.session = session
        self.settings = settings
        languageId = UserDefaults.standard.string(forKey: Self.languageDefaultsKey)
            ?? HudConstants.defaultCaptionLanguageId
        session.micPcm
            .sink { [weak self] event in self?.handleMic(event.pcm) }
            .store(in: &subscriptions)
    }

    // MARK: - Start / stop

    /// Loads the speech model, turns on the mic, and starts listening.
    func start() async {
        guard !isRunning, !isStarting else { return }
        errorMessage = nil
        let useGlassesMic = !settings.usePhoneMic

        if useGlassesMic {
            // The glasses mic lives inside our display page, which the firmware
            // won't create while its own dashboard is showing.
            if session.sdk.glassesScreenOccupied {
                errorMessage = "The glasses dashboard is open. Look down or wait for it to close, then try again."
                return
            }
        } else if !(await AVAudioApplication.requestRecordPermission()) {
            errorMessage = "Microphone permission is needed for phone-mic mode."
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
        session.sdk.setMicState(enabled: true, useGlassesMic: useGlassesMic)
        isRunning = true
    }

    /// Turns the mic off and lets the engine finish the last phrase.
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
    }

    func clearTranscript() {
        phrases = []
        livePhrase = ""
    }

    // MARK: - Input handling

    private func handleMic(_ pcm: Data) {
        guard isRunning else { return }
        engine?.append(pcm16: pcm)
        recorder.append(pcm16: pcm)
    }

    private func handleSpeech(_ update: SpeechUpdate) {
        if update.isFinal {
            livePhrase = ""
            if let phrase = appendPhrase(update.text) {
                onFinalPhrase?(phrase)
            }
        } else {
            livePhrase = update.text
        }
    }

    private func handleEngineFailure(_ error: Error) {
        errorMessage = "Speech engine stopped: \(error.localizedDescription)"
        Task { await stop() }
    }

    /// Adds a finished phrase; returns it trimmed, or nil if it was empty.
    @discardableResult
    private func appendPhrase(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        phrases.append(trimmed)
        if phrases.count > HudConstants.captionHistoryLimit {
            phrases.removeFirst(phrases.count - HudConstants.captionHistoryLimit)
        }
        return trimmed
    }
}
