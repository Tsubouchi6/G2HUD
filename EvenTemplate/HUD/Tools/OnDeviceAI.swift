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
//   reset()

import Foundation
import FoundationModels

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

    private func respond(_ question: String) async throws -> String {
        let session = self.session ?? LanguageModelSession(instructions: HudConstants.aiInstructions)
        self.session = session
        let response = try await session.respond(to: question)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
