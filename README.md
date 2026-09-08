# InvoiceQR

[![Build](https://github.com/JanHailfinger/invoiceQRCodeGeneratorMac/actions/workflows/build.yml/badge.svg)](https://github.com/JanHailfinger/invoiceQRCodeGeneratorMac/actions/workflows/build.yml)

macOS-App, die Rechnungen per OpenAI ausliest und die Zahlungsdaten als **EPC069-12 / GiroCode**
QR-Code anzeigt. Mit der Banking-App scannen statt IBAN und Betrag abzutippen.

## Herunterladen

Fertige App: **[Releases](https://github.com/JanHailfinger/invoiceQRCodeGeneratorMac/releases/latest)**
→ `InvoiceQR-x.y.z.zip`.

Die App ist ad-hoc signiert und nicht notarisiert. Beim **ersten Start** deshalb
Rechtsklick auf die App → „Öffnen“ → im Dialog nochmal „Öffnen“. Der Doppelklick allein wird von
Gatekeeper abgelehnt. Bei „beschädigt und kann nicht geöffnet werden“:

```bash
xattr -dr com.apple.quarantine /Applications/InvoiceQR.app
```

## Bauen

```bash
./build.sh run       # baut (Release) und startet
./build.sh install   # nach /Applications, registriert den Finder-Dienst
./build.sh check     # Prüfungen für IBAN, Betragsparser und EPC-Nutzdaten
./build.sh clean
```

Voraussetzungen: Xcode und `xcodegen` (`brew install xcodegen`). Das Xcode-Projekt wird aus
`project.yml` generiert und ist nicht eingecheckt.

## Einrichten

1. App starten, `⌘,` für die Einstellungen.
2. OpenAI-API-Key eintragen – landet im Schlüsselbund, nicht in den UserDefaults.
3. Modell wählen. Standard ist `gpt-5-mini`; „Modelle laden“ holt die Liste des Accounts.

## Rechnung auslesen

Vier Wege, alle gleichwertig:

- **Finder-Rechtsklick → Dienste → „Zahlungs-QR erzeugen“** (nach `./build.sh install`)
- **Finder-Rechtsklick → Öffnen mit → InvoiceQR**
- **Drag & Drop** aufs Fenster oder auf die Ablagefläche links in der Toolbar
- **⌘O** im Fenster

Danach: Felder prüfen, QR-Code scannen. Jede Änderung im Formular baut den QR-Code sofort neu.

Erscheint der Dienste-Eintrag nicht, hilft `/System/Library/CoreServices/pbs -flush` und ein
Neustart des Finders. macOS zeigt Dienste nur für Apps aus `/Applications` oder `~/Applications`.

## Wie das Auslesen läuft

Die Datei geht base64-kodiert als `input_file` an die **Responses API**. Für PDFs zieht OpenAI
serverseitig Text *und* Seitenbilder – gescannte Rechnungen funktionieren dadurch ohne eigenes OCR.
Bilder gehen als `input_image`. Die Antwort ist über **Structured Outputs** (`strict: true`) auf ein
JSON-Schema festgenagelt, siehe `Sources/Model/InvoiceExtraction.swift`.

Das Modell darf nichts erfinden: fehlende Angaben werden `null`, Auffälligkeiten landen in
`warnings` und erscheinen als Hinweiskasten. `payment_mode` erkennt Fälle, in denen gar nicht
überwiesen werden soll (SEPA-Lastschrift, bereits bezahlt, Kartenzahlung).

## QR-Code

EPC069-12, Version 002, UTF-8, Fehlerkorrektur M. Version 002 macht die BIC optional, deshalb
genügt bei SEPA-IBANs der Empfängername plus IBAN. Grenzen, die die App durchsetzt:

| Feld | Limit |
|---|---|
| Empfängername | 70 Zeichen |
| IBAN | 34, Mod-97-10-geprüft |
| Betrag | 0,01 – 999.999.999,99 EUR |
| Purpose Code | 4 Zeichen |
| Referenz (strukturiert) | 35 Zeichen |
| Verwendungszweck | 140 Zeichen |
| Hinweis an Empfänger | 70 Zeichen |
| Nutzdaten gesamt | 331 Byte |

Strukturierte Referenz und freier Verwendungszweck schließen sich laut Norm aus – die App
blockiert den QR-Code, solange beide gefüllt sind.

**Nur EUR.** GiroCode überträgt keine andere Währung; lautet die Rechnung auf etwas anderes,
warnt die App und der Betrag muss geprüft werden.

## Aufbau

```
Sources/
  App/         Einstiegspunkt, AppDelegate (Finder-Dienst, "Öffnen mit")
  Model/       IBAN/BIC-Prüfung, Betragsparser, EPC-Nutzdaten, Extraktionsschema
  Services/    OpenAI-Client, Schlüsselbund, Einstellungen, QR-Rendering
  ViewModel/   AppModel – Zustand und Ablauf
  Views/       Ablagefläche, Formular, QR-Panel, Einstellungen
Resources/
  Info.plist   NSServices + CFBundleDocumentTypes
Tests/
  PayloadChecks/  Prüfungen ohne Xcode-Testhost
```

## Grenzen

- Die App ist ad-hoc signiert und läuft ohne App-Sandbox. Für eine Weitergabe braucht es ein
  Developer-Team in `project.yml`, Hardened Runtime und Notarisierung.
- Dateien bis 30 MB.
- **Vor dem Absenden der Überweisung Empfänger, IBAN und Betrag gegen die Rechnung prüfen.**
  Das Modell kann sich irren, gerade bei mehreren IBANs im Dokument.
