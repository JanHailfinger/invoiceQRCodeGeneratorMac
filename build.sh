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
        "${overrides[@]}" \
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
        echo "Verwendung: ./build.sh [build|run|install|check|clean]" >&2
        exit 1
        ;;
esac
