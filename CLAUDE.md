# InvoiceQR

macOS-SwiftUI-App: Rechnung (PDF/Bild) → OpenAI Responses API → EPC069-12-QR-Code zum Scannen
mit der Banking-App.

## Bauen und prüfen

```bash
./build.sh run     # xcodegen + xcodebuild Release, startet die App
./build.sh check   # Logikprüfungen (IBAN, Betragsparser, EPC-Nutzdaten)
./build.sh dist    # signiert, notarisiert, verpackt (braucht Developer-ID-Zertifikat)
```

Tag `v*` pushen löst den Release-Workflow aus: baut, notarisiert und hängt das Bundle an einen
GitHub-Release. Ohne Signier-Secrets fällt er auf ad-hoc zurück statt zu scheitern.

`InvoiceQR.xcodeproj` ist generiert und nicht eingecheckt – Targets und Build-Settings gehören in
`project.yml`, nicht ins Projekt. Neue Dateien unter `Sources/` werden automatisch erfasst.

## Regeln, die hier zählen

- **EPC069-12 ist eine Norm, keine Konvention.** Feldreihenfolge, Längen und die Regel
  „strukturierte Referenz *oder* Verwendungszweck“ stehen in `Sources/Model/EPCPayload.swift`.
  Änderungen dort brauchen einen Gegencheck in `Tests/PayloadChecks/main.swift`.
- **Zeilenumbrüche in Nutzertexten sind ein Angriff auf die Feldstruktur.** `EPCPayload.sanitize`
  ersetzt Steuerzeichen; das darf nicht wegoptimiert werden.
- **Kein Betrag ohne Prüfung durch den Nutzer.** Extrahierte Werte landen in editierbaren Feldern,
  der QR-Code entsteht live daraus. Nichts wird stillschweigend übernommen.
- **API-Key gehört in den Schlüsselbund** (`KeychainStore`), nie in UserDefaults oder ins Log.
- Modell-IDs nicht hart verdrahten. `AppSettings.defaultModel` ist der Startwert, die Liste kommt
  zur Laufzeit von `/v1/models`.

## OpenAI-Aufruf

`POST /v1/responses` mit `input_file` (PDF, base64-Data-URL) oder `input_image` und
`text.format = json_schema, strict: true`. Antwort steckt in `output[].content[].text`,
Typ `output_text` – es gibt kein `output_text`-Feld auf oberster Ebene in der rohen API.
Details in `Sources/Services/OpenAIClient.swift`.
