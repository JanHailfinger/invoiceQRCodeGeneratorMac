import SwiftUI

struct ResultView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        HSplitView {
            PaymentFormView()
                .frame(minWidth: 380, idealWidth: 460)
            QRPanelView()
                .frame(minWidth: 320, idealWidth: 380)
        }
    }
}

struct PaymentFormView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !model.advisories.isEmpty {
                    AdvisoryBox(messages: model.advisories)
                }

                Group {
                    LabeledField(title: "Empfänger", text: Binding(
                        get: { model.beneficiaryName },
                        set: { model.beneficiaryName = $0 }
                    ), limit: 70)

                    LabeledField(
                        title: "IBAN",
                        text: Binding(get: { model.ibanText }, set: { model.ibanText = $0 }),
                        monospaced: true,
                        validity: validity(for: model.ibanText, isValid: IBAN.isValid, allowEmpty: true),
                        footnote: ibanFootnote
                    )

                    LabeledField(
                        title: "BIC",
                        text: Binding(get: { model.bicText }, set: { model.bicText = $0.uppercased() }),
                        monospaced: true,
                        validity: validity(for: model.bicText, isValid: BIC.isValid, allowEmpty: true),
                        footnote: model.bicText.isEmpty ? "Optional – bei SEPA-IBAN nicht nötig." : nil
                    )

                    LabeledField(
                        title: "Betrag (EUR)",
                        text: Binding(get: { model.amountText }, set: { model.amountText = $0 }),
                        monospaced: true,
                        validity: amountValidity,
                        footnote: amountFootnote
                    )
                }

                Divider()

                if model.referenceText.isEmpty {
                    LabeledField(
                        title: "Verwendungszweck",
                        text: Binding(get: { model.remittanceText }, set: { model.remittanceText = $0 }),
                        limit: 140,
                        axis: .vertical
                    )
                } else {
                    LabeledField(
                        title: "Strukturierte Referenz (ISO 11649)",
                        text: Binding(get: { model.referenceText }, set: { model.referenceText = $0 }),
                        monospaced: true,
                        limit: 35,
                        footnote: "Ersetzt den freien Verwendungszweck."
                    )
                    Button("Stattdessen freien Verwendungszweck nutzen") {
                        model.remittanceText = model.referenceText
                        model.referenceText = ""
                    }
                    .buttonStyle(.link)
                }

                DisclosureGroup("Weitere EPC-Felder") {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledField(
                            title: "Purpose Code",
                            text: Binding(get: { model.purposeCode }, set: { model.purposeCode = $0.uppercased() }),
                            monospaced: true,
                            limit: 4,
                            footnote: "ISO-20022-Code, z. B. GDDS. Die meisten Banking-Apps ignorieren ihn."
                        )
                        LabeledField(
                            title: "Hinweis an Empfänger",
                            text: Binding(get: { model.beneficiaryHint }, set: { model.beneficiaryHint = $0 }),
                            limit: 70
                        )
                    }
                    .padding(.top, 10)
                }

                if let extraction = model.extraction {
                    InvoiceMetaView(extraction: extraction)
                }
            }
            .padding(20)
        }
    }

    private var ibanFootnote: String? {
        let iban = IBAN.normalized(model.ibanText)
        guard !iban.isEmpty, IBAN.isValid(iban) else { return nil }
        return IBAN.isEEA(iban) ? nil : "Nicht-SEPA-Land \(IBAN.country(iban)) – BIC ergänzen."
    }

    private var amountValidity: Validity {
        guard !model.amountText.isEmpty else { return .neutral }
        guard let amount = Amount.parse(model.amountText) else { return .invalid }
        return (amount >= Amount.minimum && amount <= Amount.maximum) ? .valid : .invalid
    }

    private var amountFootnote: String? {
        guard let amount = Amount.parse(model.amountText) else {
            return model.amountText.isEmpty ? "Leer lassen, dann fragt die Banking-App den Betrag ab." : nil
        }
        return "Im QR-Code: EUR\(Amount.epcString(amount))"
    }

    private func validity(for text: String, isValid: (String) -> Bool, allowEmpty: Bool) -> Validity {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return allowEmpty ? .neutral : .invalid }
        return isValid(text) ? .valid : .invalid
    }
}

enum Validity {
    case neutral, valid, invalid
}

struct LabeledField: View {

    let title: String
    @Binding var text: String
    var monospaced = false
    var validity: Validity = .neutral
    var limit: Int?
    var footnote: String?
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let limit {
                    Text("\(text.count)/\(limit)")
                        .font(.caption2)
                        .foregroundStyle(text.count > limit ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                }
                switch validity {
                case .valid:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .invalid:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                case .neutral:
                    EmptyView()
                }
            }

            TextField(title, text: $text, axis: axis)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .lineLimit(axis == .vertical ? 2...4 : 1...1)

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct AdvisoryBox: View {

    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct InvoiceMetaView: View {

    let extraction: InvoiceExtraction

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aus dem Dokument")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            row("Rechnungsnummer", extraction.invoiceNumber)
            row("Rechnungsdatum", extraction.invoiceDate)
            row("Fällig am", extraction.dueDate)
            row("Zahlungsart", extraction.paymentMode.label)

            if let url = model.sourceURL {
                HStack(spacing: 12) {
                    Button("Original öffnen") { model.openSource() }
                        .buttonStyle(.link)
                    Button("Im Finder zeigen") { model.revealSource() }
                        .buttonStyle(.link)
                }
                .padding(.top, 2)
                .help(url.path(percentEncoded: false))
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 130, alignment: .leading)
                Text(value)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
    }
}
