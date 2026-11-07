// VoicePhrases.swift
//
// The fixed phrase tables for voice commands (Japanese, English, Portuguese) and the
// small text helpers that match them. Edit the tables to add new phrasings;
// matching ignores spaces, punctuation, case, and polite endings like "して".
//
// Public API:
//   VoicePhrases.normalize(_:) -> String
//   VoicePhrases.stripWakeWord(_:) -> String?      // nil = no wake word; "" = wake word only
//   VoicePhrases.soundAlikeWake(_:) -> (rest, pausedAfter)?  // starts with "new" etc. (misheard "Neo")
//   VoicePhrases.matches(_:_:) -> Bool              // whole-phrase match
//   VoicePhrases.payload(_:_:suffixes:) -> String?  // text after a prefix / before a suffix
//   VoicePhrases.stripOpenWords(_:) -> String       // "字幕を開いて" -> "字幕"
//   VoicePhrases.containsAny(_:_:) -> Bool
//   VoicePhrases.isNavigation(_:) -> Bool
//   VoicePhrases.languageMentioned(_:) -> HudLanguage?   // "英語に翻訳" -> .english
//   VoicePhrases.number(in:) -> Int?                      // "2番" -> 2
//   phrase tables: next, previous, scrollUp, scrollDown, yes, no, ...

import Foundation

enum VoicePhrases {

    // MARK: - Phrase tables

    static let next = ["次", "つぎ", "次のタブ", "右", "next", "next tab", "right",
                       "próximo", "próxima", "proximo", "proxima", "seguinte", "direita"]
    static let previous = ["前", "まえ", "前のタブ", "戻って", "戻る", "左", "back", "previous", "left",
                           "anterior", "voltar", "volta", "esquerda"]
    static let scrollUp = ["上", "うえ", "スクロールアップ", "上にスクロール", "scroll up", "up",
                           "subir", "sobe", "para cima"]
    static let scrollDown = ["下", "した", "スクロールダウン", "下にスクロール", "scroll down", "down",
                             "descer", "desce", "para baixo"]
    static let yes = ["はい", "うん", "ええ", "オッケー", "おっけー", "ok", "okay", "yes", "yeah", "いいよ", "お願い",
                      "sim", "pode", "claro", "isso"]
    static let no = ["いいえ", "いや", "やめて", "キャンセル", "no", "cancel", "stop",
                     "não", "nao", "cancelar", "cancela"]

    static let deleteLastNote = ["最後のメモを消して", "最後のメモ消して", "メモを消して", "delete last note", "delete note",
                                 "apagar última nota", "apaga a última nota", "apagar nota"]
    static let deleteAllNotes = ["メモを全部消して", "メモ全部消して", "delete all notes", "clear notes",
                                 "apagar todas as notas", "apaga todas as notas"]
    static let deleteAllReminders = ["リマインダーを全部消して", "リマインダー全部消して", "delete all reminders", "clear reminders",
                                     "apagar todos os lembretes", "apaga todos os lembretes"]
    static let clearCaptions = ["字幕をクリア", "字幕クリア", "字幕を消して", "clear captions", "limpar legendas"]

    static let notePrefixes = ["メモして", "メモ", "めも", "note", "take a note", "write down",
                               "anota", "anotar", "nota"]
    static let searchPrefixes = ["検索して", "検索", "調べて", "search for", "search", "google", "look up",
                                 "pesquisar", "pesquisa", "procurar", "procura", "buscar", "busca"]
    static let searchSuffixes = ["を検索して", "を検索", "について調べて", "を調べて", "調べて", "検索して", "検索"]
    static let calcPrefixes = ["計算して", "計算", "けいさん", "calculate", "calc", "calcular", "calcula"]
    static let aiPrefixes = ["質問", "ai", "エーアイ", "聞いて", "ask", "question", "pergunta", "perguntar"]
    /// Explicit reminder words: if the time can't be read, the user is told.
    static let reminderWords = ["リマインド", "思い出させて", "remind me", "reminder",
                                "me lembra", "me lembre", "lembrete", "lembrar"]
    /// Softer words that only count as a reminder when a time is also found.
    static let softReminderWords = ["知らせて", "教えて", "通知して", "avisa", "avise"]

