import Foundation

/// EPC069-12 ("GiroCode") – SEPA Credit Transfer als QR-Nutzdaten.
///
/// Feldreihenfolge, jede Zeile per LF getrennt:
///  1 Service Tag        "BCD"
///  2 Version            "002" (BIC optional) / "001" (BIC verpflichtend)
///  3 Zeichensatz        "1" = UTF-8
///  4 Identification     "SCT"
///  5 BIC                max 11
///  6 Empfängername      max 70
///  7 IBAN               max 34
///  8 Betrag             "EUR" + 0.01…999999999.99
///  9 Purpose Code       max 4
/// 10 Referenz strukturiert    max 35   \
/// 11 Verwendungszweck         max 140  / nur eines von beiden
/// 12 Hinweis an Empfänger     max 70
///
/// Gesamtlänge maximal 331 Byte.
struct EPCPayload {

    static let maximumByteCount = 331

    struct Fields {
        var beneficiaryName: String
        var iban: String
        var bic: String
        var amount: Decimal?
        var purposeCode: String
        var structuredReference: String
        var unstructuredRemittance: String
        var beneficiaryToOriginator: String
    }

    enum Issue: Identifiable, Hashable {
        case missingName
        case missingIBAN
        case invalidIBAN
        case invalidBIC
        case missingBICOutsideEEA
        case missingAmount
        case amountOutOfRange
        case bothReferenceKinds
        case truncated(field: String, limit: Int)
        case tooLong(bytes: Int)

        var id: Self { self }

        var isBlocking: Bool {
            switch self {
            case .missingName, .missingIBAN, .invalidIBAN, .invalidBIC,
                 .amountOutOfRange, .bothReferenceKinds, .tooLong:
                true
            case .missingBICOutsideEEA, .missingAmount, .truncated:
                false
            }
        }

        var text: String {
            switch self {
            case .missingName: "Empfängername fehlt."
            case .missingIBAN: "IBAN fehlt."
            case .invalidIBAN: "IBAN ungültig (Prüfsumme stimmt nicht)."
            case .invalidBIC: "BIC ungültig – 8 oder 11 Zeichen erwartet."
            case .missingBICOutsideEEA: "IBAN außerhalb SEPA/EWR: BIC wird von vielen Banken verlangt."
            case .missingAmount: "Kein Betrag – die Banking-App fragt ihn beim Scannen ab."
            case .amountOutOfRange: "Betrag außerhalb 0,01 – 999.999.999,99 EUR."
            case .bothReferenceKinds: "Strukturierte Referenz und Verwendungszweck schließen sich aus."
            case let .truncated(field, limit): "\(field) auf \(limit) Zeichen gekürzt."
            case let .tooLong(bytes): "QR-Nutzdaten \(bytes) Byte – Maximum ist \(maximumByteCount) Byte."
            }
        }
    }

    let text: String
    let issues: [Issue]
    let byteCount: Int

    var isUsable: Bool { !issues.contains(where: \.isBlocking) }

    init(_ fields: Fields) {
        var issues: [Issue] = []

        let name = Self.clamp(fields.beneficiaryName, limit: 70, field: "Empfängername", issues: &issues)
        let iban = IBAN.normalized(fields.iban)
        let bic = BIC.normalized(fields.bic)
        let purpose = String(Self.sanitize(fields.purposeCode).uppercased().prefix(4))
        let structured = Self.clamp(fields.structuredReference, limit: 35, field: "Referenz", issues: &issues)
        let unstructured = Self.clamp(fields.unstructuredRemittance, limit: 140, field: "Verwendungszweck", issues: &issues)
        let hint = Self.clamp(fields.beneficiaryToOriginator, limit: 70, field: "Empfängerhinweis", issues: &issues)

        if name.isEmpty { issues.append(.missingName) }
        if iban.isEmpty {
            issues.append(.missingIBAN)
        } else if !IBAN.isValid(iban) {
            issues.append(.invalidIBAN)
        }
        if !bic.isEmpty, !BIC.isValid(bic) { issues.append(.invalidBIC) }
        if bic.isEmpty, !iban.isEmpty, IBAN.isValid(iban), !IBAN.isEEA(iban) { issues.append(.missingBICOutsideEEA) }
        if !structured.isEmpty, !unstructured.isEmpty { issues.append(.bothReferenceKinds) }

        var amountLine = ""
        if let amount = fields.amount {
            if amount < Amount.minimum || amount > Amount.maximum {
                issues.append(.amountOutOfRange)
            } else {
                amountLine = "EUR" + Amount.epcString(amount)
            }
        } else {
            issues.append(.missingAmount)
        }

        // Version 002 erlaubt eine leere BIC-Zeile.
        let lines = [
            "BCD",
            "002",
            "1",
            "SCT",
            bic,
            name,
            iban,
            amountLine,
            purpose,
            structured,
            unstructured,
            hint,
        ]

        // Leere Felder am Ende dürfen entfallen – hält die Nutzdaten kurz.
        var trimmed = lines
        while let last = trimmed.last, last.isEmpty, trimmed.count > 7 {
            trimmed.removeLast()
        }

        let payload = trimmed.joined(separator: "\n")
        let bytes = payload.utf8.count
        if bytes > Self.maximumByteCount { issues.append(.tooLong(bytes: bytes)) }

        self.text = payload
        self.byteCount = bytes
        self.issues = issues
    }

    /// Steuerzeichen und Zeilenumbrüche raus – sonst zerschießen sie die Feldstruktur.
    private static func sanitize(_ value: String) -> String {
        let collapsed = value.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : Character($0) }
            .reduce(into: "") { $0.append($1) }
        return collapsed.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    private static func clamp(_ value: String, limit: Int, field: String, issues: inout [Issue]) -> String {
        let clean = sanitize(value)
        guard clean.count > limit else { return clean }
        issues.append(.truncated(field: field, limit: limit))
        return String(clean.prefix(limit))
    }
}
