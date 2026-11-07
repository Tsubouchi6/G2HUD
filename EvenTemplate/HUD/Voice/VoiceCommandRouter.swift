// VoiceCommandRouter.swift
//
// Turns finished speech phrases into actions. Cheapest path first:
//   1. Wake word ("Claude ...") marks a command; other speech is just captions.
//   2. Fixed key phrases (VoicePhrases) run instantly with no AI: tab
//      navigation, notes, reminders, explicit "search ...".
//   3. Anything else: maths to the calculator (exact), everything else to the
//      on-device AI, which knows the date/time/place and decides by itself
//      whether to search, draw a chart, or show a picture (AiTools).
// Destructive actions wait for "はい / yes / sim" before running.
//
// Public API:
//   VoiceCommandRouter(context:)
//   handle(phrase:)          // every finished phrase from the speech engine
//   run(command:)            // run a command directly (typed test box, skips wake word)

import Foundation

/// Everything the router can act on. Passed in once so the router has no
/// knowledge of how the HUD is assembled.
@MainActor
struct VoiceCommandContext {
    let lens: LensController
    let settings: HudSettings
    let captions: CaptionController
    let notes: NotesStore
    let reminders: ReminderService
    let aiTab: AiTab
    let searchTab: SearchTab
    let calcTab: CalcTab
}

@MainActor
final class VoiceCommandRouter {

    // MARK: - State

    private let context: VoiceCommandContext
    /// Set after a bare wake word: the next phrase is a command until this time.
    private var commandWindowEnds: Date?
    private var pendingConfirmation: (prompt: String, action: @MainActor () -> Void, expires: Date)?

    init(context: VoiceCommandContext) {
        self.context = context
    }

    // MARK: - Entry points

    func handle(phrase: String) {
        let text = VoicePhrases.normalize(phrase)
        guard !text.isEmpty else { return }

        if resolveConfirmation(text) { return }

        if let command = VoicePhrases.stripWakeWord(text) {
            if command.isEmpty {
                commandWindowEnds = Date().addingTimeInterval(HudConstants.commandWindowSeconds)
                context.lens.showBanner(HudText.t(.wakeAck), seconds: HudConstants.commandWindowSeconds)
            } else {
                run(command: command)
            }
            return
        }

        if let ends = commandWindowEnds, Date() < ends {
            commandWindowEnds = nil
            run(command: text)
            return
        }

        if !context.settings.requireWakeWord {
            runKeyPhraseOnly(text)
        }
    }

    /// Runs a command (no wake word needed). Used after the wake word and by
    /// the phone's typed test box.
    func run(command rawCommand: String) {
        let command = VoicePhrases.normalize(rawCommand)
        guard !command.isEmpty else { return }
        context.lens.dismissImage()
        if runKeyPhrase(command) { return }

        // Not a known phrase: maths to the exact calculator, the rest to the AI.
        if Calculator.looksLikeMath(command) {
            open("calc")
            context.calcTab.calculate(command)
        } else {
            open("ai")
            context.aiTab.ask(command)
        }
    }

    // MARK: - Key phrases

    /// Without a wake word only navigation phrases run (so normal talk
    /// can't trigger notes, searches, or AI by accident).
    private func runKeyPhraseOnly(_ text: String) {
        if VoicePhrases.isNavigation(text) { _ = runKeyPhrase(text) }
    }

