#!/bin/bash
# InvoiceQR bauen, starten oder in /Applications installieren.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-Release}"
BUILD_DIR=".build"
APP="$BUILD_DIR/Build/Products/$CONFIG/InvoiceQR.app"

generate() {
    xcodegen generate --quiet
}

build() {
    generate
    # VERSION setzt die Versionsnummer im Bundle, z. B. VERSION=1.0.0 ./build.sh build
    local overrides=()
    if [ -n "${VERSION:-}" ]; then
        overrides+=("MARKETING_VERSION=$VERSION")
    fi
    xcodebuild \
        -project InvoiceQR.xcodeproj \
        -scheme InvoiceQR \
        -configuration "$CONFIG" \
        -derivedDataPath "$BUILD_DIR" \
        ${overrides[@]+"${overrides[@]}"} \
        build
}

case "${1:-build}" in
    build)
        build
        echo "Fertig: $APP"
        ;;
    run)
        build
        open "$APP"
        ;;
    install)
        build
        rm -rf /Applications/InvoiceQR.app
        cp -R "$APP" /Applications/
        # Dienste-Eintrag im Finder-Kontextmenü registrieren.
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
            -f /Applications/InvoiceQR.app
        /System/Library/CoreServices/pbs -flush || true
        open /Applications/InvoiceQR.app
        echo "Installiert: /Applications/InvoiceQR.app"
        ;;
    dist)
        # Signiert, notarisiert, staplet und verpackt die App für die Weitergabe.
        #
        # Zertifikat:   SIGN_IDENTITY, sonst automatisch das erste "Developer ID Application"
        #               aus dem Schlüsselbund. APPLE_TEAM_ID muss gesetzt sein.
        # Notarisieren: NOTARY_PROFILE (notarytool store-credentials), oder
        #               ASC_KEY_ID + ASC_ISSUER_ID + ASC_KEY_PATH (.p8), oder
        #               APPLE_ID + APPLE_APP_PASSWORD.
        VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
            "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)}"

        # Ohne "|| true" beendet set -e das Skript still, sobald grep nichts findet.
        IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
            | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)}"
        if [ -z "$IDENTITY" ]; then
            echo "Kein 'Developer ID Application'-Zertifikat im Schlüsselbund." >&2
            echo "Anlegen: Xcode > Settings > Accounts > Manage Certificates > + , oder" >&2
            echo "per App Store Connect API-Key. Danach erneut ./build.sh dist" >&2
            exit 1
        fi
        if [ -z "${APPLE_TEAM_ID:-}" ]; then
            echo "APPLE_TEAM_ID ist nicht gesetzt (10 Zeichen, siehe developer.apple.com/account)." >&2
            exit 1
        fi

        echo "Signiere mit: $IDENTITY (Team $APPLE_TEAM_ID)"
        generate
        xcodebuild \
            -project InvoiceQR.xcodeproj \
            -scheme InvoiceQR \
            -configuration Release \
            -derivedDataPath "$BUILD_DIR" \
            MARKETING_VERSION="$VERSION" \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY="$IDENTITY" \
            DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
            ENABLE_HARDENED_RUNTIME=YES \
            OTHER_CODE_SIGN_FLAGS="--timestamp" \
            build

        DIST="InvoiceQR-$VERSION.zip"
        ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST"

        # Notarisieren, sofern Zugangsdaten vorhanden sind.
        NOTARY_ARGS=()
        if [ -n "${NOTARY_PROFILE:-}" ]; then
            NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
        elif [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ]; then
            NOTARY_ARGS=(--key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --key "$ASC_KEY_PATH")
        elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
            NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
        fi

        if [ ${#NOTARY_ARGS[@]} -eq 0 ]; then
            echo "Keine Notarisierungs-Zugangsdaten - App ist signiert, aber nicht notarisiert." >&2
            echo "Gatekeeper verlangt beim ersten Start weiterhin Rechtsklick > Öffnen." >&2
        else
            echo "Reiche zur Notarisierung ein ..."
            xcrun notarytool submit "$DIST" "${NOTARY_ARGS[@]}" --wait --timeout 30m
            xcrun stapler staple "$APP"
            rm -f "$DIST"
            ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST"
            echo "Notarisiert und gestaplet."
        fi

        echo "=== Prüfung ==="
        codesign --verify --deep --strict --verbose=2 "$APP"
        spctl -a -vvv -t install "$APP" || true
        shasum -a 256 "$DIST"
        echo "Fertig: $DIST"
        ;;
    check)
        OUT=$(mktemp -d)
        swiftc -o "$OUT/checks" \
            Sources/Model/IBAN.swift \
            Sources/Model/Amount.swift \
            Sources/Model/EPCPayload.swift \
            Tests/PayloadChecks/main.swift
        "$OUT/checks"
        rm -rf "$OUT"
        ;;
    clean)
        rm -rf "$BUILD_DIR" InvoiceQR.xcodeproj
        echo "Aufgeräumt."
        ;;
    *)
        echo "Verwendung: ./build.sh [build|run|install|dist|check|clean]" >&2
        exit 1
        ;;
esac
