// DualSpeechEngine.swift
//
// Listens for two languages at once ("auto"): the same mic audio goes to two
// Apple engines (e.g. Japanese and English). For each finished sentence the
// two versions of the same moment (matched by audio time) are compared and
// the one the engine was more confident about is kept; the other is dropped.
// A sentence only one engine produced is kept as is. In-progress text comes
// from whichever language won last, so the live line doesn't flip between them.
// Costs about twice the processing of one language.
//
// Public API:
//   DualSpeechEngine(secondLanguageId:)       // first language = start(languageId:)
//   SpeechEngine conformance (start / append / stop)

import Foundation

@MainActor
final class DualSpeechEngine: SpeechEngine {

    let displayName = "Apple (on-device, 2 languages)"

    private let secondLanguageId: String
    private let engines = [AppleSpeechEngine(), AppleSpeechEngine()]
    private var onUpdate: ((SpeechUpdate) -> Void)?

    /// Finals waiting for the other language's version of the same moment.
    private var pending: [(engine: Int, update: SpeechUpdate)] = []
    /// Audio time already covered by an emitted sentence (later duplicates are dropped).
    private var emittedUntil = 0.0
    /// The language that won last; its live text is shown.
    private var preferredEngine = 0

    init(secondLanguageId: String) {
        self.secondLanguageId = secondLanguageId
    }

    func start(
        languageId: String,
        onUpdate: @escaping (SpeechUpdate) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        self.onUpdate = onUpdate
        for (index, id) in [languageId, secondLanguageId].enumerated() {
            try await engines[index].start(
                languageId: id,
                onUpdate: { [weak self] update in self?.received(update, from: index) },
                onError: onError
            )
        }
    }

    func append(pcm16: Data) {
        for engine in engines { engine.append(pcm16: pcm16) }
    }

    func stop() async {
        for engine in engines { await engine.stop() }
        for candidate in pending { emit(candidate.update, from: candidate.engine) }
        pending = []
        onUpdate = nil
    }

    // MARK: - Choosing

    private func received(_ update: SpeechUpdate, from engine: Int) {
        guard update.isFinal else {
            if engine == preferredEngine { onUpdate?(update) }
            return
        }
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Already covered by the other language's sentence.
        if let end = update.audioEnd, end <= emittedUntil + HudConstants.dualSpeechOverlapSlackSeconds { return }

        if let index = pending.firstIndex(where: { $0.engine != engine && overlaps($0.update, update) }) {
            let other = pending.remove(at: index)
            let otherWins = (other.update.confidence ?? 0) > (update.confidence ?? 0)
            otherWins ? emit(other.update, from: other.engine) : emit(update, from: engine)
            return
        }

        pending.append((engine, update))
        // The other language may never produce this sentence: keep it after a short wait.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(HudConstants.dualSpeechPairWaitSeconds * 1_000_000_000))
            guard let self, let index = self.pending.firstIndex(where: { $0.engine == engine && $0.update.audioEnd == update.audioEnd }) else { return }
            let alone = self.pending.remove(at: index)
            self.emit(alone.update, from: alone.engine)
        }
    }

    private func emit(_ update: SpeechUpdate, from engine: Int) {
        preferredEngine = engine
        emittedUntil = max(emittedUntil, update.audioEnd ?? emittedUntil)
        onUpdate?(update)
    }

    /// Same moment in the audio (time ranges overlap). Without times, assume yes.
    private func overlaps(_ a: SpeechUpdate, _ b: SpeechUpdate) -> Bool {
        guard let aStart = a.audioStart, let aEnd = a.audioEnd, let bStart = b.audioStart, let bEnd = b.audioEnd else {
            return true
        }
        return aStart < bEnd && bStart < aEnd
    }
}
