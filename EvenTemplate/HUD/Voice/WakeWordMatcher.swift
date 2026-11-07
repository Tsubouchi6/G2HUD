// WakeWordMatcher.swift
//
// Finds the wake word "Claude" at the start of a transcript by how it SOUNDS,
// not by exact spelling. Apple's SpeechTranscriber can't be taught new words
// (only DictationTranscriber takes contextual strings, per Apple docs), so it
// writes "Claude" in many ways: "cloud", "clawed", 苦労ど, 黒ード...
//   Latin text: the first word, accents removed, against HudConstants.wakeSoundsLatin.
//   Japanese:   the first words' romaji reading (CFStringTokenizer gives readings
//               for kana and kanji), long vowels folded, against wakeSoundsJapanese.
//
// Public API: WakeWordMatcher.remainder(after text: String) -> String?
//   nil = doesn't start with the wake word; "" = wake word only.

import Foundation

enum WakeWordMatcher {

    static func remainder(after text: String) -> String? {
        latinRemainder(text) ?? japaneseRemainder(text)
    }

    // MARK: - Latin (English / Portuguese)

    private static func latinRemainder(_ text: String) -> String? {
        let wordEnd = text.firstIndex { !($0.isLetter || $0 == "'" || $0 == "’") } ?? text.endIndex
        guard wordEnd > text.startIndex else { return nil }
        var word = String(text[..<wordEnd])
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
        for suffix in ["'s", "’s"] where word.hasSuffix(suffix) { word.removeLast(suffix.count) }
        guard HudConstants.wakeSoundsLatin.contains(word) else { return nil }
        return trimmed(text[wordEnd...])
    }

    // MARK: - Japanese

    /// Reads the first few words aloud (romaji) and checks if they sound like クロード.
    private static func japaneseRemainder(_ text: String) -> String? {
        let utf16Count = text.utf16.count
        guard utf16Count > 0,
              let tokenizer = CFStringTokenizerCreate(
                  nil, text as CFString, CFRangeMake(0, utf16Count),
                  kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale
              )
        else { return nil }

        var reading = ""
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription
            ) as? String else { return nil }
            reading += fold(latin)
            if HudConstants.wakeSoundsJapanese.contains(reading) {
                let end = String.Index(utf16Offset: range.location + range.length, in: text)
                return trimmed(text[end...])
            }
            if reading.count > HudConstants.wakeReadingMaxLetters { return nil }
        }
        return nil
    }

    /// "kurōdo" / "kuroudo" -> "kurodo": no accents, letters only, long vowels single.
    private static func fold(_ romaji: String) -> String {
        var result = romaji.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isLetter }
        for (long, short) in [("ou", "o"), ("oo", "o"), ("uu", "u"), ("aa", "a"), ("ii", "i"), ("ee", "e")] {
            result = result.replacingOccurrences(of: long, with: short)
        }
        return result
    }

    private static func trimmed(_ rest: Substring) -> String {
        String(rest).trimmingCharacters(in: CharacterSet(charactersIn: " 　、。,.!！?？・「」"))
    }
}
