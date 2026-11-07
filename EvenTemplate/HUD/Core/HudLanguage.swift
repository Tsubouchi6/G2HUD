// HudLanguage.swift
//
// The HUD's language. One setting drives speech recognition, voice commands,
// lens text, and the HUD phone screens.
//
// Public API:
//   enum HudLanguage: japanese / english / portuguese
//     displayName      // "日本語", "English", "Português"
//     speechLocaleId   // locale for the speech engine
//     englishName      // "Japanese", ... (for AI instructions)
//     init?(legacyLocaleId:)   // reads the old "ja-JP"-style setting

import Foundation

enum HudLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case english = "en"
    case portuguese = "pt"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        case .portuguese: return "Português"
        }
    }

    var englishName: String {
        switch self {
        case .japanese: return "Japanese"
        case .english: return "English"
        case .portuguese: return "Brazilian Portuguese"
        }
    }

    /// Source: Apple SpeechTranscriber supports ja-JP, en-US and pt-BR
    /// (Portuguese is Brazilian only, per loronote.com SpeechAnalyzer review).
    var speechLocaleId: String {
        switch self {
        case .japanese: return "ja-JP"
        case .english: return "en-US"
        case .portuguese: return "pt-BR"
        }
    }

    /// Maps the earlier captions setting ("ja-JP", "en-US") to a language.
    init?(legacyLocaleId: String) {
        guard let match = HudLanguage.allCases.first(where: { legacyLocaleId.hasPrefix($0.rawValue) }) else {
            return nil
        }
        self = match
    }
}
