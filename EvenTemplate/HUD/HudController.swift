// HudController.swift
//
// Assembles the HUD and is its single on/off switch. Builds the lens tabs,
// wires speech -> voice commands -> tabs, glasses input -> lens, and reminders
// -> lens alerts, and the AI's tools (search, charts, pictures) -> lens. Screens talk to this object (and the parts it exposes).
//
// Tab order on the lens: 字幕, AI, 検索, 計算, メモ, リマインダー, 履歴 (saved), ナビ (nav).
//
// Public API:
//   HudController(session:)
//   settings, captions, lens, notes, reminders, tilt, conversations, claude, aiChats, listening   (exposed parts)
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
    let listening: ListeningLog

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
        let listening = ListeningLog()

        let ai = OnDeviceAI()
        let search = WebSearchService(settings: settings, ai: ai)
        let charts = ChartService()
        let aiChats = AiChatArchive()
        let navigator = Navigator(location: LocationService(), directions: DirectionsService())

        // What either AI can make the HUD do (charts, pictures, saving, listening, directions).
        let aiTab = AiTab(ai: ai, settings: settings, archive: aiChats)
        let actions = AiActions(
            // Charts and photos go into the AI chat like a message, not over the whole lens.
            showChart: { [weak lens, weak aiTab] chart in
                aiTab?.addPicture(chart.png, caption: chart.caption)
                lens?.select(id: "ai")
            },
            showPicture: { [weak lens, weak aiTab] terms, caption in
                lens?.showBanner(HudText.t(.findingImage), seconds: HudConstants.searchTimeoutSeconds)
                Task {
                    if let data = await search.findImage(terms),
                       let fitted = LensImageTiler.fitted(
                           data, width: HudConstants.chatPictureWidthPx, height: HudConstants.chatPictureHeightPx
                       ) {
                        aiTab?.addPicture(fitted, caption: caption)
                        lens?.hideBanner()
                        lens?.select(id: "ai")
                    } else {
                        lens?.showBanner(HudText.t(.imageNotFound))
                    }
                }
            },
            saveChat: { [weak lens] title in
                let saved = aiChats.saveCurrent(title: title, language: settings.language)
                lens?.showBanner(saved ? HudText.t(.chatSaved, title) : HudText.t(.nothingToSave))
                return saved
            },
            startListening: { [weak lens, weak captions] title in
                guard captions?.isRunning == true else { return false }
                listening.endSession()
                listening.startSession(language: settings.language, title: title)
                lens?.showBanner(HudText.t(.listeningStarted, title), seconds: HudConstants.listeningBannerSeconds)
                return true
            },
            stopListening: { [weak lens] in
                guard listening.isRecording else { return false }
                listening.endSession()
                lens?.showBanner(HudText.t(.listeningSaved))
                return true
            },
            startDirections: { [weak lens] destination, mode, minimal in
                navigator.start(destination: destination, mode: mode, minimal: minimal)
                lens?.select(id: "nav")
            },
            stopDirections: {
                guard case .idle = navigator.state else {
                    navigator.stop()
                    return true
                }
                return false
            }
        )
        ai.tools = AiTools.make(search: search, charts: charts, actions: actions)
        let claude = ClaudeOnPC(settings: settings, charts: charts, actions: actions)
        aiTab.claude = claude
        let savedTab = SavedTab(
            conversations: conversations, listening: listening, chats: aiChats, translator: Translator(ai: ai)
        )
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
            NavTab(navigator: navigator),
        ])
        navigator.onMapPicture = { [weak lens] png, name in lens?.showImage(png, caption: name) }
        navigator.onArrived = { [weak lens] name in lens?.showBanner(HudText.t(.navArrived, name), seconds: HudConstants.reminderAlertSeconds) }

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
        self.listening = listening
        router = VoiceCommandRouter(context: VoiceCommandContext(
            lens: lens, settings: settings, captions: captions, notes: notes,
            reminders: reminders, aiTab: aiTab, searchTab: searchTab, calcTab: calcTab, savedTab: savedTab,
            navigator: navigator,
            isAddressedToAssistant: { sentence in await ai.isAddressedToAssistant(sentence) }
        ))
        input = GlassesInputHandler(session: session, lens: lens, settings: settings, tilt: tilt)

        captions.onFinalPhrase = { [weak self] phrase in
            self?.conversations.append(phrase)
            // "Listen to this" clips keep only what others say, not "Neo ..." commands.
            if VoicePhrases.stripWakeWord(VoicePhrases.normalize(phrase)) == nil { self?.listening.append(phrase) }
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
        listening.endSession()
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
