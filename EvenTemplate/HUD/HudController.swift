// HudController.swift
//
// Assembles the HUD and is its single on/off switch. Builds the lens tabs,
// wires speech -> voice commands -> tabs, glasses input -> lens, and reminders
// -> lens alerts, and the AI's tools (search, charts, pictures) -> lens. Screens talk to this object (and the parts it exposes).
//
// Tab order on the lens: 字幕, AI, 検索, 計算, メモ, リマインダー, 履歴 (saved).
//
// Public API:
//   HudController(session:)
//   settings, captions, lens, notes, reminders, tilt, conversations, claude, aiChats   (exposed parts)
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
    let claude: ClaudeOnPC
    let aiChats: AiChatArchive

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
        let charts = ChartService()
        let aiChats = AiChatArchive()

        // Charts and pictures from either AI go on the lens.
        let showChart: @MainActor @Sendable (RenderedChart) -> Void = { [weak lens] chart in
            lens?.showImage(chart.png, caption: chart.caption)
        }
        let showPicture: @MainActor @Sendable (String, String) -> Void = { [weak lens] terms, caption in
            lens?.showBanner(HudText.t(.findingImage), seconds: HudConstants.searchTimeoutSeconds)
            Task {
                if let data = await search.findImage(terms) {
                    lens?.showImage(data, caption: caption)
                } else {
                    lens?.showBanner(HudText.t(.imageNotFound))
                }
            }
        }
        let saveChat: @MainActor @Sendable (String) -> Bool = { [weak lens] title in
            let saved = aiChats.saveCurrent(title: title, language: settings.language)
            lens?.showBanner(saved ? HudText.t(.chatSaved, title) : HudText.t(.nothingToSave))
            return saved
        }
        ai.tools = AiTools.make(
            search: search, charts: charts, showChart: showChart, showPicture: showPicture, saveChat: saveChat
        )
        let claude = ClaudeOnPC(
            settings: settings, charts: charts, showChart: showChart, showPicture: showPicture, saveChat: saveChat
        )
        let aiTab = AiTab(ai: ai, claude: claude, settings: settings, archive: aiChats)
        let savedTab = SavedTab(conversations: conversations, chats: aiChats, translator: Translator(ai: ai))
        let searchTab = SearchTab(service: search)
        let calcTab = CalcTab()
        lens.setTabs([
            CaptionsTab(captions: captions),
            aiTab,
            searchTab,
            calcTab,
            NotesTab(store: notes),
            RemindTab(service: reminders),
            savedTab,
        ])

        self.settings = settings
        self.captions = captions
        self.lens = lens
        self.notes = notes
        self.reminders = reminders
        self.tilt = tilt
        self.conversations = conversations
        self.search = search
        self.claude = claude
        self.aiChats = aiChats
        router = VoiceCommandRouter(context: VoiceCommandContext(
            lens: lens, settings: settings, captions: captions, notes: notes,
            reminders: reminders, aiTab: aiTab, searchTab: searchTab, calcTab: calcTab, savedTab: savedTab
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
