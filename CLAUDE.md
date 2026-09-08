# InvoiceQR

macOS SwiftUI app: invoice (PDF or image) → OpenAI Responses API → EPC069-12 QR code to scan with
a banking app. English and German UI.

## Build and check

```bash
./build.sh run     # xcodegen + xcodebuild release, launches the app
./build.sh check   # logic checks (IBAN, amount parser, EPC payload)
./build.sh dist    # signs, notarizes, packages (needs a Developer ID certificate)
```

`InvoiceQR.xcodeproj` is generated and not checked in - targets and build settings belong in
`project.yml`, not in the project file. New files under `Sources/` are picked up automatically.

Pushing a `v*` tag triggers the release workflow: it builds, notarizes and attaches DMG and PKG to
a GitHub release. Without signing secrets it falls back to ad-hoc instead of failing.

## Rules that matter here

- **Everything in this repository is written in English** - code, comments, commit messages,
  documentation. The user-facing German lives only in `Resources/Localizable.xcstrings`.
- **New user-facing strings need a catalog entry.** English literals are the keys: `Text("…")` in
  SwiftUI, `NSLocalizedString` elsewhere. `SWIFT_EMIT_LOC_STRINGS` is off, so the catalog is
  hand-maintained and a missing key silently falls back to English.
- **EPC069-12 is a standard, not a convention.** Field order, lengths and the "structured
  reference *or* remittance text" rule live in `Sources/Model/EPCPayload.swift`. Changes there need
  a counterpart in `Tests/PayloadChecks/main.swift`.
- **Line breaks in user text are an attack on the field structure.** `EPCPayload.sanitize` replaces
  control characters; do not optimize that away.
- **No amount without the user seeing it.** Extracted values land in editable fields and the QR
  code is derived from those. Nothing is adopted silently.
- **The API key belongs in the keychain** (`KeychainStore`), never in UserDefaults or a log.
- Do not hardcode model IDs. `AppSettings.defaultModel` is the starting value, the list comes from
  `/v1/models` at runtime.

## The OpenAI call

`POST /v1/responses` with `input_file` (PDF as a base64 data URL) or `input_image`, plus
`text.format = json_schema, strict: true`. The answer sits in `output[].content[].text` with type
`output_text` - the raw API has no top-level `output_text` field. Details in
`Sources/Services/OpenAIClient.swift`.

## Bash gotchas in build.sh

The runner and macOS ship bash 3.2: an empty array under `set -u` aborts (use
`${arr[@]+"${arr[@]}"}`), a variable is not visible later in the same `local` statement, and a
failing command substitution under `set -e` exits silently (append `|| true`).
