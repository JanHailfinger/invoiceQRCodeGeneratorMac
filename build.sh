#!/bin/bash
# InvoiceQR bauen, starten, verteilen.
#
#   ./build.sh build     ad-hoc signierter Release-Build
#   ./build.sh run       bauen und starten
#   ./build.sh install    nach /Applications, registriert den Finder-Dienst
#   ./build.sh dist      signiert, notarisiert, verpackt als DMG und PKG
#   ./build.sh package   verpackt ohne Developer-ID-Zertifikat
#   ./build.sh check     Logikprüfungen
#   ./build.sh clean
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-Release}"
BUILD_DIR=".build"
APP="$BUILD_DIR/Build/Products/$CONFIG/InvoiceQR.app"

generate() {
    xcodegen generate --quiet
}

# VERSION setzt die Versionsnummer im Bundle: VERSION=1.0.0 ./build.sh build
build() {
    generate
    local overrides=()
    [ -n "${VERSION:-}" ] && overrides+=("MARKETING_VERSION=$VERSION")
    xcodebuild \
        -project InvoiceQR.xcodeproj \
        -scheme InvoiceQR \
        -configuration "$CONFIG" \
        -derivedDataPath "$BUILD_DIR" \
        ${overrides[@]+"${overrides[@]}"} \
        build
}

bundle_version() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"
}

# "|| true" ist nötig, weil set -e sonst bei erfolglosem grep still abbricht.
find_identity() {
    security find-identity -v -p codesigning \
        | grep "$1" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true
}

find_installer_identity() {
    security find-identity -v \
        | grep "Developer ID Installer" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true
}

# DMG mit App und Programme-Verknüpfung zum Reinziehen.
make_dmg() {
    # bash 3.2 kennt den Wert einer Variablen in derselben local-Zeile noch nicht.
    local version="$1"
    local identity="$2"
    local dmg="InvoiceQR-$version.dmg"
    local stage
    stage="$(mktemp -d)"
    cp -R "$APP" "$stage/"
    ln -s /Applications "$stage/Applications"

    rm -f "$dmg"
    hdiutil create \
        -volname "InvoiceQR $version" \
        -srcfolder "$stage" \
        -fs HFS+ -format UDZO -quiet \
        "$dmg"
    rm -rf "$stage"

    [ -n "$identity" ] && codesign --sign "$identity" --timestamp --force "$dmg"
    echo "$dmg"
}

# PKG installiert direkt nach /Applications, damit der Finder-Dienst gleich greift.
make_pkg() {
    local version="$1"
    local identity="$2"
    local pkg="InvoiceQR-$version.pkg"
    local args=(--component "$APP" --install-location /Applications --version "$version")
    [ -n "$identity" ] && args+=(--sign "$identity" --timestamp)

    rm -f "$pkg"
    pkgbuild "${args[@]}" "$pkg" > /dev/null
    echo "$pkg"
}

