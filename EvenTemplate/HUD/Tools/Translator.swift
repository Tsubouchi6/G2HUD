// Translator.swift
//
// Translates saved conversations for studying. Apple's Translation framework
// first (on-device, free; the languages must be downloaded once in iOS
// Settings > Apps > Translate). If that fails, the on-device AI translates.
// Source: developer.apple.com/documentation/translation/translationsession/init(installedsource:target:)
//
// Public API:
//   Translator(ai:)
//   translate(_ lines: [String], from:to:) async throws -> [String]   // same count and order (live captions too)
//   static defaultTarget(for source: HudLanguage) -> HudLanguage       // English, or Japanese for English

import Foundation
import Translation

@MainActor
final class Translator {

    private let ai: OnDeviceAI
    /// One Apple translation session per language pair, reused (live captions
    /// translate every phrase).
    private var sessions: [String: TranslationSession] = [:]

    init(ai: OnDeviceAI) {
        self.ai = ai
    }

    func translate(_ lines: [String], from source: HudLanguage, to target: HudLanguage) async throws -> [String] {
        guard source != target else { return lines }
        do {
            let key = "\(source.rawValue)>\(target.rawValue)"
            let session = sessions[key] ?? TranslationSession(
                installedSource: Locale.Language(identifier: source.rawValue),
                target: Locale.Language(identifier: target.rawValue)
            )
            sessions[key] = session
            var result: [String] = []
            for line in lines {
                result.append(line.isEmpty ? "" : try await session.translate(line).targetText)
            }
            return result
        } catch {
            // Languages not downloaded (or unsupported): fall back to the on-device AI.
            guard ai.availabilityMessage == nil else { throw error }
            var result: [String] = []
            for line in lines {
                result.append(line.isEmpty ? "" : try await ai.translate(line, to: target))
            }
            return result
        }
    }

    static func defaultTarget(for source: HudLanguage) -> HudLanguage {
        source == .english ? .japanese : .english
    }
}
