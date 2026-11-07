// SpokenNumbers.swift
//
// Turns numbers written as words into digits, for the calculator:
//   Japanese: 3万 -> 30000, 1億2000万 -> 120000000, 三百五十 -> 350, 3.5万 -> 35000
//   English:  twelve -> 12, one hundred and five -> 105, two thousand -> 2000
//   Portuguese: vinte e dois -> 22, duzentos -> 200, três mil -> 3000
// Speech-to-text usually writes digits already; this catches the rest.
//
// Public API: SpokenNumbers.toDigits(_ text: String) -> String   // expects lowercase text

import Foundation

enum SpokenNumbers {

    static func toDigits(_ text: String) -> String {
        latinToDigits(japaneseToDigits(text))
    }

    // MARK: - Japanese (kanji numerals and 万/億/兆 units)

    private static let kanjiDigits: [Character: Double] = [
        "〇": 0, "零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    private static let smallUnits: [Character: Double] = ["十": 10, "百": 100, "千": 1000]
    private static let bigUnits: [Character: Double] = ["万": 1e4, "億": 1e8, "兆": 1e12]

    /// Replaces each run of digits/kanji numerals that contains a kanji numeral or unit.
    private static func japaneseToDigits(_ text: String) -> String {
        let pattern = #"[0-9.〇零一二三四五六七八九十百千万億兆]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            let run = String(result[range])
            guard run.contains(where: { kanjiDigits[$0] != nil || smallUnits[$0] != nil || bigUnits[$0] != nil }),
                  let value = japaneseValue(run)
            else { continue }
            result.replaceSubrange(range, with: plain(value))
        }
        return result
    }

    /// Standard reading: digits accumulate, 十百千 multiply within a section,
    /// 万億兆 close a section. Arabic digits may mix in ("3.5万", "2000万").
    private static func japaneseValue(_ run: String) -> Double? {
        var total = 0.0, section = 0.0
        var current: Double?
        var arabic = ""
        func flushArabic() -> Bool {
            guard !arabic.isEmpty else { return true }
            guard let value = Double(arabic) else { return false }
            current = value
            arabic = ""
            return true
        }
        for character in run {
            if character.isASCII, character.isNumber || character == "." {
                arabic.append(character)
                continue
            }
            guard flushArabic() else { return nil }
            if let digit = kanjiDigits[character] {
                current = (current ?? 0) * 10 + digit  // 二〇二六 reads positionally
            } else if let unit = smallUnits[character] {
                section += (current ?? 1) * unit
                current = nil
            } else if let unit = bigUnits[character] {
                let amount = section + (current ?? 0)
                total += (amount == 0 ? 1 : amount) * unit
                section = 0
                current = nil
            }
        }
        guard flushArabic() else { return nil }
        return total + section + (current ?? 0)
    }

    // MARK: - English / Portuguese words

    private enum Word {
        case unit(Double)       // added: one, twenty, vinte, duzentos
        case hundred            // multiplies: (one) hundred
        case scale(Double)      // closes a group: thousand, mil, million
        case joiner             // "and" / "e" between number words
    }

    private static let words: [String: Word] = {
        var table: [String: Word] = [:]
        let english = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                       "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
                       "eighteen", "nineteen"]
        for (value, word) in english.enumerated() { table[word] = .unit(Double(value)) }
        for (value, word) in ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"].enumerated() {
            table[word] = .unit(Double((value + 2) * 10))
        }
        table["hundred"] = .hundred
        table["thousand"] = .scale(1e3)
        table["million"] = .scale(1e6)
        table["billion"] = .scale(1e9)
        table["and"] = .joiner

        let portuguese: [(String, Double)] = [
            ("um", 1), ("uma", 1), ("dois", 2), ("duas", 2), ("três", 3), ("tres", 3), ("quatro", 4),
            ("cinco", 5), ("seis", 6), ("sete", 7), ("oito", 8), ("nove", 9), ("dez", 10), ("onze", 11),
            ("doze", 12), ("treze", 13), ("catorze", 14), ("quatorze", 14), ("quinze", 15),
            ("dezesseis", 16), ("dezessete", 17), ("dezoito", 18), ("dezenove", 19),
            ("vinte", 20), ("trinta", 30), ("quarenta", 40), ("cinquenta", 50), ("sessenta", 60),
            ("setenta", 70), ("oitenta", 80), ("noventa", 90),
            ("cem", 100), ("cento", 100), ("duzentos", 200), ("duzentas", 200), ("trezentos", 300),
            ("quatrocentos", 400), ("quinhentos", 500), ("seiscentos", 600), ("setecentos", 700),
            ("oitocentos", 800), ("novecentos", 900),
        ]
        for (word, value) in portuguese { table[word] = .unit(value) }
        table["mil"] = .scale(1e3)
        for word in ["milhão", "milhao", "milhões", "milhoes"] { table[word] = .scale(1e6) }
        table["e"] = .joiner
        return table
    }()

    /// Replaces each run of number words with its value; other words stay.
    private static func latinToDigits(_ text: String) -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var index = 0
        while index < tokens.count {
            guard case .some(let first) = words[tokens[index]], !isJoiner(first) else {
                output.append(tokens[index])
                index += 1
                continue
            }
            var total = 0.0, current = 0.0
            var end = index
            var scan = index
            while scan < tokens.count, let word = words[tokens[scan]] {
                switch word {
                case .unit(let value): current += value
                case .hundred: current = (current == 0 ? 1 : current) * 100
                case .scale(let value):
                    total += (current == 0 ? 1 : current) * value
                    current = 0
                case .joiner:
                    // Only joins when another number word follows.
                    guard scan + 1 < tokens.count, let next = words[tokens[scan + 1]], !isJoiner(next) else {
                        scan = tokens.count
                        continue
                    }
                }
                end = scan
                scan += 1
            }
            output.append(plain(total + current))
            index = end + 1
        }
        return output.joined(separator: " ")
    }

    private static func isJoiner(_ word: Word) -> Bool {
        if case .joiner = word { return true }
        return false
    }

    /// 30000.0 -> "30000", 3.5 -> "3.5"
    private static func plain(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }
}
