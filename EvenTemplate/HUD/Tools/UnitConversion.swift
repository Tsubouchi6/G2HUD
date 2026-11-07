// UnitConversion.swift
//
// Exact unit conversion with Apple's Measurement/UnitConverter (free,
// on-device), plus currencies from Yahoo Finance's live rate ("USDJPY=X",
// free, no key). Unit names are matched loosely ("km", "kilometers", "キロ").
//
// Public API:
//   UnitConversion.convert(_ value:, from:, to:) async throws -> Double
//   enum UnitConversionError

import Foundation

enum UnitConversionError: LocalizedError {
    case unknownUnit(String)
    case incompatible(String, String)

    var errorDescription: String? {
        switch self {
        case .unknownUnit(let name): return "Unknown unit: \(name)"
        case .incompatible(let from, let to): return "Can't convert \(from) to \(to)"
        }
    }
}

enum UnitConversion {

    static func convert(_ value: Double, from: String, to: String) async throws -> Double {
        let fromKey = key(from), toKey = key(to)
        if let fromUnit = units[fromKey], let toUnit = units[toKey] {
            guard ObjectIdentifier(type(of: fromUnit)) == ObjectIdentifier(type(of: toUnit)) else {
                throw UnitConversionError.incompatible(from, to)
            }
            return Measurement(value: value, unit: fromUnit).converted(to: toUnit).value
        }
        if let fromCode = currency(fromKey), let toCode = currency(toKey) {
            if fromCode == toCode { return value }
            let rate = try await StockClient.history(symbol: "\(fromCode)\(toCode)=X", range: .day).price
            return value * rate
        }
        throw UnitConversionError.unknownUnit(units[fromKey] == nil && currency(fromKey) == nil ? from : to)
    }

    // MARK: - Units

    private static func key(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "°", with: "")
    }

    /// 坪 (tsubo) = 400/121 m², Japanese floor area. Source: 計量法 (Japan Measurement Act).
    private static let tsubo = UnitArea(symbol: "坪", converter: UnitConverterLinear(coefficient: 400.0 / 121.0))

    private static let units: [String: Dimension] = {
        var table: [String: Dimension] = [:]
        func add(_ unit: Dimension, _ names: [String]) { for name in names { table[name] = unit } }
        // Length
        add(UnitLength.meters, ["m", "meter", "meters", "metre", "metres", "metro", "metros", "メートル"])
        add(UnitLength.kilometers, ["km", "kilometer", "kilometers", "kilometre", "quilômetro", "quilômetros", "quilometros", "キロ", "キロメートル"])
        add(UnitLength.centimeters, ["cm", "centimeter", "centimeters", "centímetro", "centímetros", "センチ", "センチメートル"])
        add(UnitLength.millimeters, ["mm", "millimeter", "millimeters", "milímetro", "milímetros", "ミリ", "ミリメートル"])
        add(UnitLength.miles, ["mi", "mile", "miles", "milha", "milhas", "マイル"])
        add(UnitLength.feet, ["ft", "foot", "feet", "pé", "pés", "フィート"])
        add(UnitLength.inches, ["in", "inch", "inches", "polegada", "polegadas", "インチ"])
        add(UnitLength.yards, ["yd", "yard", "yards", "jarda", "jardas", "ヤード"])
        // Mass
        add(UnitMass.kilograms, ["kg", "kilogram", "kilograms", "kilo", "kilos", "quilo", "quilos", "キログラム"])
        add(UnitMass.grams, ["g", "gram", "grams", "grama", "gramas", "グラム"])
        add(UnitMass.pounds, ["lb", "lbs", "pound", "pounds", "libra", "libras", "ポンド"])
        add(UnitMass.ounces, ["oz", "ounce", "ounces", "onça", "onças", "オンス"])
        // Temperature
        add(UnitTemperature.celsius, ["c", "celsius", "centigrade", "摂氏", "度"])
        add(UnitTemperature.fahrenheit, ["f", "fahrenheit", "華氏"])
        add(UnitTemperature.kelvin, ["k", "kelvin", "ケルビン"])
        // Volume
        add(UnitVolume.liters, ["l", "liter", "liters", "litre", "litres", "litro", "litros", "リットル"])
        add(UnitVolume.milliliters, ["ml", "milliliter", "milliliters", "mililitro", "mililitros", "ミリリットル"])
        add(UnitVolume.gallons, ["gal", "gallon", "gallons", "galão", "galões", "ガロン"])
        add(UnitVolume.cups, ["cup", "cups", "xícara", "xícaras", "カップ"])
        add(UnitVolume.fluidOunces, ["fl oz", "floz", "fluid ounce", "fluid ounces"])
        // Speed
        add(UnitSpeed.kilometersPerHour, ["km/h", "kmh", "kph", "kilometers per hour", "時速"])
        add(UnitSpeed.milesPerHour, ["mph", "miles per hour"])
        add(UnitSpeed.metersPerSecond, ["m/s", "meters per second", "秒速"])
        add(UnitSpeed.knots, ["knot", "knots", "kn", "nó", "nós", "ノット"])
        // Area
        add(UnitArea.squareMeters, ["m2", "m²", "square meter", "square meters", "metro quadrado", "metros quadrados", "平米", "平方メートル"])
        add(UnitArea.squareKilometers, ["km2", "km²", "square kilometer", "square kilometers"])
        add(UnitArea.squareFeet, ["ft2", "ft²", "sq ft", "square foot", "square feet"])
        add(UnitArea.acres, ["acre", "acres"])
        add(UnitArea.hectares, ["ha", "hectare", "hectares"])
        add(tsubo, ["坪", "tsubo"])
        return table
    }()

    // MARK: - Currencies

    /// Common names to ISO codes; any other 3-letter code is passed through.
    private static let currencyNames: [String: String] = [
        "円": "JPY", "yen": "JPY", "iene": "JPY", "ドル": "USD", "dollar": "USD", "dollars": "USD",
        "dólar": "USD", "dólares": "USD", "real": "BRL", "reais": "BRL", "レアル": "BRL",
        "euro": "EUR", "euros": "EUR", "ユーロ": "EUR", "pound sterling": "GBP",
        "won": "KRW", "ウォン": "KRW", "yuan": "CNY", "元": "CNY", "人民元": "CNY",
    ]

    private static func currency(_ key: String) -> String? {
        if let code = currencyNames[key] { return code }
        let upper = key.uppercased()
        guard upper.count == 3, upper.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return upper
    }
}
