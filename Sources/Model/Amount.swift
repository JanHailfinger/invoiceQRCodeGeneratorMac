import Foundation

/// Amount parsing for mixed notations ("1.234,56", "1,234.56", "1234.5", "EUR 89.00").
enum Amount {

    static func parse(_ raw: String?) -> Decimal? {
        guard let raw, !raw.isEmpty else { return nil }

        // Drop everything but digits, separators and the minus sign (currency symbols, NBSP, "EUR" ...).
        var cleaned = raw.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" || $0 == "'" }
        cleaned = cleaned.replacingOccurrences(of: "'", with: "") // Swiss grouping
        guard !cleaned.isEmpty else { return nil }

        let negative = cleaned.hasPrefix("-")
        cleaned = cleaned.replacingOccurrences(of: "-", with: "")

        let lastComma = cleaned.lastIndex(of: ",")
        let lastDot = cleaned.lastIndex(of: ".")

        var normalized: String
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            // Whichever comes last is the decimal separator, the other one is grouping.
            let decimalSeparator: Character = comma > dot ? "," : "."
            normalized = cleaned.filter { $0.isNumber || $0 == decimalSeparator }
            normalized = normalized.replacingOccurrences(of: String(decimalSeparator), with: ".")
        case let (comma?, nil):
            normalized = decideSingleSeparator(cleaned, separator: ",", at: comma)
        case let (nil, dot?):
            normalized = decideSingleSeparator(cleaned, separator: ".", at: dot)
        case (nil, nil):
            normalized = cleaned
        }

        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }

    /// A lone separator means grouping when exactly three digits follow and one to three
    /// digits lead ("1.234"), otherwise it is the decimal separator ("1234.5").
    private static func decideSingleSeparator(_ text: String, separator: Character, at index: String.Index) -> String {
        let fractionDigits = text.distance(from: text.index(after: index), to: text.endIndex)
        let integerDigits = text.distance(from: text.startIndex, to: index)
        let isGrouping = fractionDigits == 3 && (1...3).contains(integerDigits)
        return isGrouping
            ? text.filter(\.isNumber)
            : text.filter { $0.isNumber || $0 == separator }.replacingOccurrences(of: String(separator), with: ".")
    }

    /// EPC field 8: exactly two decimals, dot separator, no grouping.
    static func epcString(_ value: Decimal) -> String {
        let rounded = NSDecimalNumber(decimal: value).rounding(accordingToBehavior: roundingBehavior)
        return Self.epcFormatter.string(from: rounded) ?? "0.00"
    }

    /// Localized display inside the form.
    static func display(_ value: Decimal) -> String {
        Self.displayFormatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }

    /// EPC069-12 allows 0.01 to 999,999,999.99 EUR.
    static let minimum = Decimal(string: "0.01")!
    static let maximum = Decimal(string: "999999999.99")!

    private static let roundingBehavior = NSDecimalNumberHandler(
        roundingMode: .plain, scale: 2,
        raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false
    )

    private static let epcFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let displayFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
