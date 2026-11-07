// HudController.swift
//
// Assembles the HUD and is its single on/off switch. Builds the lens tabs,
// wires speech -> voice commands -> tabs, glasses input -> lens, and reminders
// -> lens alerts. Screens talk to this object (and the parts it exposes).
//
// Tab order on the lens: 字幕, AI, 検索, 計算, メモ, リマインダー.
//
// Public API:
//   HudController(session:)
//   settings, captions, lens, notes, reminders, tilt, conversations   (exposed parts)
//   start() async / stop() async
//   runTyped(_ command: String)      // phone test box: runs like a spoken command

import Combine
import Foundation

@MainActor
final class HudController: ObservableObject {

    // MARK: - Parts

    let settings: HudSettings
    let captions: CaptionController
    let lens: LensController
    let notes: NotesStore
    let reminders: ReminderService
    let tilt: HeadTiltDetector
    let conversations: ConversationLog

    private let search: WebSearchService
    private let router: VoiceCommandRouter
    private let input: GlassesInputHandler
    private var languageSubscription: AnyCancellable?

    // MARK: - Assembly

    init(session: BluetoothSession) {
        let settings = HudSettings()
        let captions = CaptionController(session: session, settings: settings)
        let lens = LensController(pusher: LensPusher(session: session))
        let notes = NotesStore()
        let reminders = ReminderService()
        let tilt = HeadTiltDetector()
        let conversations = ConversationLog()

        let ai = OnDeviceAI()
        let search = WebSearchService(settings: settings, ai: ai)
        let aiTab = AiTab(ai: ai)
        let searchTab = SearchTab(service: search)
        let calcTab = CalcTab()
        lens.setTabs([
            CaptionsTab(captions: captions),
            aiTab,
            searchTab,
            calcTab,
            NotesTab(store: notes),
            RemindTab(service: reminders),
        ])

        self.settings = settings
        self.captions = captions
        self.lens = lens
        self.notes = notes
        self.reminders = reminders
        self.tilt = tilt
        self.conversations = conversations
        self.search = search
        let showPicture: @MainActor (String, String?) -> Void = { [weak lens] terms, caption in
            lens?.showBanner(HudText.t(.findingImage), seconds: HudConstants.searchTimeoutSeconds)
            Task {
                if let data = await search.findImage(terms) {
                    lens?.showImage(data, caption: caption ?? terms)
                } else {
                    lens?.showBanner(HudText.t(.imageNotFound))
                }
            }
        }
        aiTab.onWantsImage = { terms, caption in showPicture(terms, caption) }
        searchTab.onImage = { [weak lens] data, caption in lens?.showImage(data, caption: caption) }
        router = VoiceCommandRouter(context: VoiceCommandContext(
            lens: lens, settings: settings, captions: captions, notes: notes,
            reminders: reminders, aiTab: aiTab, searchTab: searchTab, calcTab: calcTab,
            showPicture: { terms in showPicture(terms, nil) }
        ))
        input = GlassesInputHandler(session: session, lens: lens, settings: settings, tilt: tilt)

        captions.onFinalPhrase = { [weak self] phrase in
            self?.conversations.append(phrase)
            self?.router.handle(phrase: phrase)
        }
        // Redraw the lens in the new language (next tick, after the value is stored).
        languageSubscription = settings.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak lens] _ in lens?.render() }
        reminders.onDue = { [weak self] reminder in self?.showReminder(reminder) }
        reminders.start()
    }

    // MARK: - On / off

    /// Starts listening, then shows the HUD on the lens.
    func start() async {
        await captions.start()
        guard captions.isRunning else { return }
        if settings.saveConversations { conversations.startSession(language: settings.language) }
        lens.activate()
        input.start()
    }

    func stop() async {
        input.stop()
        await captions.stop()
        conversations.endSession()
        lens.deactivate()
    }

    // MARK: - Actions

    func runTyped(_ command: String) {
        router.run(command: command)
    }

    private func showReminder(_ reminder: Reminder) {
        lens.select(id: "remind")
        lens.showBanner("【リマインド】\(reminder.text)", seconds: HudConstants.reminderAlertSeconds)
    }
}
