// SpeechEngine.swift
//
// The contract every speech-to-text engine implements, so engines can be
// swapped (Apple on-device now; WhisperKit or cloud later) without touching
// the captions code.
//
// Public API:
//   protocol SpeechEngine
//     var displayName: String
//     func start(languageId:onUpdate:onError:) async throws
//     func append(pcm16: Data)           // 16 kHz mono Int16 frames from the mic
//     func stop() async
//   struct SpeechUpdate                  // one finished or in-progress phrase (+ confidence, audio time, language)
//   enum SpeechEngineError

import Foundation

// MARK: - Types

/// One result from an engine. `isFinal == false` means the text may still
/// change (shown live); `true` means it is settled and will not change.
/// confidence: the engine's mean certainty (0-1), audioStart/End: where in the
/// audio it was said (seconds), languageId: the language it was heard as.
/// These let DualSpeechEngine pick between two languages; nil when unknown.
struct SpeechUpdate {
    let text: String
    let isFinal: Bool
    var confidence: Double? = nil
    var audioStart: Double? = nil
    var audioEnd: Double? = nil
    var languageId: String? = nil
}

enum SpeechEngineError: LocalizedError {
    case unsupportedLanguage(String)
    case noAudioFormat
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let id):
            return "Speech-to-text doesn't support \(id) on this iPhone."
        case .noAudioFormat:
            return "Couldn't find an audio format the speech model accepts."
        case .permissionDenied:
            return "Speech recognition permission was denied (Settings > G2HUD)."
        }
    }
}

// MARK: - Protocol

@MainActor
protocol SpeechEngine: AnyObject {
    /// Short name shown in the UI, e.g. "Apple (on-device)".
    var displayName: String { get }

    /// Prepare the model (downloading it if needed) and begin transcribing.
    /// `onUpdate` is called on the main actor for every result; `onError` is
    /// called on the main actor if transcription dies mid-session.
    func start(
        languageId: String,
        onUpdate: @escaping (SpeechUpdate) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws

    /// Feed one chunk of 16 kHz mono signed 16-bit PCM. No-op when not running.
    func append(pcm16: Data)

    /// Flush pending audio, deliver final results, and release the model.
    func stop() async
}
