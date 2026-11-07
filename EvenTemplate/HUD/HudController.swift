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
//   settings, captions, lens, notes, reminders, tilt, conversations, claude, aiChats, listening, navigator   (exposed parts)
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
    let navigator: Navigator

    private let search: WebSearchService
    private let router: VoiceCommandRouter
    private let input: GlassesInputHandler
    private let status: LensStatus
    private let listenSchedule: ListeningScheduler
    private let weather: WeatherService
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
        let listenSchedule = ListeningScheduler()

        let ai = OnDeviceAI()
        let search = WebSearchService(settings: settings, ai: ai)
        let charts = ChartService()
        let aiChats = AiChatArchive()
        // Without glasses connected, the phone's compass drives the directions arrow.
        let locationService = LocationService()
        let weather = WeatherService(location: locationService)
        let directions = DirectionsService()
        let planner = RoutePlanner(directions: directions, transit: TransitService(settings: settings))
        let navigator = Navigator(
            location: locationService, directions: directions, planner: planner, heading: HeadingService(),
            useCompass: { [weak session] in session?.glasses.connected != true }
        )

        // What either AI can make the HUD do (charts, pictures, saving, listening, directions).
        let aiTab = AiTab(ai: ai, settings: settings, archive: aiChats)
        let calcTab = CalcTab()
        let translator = Translator(ai: ai)
        let savedTab = SavedTab(
            conversations: conversations, listening: listening, chats: aiChats, translator: translator
        )
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
            startListening: { [weak lens, weak captions] title, code, start, stop in
                guard captions?.isRunning == true else { return false }
                // "My friend will speak Japanese": record in that language.
                if let code, let language = HudLanguage(rawValue: code) { settings.hearingLanguage = language }
                let until = stop.map { " (\(HudText.t(.listeningUntil, ListeningScheduler.clock($0))))" } ?? ""
                if let start {
                    lens?.showBanner(HudText.t(.listeningScheduled, ListeningScheduler.clock(start), title) + until)
                }
                // "From 5:08 to 5:09": the scheduler starts and stops it at those times.
                return listenSchedule.plan(start: start, stop: stop, begin: { [weak lens, weak captions] in
                    guard captions?.isRunning == true else { return false }
                    listening.endSession()
                    listening.startSession(language: settings.hearingLanguage, title: title)
                    captions?.isRecording = true  // switch to the recording languages
                    lens?.showBanner(HudText.t(.listeningStarted, title) + until, seconds: HudConstants.listeningBannerSeconds)
                    return true
                }, end: { [weak lens, weak captions] in
                    guard listening.isRecording else { return }
                    listening.endSession()
                    captions?.isRecording = false
                    lens?.showBanner(HudText.t(.listeningSaved))
                })
            },
            stopListening: { [weak lens] in
                let cancelledPlan = listenSchedule.cancel()
                guard listening.isRecording else { return cancelledPlan }
                listening.endSession()
                captions.isRecording = false
                lens?.showBanner(HudText.t(.listeningSaved))
                return true
            },
            startDirections: { [weak lens] destination, match, mode in
                lens?.select(id: "nav")
                let failure = await navigator.start(destination: destination, match: match, mode: mode).value
                return failure.map { "Failed: \($0)" } ?? navigator.summaryForAI ?? "Started."
            },
            goToShownPlace: { [weak lens] mode in
                guard let task = navigator.goToShownPlace(mode: mode) else { return "Failed: no place is shown on the map." }
                lens?.select(id: "nav")
                let failure = await task.value
                return failure.map { "Failed: \($0)" } ?? navigator.summaryForAI ?? "Started."
            },
            chooseRoute: { [weak lens] number in
                guard navigator.choose(number) else { return "Failed: no ways are listed, or no such number." }
                lens?.select(id: "nav")
                return navigator.summaryForAI ?? "Started."
            },
            stopDirections: {
                guard case .idle = navigator.state else {
                    navigator.stop()
                    return true
                }
                return false
            },
            showPlace: { [weak lens] query, match in
                lens?.select(id: "nav")
                let failure = await navigator.showPlace(query, match: match).value
                return failure.map { "Failed: \($0)" } ?? navigator.summaryForAI ?? "Shown."
            },
            directionsView: { [weak lens] view in
                if case .idle = navigator.state { return false }
                switch view.lowercased() {
                case "minimal": navigator.minimal = true
                case "zoomin": navigator.zoom(in: true)
                case "zoomout": navigator.zoom(in: false)
                default: navigator.showMap()
                }
                lens?.select(id: "nav")
                return true
            },
            calculate: { [weak calcTab] expression in calcTab?.calculate(expression) ?? "" },
            convert: { [weak calcTab] value, from, to in await calcTab?.convert(value, from: from, to: to) ?? "" },
            openTab: { [weak lens, weak savedTab] id in
                if id == "saved" { savedTab?.showList() }  // the list, not a previously opened item
                return lens?.select(id: id) ?? false
            },
            setLanguage: { which, code in
                guard let language = HudLanguage(rawValue: code) else { return false }
                if which == "hearing" { settings.hearingLanguage = language } else { settings.language = language }
                return true
            }
        )
        ai.tools = AiTools.make(search: search, charts: charts, actions: actions)
        let claude = ClaudeOnPC(settings: settings, charts: charts, actions: actions)
        // Both AIs know which place the Nav map shows ("go there", "how far is it").
        ai.situation = { [weak navigator] in navigator?.summaryForAI }
        claude.situation = { [weak navigator] in navigator?.summaryForAI }
        aiTab.claude = claude
        let searchTab = SearchTab(service: search)
        lens.setTabs([
            CaptionsTab(captions: captions, settings: settings, translator: translator),
            aiTab,
            searchTab,
            calcTab,
            NotesTab(store: notes),
            RemindTab(service: reminders),
            savedTab,
            NavTab(navigator: navigator),
        ])
        navigator.onArrived = { [weak lens] name in lens?.showBanner(HudText.t(.navArrived, name), seconds: HudConstants.reminderAlertSeconds) }
        navigator.onNotice = { [weak lens] text in lens?.showBanner(text, seconds: HudConstants.reminderAlertSeconds) }

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
        self.navigator = navigator
        self.listenSchedule = listenSchedule
        self.weather = weather
        router = VoiceCommandRouter(context: VoiceCommandContext(
            lens: lens, settings: settings, captions: captions, notes: notes,
            reminders: reminders, aiTab: aiTab, searchTab: searchTab, calcTab: calcTab, savedTab: savedTab,
            navigator: navigator,
            isAddressedToAssistant: { sentence in await ai.isAddressedToAssistant(sentence) }
        ))
        input = GlassesInputHandler(session: session, lens: lens, settings: settings, tilt: tilt)
        // Status bar (time, listening dot, batteries) in the corner of every screen.
        status = LensStatus(
            session: session,
            isListening: { [weak captions] in captions?.isRunning == true },
            weather: { [weak weather] in weather?.latestText },
            onText: { [weak lens] text in lens?.updateStatus(text) }
        )

        captions.onFinalPhrase = { [weak self] phrase in
            guard let self else { return }
            self.conversations.append(phrase)
            // "Listen to this" clips keep only what others say, not commands to Neo.
            let isCommand = self.router.window.isOpen || VoicePhrases.stripWakeWord(VoicePhrases.normalize(phrase)) != nil
            if !isCommand { self.listening.append(phrase) }
            self.router.handle(phrase: phrase)
        }
        // Listening window after "Neo": pause while talking, 10 s after an answer, indicator on the lens.
        captions.onSpeaking = { [weak self] in self?.router.userIsSpeaking() }
        aiTab.onAnswered = { [weak self] in self?.router.replyShown() }
        searchTab.onFinished = { [weak self] in self?.router.replyShown() }
        router.window.onOpen = { [weak lens] in
            lens?.showBanner(HudText.t(.wakeAck), seconds: HudConstants.listenIndicatorSeconds)
        }
        router.window.onClose = { [weak lens] in lens?.hideBanner() }
        // Redraw the lens in the new language (next tick, after the value is stored).
        languageSubscription = settings.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak lens] _ in lens?.render() }
        reminders.onDue = { [weak self] reminder in self?.showReminder(reminder) }
        reminders.start()
        // Time, battery and weather tick from launch, so the preview shows them
        // before the HUD starts (the lens itself only draws while active).
        status.start()
        weather.start()
    }

    // MARK: - On / off

    /// Starts listening, then shows the HUD on the lens.
    func start() async {
        await captions.start()
        guard captions.isRunning else { return }
        if settings.saveConversations { conversations.startSession(language: settings.hearingLanguage) }
        lens.activate()
        input.start()
    }

    func stop() async {
        input.stop()
        await captions.stop()
        conversations.endSession()
        _ = listenSchedule.cancel()
        listening.endSession()
        captions.isRecording = false
        router.window.close()
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
