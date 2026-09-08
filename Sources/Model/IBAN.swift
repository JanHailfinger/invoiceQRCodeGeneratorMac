import Foundation

/// IBAN-Hilfen: Normalisierung, ISO 7064 Mod-97-10 Prüfung, Anzeigeformat.
enum IBAN {

    /// Nur Buchstaben/Ziffern, groß.
    static func normalized(_ raw: String) -> String {
        raw.uppercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    /// Mod-97-10 laut ISO 13616 / ISO 7064.
    static func isValid(_ raw: String) -> Bool {
        let iban = normalized(raw)
        guard (15...34).contains(iban.count) else { return false }

        let country = iban.prefix(2)
        let checkDigits = iban.dropFirst(2).prefix(2)
        guard country.allSatisfy(\.isLetter), checkDigits.allSatisfy(\.isNumber) else { return false }
        guard expectedLength(forCountry: String(country)).map({ $0 == iban.count }) ?? true else { return false }

        // Erste vier Zeichen ans Ende, Buchstaben -> A=10 ... Z=35, stückweise mod 97.
        var remainder = 0
        for character in iban.dropFirst(4) + iban.prefix(4) {
            if character.isNumber, let digit = character.wholeNumberValue {
                remainder = (remainder * 10 + digit) % 97
            } else if character.isLetter, let ascii = character.asciiValue {
                remainder = (remainder * 100 + Int(ascii - 65) + 10) % 97
            } else {
                return false
            }
        }
        return remainder == 1
    }

    /// Vierergruppen für die Anzeige.
    static func display(_ raw: String) -> String {
        let iban = normalized(raw)
        return stride(from: 0, to: iban.count, by: 4).map { offset in
            let start = iban.index(iban.startIndex, offsetBy: offset)
            let end = iban.index(start, offsetBy: min(4, iban.count - offset))
            return String(iban[start..<end])
        }.joined(separator: " ")
    }

    static func country(_ raw: String) -> String {
        String(normalized(raw).prefix(2))
    }

    /// EPC-Version 002 macht die BIC optional – außerhalb des EWR fordern Banken sie aber weiter an.
    static func isEEA(_ raw: String) -> Bool {
        eeaCountries.contains(country(raw))
    }

    private static let eeaCountries: Set<String> = [
        "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU", "IE",
        "IS", "IT", "LI", "LT", "LU", "LV", "MT", "NL", "NO", "PL", "PT", "RO", "SE", "SI", "SK",
        // SEPA-Teilnehmer außerhalb des EWR, für die keine BIC nötig ist
        "CH", "GB", "MC", "SM", "VA", "AD", "GI",
    ]

    /// Länge je Land, soweit bekannt – fängt Tippfehler ab, die Mod-97 überlebt.
    private static func expectedLength(forCountry code: String) -> Int? {
        lengths[code]
    }

    private static let lengths: [String: Int] = [
        "AD": 24, "AE": 23, "AL": 28, "AT": 20, "AZ": 28, "BA": 20, "BE": 16, "BG": 22, "BH": 22,
        "BR": 29, "BY": 28, "CH": 21, "CR": 22, "CY": 28, "CZ": 24, "DE": 22, "DK": 18, "DO": 28,
        "EE": 20, "EG": 29, "ES": 24, "FI": 18, "FO": 18, "FR": 27, "GB": 22, "GE": 22, "GI": 23,
        "GL": 18, "GR": 27, "GT": 28, "HR": 21, "HU": 28, "IE": 22, "IL": 23, "IS": 26, "IT": 27,
        "JO": 30, "KW": 30, "KZ": 20, "LB": 28, "LC": 32, "LI": 21, "LT": 20, "LU": 20, "LV": 21,
        "LY": 25, "MC": 27, "MD": 24, "ME": 22, "MK": 19, "MR": 27, "MT": 31, "MU": 30, "NL": 18,
        "NO": 15, "PK": 24, "PL": 28, "PS": 29, "PT": 25, "QA": 29, "RO": 24, "RS": 22, "SA": 24,
        "SC": 31, "SD": 18, "SE": 24, "SI": 19, "SK": 24, "SM": 27, "ST": 25, "SV": 28, "TL": 23,
        "TN": 24, "TR": 26, "UA": 29, "VA": 22, "VG": 24, "XK": 20,
    ]
}

/// BIC-Format nach ISO 9362: 8 oder 11 alphanumerische Zeichen.
enum BIC {
    static func normalized(_ raw: String) -> String {
        raw.uppercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    static func isValid(_ raw: String) -> Bool {
        let bic = normalized(raw)
        guard bic.count == 8 || bic.count == 11 else { return false }
        guard bic.prefix(4).allSatisfy(\.isLetter) else { return false }          // Bankcode
        guard bic.dropFirst(4).prefix(2).allSatisfy(\.isLetter) else { return false } // Ländercode
        return true
    }
}
