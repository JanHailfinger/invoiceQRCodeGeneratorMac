# InvoiceQR

[![Build](https://github.com/JanHailfinger/invoiceQRCodeGeneratorMac/actions/workflows/build.yml/badge.svg)](https://github.com/JanHailfinger/invoiceQRCodeGeneratorMac/actions/workflows/build.yml)

macOS-App, die Rechnungen per OpenAI ausliest und die Zahlungsdaten als **EPC069-12 / GiroCode**
QR-Code anzeigt. Mit der Banking-App scannen statt IBAN und Betrag abzutippen.

## Herunterladen

Fertige App: **[Releases](https://github.com/JanHailfinger/invoiceQRCodeGeneratorMac/releases/latest)**

- `InvoiceQR-x.y.z.dmg` — öffnen, App nach „Programme" ziehen.
- `InvoiceQR-x.y.z.pkg` — Doppelklick, Installer legt die App nach `/Programme`. Der Weg, wenn der
  Finder-Dienst sofort greifen soll, weil macOS Dienste nur aus `/Programme` und
  `~/Programme` anbietet.

Ob ein Build signiert ist, stehen die Release-Notes dazu. Ist er nur ad-hoc signiert, verlangt
Gatekeeper beim **ersten Start** Rechtsklick auf die App → „Öffnen“ → im Dialog nochmal „Öffnen“.
Bei „beschädigt und kann nicht geöffnet werden“:

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

## Signieren und notarisieren

Ohne Developer-ID-Zertifikat baut alles ad-hoc signiert – lokal völlig ausreichend, für die
Weitergabe nicht. Mit Zertifikat:

```bash
export APPLE_TEAM_ID=XXXXXXXXXX          # 10 Zeichen, developer.apple.com/account
export NOTARY_PROFILE=notarytool         # oder ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH
VERSION=1.0.0 ./build.sh dist
```

`dist` signiert mit dem ersten „Developer ID Application“-Zertifikat aus dem Schlüsselbund
(oder `SIGN_IDENTITY`), reicht zur Notarisierung ein, wartet, staplet das Ticket ins Bundle und
prüft am Ende mit `codesign --verify` und `spctl`. Ohne Notarisierungs-Zugang bleibt es beim
signierten, nicht notarisierten Bundle und sagt das auch.

Zugangsdaten einmalig hinterlegen, dann genügt `NOTARY_PROFILE`:

```bash
xcrun notarytool store-credentials notarytool \
  --apple-id DEINE@apple-id.de --team-id XXXXXXXXXX --password APP-SPEZIFISCHES-PASSWORT
```

### In der CI

Der Release-Workflow signiert und notarisiert, sobald diese Repository-Secrets liegen. Fehlen sie,
läuft der Release ad-hoc signiert weiter und schreibt eine Warnung ins Log.

| Secret | Inhalt |
|---|---|
| `MACOS_CERTIFICATE_P12` | Developer-ID-Zertifikat als `.p12`, base64 (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PASSWORD` | Passwort des `.p12` |
| `MACOS_SIGN_IDENTITY` | optional, z. B. `Developer ID Application: Name (TEAMID)` |
| `APPLE_TEAM_ID` | Team ID |
| `ASC_KEY_ID` | App-Store-Connect-API-Key-ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | `.p8`-Datei, base64 |

Der Schlüsselbund wird pro Lauf temporär angelegt und danach gelöscht. Secrets gehen bei
Fork-Pull-Requests nicht mit, und der Workflow läuft ohnehin nur auf Tags.

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
