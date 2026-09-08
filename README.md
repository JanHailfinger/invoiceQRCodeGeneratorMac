# InvoiceQR

[![Build](https://github.com/JanHailfinger/invoiceQRCodeGeneratorMac/actions/workflows/build.yml/badge.svg)](https://github.com/JanHailfinger/invoiceQRCodeGeneratorMac/actions/workflows/build.yml)

macOS app that reads invoices with OpenAI and shows the payment details as an
**EPC069-12 / GiroCode** QR code. Scan it with your banking app instead of typing IBAN and amount.

The interface is available in English and German and follows the system language.

## Download

Ready-built app: **[Releases](https://github.com/JanHailfinger/invoiceQRCodeGeneratorMac/releases/latest)**

- `InvoiceQR-x.y.z.dmg` — open it, drag the app to Applications.
- `InvoiceQR-x.y.z.pkg` — double-click, the installer puts the app in `/Applications`. Take this
  one if you want the Finder service to work immediately, because macOS only offers services for
  apps in `/Applications` and `~/Applications`.

The release notes say whether a build is notarized. If it is only ad-hoc signed, Gatekeeper
requires right-click → Open on **first launch**. If macOS claims the app is damaged:

```bash
xattr -dr com.apple.quarantine /Applications/InvoiceQR.app
```

## Build

```bash
./build.sh run       # build (release) and launch
./build.sh install   # copy to /Applications, register the Finder service
./build.sh dist      # sign, notarize, package as DMG and PKG
./build.sh check     # checks for IBAN, amount parser and EPC payload
./build.sh clean
```

Requires Xcode and `xcodegen` (`brew install xcodegen`). The Xcode project is generated from
`project.yml` and is not checked in.

## Signing and notarization

Without a Developer ID certificate everything builds ad-hoc signed, which is fine locally but not
for distribution. With a certificate:

```bash
export NOTARY_PROFILE=notarytool         # or ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH
VERSION=1.0.0 ./build.sh dist
```

`dist` signs with the first "Developer ID Application" certificate in the keychain (or
`SIGN_IDENTITY`), derives the team ID from it, notarizes the app, staples the ticket, then builds
DMG and PKG from the stapled app and notarizes those too. Without notarization credentials it
stops at the signed bundle and says so.

Store the credentials once, then `NOTARY_PROFILE` is enough:

```bash
xcrun notarytool store-credentials notarytool \
  --apple-id YOUR@apple-id.com --team-id XXXXXXXXXX --password APP-SPECIFIC-PASSWORD
```

### In CI

The release workflow signs and notarizes as soon as these repository secrets exist. Without them
the release still ships, ad-hoc signed, and logs a warning.

| Secret | Content |
|---|---|
| `MACOS_CERTIFICATE_P12` | Developer ID certificate as `.p12`, base64 (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PASSWORD` | Password of the `.p12` |
| `MACOS_SIGN_IDENTITY` | Optional, e.g. `Developer ID Application: Name (TEAMID)` |
| `APPLE_TEAM_ID` | Team ID |
| `APPLE_ID` + `APPLE_APP_PASSWORD` | Apple ID and app-specific password, or … |
| `ASC_KEY_ID` + `ASC_ISSUER_ID` + `ASC_KEY_P8` | … App Store Connect API key, the `.p8` base64 encoded |

The keychain is created per run and deleted afterwards. Secrets are not exposed to pull requests
from forks, and the workflow only runs on tags.

## Setup

1. Launch the app, press `⌘,` for settings.
2. Enter your OpenAI API key. It goes into the keychain, not into UserDefaults.
3. Pick a model. The default is `gpt-5-mini`; "Load Models" fetches the account's list.

## Reading an invoice

Four equivalent ways:

- **Finder right-click → Services → "Create Payment QR Code"** (after `./build.sh install`)
- **Finder right-click → Open With → InvoiceQR**
- **Drag and drop** onto the window or onto the drop area on the left of the toolbar
- **⌘O** in the window

Then check the fields and scan the code. Every edit in the form rebuilds the QR code immediately.

If the Services entry does not show up, run `/System/Library/CoreServices/pbs -flush` and restart
Finder. macOS only lists services for apps in `/Applications` or `~/Applications`.

## How the extraction works

The file is sent base64 encoded as `input_file` to the **Responses API**. For PDFs OpenAI extracts
text *and* page images server side, so scanned invoices work without local OCR. Images are sent as
`input_image`. The answer is pinned to a JSON schema through **Structured Outputs**
(`strict: true`), see `Sources/Model/InvoiceExtraction.swift`.

The model must not invent anything: missing values become `null`, anything noteworthy lands in
`warnings` and is shown as an advisory box. `payment_mode` detects cases where no transfer is
wanted at all (SEPA direct debit, already paid, card payment). Warnings are requested in the app's
language, so they match the rest of the interface.

## The QR code

EPC069-12, version 002, UTF-8, error correction level M. Version 002 makes the BIC optional, so a
payee name plus IBAN is enough for SEPA. Limits the app enforces:

| Field | Limit |
|---|---|
| Payee name | 70 characters |
| IBAN | 34, validated with mod-97-10 |
| Amount | 0.01 – 999,999,999.99 EUR |
| Purpose code | 4 characters |
| Structured reference | 35 characters |
| Remittance text | 140 characters |
| Note to payee | 70 characters |
| Payload total | 331 bytes |

A structured reference and a free-form remittance text are mutually exclusive per the standard, so
the app blocks the QR code while both are filled.

**EUR only.** A GiroCode cannot carry another currency; if the invoice is denominated differently
the app warns and the amount needs checking.

## Layout

```
Sources/
  App/         entry point, AppDelegate (Finder service, Open With)
  Model/       IBAN/BIC validation, amount parser, EPC payload, extraction schema
  Services/    OpenAI client, keychain, settings, QR rendering
  ViewModel/   AppModel - state and flow
  Views/       drop zone, form, QR panel, settings
Resources/
  Info.plist            NSServices and CFBundleDocumentTypes
  en.lproj/, de.lproj/   Localizable.strings, English literals as keys
Tests/
  PayloadChecks/  checks that run without an Xcode test host
```

## Limits

- Files up to 30 MB.
- The app is not sandboxed. Sandboxing is only required for the Mac App Store.
- **Check payee, IBAN and amount against the invoice before sending the transfer.** The model can
  be wrong, especially when the document contains several IBANs.