    /// Returns true if `command` matched a fixed phrase and was handled.
    private func runKeyPhrase(_ command: String) -> Bool {
        let lens = context.lens

        // Navigation
        if VoicePhrases.matches(command, VoicePhrases.next) { lens.next(); return true }
        if VoicePhrases.matches(command, VoicePhrases.previous) { lens.previous(); return true }
        if VoicePhrases.matches(command, VoicePhrases.scrollUp) {
            lens.scroll(linesUp: HudConstants.lensScrollStepLines); return true
        }
        if VoicePhrases.matches(command, VoicePhrases.scrollDown) {
            lens.scroll(linesDown: HudConstants.lensScrollStepLines); return true
        }
        if let tab = lens.tab(named: VoicePhrases.stripOpenWords(command)) {
            lens.select(id: tab.id); return true
        }

        // Destructive (confirm first)
        if VoicePhrases.matches(command, VoicePhrases.deleteLastNote) {
            confirm(HudText.t(.confirmDeleteLastNote)) { [context] in context.notes.deleteNewest() }
            return true
        }
        if VoicePhrases.matches(command, VoicePhrases.deleteAllNotes) {
            confirm(HudText.t(.confirmDeleteAllNotes)) { [context] in context.notes.deleteAll() }
            return true
        }
        if VoicePhrases.matches(command, VoicePhrases.deleteAllReminders) {
            confirm(HudText.t(.confirmDeleteAllReminders)) { [context] in context.reminders.deleteAll() }
            return true
        }
        if VoicePhrases.matches(command, VoicePhrases.clearCaptions) {
            context.captions.clearTranscript(); return true
        }

        // Actions with a payload: "メモ 牛乳買う", "検索 天気", "計算 12×3", "AI ..."
        if let text = VoicePhrases.payload(command, VoicePhrases.notePrefixes) {
            context.notes.add(text)
            open("notes")
            lens.showBanner(HudText.t(.noted))
            return true
        }
        if let query = VoicePhrases.payload(command, VoicePhrases.searchPrefixes, suffixes: VoicePhrases.searchSuffixes) {
            open("search")
            context.searchTab.search(query)
            return true
        }
        if let expression = VoicePhrases.payload(command, VoicePhrases.calcPrefixes) {
            open("calc")
            context.calcTab.calculate(expression)
            return true
        }
        if let question = VoicePhrases.payload(command, VoicePhrases.aiPrefixes) {
            open("ai")
            context.aiTab.ask(question)
            return true
        }
        if VoicePhrases.containsAny(command, VoicePhrases.reminderWords) {
            addReminder(command)
            return true
        }
        if VoicePhrases.containsAny(command, VoicePhrases.softReminderWords),
           ReminderParser.parse(command) != nil {
            addReminder(command)
            return true
        }
        return false
    }

    // MARK: - Actions

    private func addReminder(_ command: String) {
        guard let parsed = ReminderParser.parse(command) else {
            context.lens.showBanner(HudText.t(.timeUnknown))
            return
        }
        context.reminders.add(text: parsed.text, at: parsed.date)
        open("remind")
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        context.lens.showBanner(HudText.t(.reminderSet, formatter.string(from: parsed.date)))
    }

    private func open(_ tabId: String) {
        if context.lens.activeTab?.id != tabId { context.lens.select(id: tabId) }
    }

    // MARK: - Confirmation

    private func confirm(_ prompt: String, action: @escaping @MainActor () -> Void) {
        pendingConfirmation = (prompt, action, Date().addingTimeInterval(HudConstants.confirmWindowSeconds))
        context.lens.showBanner("\(prompt) \(HudText.t(.confirmSuffix))", seconds: HudConstants.confirmWindowSeconds)
    }

    /// Handles "はい/いいえ" while a confirmation is pending. Returns true if consumed.
    private func resolveConfirmation(_ text: String) -> Bool {
        guard let pending = pendingConfirmation else { return false }
        guard Date() < pending.expires else {
            pendingConfirmation = nil
            return false
        }
        let answer = VoicePhrases.stripWakeWord(text) ?? text
        if VoicePhrases.matches(answer, VoicePhrases.yes) {
            pendingConfirmation = nil
            pending.action()
            context.lens.showBanner(HudText.t(.ok))
            return true
        }
        if VoicePhrases.matches(answer, VoicePhrases.no) {
            pendingConfirmation = nil
            context.lens.showBanner(HudText.t(.cancelled))
            return true
        }
        return false
    }
}
