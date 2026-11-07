// HudText.swift
//
// Every user-visible HUD string in Japanese, English and Portuguese.
// The current language is set from HudSettings; screens and tabs call
// `HudText.t(.key)` (or `t(.key, args...)` for formatted strings).
//
// Public API:
//   HudText.language: HudLanguage          // set by HudSettings
//   HudText.t(_ key: Key) -> String
//   HudText.t(_ key: Key, _ args: CVarArg...) -> String
//   enum HudText.Key

import Foundation

@MainActor
enum HudText {

    static var language: HudLanguage = .japanese

    // MARK: - Lookup

    static func t(_ key: Key) -> String {
        guard let entry = table[key] else { return "\(key)" }
        switch language {
        case .japanese: return entry.ja
        case .english: return entry.en
        case .portuguese: return entry.pt
        }
    }

    static func t(_ key: Key, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    // MARK: - Keys

    enum Key {
        // Lens tabs
        case tabCaptions, tabAI, tabSearch, tabCalc, tabNotes, tabRemind
        // Lens content
        case listening, captionsOff, aiHint, searchHint, calcHint, notesHint, remindHint
        case searchLabel, noResults, aiError, aiUnavailable, aiBlocked
        // Lens feedback
        case wakeAck, noted, timeUnknown, reminderSet, reminderAlert
        case confirmDeleteLastNote, confirmDeleteAllNotes, confirmDeleteAllReminders, confirmSuffix
        case ok, cancelled, countdownMinutes, countdownHours
        // Phone: tab bar
        case screenHud, screenCaptions, screenSettings
        // Phone: HUD screen
        case startHud, stopHud, language, loadingModel, statusHeader, connected, notConnected, hearingLanguage, autoLanguage
        case micPhone, micGlasses, hudFooter, lensPreview, tryCommand, commandPlaceholder
        case runCommand, commandFooter, dashboardOpen, micPermission, engineStopped
        // Phone: Captions screen
        case startHudToBegin, clearTranscript, transcriptHeader, recordStart, recordStop
        case testRecordings, recordingsFooter
        // Phone: Settings screen
        case voice, requireWakeWord, usePhoneMic, voiceFooter, search
        case searchFooter, glassesControls, touchControls, touchHelp, headTilt, headTiltToggle
        case swapLeftRight, tiltReadout, calibrate, headTiltFooter, notesHeader, remindersHeader
        case tavilyKeyPlaceholder, noSearchKey, offlineTag
        case savedConversations, noConversations, saveConversations, saveConversationsFooter
        case findingImage, imageNotFound
        case tabSaved, savedHint, savedAiTag, savedTalkTag, translating, translationFailed
        case chatSaved, nothingToSave, aiChats
        case navPlaceWalk, navAngleRight, navAngleLeft, navStraight
        case tabNav, navHint, navFinding, navArrived, navRemaining, navThen, navRerouting, navToArrival
        case navWalk, navTrain, navBus, navMixed, navFree, navBoard, navLineToward, navGetOff, navStops
        case navNoTransitKey, navNoTransit, navWalkTo, navExitGate, transitKeyPlaceholder, transitHeader, transitFooter
        case listeningStarted, listeningSaved, listeningScheduled, listeningUntil, savedListenTag, listenedClips
        case claudeHeader, useClaudeOnPC, pcUrlPlaceholder, pcTokenPlaceholder, claudeFooter
        case checkConnection, connectionOk, iphoneAiTag
    }

    // MARK: - Table (ja, en, pt)

    private static let table: [Key: (ja: String, en: String, pt: String)] = [
        .tabCaptions: ("字幕", "Captions", "Legendas"),
        .tabAI: ("AI", "AI", "IA"),
        .tabSearch: ("検索", "Search", "Pesquisa"),
        .tabCalc: ("計算", "Calc", "Calculadora"),
        .tabNotes: ("メモ", "Notes", "Notas"),
        .tabRemind: ("リマインダー", "Reminders", "Lembretes"),

        .listening: ("聞いています...", "Listening...", "Ouvindo..."),
        .captionsOff: ("字幕オフ", "Captions off", "Legendas desligadas"),
        .aiHint: ("ネオに質問", "Ask Neo", "Pergunte ao Neo"),
        .searchHint: ("ウェブ検索", "Web Search", "Pesquisa na web"),
        .calcHint: ("計算", "Solve Math", "Resolver contas"),
        .notesHint: ("メモ", "Notes", "Notas"),
        .remindHint: ("リマインダー", "Reminders", "Lembretes"),
        .searchLabel: ("検索: %@", "Search: %@", "Pesquisa: %@"),
        .noResults: ("結果なし", "No results", "Sem resultados"),
        .aiError: ("AIエラー: %@", "AI error: %@", "Erro da IA: %@"),
        .aiBlocked: ("iPhoneのAIはこの話題に答えられないみたい。PCのClaudeなら答えられるよ", "The iPhone AI won't answer this one. Claude on your PC can.",
                     "A IA do iPhone não responde isso. O Claude no seu PC responde."),
        .aiUnavailable: ("AIが使えません (Apple Intelligenceをオンに)", "AI unavailable (turn on Apple Intelligence)",
                         "IA indisponível (ative a Apple Intelligence)"),

        .wakeAck: ("* はい? (聞いています)", "* Yes? (listening)", "* Sim? (ouvindo)"),
        .noted: ("メモした", "Noted", "Anotado"),
        .timeUnknown: ("時間が分からない", "Couldn't read the time", "Não entendi o horário"),
        .reminderSet: ("%@ にリマインド", "Reminder at %@", "Lembrete às %@"),
        .reminderAlert: ("【リマインド】%@", "[Reminder] %@", "[Lembrete] %@"),
        .confirmDeleteLastNote: ("最後のメモを消す?", "Delete last note?", "Apagar a última nota?"),
        .confirmDeleteAllNotes: ("メモを全部消す?", "Delete all notes?", "Apagar todas as notas?"),
        .confirmDeleteAllReminders: ("リマインダーを全部消す?", "Delete all reminders?", "Apagar todos os lembretes?"),
        .confirmSuffix: ("はい/いいえ", "yes/no", "sim/não"),
        .ok: ("OK", "OK", "OK"),
        .cancelled: ("キャンセル", "Cancelled", "Cancelado"),
        .countdownMinutes: ("あと%d分", "in %d min", "em %d min"),
        .countdownHours: ("あと%d時間%d分", "in %dh %dm", "em %dh %dmin"),

        .screenHud: ("HUD", "HUD", "HUD"),
        .screenCaptions: ("字幕", "Captions", "Legendas"),
        .screenSettings: ("設定", "Settings", "Ajustes"),

        .startHud: ("HUDを開始", "Start HUD", "Iniciar HUD"),
        .stopHud: ("HUDを停止", "Stop HUD", "Parar HUD"),
        .language: ("HUDの言語", "HUD language", "Idioma do HUD"),
        .hearingLanguage: ("聞き取りの言語 (録音中)", "Listen for (while recording)", "Ouvir em (gravando)"),
        .autoLanguage: ("録音中はHUDの言語も聞く (文ごとに判断)", "While recording, also listen for the HUD language", "Gravando, ouvir também o idioma do HUD"),
        .loadingModel: ("音声モデルを読み込み中 (初回はダウンロード)...", "Loading speech model (first time downloads it)...",
                        "Carregando modelo de voz (baixa na primeira vez)..."),
        .statusHeader: ("メガネ: %@ · マイク: %@", "Glasses: %@ · Mic: %@", "Óculos: %@ · Microfone: %@"),
        .connected: ("接続中", "connected", "conectado"),
        .notConnected: ("未接続", "not connected", "desconectado"),
        .micPhone: ("スマホ (テスト)", "phone (test)", "celular (teste)"),
        .micGlasses: ("メガネ", "glasses", "óculos"),
        .hudFooter: ("「ネオ」の後にコマンド: 次 / メモ 牛乳買う / 5時にロット確認 / 天気を検索",
                     "Say \"Neo\" then a command: next / note buy milk / remind me at 5 to call / search weather",
                     "Diga \"Neo\" e um comando: próximo / anota comprar leite / me lembra às 5 de ligar / pesquisar tempo"),
        .lensPreview: ("レンズのプレビュー", "Lens preview", "Prévia da lente"),
        .tryCommand: ("コマンドを試す", "Try a command", "Testar um comando"),
        .commandPlaceholder: ("例: メモ 牛乳買う", "e.g. note buy milk", "ex.: anota comprar leite"),
        .runCommand: ("実行", "Run command", "Executar"),
        .commandFooter: ("「ネオ」の後に話したのと同じ動き。メガネ無しでも使えます。",
                         "Runs like a spoken command after \"Neo\". Works without the glasses.",
                         "Funciona como um comando falado depois de \"Neo\". Funciona sem os óculos."),
        .dashboardOpen: ("メガネのダッシュボードが開いています。下を見るか閉じるのを待ってから再試行。",
                         "The glasses dashboard is open. Look down or wait for it to close, then try again.",
                         "O painel dos óculos está aberto. Olhe para baixo ou espere fechar e tente de novo."),
        .micPermission: ("スマホのマイクの許可が必要です。", "Microphone permission is needed for phone-mic mode.",
                         "É preciso permitir o microfone para o modo celular."),
        .engineStopped: ("音声認識が停止: %@", "Speech engine stopped: %@", "Reconhecimento de voz parou: %@"),

        .startHudToBegin: ("HUDを開始してください", "Start the HUD to begin", "Inicie o HUD para começar"),
        .clearTranscript: ("字幕を消去", "Clear transcript", "Limpar transcrição"),
        .transcriptHeader: ("文字起こし · %@", "Transcript · %@", "Transcrição · %@"),
        .recordStart: ("マイク音声を録音", "Record raw mic audio", "Gravar áudio do microfone"),
        .recordStop: ("録音を停止", "Stop recording", "Parar gravação"),
        .testRecordings: ("テスト録音", "Test recordings", "Gravações de teste"),
        .recordingsFooter: ("HUD実行中のマイク音声をそのまま保存。ファイル: このiPhone内 > G2HUD > Recordings",
                            "Records exactly what the mic hears while the HUD runs. Files: On My iPhone > G2HUD > Recordings.",
                            "Grava exatamente o que o microfone ouve com o HUD ligado. Arquivos: No Meu iPhone > G2HUD > Recordings."),

        .voice: ("音声", "Voice", "Voz"),
        .requireWakeWord: ("ウェイクワードが必要 (ネオ)", "Require wake word (Neo)", "Exigir palavra de ativação (Neo)"),
        .usePhoneMic: ("スマホのマイクを使う (テスト用)", "Use phone mic (test without glasses)", "Usar microfone do celular (teste)"),
        .voiceFooter: ("オフの時は移動系 (次/前/上/下) だけが動きます。マイク変更はHUD停止中に。",
                       "With the wake word off, only navigation (next / back / up / down) runs without it. Change the mic while the HUD is stopped.",
                       "Sem a palavra de ativação, só navegação (próximo / anterior / subir / descer) funciona. Troque o microfone com o HUD parado."),
        .search: ("検索", "Search", "Pesquisa"),
        .searchFooter: ("Tavily (tavily.com、無料 月1000回) が検索してAIが要約。使い切ったらiPhone内のAIが知識だけで答えます (オフライン表示)。キーはこのiPhoneにだけ保存。",
                        "Tavily (tavily.com, free 1,000/month) searches and writes an AI summary. When it runs out, the iPhone's on-device AI answers from memory (marked offline). The key stays on this iPhone.",
                        "Tavily (tavily.com, grátis 1.000/mês) pesquisa e resume com IA. Quando acabar, a IA do iPhone responde de memória (marcado offline). A chave fica só neste iPhone."),
        .tavilyKeyPlaceholder: ("Tavily APIキー", "Tavily API key", "Chave da API Tavily"),
        .noSearchKey: ("設定で Tavily のキーを入れてください", "Add a Tavily key in Settings",
                       "Adicione uma chave Tavily nos Ajustes"),
        .offlineTag: ("(オフライン)", "(offline)", "(offline)"),
        .savedConversations: ("保存した会話", "Saved conversations", "Conversas salvas"),
        .findingImage: ("画像を探しています...", "Finding a picture...", "Procurando uma imagem..."),
        .tabSaved: ("履歴", "Saved", "Salvos"),
        .savedHint: ("保存した会話", "Saved Interactions", "Interações salvas"),
        .savedAiTag: ("AI", "AI", "IA"),
        .savedTalkTag: ("会話", "Talk", "Conversa"),
        .translating: ("翻訳中...", "Translating...", "Traduzindo..."),
        .translationFailed: ("翻訳できませんでした (設定 > アプリ > 翻訳 で言語をダウンロード)", "Couldn't translate (download the languages in Settings > Apps > Translate)", "Não foi possível traduzir (baixe os idiomas em Ajustes > Apps > Traduzir)"),
        .chatSaved: ("保存した: %@", "Saved: %@", "Salvo: %@"),
        .nothingToSave: ("保存する会話がない", "Nothing to save", "Nada para salvar"),
        .tabNav: ("ナビ", "Nav", "Rota"),
        .navAngleRight: ("右 %d°", "%d° right", "%d° à direita"),
        .navAngleLeft: ("左 %d°", "%d° left", "%d° à esquerda"),
        .navStraight: ("まっすぐ", "straight ahead", "em frente"),
        .navPlaceWalk: ("徒歩 %@ · %d分", "%@ on foot · %d min", "%@ a pé · %d min"),
        .navHint: ("地図ナビ", "Map Navigation", "Navegação no mapa"),
        .navFinding: ("探しています: %@", "Finding: %@", "Procurando: %@"),
        .navArrived: ("到着: %@", "Arrived: %@", "Chegou: %@"),
        .navRemaining: ("残り %@ · %d分", "%@ left · %d min", "Faltam %@ · %d min"),
        .navThen: ("その次: %@", "Then: %@", "Depois: %@"),
        .navRerouting: ("ルート再検索中...", "Rerouting...", "Recalculando..."),
        .navToArrival: ("到着まで", "to arrival", "até a chegada"),
        .navWalk: ("徒歩", "Walk", "A pé"),
        .navTrain: ("電車", "Train", "Trem"),
        .navBus: ("バス", "Bus", "Ônibus"),
        .navMixed: ("電車+バス", "Train+Bus", "Trem+Ônibus"),
        .navFree: ("無料", "free", "grátis"),
        .navBoard: ("%@ に乗る (%@)", "Take %@ (%@)", "Pegue %@ (%@)"),
        .navLineToward: ("%@ %@方面", "%@ for %@", "%@ sentido %@"),
        .navGetOff: ("%@で降りる", "Get off at %@", "Desça em %@"),
        .navStops: ("%d駅", "%d stops", "%d paradas"),
        .navNoTransitKey: ("電車・バスは設定でRapidAPIのキーを入れてください", "Add a RapidAPI key in Settings for trains and buses",
                           "Adicione uma chave RapidAPI nos Ajustes para trem e ônibus"),
        .navWalkTo: ("%@まで歩く", "Walk to %@", "Caminhe até %@"),
        .navExitGate: ("出口: %@", "exit: %@", "saída: %@"),
        .navNoTransit: ("電車・バスのルートが見つからない", "No train or bus route found", "Nenhuma rota de trem ou ônibus"),
        .transitKeyPlaceholder: ("RapidAPIキー (NAVITIME)", "RapidAPI key (NAVITIME)", "Chave RapidAPI (NAVITIME)"),
        .transitHeader: ("電車・バス (NAVITIME)", "Trains and buses (NAVITIME)", "Trem e ônibus (NAVITIME)"),
        .transitFooter: ("RapidAPIのNAVITIME Route(totalnavi)、無料プランは月500回まで (超えると止まるだけで課金なし)。キーはこのiPhoneにだけ保存。",
                         "NAVITIME Route (totalnavi) on RapidAPI. Free plan: 500 a month; it just stops after that, no charges. The key stays on this iPhone.",
                         "NAVITIME Route (totalnavi) no RapidAPI. Plano grátis: 500 por mês; depois só para, sem cobrança. A chave fica só neste iPhone."),
        .listeningStarted: ("聞き取り中: %@", "Listening: %@", "Ouvindo: %@"),
        .listeningSaved: ("聞き取りを保存した", "Listening saved", "Escuta salva"),
        .listeningScheduled: ("%@から聞き取り: %@", "Listening from %@: %@", "Ouvindo a partir de %@: %@"),
        .listeningUntil: ("%@まで", "until %@", "até %@"),
        .savedListenTag: ("聞き取り", "Listened", "Ouvido"),
        .listenedClips: ("聞き取り", "Listened", "Escutas"),
        .aiChats: ("保存したAIチャット", "Saved AI chats", "Conversas com IA salvas"),
        .claudeHeader: ("Claude (PC経由)", "Claude (through your PC)", "Claude (pelo PC)"),
        .useClaudeOnPC: ("AIタブでClaudeを使う", "Use Claude in the AI tab", "Usar Claude na aba IA"),
        .pcUrlPlaceholder: ("PCのアドレス (https://...ts.net)", "PC address (https://...ts.net)", "Endereço do PC (https://...ts.net)"),
        .pcTokenPlaceholder: ("トークン (token.txt)", "Token (token.txt)", "Token (token.txt)"),
        .claudeFooter: ("PCで start-bridge.cmd を起動し、TailscaleをPCとiPhoneで同じアカウントにログイン。Claudeのプランを使用 (APIキー不要)。PCがオフの時はiPhoneのAIが答えます。",
                        "Run start-bridge.cmd on the PC and sign in to Tailscale on the PC and iPhone with the same account. Uses your Claude plan (no API key). When the PC is off, the iPhone AI answers.",
                        "Rode start-bridge.cmd no PC e entre no Tailscale no PC e no iPhone com a mesma conta. Usa seu plano do Claude (sem chave de API). Com o PC desligado, a IA do iPhone responde."),
        .checkConnection: ("接続を確認", "Check connection", "Verificar conexão"),
        .connectionOk: ("PCに接続OK", "Connected to the PC", "Conectado ao PC"),
        .iphoneAiTag: ("(iPhone AI)", "(iPhone AI)", "(IA do iPhone)"),
        .imageNotFound: ("画像が見つからない", "No picture found", "Nenhuma imagem encontrada"),
        .noConversations: ("まだありません", "None yet", "Nenhuma ainda"),
        .saveConversations: ("会話を保存", "Save conversations", "Salvar conversas"),
        .saveConversationsFooter: ("HUD実行中の文字起こしを時刻付きで保存。字幕タブ > 保存した会話 で見られます (ファイル: このiPhone内 > G2HUD > Conversations)。",
                                   "Saves each HUD session's transcript with times. Open it in Captions > Saved conversations (Files: On My iPhone > G2HUD > Conversations).",
                                   "Salva a transcrição de cada sessão com horários. Veja em Legendas > Conversas salvas (Arquivos: No Meu iPhone > G2HUD > Conversations)."),
        .glassesControls: ("メガネの操作", "Glasses controls", "Controles dos óculos"),
        .touchControls: ("タッチパッド / リング操作", "Touchpad / ring controls", "Touchpad / anel"),
        .touchHelp: ("タップ=次のタブ · ダブルタップ=前 · スワイプ=スクロール",
                     "Tap = next tab · double tap = previous · swipe = scroll",
                     "Toque = próxima aba · toque duplo = anterior · deslizar = rolar"),
        .headTilt: ("頭の傾き", "Head tilt", "Inclinação da cabeça"),
        .headTiltToggle: ("頭を傾けてタブ切替", "Head tilt switches tabs", "Inclinar a cabeça troca de aba"),
        .swapLeftRight: ("左右を入れ替え", "Swap left / right", "Inverter esquerda / direita"),
        .tiltReadout: ("傾き %+.0f°   上下 %+.0f°", "Tilt %+.0f°   Up/down %+.0f°", "Inclinação %+.0f°   Cima/baixo %+.0f°"),
        .calibrate: ("キャリブレーション (正面を見てタップ)", "Calibrate (look straight ahead, then tap)",
                     "Calibrar (olhe para a frente e toque)"),
        .headTiltFooter: ("耳を肩に近づけて約0.5秒。仕事中に誤作動するならオフに。HUD実行中のみ角度が更新。",
                          "Tilt an ear toward a shoulder and hold ~0.5 s. Turn off at work if bending down triggers it. Angles update only while the HUD runs.",
                          "Incline a orelha para o ombro por ~0,5 s. Desligue no trabalho se ao se abaixar disparar. Ângulos só atualizam com o HUD ligado."),
        .notesHeader: ("メモ (%d)", "Notes (%d)", "Notas (%d)"),
        .remindersHeader: ("リマインダー (%d)", "Reminders (%d)", "Lembretes (%d)"),
    ]
}
