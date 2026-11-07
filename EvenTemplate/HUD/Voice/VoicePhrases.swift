// VoicePhrases.swift
//
// The fixed phrase tables for voice commands (Japanese, English, Portuguese) and the
// small text helpers that match them. Edit the tables to add new phrasings;
// matching ignores spaces, punctuation, case, and polite endings like "して".
//
// Public API:
//   VoicePhrases.normalize(_:) -> String
//   VoicePhrases.stripWakeWord(_:) -> String?      // nil = no wake word; "" = wake word only
//   VoicePhrases.matches(_:_:) -> Bool              // whole-phrase match
//   VoicePhrases.payload(_:_:suffixes:) -> String?  // text after a prefix / before a suffix
//   VoicePhrases.stripOpenWords(_:) -> String       // "字幕を開いて" -> "字幕"
//   VoicePhrases.containsAny(_:_:) -> Bool
//   VoicePhrases.isNavigation(_:) -> Bool
//   VoicePhrases.mentionsLiveInfo(_:) -> Bool      // needs the web (weather, news, now...)
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

    /// Words that mean the answer needs live web data, so the command goes to
    /// Search instead of the offline AI. Japanese is matched as substrings;
    /// English/Portuguese as whole words (so "know" doesn't match "now").
    static let liveInfoSubstrings = [
        "天気", "気温", "温度", "何度", "予報", "雨", "雪", "ニュース", "株価", "値段", "価格",
        "営業時間", "何時まで", "開いてる", "今日", "今", "現在", "最新", "為替", "地震", "渋滞",
    ]
    static let liveInfoWords = [
        "weather", "temperature", "forecast", "rain", "snow", "news", "price", "prices", "stock",
        "hours", "open", "now", "today", "tonight", "latest", "current", "score", "exchange",
        "tempo", "temperatura", "previsão", "chuva", "notícias", "noticias", "preço", "preços",
        "cotação", "horário", "aberto", "agora", "hoje", "atual", "últimas",
    ]

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
        var remainder = text
        for call in callPrefixes where remainder.hasPrefix(call) {
            remainder = String(remainder.dropFirst(call.count)).trimmingCharacters(in: separators)
            break
        }
        for word in HudConstants.wakeWords where remainder.hasPrefix(word) {
            return String(remainder.dropFirst(word.count)).trimmingCharacters(in: separators)
        }
        return nil
    }

    // MARK: - Matching

    static func matches(_ text: String, _ phrases: [String]) -> Bool {
        let key = core(text)
        return phrases.contains { core($0) == key }
    }

    static func containsAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    static func mentionsLiveInfo(_ text: String) -> Bool {
        if liveInfoSubstrings.contains(where: { text.contains($0) }) { return true }
        let words = Set(text.lowercased().components(separatedBy: CharacterSet.letters.inverted))
        return liveInfoWords.contains(where: { words.contains($0) })
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