    /// Saved tab (only while it is open): back to the list, translate.
    static let savedListWords = ["一覧", "リスト", "一覧に戻って", "閉じて", "list", "back to list", "close", "lista", "fechar"]
    static let translateWords = ["翻訳", "訳して", "translate", "translation", "traduz", "traduzir", "tradução", "traducao"]
    /// Nav tab (only while it is open): minimal view, full view, route map.
    static let navMinimalWords = ["シンプル", "シンプルにして", "ミニマル", "画面をすっきり", "simple", "minimal", "clear screen", "simples", "mínimo", "minimo"]
    static let navFullWords = ["詳しく", "詳細", "全部表示", "full", "details", "detailed", "completo", "detalhes"]
    static let navZoomInWords = ["ズームイン", "拡大", "大きく", "zoom in", "closer", "aproximar", "aproxima", "mais perto"]
    static let navZoomOutWords = ["ズームアウト", "縮小", "小さく", "zoom out", "further", "afastar", "afasta", "mais longe"]
    static let navMapWords = ["地図", "マップ", "地図を見せて", "map", "show map", "mapa", "mostra o mapa"]

    /// Ends the listening window after "Neo" (whole phrase only).
    static let endConversationWords = [
        "ありがとう", "ありがとうございます", "以上", "終わり", "おわり", "もう大丈夫",
        "thanks", "thank you", "that's all", "thats all", "bye", "goodbye",
        "obrigado", "obrigada", "valeu", "tchau", "é isso", "e isso",
    ]

