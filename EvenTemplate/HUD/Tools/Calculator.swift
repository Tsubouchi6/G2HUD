// Calculator.swift
//
// Evaluates spoken or typed arithmetic safely (no NSExpression, which crashes
// on bad input). Understands digits, + - * / ^ ( ), %, √, spoken operators in
// Japanese, English and Portuguese ("3かける4", "10 divided by 4", "2の3乗",
// "5 vezes 3", "3に4を足す"), and numbers as words or with 万/億 (SpokenNumbers).
// Percent works like a phone calculator: 4800 + 10% = 5280, 4800 * 10% = 480.
// Follow-ups use the last answer: "plus 5", "×2", "5足して", "答え÷3".
//
// Public API:
//   Calculator.evaluate(_ input: String, previous: Double?) throws -> Double
//   Calculator.format(_ value: Double) -> String
//   Calculator.looksLikeMath(_ input: String) -> Bool
//   enum CalculatorError

import Foundation

enum CalculatorError: LocalizedError {
    case empty
    case unexpected(String)
    case divideByZero
    case noPreviousAnswer

    var errorDescription: String? {
        switch self {
        case .empty: return "Nothing to calculate"
        case .unexpected(let token): return "Can't read \"\(token)\""
        case .divideByZero: return "Division by zero"
        case .noPreviousAnswer: return "No previous answer"
        }
    }
}

enum Calculator {

    // MARK: - Public

    static func evaluate(_ input: String, previous: Double? = nil) throws -> Double {
        var tokens = try tokenize(normalize(input), previous: previous)
        guard !tokens.isEmpty else { throw CalculatorError.empty }
        tokens = try continuing(tokens, previous: previous)
        var parser = Parser(tokens: tokens)
        let value = try parser.parseExpression()
        if parser.index < tokens.count { throw CalculatorError.unexpected(tokens[parser.index].text) }
        return value
    }

