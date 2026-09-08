import Foundation

/// Result of the OpenAI extraction. Every field is optional - the model must not invent values.
struct InvoiceExtraction: Codable, Sendable {
    var creditorName: String?
    var iban: String?
    var bic: String?
    var amount: String?
    var currency: String?
    var remittanceText: String?
    var creditorReference: String?
    var invoiceNumber: String?
    var invoiceDate: String?
    var dueDate: String?
    var paymentMode: PaymentMode
    var warnings: [String]

    enum PaymentMode: String, Codable, Sendable {
        case bankTransfer = "bank_transfer"
        case directDebit = "direct_debit"
        case alreadyPaid = "already_paid"
        case card
        case other
        case unknown

        var label: String {
            switch self {
            case .bankTransfer: NSLocalizedString("Bank transfer", comment: "Payment mode")
            case .directDebit: NSLocalizedString("SEPA direct debit", comment: "Payment mode")
            case .alreadyPaid: NSLocalizedString("Already paid", comment: "Payment mode")
            case .card: NSLocalizedString("Card or payment provider", comment: "Payment mode")
            case .other: NSLocalizedString("Other", comment: "Payment mode")
            case .unknown: NSLocalizedString("Not recognized", comment: "Payment mode")
            }
        }

        /// Shown when a bank transfer is not what the invoice asks for.
        var warning: String? {
            switch self {
            case .directDebit:
                NSLocalizedString("This invoice is collected by SEPA direct debit. Do not transfer on top of that.", comment: "Payment mode warning")
            case .alreadyPaid:
                NSLocalizedString("According to the document this invoice has already been paid.", comment: "Payment mode warning")
            case .card:
                NSLocalizedString("According to the document payment runs through a card or payment provider.", comment: "Payment mode warning")
            case .bankTransfer, .other, .unknown:
                nil
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case creditorName = "creditor_name"
        case iban
        case bic
        case amount
        case currency
        case remittanceText = "remittance_text"
        case creditorReference = "creditor_reference"
        case invoiceNumber = "invoice_number"
        case invoiceDate = "invoice_date"
        case dueDate = "due_date"
        case paymentMode = "payment_mode"
        case warnings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        creditorName = try container.decodeIfPresent(String.self, forKey: .creditorName)
        iban = try container.decodeIfPresent(String.self, forKey: .iban)
        bic = try container.decodeIfPresent(String.self, forKey: .bic)
        amount = try container.decodeIfPresent(String.self, forKey: .amount)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        remittanceText = try container.decodeIfPresent(String.self, forKey: .remittanceText)
        creditorReference = try container.decodeIfPresent(String.self, forKey: .creditorReference)
        invoiceNumber = try container.decodeIfPresent(String.self, forKey: .invoiceNumber)
        invoiceDate = try container.decodeIfPresent(String.self, forKey: .invoiceDate)
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        // Never fail on an unexpected enum value.
        paymentMode = (try? container.decodeIfPresent(PaymentMode.self, forKey: .paymentMode)) ?? .unknown
        warnings = (try? container.decodeIfPresent([String].self, forKey: .warnings)) ?? []
    }

    /// JSON schema for Structured Outputs. Strict mode requires every property in `required`,
    /// so optionality is expressed through the type ["string", "null"].
    static var jsonSchema: [String: Any] {
        func nullableString(_ description: String) -> [String: Any] {
            ["type": ["string", "null"], "description": description]
        }

        return [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "creditor_name", "iban", "bic", "amount", "currency", "remittance_text",
                "creditor_reference", "invoice_number", "invoice_date", "due_date",
                "payment_mode", "warnings",
            ],
            "properties": [
                "creditor_name": nullableString("Name of the payee exactly as printed, at most 70 characters."),
                "iban": nullableString("Payee IBAN without spaces. Never the IBAN of the invoice recipient."),
                "bic": nullableString("BIC/SWIFT of the payee bank if the document states one."),
                "amount": nullableString("Outstanding total as a number with a dot as decimal separator, e.g. 1234.56."),
                "currency": nullableString("ISO 4217 code, e.g. EUR."),
                "remittance_text": nullableString("Remittance information, at most 140 characters. Verbatim if the document prescribes one, otherwise invoice number plus customer or reference number."),
                "creditor_reference": nullableString("Structured creditor reference per ISO 11649, starts with RF. Only if the document contains one."),
                "invoice_number": nullableString("Invoice number."),
                "invoice_date": nullableString("Invoice date as YYYY-MM-DD."),
                "due_date": nullableString("Due date or payment deadline as YYYY-MM-DD."),
                "payment_mode": [
                    "type": "string",
                    "enum": ["bank_transfer", "direct_debit", "already_paid", "card", "other", "unknown"],
                    "description": "How the document says the invoice is paid.",
                ],
                "warnings": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Short notes about early payment discounts, partial payments, several IBANs, unreadable spots or a deviating amount.",
                ],
            ],
        ]
    }

    /// The model writes its warnings in the app's language, so they fit the rest of the UI.
    static func systemPrompt(warningLanguage: String) -> String {
        """
        You extract payment details from an invoice for a SEPA credit transfer QR code \
        (EPC069-12 / GiroCode).

        Rules:
        - Take the bank details of the payee (the issuer, the supplier). If the document lists \
        several IBANs, pick the one meant for this payment and record the ambiguity in "warnings".
        - "amount" is the outstanding total including tax. Subtract prepayments when the document \
        states a remaining balance. Do NOT subtract an early payment discount; mention it in \
        "warnings" instead.
        - For credit notes or a negative balance set "amount" to null and explain it in "warnings".
        - If the document prescribes remittance information, copy it verbatim. Otherwise build it \
        from the invoice number and, when present, the customer number.
        - Use "creditor_reference" only for a real ISO 11649 reference (RF...). Never put the \
        invoice number there.
        - Detect whether a transfer is wanted at all: SEPA direct debit, already paid, card, \
        PayPal and so on belong in "payment_mode".
        - Invent nothing and guess nothing. If a value is absent, set null.
        - Write every entry in "warnings" in \(warningLanguage).
        - Answer strictly in the given JSON schema.
        """
    }
}