# Notarisierungs-Zugang: NOTARY_PROFILE, oder ASC_KEY_*, oder APPLE_ID + APPLE_APP_PASSWORD.
notary_args() {
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        echo "--keychain-profile|$NOTARY_PROFILE"
    elif [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ]; then
        echo "--key-id|$ASC_KEY_ID|--issuer|$ASC_ISSUER_ID|--key|$ASC_KEY_PATH"
    elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
        echo "--apple-id|$APPLE_ID|--password|$APPLE_APP_PASSWORD|--team-id|$APPLE_TEAM_ID"
    fi
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
        IDENTITY="${SIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
        if [ -z "$IDENTITY" ]; then
            echo "Kein 'Developer ID Application'-Zertifikat im Schlüsselbund." >&2
            echo "Anlegen: Xcode > Settings > Accounts > Manage Certificates > + " >&2
            exit 1
        fi

        # Team ID steckt in Klammern im Zertifikatsnamen.
        TEAM="${APPLE_TEAM_ID:-$(echo "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/')}"
        if [ -z "$TEAM" ]; then
            echo "APPLE_TEAM_ID ist nicht gesetzt und nicht aus dem Zertifikat ableitbar." >&2
            exit 1
        fi
        export APPLE_TEAM_ID="$TEAM"

        echo "Signiere mit: $IDENTITY (Team $TEAM)"
        generate
        xcodebuild \
            -project InvoiceQR.xcodeproj \
            -scheme InvoiceQR \
            -configuration Release \
            -derivedDataPath "$BUILD_DIR" \
            ${VERSION:+MARKETING_VERSION=$VERSION} \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY="$IDENTITY" \
            DEVELOPMENT_TEAM="$TEAM" \
            ENABLE_HARDENED_RUNTIME=YES \
            OTHER_CODE_SIGN_FLAGS="--timestamp" \
            build

        VERSION="${VERSION:-$(bundle_version)}"
        INSTALLER_IDENTITY="$(find_installer_identity)"
        [ -z "$INSTALLER_IDENTITY" ] && \
            echo "Warnung: kein 'Developer ID Installer'-Zertifikat, PKG bleibt unsigniert." >&2

        IFS='|' read -r -a NOTARY <<< "$(notary_args)"

        if [ ${#NOTARY[@]} -eq 0 ] || [ -z "${NOTARY[0]}" ]; then
            echo "Keine Notarisierungs-Zugangsdaten - signiert, aber nicht notarisiert." >&2
            echo "Gatekeeper verlangt beim ersten Start weiterhin Rechtsklick > Öffnen." >&2
            NOTARIZE=0
        else
            NOTARIZE=1
        fi

        # Erst die App notarisieren und staplen, dann daraus DMG und PKG bauen -
        # so trägt jede Kopie der App ihr Ticket auch offline.
        if [ "$NOTARIZE" = 1 ]; then
            APP_ZIP="$BUILD_DIR/InvoiceQR-app.zip"
            ditto -c -k --sequesterRsrc --keepParent "$APP" "$APP_ZIP"
            echo "Notarisiere App ..."
            xcrun notarytool submit "$APP_ZIP" "${NOTARY[@]}" --wait --timeout 30m
            xcrun stapler staple "$APP"
            rm -f "$APP_ZIP"
        fi

        DMG="$(make_dmg "$VERSION" "$IDENTITY")"
        PKG="$(make_pkg "$VERSION" "$INSTALLER_IDENTITY")"

        if [ "$NOTARIZE" = 1 ]; then
            for artifact in "$DMG" "$PKG"; do
                echo "Notarisiere $artifact ..."
                xcrun notarytool submit "$artifact" "${NOTARY[@]}" --wait --timeout 30m
                xcrun stapler staple "$artifact"
            done
        fi

        echo "=== Prüfung ==="
        codesign --verify --deep --strict --verbose=2 "$APP"
        spctl -a -vvv -t install "$APP" || true
        pkgutil --check-signature "$PKG" | head -4 || true
        shasum -a 256 "$DMG" "$PKG"
        echo "Fertig: $DMG und $PKG"
        ;;
    package)
        # Unsigniert bzw. ad-hoc verpacken - für Builds ohne Zertifikat.
        build
        VERSION="${VERSION:-$(bundle_version)}"
        DMG="$(make_dmg "$VERSION" "")"
        PKG="$(make_pkg "$VERSION" "")"
        shasum -a 256 "$DMG" "$PKG"
        echo "Fertig: $DMG und $PKG"
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
        rm -rf "$BUILD_DIR" InvoiceQR.xcodeproj InvoiceQR-*.dmg InvoiceQR-*.pkg InvoiceQR-*.zip
        echo "Aufgeräumt."
        ;;
    *)
        echo "Verwendung: ./build.sh [build|run|install|dist|package|check|clean]" >&2
        exit 1
        ;;
esac
