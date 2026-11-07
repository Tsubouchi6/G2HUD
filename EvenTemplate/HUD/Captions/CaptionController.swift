// CaptionController.swift
//
// Listening: turns the mic on/off, feeds every mic frame to the active speech
// engine (in settings.hearingLanguage, plus the HUD language when auto is on —
// DualSpeechEngine keeps whichever fits each sentence; restarts when these
// change), and keeps the transcript in the language heard. It does not draw on
// the lens; CaptionsTab shows the transcript and VoiceCommandRouter reads
// finished phrases through `onFinalPhrase`.
//
// Public API:
//   CaptionController(session:settings:)
//   @Published isRunning, isStarting: Bool
//   @Published phrases: [String]        // finished phrases, oldest first
//   @Published livePhrase: String       // in-progress phrase (may still change)
//   @Published errorMessage: String?
//   onFinalPhrase: ((String) -> Void)?
//   onSpeaking: (() -> Void)?                // partial speech (the user is talking now)
//   engineName: String
//   recorder: RawAudioRecorder
//   start() async / stop() async / clearTranscript()
//   language(of phrase:) -> HudLanguage?   // language a phrase was heard as (auto: either one)

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

    var onFinalPhrase: ((String) -> Void)?
    var onSpeaking: (() -> Void)?
    let recorder = RawAudioRecorder()
    private(set) var engineName = "Apple (on-device)"

    // MARK: - Dependencies

    private let session: BluetoothSession
    private let settings: HudSettings
    private var engine: SpeechEngine?
    /// Which language each finished phrase was heard as (two-language listening).
    private var phraseLanguages: [String: HudLanguage] = [:]
    private var subscriptions = Set<AnyCancellable>()

    // MARK: - Lifecycle

    init(session: BluetoothSession, settings: HudSettings) {
        self.session = session
        self.settings = settings
        session.micPcm
            .sink { [weak self] event in self?.handleMic(event.pcm) }
            .store(in: &subscriptions)
        // A new listening language (or auto setting, or HUD language while auto)
        // takes effect right away: restart the engine.
        Publishers.CombineLatest3(settings.$hearingLanguage, settings.$language, settings.$autoLanguage)
            .dropFirst()
            .map { hearing, hud, auto in "\(hearing.rawValue)|\(auto ? hud.rawValue : "-")" }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.restartIfRunning() }
            .store(in: &subscriptions)
    }

    /// Restarts listening (e.g. with a new hearing language) if it's on.
    private func restartIfRunning() {
        guard isRunning else { return }
        Task {
            await stop()
            await start()
        }
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
                errorMessage = HudText.t(.dashboardOpen)
                return
            }
        } else if !(await AVAudioApplication.requestRecordPermission()) {
            errorMessage = HudText.t(.micPermission)
            return
        }

        isStarting = true
        defer { isStarting = false }

        // Auto: also listen for the HUD language and keep whichever fits each sentence.
        let engine: SpeechEngine = settings.autoLanguage && settings.hearingLanguage != settings.language
            ? DualSpeechEngine(secondLanguageId: settings.language.speechLocaleId)
            : AppleSpeechEngine()
        do {
            try await engine.start(
                languageId: settings.hearingLanguage.speechLocaleId,
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
        phraseLanguages = [:]
    }

    /// The language a finished phrase was heard as (nil if unknown).
    func language(of phrase: String) -> HudLanguage? {
        phraseLanguages[phrase]
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
                if let id = update.languageId, let language = HudLanguage(legacyLocaleId: id) {
                    phraseLanguages[phrase] = language
                }
                onFinalPhrase?(phrase)
            }
        } else {
            livePhrase = update.text
            if !update.text.trimmingCharacters(in: .whitespaces).isEmpty { onSpeaking?() }
        }
    }

    private func handleEngineFailure(_ error: Error) {
        errorMessage = HudText.t(.engineStopped, error.localizedDescription)
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