    /// Up to 6 decimals, trailing zeros removed ("420", "214.285714").
    static func format(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "error" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// True when the text is only numbers and operators once spoken words are
    /// converted (routes "12×35", "twelve times three", "plus 5" to the calculator).
    static func looksLikeMath(_ input: String) -> Bool {
        let normalized = normalize(input)
        guard normalized.contains(where: { $0.isNumber || $0 == previousMarker }) else { return false }
        return normalized.allSatisfy { $0.isNumber || "+-*/^().%√ ".contains($0) || $0 == previousMarker }
    }

    /// A follow-up like "+ 5" or "5 +" (Japanese "5足して") continues from the
    /// last answer: previous + 5.
    private static func continuing(_ tokens: [Token], previous: Double?) throws -> [Token] {
        let binary: Set<Character> = ["+", "-", "*", "/", "^"]
        let previousToken = { (value: Double) in Token(kind: .number(value), text: format(value)) }
        if case .op(let op) = tokens[0].kind, binary.contains(op), tokens.count > 1 {
            guard let previous else {
                if op == "-" || op == "+" { return tokens }  // just a signed number
                throw CalculatorError.noPreviousAnswer
            }
            return [previousToken(previous)] + tokens
        }
        if case .op(let op) = tokens[tokens.count - 1].kind, binary.contains(op), tokens.count > 1 {
            guard let previous else { throw CalculatorError.noPreviousAnswer }
            return [previousToken(previous), tokens[tokens.count - 1]] + tokens.dropLast()
        }
        return tokens
    }

    // MARK: - Normalizing spoken words

    /// Longest phrases first so "divided by" wins over "by".
    private static let wordOperators: [(String, String)] = [
        ("divided by", "/"), ("multiplied by", "*"), ("to the power of", "^"),
        ("dividido por", "/"), ("multiplicado por", "*"), ("elevado a", "^"), ("por cento", "%"),
        ("quanto é", ""), ("quanto e", ""), ("mais", "+"), ("menos", "-"), ("vezes", "*"),
        ("plus", "+"), ("minus", "-"), ("times", "*"), ("over", "/"),
        ("square root of", "√"), ("raiz quadrada de", "√"), ("raiz de", "√"), ("ルート", "√"),
        ("percent", "%"),
        ("答え", "@"), ("the answer", "@"), ("answer", "@"), ("resposta", "@"), ("それ", "@"), ("isso", "@"),
        ("足して", "+"), ("足す", "+"), ("たす", "+"), ("プラス", "+"),
        ("引いて", "-"), ("引く", "-"), ("ひく", "-"), ("マイナス", "-"),
        ("掛けて", "*"), ("かけて", "*"), ("掛ける", "*"), ("かける", "*"),
        ("割って", "/"), ("割る", "/"), ("わる", "/"),
        ("の二乗", "^2"),
        ("パーセント", "%"),
        ("×", "*"), ("÷", "/"), ("−", "-"), ("＋", "+"), ("＊", "*"), ("／", "/"),
        ("（", "("), ("）", ")"), ("，", ""), (",", ""),
        ("は", ""), ("いくつ", ""), ("いくら", ""), ("？", ""), ("?", ""), ("=", ""), ("＝", ""),
        ("what is", ""), ("what's", ""),
        // Japanese fillers last, after the operator words that contain them ("足して").
        ("して", ""), ("あと", ""), ("さらに", ""), ("に", ""), ("を", ""), ("で", ""),
    ]

    private static let fullwidthDigits: [Character: Character] = [
        "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
        "５": "5", "６": "6", "７": "7", "８": "8", "９": "9", "．": ".",
    ]

    /// Stands for the previous answer after normalizing ("答え", "answer", "それ").
    private static let previousMarker: Character = "@"

    private static func normalize(_ input: String) -> String {
        // Full-width digits to ASCII (only digits: a full transform would also
        // turn katakana like "プラス" half-width and break the word table).
        var text = String(input.lowercased().map { fullwidthDigits[$0] ?? $0 })
        text = SpokenNumbers.toDigits(text)
        // Japanese word order: "3に4を足す" -> "3+4", "10から4を引く" -> "10-4", "12を3で割る" -> "12/3"
        let number = #"(\d+(?:\.\d+)?|答え|それ)"#
        text = text.replacingOccurrences(
            of: number + #"\s*に\s*"# + number + #"\s*を\s*(足す|たす|足して)"#, with: "$1+$2", options: .regularExpression)
        text = text.replacingOccurrences(
            of: number + #"\s*に\s*"# + number + #"\s*を\s*(掛ける|かける|掛けて|かけて)"#, with: "$1*$2", options: .regularExpression)
        text = text.replacingOccurrences(
            of: number + #"\s*から\s*"# + number + #"\s*を\s*(引く|ひく|引いて|ひいて)"#, with: "$1-$2", options: .regularExpression)
        text = text.replacingOccurrences(
            of: number + #"\s*を\s*"# + number + #"\s*で\s*(割る|わる|割って|わって)"#, with: "$1/$2", options: .regularExpression)
        // "x" as times only between numbers / spaces ("12 x 3", "12x3"), not inside words.
        text = text.replacingOccurrences(of: #"(?<=[\d\s])x(?=[\d\s])"#, with: " * ", options: .regularExpression)
        // "2の3乗" -> "2^3";  "100の20%" / "100の20パーセント" -> "100*20%"
        text = text.replacingOccurrences(
            of: #"(\d+(?:\.\d+)?)の(\d+(?:\.\d+)?)乗"#, with: "$1^$2", options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"の\s*(\d+(?:\.\d+)?)\s*(%|パーセント)"#, with: "*$1%", options: .regularExpression
        )
        for (word, symbol) in wordOperators {
            text = text.replacingOccurrences(of: word, with: " \(symbol) ")
        }
        return text
    }

    // MARK: - Tokenizer

    private struct Token {
        enum Kind { case number(Double), op(Character), open, close }
        let kind: Kind
        let text: String
    }

    private static func tokenize(_ text: String, previous: Double?) throws -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
            } else if character.isNumber || character == "." {
                var end = index
                while end < text.endIndex, text[end].isNumber || text[end] == "." {
                    end = text.index(after: end)
                }
                let literal = String(text[index ..< end])
                guard let value = Double(literal) else { throw CalculatorError.unexpected(literal) }
                tokens.append(Token(kind: .number(value), text: literal))
                index = end
            } else if character == previousMarker {
                guard let previous else { throw CalculatorError.noPreviousAnswer }
                tokens.append(Token(kind: .number(previous), text: format(previous)))
                index = text.index(after: index)
            } else if "+-*/^%√".contains(character) {
                tokens.append(Token(kind: .op(character), text: String(character)))
                index = text.index(after: index)
            } else if character == "(" {
                tokens.append(Token(kind: .open, text: "("))
                index = text.index(after: index)
            } else if character == ")" {
                tokens.append(Token(kind: .close, text: ")"))
                index = text.index(after: index)
            } else {
                throw CalculatorError.unexpected(String(character))
            }
        }
        return tokens
    }

    // MARK: - Parser (recursive descent)
    // expression = term (("+" | "-") term)*     a lone "n%" term adds/subtracts n% of the left side
    // term       = power (("*" | "/") power)*
    // power      = unary ("^" power)?
    // unary      = "-" unary | "√" unary | postfix
    // postfix    = primary "%"?
    // primary    = number | "(" expression ")"

    private struct Parser {
        let tokens: [Token]
        var index = 0

        init(tokens: [Token]) { self.tokens = tokens }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while let op = peekOp(), op == "+" || op == "-" {
                index += 1
                let start = index
                var rhs = try parseTerm()
                // Phone-calculator percent: "4800 + 10%" = 4800 + 480.
                if index == start + 2, case .op("%") = tokens[index - 1].kind { rhs *= value }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() throws -> Double {
            var value = try parsePower()
            while let op = peekOp(), op == "*" || op == "/" {
                index += 1
                let rhs = try parsePower()
                if op == "/" {
                    guard rhs != 0 else { throw CalculatorError.divideByZero }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        mutating func parsePower() throws -> Double {
            let base = try parseUnary()
            if peekOp() == "^" {
                index += 1
                return pow(base, try parsePower())
            }
            return base
        }

        mutating func parseUnary() throws -> Double {
            if peekOp() == "-" {
                index += 1
                return -(try parseUnary())
            }
            if peekOp() == "+" {
                index += 1
                return try parseUnary()
            }
            if peekOp() == "√" {
                index += 1
                let value = try parseUnary()
                guard value >= 0 else { throw CalculatorError.unexpected("√") }
                return value.squareRoot()
            }
            return try parsePostfix()
        }

        mutating func parsePostfix() throws -> Double {
            var value = try parsePrimary()
            if peekOp() == "%" {
                index += 1
                value /= 100
            }
            return value
        }

        mutating func parsePrimary() throws -> Double {
            guard index < tokens.count else { throw CalculatorError.empty }
            let token = tokens[index]
            switch token.kind {
            case .number(let value):
                index += 1
                return value
            case .open:
                index += 1
                let value = try parseExpression()
                guard index < tokens.count, case .close = tokens[index].kind else {
                    throw CalculatorError.unexpected("(")
                }
                index += 1
                return value
            default:
                throw CalculatorError.unexpected(token.text)
            }
        }

        private func peekOp() -> Character? {
            guard index < tokens.count, case .op(let op) = tokens[index].kind else { return nil }
            return op
        }
    }
}
