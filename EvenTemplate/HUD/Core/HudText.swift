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
        case searchLabel, noResults, aiError, aiUnavailable
        // Lens feedback
        case wakeAck, noted, timeUnknown, reminderSet, reminderAlert
        case confirmDeleteLastNote, confirmDeleteAllNotes, confirmDeleteAllReminders, confirmSuffix
        case ok, cancelled, countdownMinutes, countdownHours
        // Phone: tab bar
        case screenHud, screenCaptions, screenSettings
        // Phone: HUD screen
        case startHud, stopHud, language, loadingModel, statusHeader, connected, notConnected
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
        .aiHint: ("(Claude + 質問)", "(Claude + question)", "(Claude + pergunta)"),
        .searchHint: ("(Claude 天気を検索)", "(Claude search weather)", "(Claude pesquisar tempo)"),
        .calcHint: ("(Claude 計算 12かける35)", "(Claude calculate 12 times 35)", "(Claude calcular 12 vezes 35)"),
        .notesHint: ("(Claude メモ 牛乳買う)", "(Claude note buy milk)", "(Claude anota comprar leite)"),
        .remindHint: ("(Claude 5時にロット確認)", "(Claude remind me at 5 to check)", "(Claude me lembra às 5 de conferir)"),
        .searchLabel: ("検索: %@", "Search: %@", "Pesquisa: %@"),
        .noResults: ("結果なし", "No results", "Sem resultados"),
        .aiError: ("AIエラー: %@", "AI error: %@", "Erro da IA: %@"),
        .aiUnavailable: ("AIが使えません (Apple Intelligenceをオンに)", "AI unavailable (turn on Apple Intelligence)",
                         "IA indisponível (ative a Apple Intelligence)"),

        .wakeAck: ("はい?", "Yes?", "Sim?"),
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
        .language: ("言語", "Language", "Idioma"),
        .loadingModel: ("音声モデルを読み込み中 (初回はダウンロード)...", "Loading speech model (first time downloads it)...",
                        "Carregando modelo de voz (baixa na primeira vez)..."),
        .statusHeader: ("メガネ: %@ · マイク: %@", "Glasses: %@ · Mic: %@", "Óculos: %@ · Microfone: %@"),
        .connected: ("接続中", "connected", "conectado"),
        .notConnected: ("未接続", "not connected", "desconectado"),
        .micPhone: ("スマホ (テスト)", "phone (test)", "celular (teste)"),
        .micGlasses: ("メガネ", "glasses", "óculos"),
        .hudFooter: ("「Claude」の後にコマンド: 次 / メモ 牛乳買う / 5時にロット確認 / 天気を検索",
                     "Say \"Claude\" then a command: next / note buy milk / remind me at 5 to call / search weather",
                     "Diga \"Claude\" e um comando: próximo / anota comprar leite / me lembra às 5 de ligar / pesquisar tempo"),
        .lensPreview: ("レンズのプレビュー", "Lens preview", "Prévia da lente"),
        .tryCommand: ("コマンドを試す", "Try a command", "Testar um comando"),
        .commandPlaceholder: ("例: メモ 牛乳買う", "e.g. note buy milk", "ex.: anota comprar leite"),
        .runCommand: ("実行", "Run command", "Executar"),
        .commandFooter: ("「Claude」の後に話したのと同じ動き。メガネ無しでも使えます。",
                         "Runs like a spoken command after \"Claude\". Works without the glasses.",
                         "Funciona como um comando falado depois de \"Claude\". Funciona sem os óculos."),
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
        .requireWakeWord: ("ウェイクワードが必要 (Claude)", "Require wake word (Claude)", "Exigir palavra de ativação (Claude)"),
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
