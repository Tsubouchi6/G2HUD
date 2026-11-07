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
//   VoicePhrases.wantsPicture(_:) -> Bool          // "show me a picture of ..."
//   VoicePhrases.wantsStock(_:) -> Bool            // "トヨタの株価", "apple stock"
//   VoicePhrases.wantsChart(_:) -> Bool            // "日本の人口のグラフ", "chart of ..."
//   VoicePhrases.stockRange(_:) -> StockRange      // "今年" -> .year (default .month)
//   VoicePhrases.stripChartWords(_:) -> String     // "トヨタの株価" -> "トヨタ"
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

    /// Words asking to see a picture. Japanese as substrings, others as phrases.
    static let pictureSubstrings = ["画像", "写真", "見せて", "見た目", "どんな形"]
    static let picturePhrases = [
        "picture", "image", "photo", "show me", "look like", "looks like",
        "foto", "imagem", "mostra", "mostrar", "aparência", "parece",
    ]

    /// Stock / market words (checked before pictures, so "show me Apple's
    /// stock" draws a chart). Japanese as substrings, others as whole words.
    static let stockSubstrings = ["株価", "株", "日経平均", "ダウ", "ナスダック", "ビットコイン", "仮想通貨", "為替", "ドル円"]
    static let stockWords = [
        "stock", "stocks", "shares", "share price", "ticker", "nasdaq", "nikkei", "dow", "bitcoin", "crypto",
        "ação", "ações", "acao", "acoes", "bolsa", "cotação", "cotacao", "ibovespa",
    ]
    /// Chart / statistics words. Same matching rules.
    static let chartSubstrings = ["統計", "グラフ", "チャート", "推移"]
    static let chartWords = [
        "chart", "graph", "statistics", "stats", "statistic", "trend",
        "gráfico", "grafico", "estatística", "estatisticas", "estatísticas", "estatistica",
    ]
    /// Time-range words for stock charts, longest range first so "5年" beats "年".
    static let fiveYearWords = ["5年", "五年", "five years", "5 years", "cinco anos", "5 anos"]
    static let yearWords = ["今年", "1年", "一年", "年間", "year", "ano"]
    static let weekWords = ["今週", "1週間", "一週間", "週", "week", "semana"]
    static let dayWords = ["今日", "本日", "1日", "today", "day", "hoje", "dia"]

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

    static func wantsPicture(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if pictureSubstrings.contains(where: { lowered.contains($0) }) { return true }
        let padded = " " + lowered.components(separatedBy: CharacterSet.letters.inverted).joined(separator: " ") + " "
        return picturePhrases.contains(where: { padded.contains(" \($0) ") })
    }

    static func wantsStock(_ text: String) -> Bool {
        containsSubstringOrWord(text, substrings: stockSubstrings, words: stockWords)
    }

    static func wantsChart(_ text: String) -> Bool {
        containsSubstringOrWord(text, substrings: chartSubstrings, words: chartWords)
    }

    static func stockRange(_ text: String) -> StockRange {
        if containsAny(text.lowercased(), fiveYearWords) { return .fiveYears }
        if containsSubstringOrWord(text, substrings: ["年"], words: yearWords) { return .year }
        if containsSubstringOrWord(text, substrings: ["週"], words: weekWords) { return .week }
        if containsSubstringOrWord(text, substrings: ["今日", "本日"], words: dayWords) { return .day }
        return .month
    }

    /// Removes stock, chart, range, and filler words, leaving the subject
    /// ("トヨタの今年の株価のグラフ" -> "トヨタ").
    static func stripChartWords(_ text: String) -> String {
        var result = " " + text.lowercased().replacingOccurrences(of: "'", with: " ") + " "
        let japanese = stockSubstrings + chartSubstrings + ["今年", "今週", "今日", "本日", "5年", "1年", "1週間",
                                                            "見せて", "表示して", "出して", "教えて", "の", "を"]
        for word in japanese.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: word, with: " ")
        }
        let latin = stockWords + chartWords + fiveYearWords + yearWords + weekWords + dayWords + [
            "show me", "show", "the", "of", "for", "price", "this", "last", "past", "a", "an", "s",
            "mostra", "mostrar", "me", "do", "da", "de", "o", "a", "preço", "preco", "este", "esse", "último", "ultimo",
        ]
        for word in latin.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: " \(word) ", with: " ")
        }
        return result.components(separatedBy: separators).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Japanese substrings anywhere, or Latin words/phrases on word boundaries.
    private static func containsSubstringOrWord(_ text: String, substrings: [String], words: [String]) -> Bool {
        let lowered = text.lowercased()
        if substrings.contains(where: { lowered.contains($0) }) { return true }
        let padded = " " + lowered.components(separatedBy: CharacterSet.letters.inverted.subtracting(.decimalDigits))
            .joined(separator: " ") + " "
        return words.contains(where: { padded.contains(" \($0) ") })
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
