import Foundation

/// Ergebnis der OpenAI-Extraktion. Alle Felder optional – das Modell darf nichts erfinden.
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
            case .bankTransfer: "Überweisung"
            case .directDebit: "SEPA-Lastschrift"
            case .alreadyPaid: "bereits bezahlt"
            case .card: "Karte / Zahlungsdienstleister"
            case .other: "andere"
            case .unknown: "nicht erkennbar"
            }
        }

        /// Hinweis, wenn eine Überweisung gar nicht erwünscht ist.
        var warning: String? {
            switch self {
            case .directDebit: "Rechnung wird per SEPA-Lastschrift eingezogen – nicht zusätzlich überweisen."
            case .alreadyPaid: "Rechnung ist laut Dokument bereits bezahlt."
            case .card: "Zahlung läuft laut Dokument über Karte/Zahlungsdienstleister."
            case .bankTransfer, .other, .unknown: nil
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
        // Unbekannte Werte nicht als Fehler behandeln.
        paymentMode = (try? container.decodeIfPresent(PaymentMode.self, forKey: .paymentMode)) ?? .unknown
        warnings = (try? container.decodeIfPresent([String].self, forKey: .warnings)) ?? []
    }

    /// JSON-Schema für Structured Outputs (strict: alle Properties in `required`,
    /// Optionalität über den Typ ["string","null"]).
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
                "creditor_name": nullableString("Name des Zahlungsempfängers exakt wie im Dokument, max. 70 Zeichen."),
                "iban": nullableString("IBAN des Zahlungsempfängers ohne Leerzeichen. Niemals die IBAN des Rechnungsempfängers."),
                "bic": nullableString("BIC/SWIFT des Empfängerinstituts, falls angegeben."),
                "amount": nullableString("Offener Gesamtbetrag als Zahl, Punkt als Dezimaltrennzeichen, z. B. 1234.56."),
                "currency": nullableString("ISO-4217-Code, z. B. EUR."),
                "remittance_text": nullableString("Verwendungszweck, max. 140 Zeichen. Wörtlich, wenn das Dokument einen vorgibt, sonst Rechnungsnummer plus Kunden-/Referenznummer."),
                "creditor_reference": nullableString("Strukturierte Creditor Reference (ISO 11649, beginnt mit RF), nur wenn das Dokument eine enthält."),
                "invoice_number": nullableString("Rechnungsnummer."),
                "invoice_date": nullableString("Rechnungsdatum als YYYY-MM-DD."),
                "due_date": nullableString("Fälligkeitsdatum bzw. Zahlungsziel als YYYY-MM-DD."),
                "payment_mode": [
                    "type": "string",
                    "enum": ["bank_transfer", "direct_debit", "already_paid", "card", "other", "unknown"],
                    "description": "Wie laut Dokument gezahlt wird.",
                ],
                "warnings": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Kurze Hinweise auf Deutsch: Skonto, Teilzahlung, mehrere IBANs, unleserliche Stellen, abweichender Betrag.",
                ],
            ],
        ]
    }

    static let systemPrompt = """
    Du extrahierst Zahlungsdaten aus einer Rechnung für einen SEPA-Überweisungs-QR-Code (EPC069-12 / GiroCode).

    Regeln:
    - Nimm die Bankverbindung des Zahlungsempfängers (Rechnungssteller, Lieferant). Wenn im Dokument mehrere \
    IBANs stehen, wähle die für diese Zahlung vorgesehene und vermerke die Mehrdeutigkeit in "warnings".
    - "amount" ist der offene Gesamtbetrag inklusive Umsatzsteuer. Bereits geleistete Anzahlungen abziehen, \
    wenn das Dokument einen Restbetrag ausweist. Skonto NICHT abziehen, sondern in "warnings" nennen.
    - Bei Gutschriften oder negativem Restbetrag setze "amount" auf null und erkläre es in "warnings".
    - Gibt das Dokument einen Verwendungszweck vor, übernimm ihn wörtlich. Sonst bilde ihn aus Rechnungsnummer \
    und, falls vorhanden, Kundennummer.
    - "creditor_reference" nur bei echter ISO-11649-Referenz (RF...), nicht die Rechnungsnummer hineinschreiben.
    - Erkenne, ob überhaupt überwiesen werden soll: SEPA-Lastschrift/Einzug, bereits bezahlt, Kartenzahlung, \
    PayPal usw. gehören in "payment_mode".
    - Nichts erfinden und nichts raten. Fehlt eine Angabe, setze null.
    - Antworte ausschließlich im vorgegebenen JSON-Schema.
    """
}
