import Foundation

/// Betrags-Parsing für gemischte Schreibweisen ("1.234,56", "1,234.56", "1234.5", "EUR 89,00").
enum Amount {

    static func parse(_ raw: String?) -> Decimal? {
        guard let raw, !raw.isEmpty else { return nil }

        // Alles außer Ziffern, Trennzeichen und Minus entfernen (Währungszeichen, NBSP, "EUR" …).
        var cleaned = raw.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" || $0 == "'" }
        cleaned = cleaned.replacingOccurrences(of: "'", with: "") // CH-Tausendertrennung
        guard !cleaned.isEmpty else { return nil }

        let negative = cleaned.hasPrefix("-")
        cleaned = cleaned.replacingOccurrences(of: "-", with: "")

        let lastComma = cleaned.lastIndex(of: ",")
        let lastDot = cleaned.lastIndex(of: ".")

        var normalized: String
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            // Das hintere Zeichen ist das Dezimaltrennzeichen, das andere Tausendertrennung.
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

    /// Ein einzelnes Trennzeichen ist Tausendertrennung, wenn genau drei Ziffern folgen
    /// und links davon 1–3 Ziffern stehen ("1.234"), sonst Dezimaltrennzeichen ("1234.5").
    private static func decideSingleSeparator(_ text: String, separator: Character, at index: String.Index) -> String {
        let fractionDigits = text.distance(from: text.index(after: index), to: text.endIndex)
        let integerDigits = text.distance(from: text.startIndex, to: index)
        let isGrouping = fractionDigits == 3 && (1...3).contains(integerDigits)
        return isGrouping
            ? text.filter(\.isNumber)
            : text.filter { $0.isNumber || $0 == separator }.replacingOccurrences(of: String(separator), with: ".")
    }

    /// EPC-Feld 8: exakt zwei Dezimalstellen, Punkt als Trennzeichen, keine Gruppierung.
    static func epcString(_ value: Decimal) -> String {
        let rounded = NSDecimalNumber(decimal: value).rounding(accordingToBehavior: roundingBehavior)
        return Self.formatter.string(from: rounded) ?? "0.00"
    }

    /// Deutsche Anzeige im Formular.
    static func display(_ value: Decimal) -> String {
        Self.displayFormatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }

    /// EPC069-12 erlaubt 0,01 – 999.999.999,99 EUR.
    static let minimum = Decimal(string: "0.01")!
    static let maximum = Decimal(string: "999999999.99")!

    private static let roundingBehavior = NSDecimalNumberHandler(
        roundingMode: .plain, scale: 2,
        raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false
    )

    private static let formatter: NumberFormatter = {
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
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
