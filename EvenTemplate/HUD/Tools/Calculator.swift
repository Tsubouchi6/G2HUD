// Calculator.swift
//
// Evaluates spoken or typed arithmetic safely (no NSExpression, which crashes
// on bad input). Understands digits, + - * / ^ ( ), %, and spoken operators in
// Japanese and English ("3かける4", "10 divided by 4", "2の3乗").
//
// Public API:
//   Calculator.evaluate(_ input: String) throws -> Double
//   Calculator.format(_ value: Double) -> String
//   Calculator.looksLikeMath(_ input: String) -> Bool
//   enum CalculatorError

import Foundation

enum CalculatorError: LocalizedError {
    case empty
    case unexpected(String)
    case divideByZero

    var errorDescription: String? {
        switch self {
        case .empty: return "Nothing to calculate"
        case .unexpected(let token): return "Can't read \"\(token)\""
        case .divideByZero: return "Division by zero"
        }
    }
}

enum Calculator {

    // MARK: - Public

    static func evaluate(_ input: String) throws -> Double {
        let tokens = try tokenize(normalize(input))
        guard !tokens.isEmpty else { throw CalculatorError.empty }
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

    /// True when the text is mostly numbers and operators (used to route
    /// commands like "12×35" straight to the calculator).
    static func looksLikeMath(_ input: String) -> Bool {
        let normalized = normalize(input)
        guard normalized.contains(where: \.isNumber) else { return false }
        return normalized.allSatisfy { $0.isNumber || "+-*/^().% ".contains($0) }
    }

    // MARK: - Normalizing spoken words

    /// Longest phrases first so "divided by" wins over "by".
    private static let wordOperators: [(String, String)] = [
        ("divided by", "/"), ("multiplied by", "*"), ("to the power of", "^"),
        ("plus", "+"), ("minus", "-"), ("times", "*"), ("over", "/"),
        ("percent", "%"), ("x", "*"),
        ("足す", "+"), ("たす", "+"), ("プラス", "+"),
        ("引く", "-"), ("ひく", "-"), ("マイナス", "-"),
        ("掛ける", "*"), ("かける", "*"),
        ("割る", "/"), ("わる", "/"),
        ("の二乗", "^2"),
        ("パーセント", "%"),
        ("×", "*"), ("÷", "/"), ("−", "-"), ("＋", "+"), ("＊", "*"), ("／", "/"),
        ("（", "("), ("）", ")"), ("，", ""), (",", ""),
        ("は", ""), ("いくつ", ""), ("いくら", ""), ("？", ""), ("?", ""), ("=", ""), ("＝", ""),
        ("what is", ""), ("what's", ""),
    ]

    private static let fullwidthDigits: [Character: Character] = [
        "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
        "５": "5", "６": "6", "７": "7", "８": "8", "９": "9", "．": ".",
    ]

    private static func normalize(_ input: String) -> String {
        // Full-width digits to ASCII (only digits: a full transform would also
        // turn katakana like "プラス" half-width and break the word table).
        var text = String(input.lowercased().map { fullwidthDigits[$0] ?? $0 })
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

    private static func tokenize(_ text: String) throws -> [Token] {
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
            } else if "+-*/^%".contains(character) {
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
    // expression = term (("+" | "-") term)*
    // term       = power (("*" | "/") power)*
    // power      = unary ("^" power)?
    // unary      = "-" unary | postfix
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
                let rhs = try parseTerm()
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
