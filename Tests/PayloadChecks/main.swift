// Checks for IBAN validation, the amount parser and the EPC069-12 payload.
// Runs without an Xcode test host: ./build.sh check

import Foundation

var failed = 0
func expect(_ actual: String, _ expected: String, _ label: String) {
    if actual == expected { print("ok   \(label)") }
    else { print("FAIL \(label)\n     got:      \(actual.debugDescription)\n     expected: \(expected.debugDescription)"); failed += 1 }
}
func expect(_ actual: Bool, _ expected: Bool, _ label: String) {
    expect(String(actual), String(expected), label)
}
func expect(_ actual: Int, _ expected: String, _ label: String) {
    expect(String(actual), expected, label)
}

// MARK: - IBAN

expect(IBAN.isValid("DE89 3704 0044 0532 0130 00"), true, "German IBAN with spaces is valid")
expect(IBAN.isValid("DE89370400440532013001"), false, "German IBAN with wrong checksum")
expect(IBAN.isValid("CH9300762011623852957"), true, "Swiss IBAN is valid")
expect(IBAN.isValid("AT611904300234573201"), true, "Austrian IBAN is valid")
expect(IBAN.isValid("GB82WEST12345698765432"), true, "British IBAN is valid")
expect(IBAN.isValid("DE8937040044053201300"), false, "German IBAN too short for the country")
expect(IBAN.isValid("TR330006100519786457841326"), true, "Turkish IBAN is valid")
expect(IBAN.isSEPA("DE89370400440532013000"), true, "DE is in SEPA")
expect(IBAN.isSEPA("TR330006100519786457841326"), false, "TR is outside SEPA")
expect(IBAN.display("DE89370400440532013000"), "DE89 3704 0044 0532 0130 00", "IBAN display format")

// MARK: - BIC

expect(BIC.isValid("GENODEF1M04"), true, "11 character BIC")
expect(BIC.isValid("COBADEFF"), true, "8 character BIC")
expect(BIC.isValid("COBADEF"), false, "7 character BIC is invalid")
expect(BIC.isValid("1234DEFF"), false, "digits in the bank code are invalid")

// MARK: - Amounts

func amount(_ s: String) -> String { Amount.parse(s).map { Amount.epcString($0) } ?? "nil" }
expect(amount("1.234,56"), "1234.56", "German notation with grouping dot")
expect(amount("1,234.56"), "1234.56", "English notation")
expect(amount("1234.5"), "1234.50", "single decimal digit")
expect(amount("89,00 EUR"), "89.00", "amount with currency suffix")
expect(amount("EUR 1.100"), "1100.00", "grouping dot without decimals")
expect(amount("1100"), "1100.00", "plain integer")
expect(amount("12.345"), "12345.00", "12.345 is grouping, not decimals")
expect(amount("1234"), "1234.00", "integer without separators")
expect(amount("0,01"), "0.01", "minimum amount")
expect(amount("1'234.55"), "1234.55", "Swiss notation")
expect(amount("1.234.567,89"), "1234567.89", "two grouping dots")
expect(amount(""), "nil", "empty amount")
expect(amount("abc"), "nil", "not an amount")

// MARK: - EPC payload

let full = EPCPayload(.init(
    beneficiaryName: "Musterfirma GmbH", iban: "DE89 3704 0044 0532 0130 00", bic: "GENODEF1M04",
    amount: Amount.parse("1.234,56"), purposeCode: "", structuredReference: "",
    unstructuredRemittance: "RE-2026-0815 Kd. 4711", beneficiaryToOriginator: ""))
expect(full.text, "BCD\n002\n1\nSCT\nGENODEF1M04\nMusterfirma GmbH\nDE89370400440532013000\nEUR1234.56\n\n\nRE-2026-0815 Kd. 4711", "complete payload")
expect(full.isUsable, true, "payload is usable")
expect(full.issues.isEmpty, true, "payload has no issues")

let noBIC = EPCPayload(.init(
    beneficiaryName: "Test AG", iban: "DE89370400440532013000", bic: "",
    amount: Amount.parse("10,00"), purposeCode: "", structuredReference: "",
    unstructuredRemittance: "Reference", beneficiaryToOriginator: ""))
expect(noBIC.text, "BCD\n002\n1\nSCT\n\nTest AG\nDE89370400440532013000\nEUR10.00\n\n\nReference", "payload without BIC")
expect(noBIC.isUsable, true, "version 002 allows an empty BIC")

// Line breaks in user text must not break the field structure.
let injected = EPCPayload(.init(
    beneficiaryName: "Bad\nName\rX", iban: "DE89370400440532013000", bic: "",
    amount: Amount.parse("5,00"), purposeCode: "", structuredReference: "",
    unstructuredRemittance: "a\nb", beneficiaryToOriginator: ""))
expect(injected.text.split(separator: "\n", omittingEmptySubsequences: false).count, "11", "field count survives line breaks")
expect(injected.text.contains("Bad Name X"), true, "line breaks become spaces")

// Both reference kinds at once is blocking.
let both = EPCPayload(.init(
    beneficiaryName: "A", iban: "DE89370400440532013000", bic: "", amount: Amount.parse("1,00"),
    purposeCode: "", structuredReference: "RF18539007547034", unstructuredRemittance: "Reference",
    beneficiaryToOriginator: ""))
expect(both.isUsable, false, "reference plus remittance text is blocked")

// No amount is allowed, but advisory.
let noAmount = EPCPayload(.init(
    beneficiaryName: "A", iban: "DE89370400440532013000", bic: "", amount: nil,
    purposeCode: "", structuredReference: "", unstructuredRemittance: "Reference", beneficiaryToOriginator: ""))
expect(noAmount.isUsable, true, "payload without amount is usable")
expect(noAmount.issues.contains(.missingAmount), true, "missing amount is reported")

// An invalid IBAN blocks the code.
let badIBAN = EPCPayload(.init(
    beneficiaryName: "A", iban: "DE89370400440532013001", bic: "", amount: Amount.parse("1,00"),
    purposeCode: "", structuredReference: "", unstructuredRemittance: "", beneficiaryToOriginator: ""))
expect(badIBAN.isUsable, false, "invalid IBAN is blocked")

// Length limits.
let longRemittance = EPCPayload(.init(
    beneficiaryName: String(repeating: "N", count: 80), iban: "DE89370400440532013000", bic: "",
    amount: Amount.parse("1,00"), purposeCode: "", structuredReference: "",
    unstructuredRemittance: String(repeating: "Z", count: 200), beneficiaryToOriginator: ""))
expect(longRemittance.text.split(separator: "\n", omittingEmptySubsequences: false)[5].count, "70", "name truncated to 70")
expect(longRemittance.text.split(separator: "\n", omittingEmptySubsequences: false)[10].count, "140", "remittance truncated to 140")
expect(longRemittance.byteCount <= EPCPayload.maximumByteCount, true, "payload stays within 331 bytes")

print(failed == 0 ? "\nALL CHECKS PASSED" : "\n\(failed) FAILED")
exit(failed == 0 ? 0 : 1)
