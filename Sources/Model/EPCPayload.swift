import Foundation

/// EPC069-12 ("GiroCode") - SEPA credit transfer as QR payload.
///
/// Field order, one per line, separated by LF:
///  1 Service tag         "BCD"
///  2 Version             "002" (BIC optional) / "001" (BIC required)
///  3 Character set       "1" = UTF-8
///  4 Identification      "SCT"
///  5 BIC                 max 11
///  6 Beneficiary name    max 70
///  7 IBAN                max 34
///  8 Amount              "EUR" + 0.01 ... 999999999.99
///  9 Purpose code        max 4
/// 10 Structured reference    max 35   \
/// 11 Unstructured remittance max 140  / only one of the two
/// 12 Beneficiary to originator information  max 70
///
/// Total payload must stay within 331 bytes.
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
        case missingBICOutsideSEPA
        case missingAmount
        case amountOutOfRange
        case bothReferenceKinds
        case truncated(field: String, limit: Int)
        case tooLong(bytes: Int)

        var id: Self { self }

        /// Blocking issues suppress the QR code; the rest are advisory.
        var isBlocking: Bool {
            switch self {
            case .missingName, .missingIBAN, .invalidIBAN, .invalidBIC,
                 .amountOutOfRange, .bothReferenceKinds, .tooLong:
                true
            case .missingBICOutsideSEPA, .missingAmount, .truncated:
                false
            }
        }

        var text: String {
            switch self {
            case .missingName:
                NSLocalizedString("Payee name is missing.", comment: "EPC validation")
            case .missingIBAN:
                NSLocalizedString("IBAN is missing.", comment: "EPC validation")
            case .invalidIBAN:
                NSLocalizedString("IBAN is invalid, the checksum does not match.", comment: "EPC validation")
            case .invalidBIC:
                NSLocalizedString("BIC is invalid, expected 8 or 11 characters.", comment: "EPC validation")
            case .missingBICOutsideSEPA:
                NSLocalizedString("IBAN is outside SEPA, most banks require a BIC.", comment: "EPC validation")
            case .missingAmount:
                NSLocalizedString("No amount set. Your banking app will ask for it when scanning.", comment: "EPC validation")
            case .amountOutOfRange:
                NSLocalizedString("Amount is outside 0.01 to 999,999,999.99 EUR.", comment: "EPC validation")
            case .bothReferenceKinds:
                NSLocalizedString("Structured reference and remittance text are mutually exclusive.", comment: "EPC validation")
            case let .truncated(field, limit):
                String(
                    format: NSLocalizedString("%1$@ was truncated to %2$ld characters.", comment: "EPC validation"),
                    field, limit
                )
            case let .tooLong(bytes):
                String(
                    format: NSLocalizedString("QR payload is %1$ld bytes, the maximum is %2$ld.", comment: "EPC validation"),
                    bytes, EPCPayload.maximumByteCount
                )
            }
        }
    }

    /// Field names as they appear in truncation messages.
    enum FieldName {
        static let name = NSLocalizedString("Payee name", comment: "EPC field")
        static let reference = NSLocalizedString("Reference", comment: "EPC field")
        static let remittance = NSLocalizedString("Remittance text", comment: "EPC field")
        static let hint = NSLocalizedString("Note to payee", comment: "EPC field")
    }

    let text: String
    let issues: [Issue]
    let byteCount: Int

    var isUsable: Bool { !issues.contains(where: \.isBlocking) }

    init(_ fields: Fields) {
        var issues: [Issue] = []

        let name = Self.clamp(fields.beneficiaryName, limit: 70, field: FieldName.name, issues: &issues)
        let iban = IBAN.normalized(fields.iban)
        let bic = BIC.normalized(fields.bic)
        let purpose = String(Self.sanitize(fields.purposeCode).uppercased().prefix(4))
        let structured = Self.clamp(fields.structuredReference, limit: 35, field: FieldName.reference, issues: &issues)
        let unstructured = Self.clamp(fields.unstructuredRemittance, limit: 140, field: FieldName.remittance, issues: &issues)
        let hint = Self.clamp(fields.beneficiaryToOriginator, limit: 70, field: FieldName.hint, issues: &issues)

        if name.isEmpty { issues.append(.missingName) }
        if iban.isEmpty {
            issues.append(.missingIBAN)
        } else if !IBAN.isValid(iban) {
            issues.append(.invalidIBAN)
        }
        if !bic.isEmpty, !BIC.isValid(bic) { issues.append(.invalidBIC) }
        if bic.isEmpty, !iban.isEmpty, IBAN.isValid(iban), !IBAN.isSEPA(iban) { issues.append(.missingBICOutsideSEPA) }
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

        // Version 002 permits an empty BIC line.
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

        // Trailing empty fields may be omitted, which keeps the payload short.
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

    /// Strip control characters and line breaks - they would break the field structure.
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