    /// Language names for "英語に翻訳" / "translate to Portuguese".
    static let languageWords: [HudLanguage: [String]] = [
        .japanese: ["日本語", "japanese", "japonês", "japones"],
        .english: ["英語", "english", "inglês", "ingles"],
        .portuguese: ["ポルトガル語", "portuguese", "português", "portugues"],
    ]
    private static let kanjiDigits: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]

    private static let politeEndings = ["してください", "ください", "して", "へ", "に"]
    private static let openWords = ["タブを開いて", "を開いて", "開いて", "タブ", "に切り替えて", "を表示", "見せて",
                                    "open ", "go to ", "show ", " tab",
                                    "abrir ", "abre ", "mostrar ", "vai para ", "aba "]
    private static let callPrefixes = ["ねえ", "ねぇ", "えっと", "あの", "hey ", "ok ", "okay ", "ei ", "ô ", "oi ", "ヘイ"]

    // MARK: - Normalizing

    /// Lowercased, trimmed, with surrounding punctuation removed.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: separators)
    }

    private static let separators = CharacterSet(charactersIn: " 　、。,.!！?？・「」")

    /// Spaces and punctuation removed, for loose comparison.
    private static func compact(_ text: String) -> String {
        String(text.unicodeScalars.filter { !separators.contains($0) })
    }

    /// Compact form with polite endings removed ("次へ" -> "次").
    private static func core(_ text: String) -> String {
        var result = compact(text)
        for ending in politeEndings where result.hasSuffix(ending) && result.count > ending.count {
            result.removeLast(ending.count)
            break
        }
        return result
    }

    // MARK: - Wake word

    /// If `text` starts with a wake word, returns what follows it ("" if
    /// nothing does). Returns nil when there is no wake word.
    static func stripWakeWord(_ text: String) -> String? {
        matchStart(text, words: HudConstants.wakeWords)?.rest
    }

    /// When `text` starts with a word speech-to-text writes instead of the wake
    /// word ("new" for "Neo"): what follows it, and whether a comma came right
    /// after (a pause, as when addressing someone). nil otherwise.
    /// The router then decides from context whether it was meant as a command.
    static func soundAlikeWake(_ text: String) -> (rest: String, pausedAfter: Bool)? {
        guard let match = matchStart(text, words: HudConstants.wakeSoundAlikes) else { return nil }
        let paused = match.rawRest.first.map { [",", "、", "，"].contains($0) } ?? false
        return (match.rest, paused)
    }

    /// Skips a call prefix ("hey", "ねえ"), then matches one of `words` as a
    /// whole word ("neon" / "ネオン" don't count as "neo" / "ネオ").
    private static func matchStart(_ text: String, words: [String]) -> (rest: String, rawRest: Substring)? {
        var remainder = text
        for call in callPrefixes where remainder.hasPrefix(call) {
            remainder = String(remainder.dropFirst(call.count)).trimmingCharacters(in: separators)
            break
        }
        for word in words where remainder.hasPrefix(word) {
            let rest = remainder.dropFirst(word.count)
            if let next = rest.first, let last = word.last, sameScript(last, next) { continue }
            return (String(rest).trimmingCharacters(in: separators), rest)
        }
        return nil
    }

    /// True when both characters are Latin letters, both katakana, or both
    /// hiragana, i.e. the second continues the same word.
    private static func sameScript(_ a: Character, _ b: Character) -> Bool {
        func script(_ c: Character) -> Int? {
            guard let value = c.unicodeScalars.first?.value else { return nil }
            if c.isASCII && c.isLetter { return 0 }
            if (0x30A0...0x30FF).contains(value) { return 1 }  // katakana (incl. ー)
            if (0x3040...0x309F).contains(value) { return 2 }  // hiragana
            return nil
        }
        guard let first = script(a) else { return false }
        return first == script(b)
    }

    // MARK: - Matching

    static func matches(_ text: String, _ phrases: [String]) -> Bool {
        let key = core(text)
        return phrases.contains { core($0) == key }
    }

    static func containsAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    /// A language named in `text` (for translation targets), if any.
    static func languageMentioned(_ text: String) -> HudLanguage? {
        let lowered = text.lowercased()
        return languageWords.first { _, words in words.contains { lowered.contains($0) } }?.key
    }

    /// First number in "2番", "number 12", "número 3", "三番" (1-99).
    static func number(in text: String) -> Int? {
        let digits = text.drop { !$0.isNumber }.prefix { $0.isNumber }
        if let value = Int(String(digits).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? String(digits)) { return value }
        for character in text { if let value = kanjiDigits[character] { return value } }
        return nil
    }

    static func isNavigation(_ text: String) -> Bool {
        matches(text, next) || matches(text, previous) || matches(text, scrollUp) || matches(text, scrollDown)
    }

    /// "字幕を開いて" -> "字幕", "open notes" -> "notes".
    static func stripOpenWords(_ text: String) -> String {
        var result = text
        for word in openWords {
            result = result.replacingOccurrences(of: word, with: "")
        }
        return core(result)
    }

    /// Text after one of `prefixes` ("メモ 牛乳" -> "牛乳") or before one of
    /// `suffixes` ("天気を検索" -> "天気"). nil if none match or nothing is left.
    static func payload(_ text: String, _ prefixes: [String], suffixes: [String] = []) -> String? {
        // Longest first so "メモして" wins over "メモ".
        for prefix in prefixes.sorted(by: { $0.count > $1.count }) where text.hasPrefix(prefix) {
            let rest = String(text.dropFirst(prefix.count)).trimmingCharacters(in: separators)
            if !rest.isEmpty { return rest }
        }
        for suffix in suffixes.sorted(by: { $0.count > $1.count }) where text.hasSuffix(suffix) {
            let rest = String(text.dropLast(suffix.count)).trimmingCharacters(in: separators)
            if !rest.isEmpty { return rest }
        }
        return nil
    }
}
