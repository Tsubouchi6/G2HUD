// OnDeviceAI.swift
//
// Apple's on-device language model (Foundation Models, iOS 26+). Free and
// offline. Good for short everyday questions; weak at facts and math (math
// goes to Calculator instead). Keeps one conversation so follow-ups work, and
// starts a fresh one when the ~4k-token context fills up.
//
// Public API:
//   OnDeviceAI()
//   availabilityMessage: String?     // nil when the model is ready
//   ask(_ question: String) async throws -> String
//   answerOffline(query:language:) async throws -> String   // search fallback, no web, no chat history
//   condense(answer:query:language:) async throws -> String  // web answer -> short, in the HUD language
//   englishAssetName(_ subject: String) async throws -> String // "トヨタ" -> "Toyota" (for ticker lookup)
//   extractSeries(question:text:) async throws -> ExtractedSeries // numbers from search text, for charts
//   reset()

import Foundation
import FoundationModels

/// Numbers pulled from text for a statistics chart.
struct ExtractedSeries {
    let title: String
    let unit: String
    let points: [ChartPoint]
}

/// Guided-generation shapes (the model fills these directly, no text parsing).
@Generable
private struct GeneratedSeries {
    @Guide(description: "Very short chart title in the question's language")
    let title: String
    @Guide(description: "Unit of the values, e.g. %, people, USD, km. Empty if none")
    let unit: String
    @Guide(description: "Data points found in the text, in chronological or ranked order. Empty if the text has no numbers for the question")
    let points: [GeneratedPoint]
}

@Generable
private struct GeneratedPoint {
    @Guide(description: "Short label, e.g. a year or a country name (max 8 characters)")
    let label: String
    @Guide(description: "The number, as written in the text, without units")
    let value: Double
}

@MainActor
final class OnDeviceAI {

    // MARK: - State

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

    func ask(_ question: String) async throws -> String {
        do {
            return try await respond(question)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize(_) {
            // Conversation got too long: start fresh and retry once.
            reset()
            return try await respond(question)
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
        let response = try await session.respond(to: query)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rewrites a web answer (Tavily replies in English, sometimes at length)
    /// as a short answer in the HUD language. Fresh session, no chat history.
    func condense(answer: String, query: String, language: HudLanguage) async throws -> String {
        let instructions = """
        Rewrite the given search answer so it directly answers the question in \
        \(language.englishName), in at most \(HudConstants.searchSummaryMaxChars) characters. \
        Keep only what the question asks for. Keep numbers exactly. Plain text only.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: "Question: \(query)\n\nAnswer: \(answer)")
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Charts

    /// English company, index, or coin name for a Yahoo ticker search.
    /// Fresh session each time so the chat context stays clean.
    func englishAssetName(_ subject: String) async throws -> String {
        let instructions = """
        Convert the user's text into the English name of the company, stock index, \
        currency pair, or cryptocurrency it refers to, as Yahoo Finance would list it \
        (e.g. トヨタ -> Toyota, 日経平均 -> Nikkei 225, ドル円 -> USD/JPY). \
        Reply with the name only.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: subject)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
    }

    /// Pulls the numbers that answer `question` out of search `text`. Only
    /// numbers present in the text are allowed (the model must not invent data).
    func extractSeries(question: String, text: String) async throws -> ExtractedSeries {
        let instructions = """
        You extract numeric data for a chart. Use only numbers that appear in the \
        given text. Never estimate or invent values. At most \(HudConstants.chartMaxPoints) points.
        """
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Question: \(question)\n\nText:\n\(text.prefix(HudConstants.chartSourceMaxChars))"
        let generated = try await session.respond(to: prompt, generating: GeneratedSeries.self).content
        let points = generated.points.prefix(HudConstants.chartMaxPoints).map {
            ChartPoint(label: String($0.label.prefix(8)), value: $0.value)
        }
        return ExtractedSeries(title: generated.title, unit: generated.unit, points: Array(points))
    }

    private func respond(_ question: String) async throws -> String {
        let session = self.session ?? LanguageModelSession(instructions: HudConstants.aiInstructions)
        self.session = session
        let response = try await session.respond(to: question)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
