// OnDeviceAI.swift
//
// Apple's on-device language model (Foundation Models, iOS 26+). Free and
// offline. Every question carries the current context (AiContext: date, time,
// time zone, reply language), so obvious things like "what time is it" are
// answered directly. For what it can't know it calls its tools (AiTools:
// web search, stock chart, chart, picture) by its own judgement.
// Keeps one conversation so follow-ups work, and starts a fresh one when the
// ~4k-token context fills up. Math goes to Calculator instead (exact).
//
// Public API:
//   OnDeviceAI()
//   tools: [any Tool]                // set once by HudController, before the first question
//   availabilityMessage: String?     // nil when the model is ready
//   ask(_ question:, language:) async throws -> String
//   answerOffline(query:language:) async throws -> String   // search fallback, no web, no chat history
//   condense(answer:query:language:) async throws -> String  // web answer -> short, in the HUD language
//   translate(_ text:, to:) async throws -> String           // fallback for Translator
//   reset()

import Foundation
import FoundationModels

@MainActor
final class OnDeviceAI {

    // MARK: - State

    var tools: [any Tool] = []
    private var session: LanguageModelSession?

    // MARK: - Availability

    /// nil when ready; otherwise a short reason to show the user.
    var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            return "On-device AI unavailable (\(reason)). Turn on Apple Intelligence in Settings."
        @unknown default:
            return "On-device AI unavailable."
        }
    }

    // MARK: - Asking

    func ask(_ question: String, language: HudLanguage) async throws -> String {
        let prompt = "\(AiContext.line(language: language))\n\(question)"
        do {
            return try await respond(prompt)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize(_) {
            // Conversation got too long: start fresh and retry once.
            reset()
            return try await respond(prompt)
        }
    }

    func reset() {
        session = nil
    }

    /// Search fallback when the web is unavailable: answers from the model's
    /// own knowledge in 1-2 sentences, saying so if it can't know (e.g. today's
    /// weather). Uses its own short-lived session so it doesn't fill the chat context.
    func answerOffline(query: String, language: HudLanguage) async throws -> String {
        let instructions = """
        You have no internet access. Answer the user's search in 1-2 short sentences \
        (under 120 characters) in \(language.englishName), from general knowledge only. \
        If it needs live or recent information (weather, news, prices, hours), say briefly \
        that you can't know without the web. Plain text only.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: "\(AiContext.line(language: language))\n\(query)")
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rewrites a web answer (Tavily replies in English, sometimes at length)
    /// as a short answer in the HUD language. Fresh session, no chat history.
    func condense(answer: String, query: String, language: HudLanguage) async throws -> String {
        let instructions = """
        Rewrite the given search answer so it directly answers the question in \
        \(language.englishName), in at most \(HudConstants.searchSummaryMaxChars) characters. \
        Keep only what the question asks for, for the user's own place and time unless \
        the question names another. Keep numbers exactly. Plain text only.
        """
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "\(AiContext.line(language: language))\nQuestion: \(query)\n\nAnswer: \(answer)"
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One line, translated. Fresh session each time (no chat history).
    func translate(_ text: String, to language: HudLanguage) async throws -> String {
        let session = LanguageModelSession(instructions: """
        Translate the user's text into \(language.englishName). Reply with the translation only.
        """)
        let response = try await session.respond(to: text)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private func respond(_ prompt: String) async throws -> String {
        let session = self.session ?? LanguageModelSession(tools: tools, instructions: HudConstants.aiInstructions)
        self.session = session
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
