// Prüfungen für IBAN, Betragsparser und EPC069-12-Nutzdaten.
// Läuft ohne Xcode-Testhost: ./build.sh check

import Foundation

var failed = 0
func expect(_ actual: String, _ expected: String, _ label: String) {
    if actual == expected { print("ok   \(label)") }
    else { print("FAIL \(label)\n     ist:  \(actual.debugDescription)\n     soll: \(expected.debugDescription)"); failed += 1 }
}
func expect(_ actual: Bool, _ expected: Bool, _ label: String) {
    expect(String(actual), String(expected), label)
}
func expect(_ actual: Int, _ expected: String, _ label: String) {
    expect(String(actual), expected, label)
}

// IBAN
expect(IBAN.isValid("DE89 3704 0044 0532 0130 00"), true, "IBAN DE gültig (mit Leerzeichen)")
expect(IBAN.isValid("DE89370400440532013001"), false, "IBAN DE falsche Prüfsumme")
expect(IBAN.isValid("CH9300762011623852957"), true, "IBAN CH gültig")
expect(IBAN.isValid("AT611904300234573201"), true, "IBAN AT gültig")
expect(IBAN.isValid("GB82WEST12345698765432"), true, "IBAN GB gültig")
expect(IBAN.isValid("DE8937040044053201300"), false, "IBAN DE zu kurz für Land")
expect(IBAN.isValid("TR330006100519786457841326"), true, "IBAN TR gültig")
expect(IBAN.isEEA("DE89370400440532013000"), true, "DE ist SEPA")
expect(IBAN.isEEA("TR330006100519786457841326"), false, "TR ist nicht SEPA")
expect(IBAN.display("DE89370400440532013000"), "DE89 3704 0044 0532 0130 00", "IBAN Anzeige")

// BIC
expect(BIC.isValid("GENODEF1M04"), true, "BIC 11 Zeichen")
expect(BIC.isValid("COBADEFF"), true, "BIC 8 Zeichen")
expect(BIC.isValid("COBADEF"), false, "BIC 7 Zeichen ungültig")
expect(BIC.isValid("1234DEFF"), false, "BIC mit Ziffern im Bankcode ungültig")

// Beträge
func amount(_ s: String) -> String { Amount.parse(s).map { Amount.epcString($0) } ?? "nil" }
expect(amount("1.234,56"), "1234.56", "Betrag deutsch mit Tausenderpunkt")
expect(amount("1,234.56"), "1234.56", "Betrag englisch")
expect(amount("1234.5"), "1234.50", "Betrag eine Dezimalstelle")
expect(amount("89,00 EUR"), "89.00", "Betrag mit Währung")
expect(amount("EUR 1.100"), "1100.00", "Tausenderpunkt ohne Dezimalstellen")
expect(amount("1100"), "1100.00", "Ganzzahl")
expect(amount("12.345"), "12345.00", "12.345 = Tausendertrennung")
expect(amount("1234"), "1234.00", "1234 ohne Trenner")
expect(amount("0,01"), "0.01", "Minimalbetrag")
expect(amount("1'234.55"), "1234.55", "CH-Schreibweise")
expect(amount("1.234.567,89"), "1234567.89", "zwei Tausenderpunkte")
expect(amount(""), "nil", "leerer Betrag")
expect(amount("abc"), "nil", "kein Betrag")

// EPC-Payload
let full = EPCPayload(.init(
    beneficiaryName: "Musterfirma GmbH", iban: "DE89 3704 0044 0532 0130 00", bic: "GENODEF1M04",
    amount: Amount.parse("1.234,56"), purposeCode: "", structuredReference: "",
    unstructuredRemittance: "RE-2026-0815 Kd. 4711", beneficiaryToOriginator: ""))
expect(full.text, "BCD\n002\n1\nSCT\nGENODEF1M04\nMusterfirma GmbH\nDE89370400440532013000\nEUR1234.56\n\n\nRE-2026-0815 Kd. 4711", "EPC Nutzdaten vollständig")
expect(full.isUsable, true, "EPC nutzbar")
expect(full.issues.isEmpty, true, "EPC ohne Beanstandung")

let noBIC = EPCPayload(.init(
    beneficiaryName: "Test AG", iban: "DE89370400440532013000", bic: "",
    amount: Amount.parse("10,00"), purposeCode: "", structuredReference: "",
    unstructuredRemittance: "Zweck", beneficiaryToOriginator: ""))
expect(noBIC.text, "BCD\n002\n1\nSCT\n\nTest AG\nDE89370400440532013000\nEUR10.00\n\n\nZweck", "EPC ohne BIC")
expect(noBIC.isUsable, true, "EPC ohne BIC nutzbar (Version 002)")

// Zeilenumbrüche im Namen dürfen die Feldstruktur nicht sprengen
let injected = EPCPayload(.init(
    beneficiaryName: "Böse\nGmbH\rX", iban: "DE89370400440532013000", bic: "",
    amount: Amount.parse("5,00"), purposeCode: "", structuredReference: "",
    unstructuredRemittance: "a\nb", beneficiaryToOriginator: ""))
expect(injected.text.split(separator: "\n", omittingEmptySubsequences: false).count, "11", "Feldanzahl trotz Umbrüchen im Text")
expect(injected.text.contains("Böse GmbH X"), true, "Umbrüche zu Leerzeichen")

// Beides gesetzt = blockierend
let both = EPCPayload(.init(
    beneficiaryName: "A", iban: "DE89370400440532013000", bic: "", amount: Amount.parse("1,00"),
    purposeCode: "", structuredReference: "RF18539007547034", unstructuredRemittance: "Zweck",
    beneficiaryToOriginator: ""))
expect(both.isUsable, false, "Referenz + Zweck gleichzeitig blockiert")

// Ohne Betrag: erlaubt, aber Hinweis
let noAmount = EPCPayload(.init(
    beneficiaryName: "A", iban: "DE89370400440532013000", bic: "", amount: nil,
    purposeCode: "", structuredReference: "", unstructuredRemittance: "Zweck", beneficiaryToOriginator: ""))
expect(noAmount.isUsable, true, "ohne Betrag nutzbar")
expect(noAmount.issues.contains(.missingAmount), true, "Hinweis fehlender Betrag")

// Ungültige IBAN blockiert
let badIBAN = EPCPayload(.init(
    beneficiaryName: "A", iban: "DE89370400440532013001", bic: "", amount: Amount.parse("1,00"),
    purposeCode: "", structuredReference: "", unstructuredRemittance: "", beneficiaryToOriginator: ""))
expect(badIBAN.isUsable, false, "ungültige IBAN blockiert")

// Längenlimits
let longZweck = EPCPayload(.init(
    beneficiaryName: String(repeating: "N", count: 80), iban: "DE89370400440532013000", bic: "",
    amount: Amount.parse("1,00"), purposeCode: "", structuredReference: "",
    unstructuredRemittance: String(repeating: "Z", count: 200), beneficiaryToOriginator: ""))
expect(longZweck.text.split(separator: "\n", omittingEmptySubsequences: false)[5].count, "70", "Name auf 70 gekürzt")
expect(longZweck.text.split(separator: "\n", omittingEmptySubsequences: false)[10].count, "140", "Zweck auf 140 gekürzt")
expect(longZweck.byteCount <= EPCPayload.maximumByteCount, true, "Nutzdaten <= 331 Byte")

print(failed == 0 ? "\nALLE TESTS OK" : "\n\(failed) FEHLER")
exit(failed == 0 ? 0 : 1)
