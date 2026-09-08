#!/bin/bash
# Build, run and distribute InvoiceQR.
#
#   ./build.sh build     ad-hoc signed release build
#   ./build.sh run       build and launch
#   ./build.sh install   copy to /Applications and register the Finder service
#   ./build.sh dist      sign, notarize and package as DMG and PKG
#   ./build.sh package   package without a Developer ID certificate
#   ./build.sh check     logic checks
#   ./build.sh clean
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-Release}"
BUILD_DIR=".build"
APP="$BUILD_DIR/Build/Products/$CONFIG/InvoiceQR.app"

generate() {
    xcodegen generate --quiet
}

# VERSION sets the bundle version: VERSION=1.0.0 ./build.sh build
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

# The "|| true" matters: without it set -e aborts silently when grep finds nothing.
find_identity() {
    security find-identity -v -p codesigning \
        | grep "$1" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true
}

find_installer_identity() {
    security find-identity -v \
        | grep "Developer ID Installer" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true
}

# DMG holding the app plus an Applications link to drag it into.
make_dmg() {
    # bash 3.2 cannot see a variable assigned earlier in the same local statement.
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

# The PKG installs straight into /Applications so the Finder service works right away.
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

# Notarization credentials: NOTARY_PROFILE, or ASC_KEY_*, or APPLE_ID + APPLE_APP_PASSWORD.
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
        echo "Done: $APP"
        ;;
    run)
        build
        open "$APP"
        ;;
    install)
        build
        rm -rf /Applications/InvoiceQR.app
        cp -R "$APP" /Applications/
        # Register the service entry in the Finder context menu.
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
            -f /Applications/InvoiceQR.app
        /System/Library/CoreServices/pbs -flush || true
        open /Applications/InvoiceQR.app
        echo "Installed: /Applications/InvoiceQR.app"
        ;;
    dist)
        # Certificate: SIGN_IDENTITY, otherwise the first "Developer ID Application"
        # in the keychain. The team ID is derived from the certificate name.
        IDENTITY="${SIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
        if [ -z "$IDENTITY" ]; then
            echo "No 'Developer ID Application' certificate in the keychain." >&2
            echo "Create one: Xcode > Settings > Accounts > Manage Certificates > +" >&2
            exit 1
        fi

        # The team ID sits in parentheses at the end of the certificate name.
        TEAM="${APPLE_TEAM_ID:-$(echo "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/')}"
        if [ -z "$TEAM" ]; then
            echo "APPLE_TEAM_ID is unset and cannot be derived from the certificate." >&2
            exit 1
        fi
        export APPLE_TEAM_ID="$TEAM"

        echo "Signing with: $IDENTITY (team $TEAM)"
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
            echo "Warning: no 'Developer ID Installer' certificate, the PKG stays unsigned." >&2

        IFS='|' read -r -a NOTARY <<< "$(notary_args)"

        if [ ${#NOTARY[@]} -eq 0 ] || [ -z "${NOTARY[0]}" ]; then
            echo "No notarization credentials - signed but not notarized." >&2
            echo "Gatekeeper will still require right-click > Open on first launch." >&2
            NOTARIZE=0
        else
            NOTARIZE=1
        fi

        # Notarize and staple the app first, then build DMG and PKG from it, so every
        # copy of the app carries its ticket even offline.
        if [ "$NOTARIZE" = 1 ]; then
            APP_ZIP="$BUILD_DIR/InvoiceQR-app.zip"
            ditto -c -k --sequesterRsrc --keepParent "$APP" "$APP_ZIP"
            echo "Notarizing the app ..."
            xcrun notarytool submit "$APP_ZIP" "${NOTARY[@]}" --wait --timeout 30m
            xcrun stapler staple "$APP"
            rm -f "$APP_ZIP"
        fi

        DMG="$(make_dmg "$VERSION" "$IDENTITY")"
        PKG="$(make_pkg "$VERSION" "$INSTALLER_IDENTITY")"

        if [ "$NOTARIZE" = 1 ]; then
            for artifact in "$DMG" "$PKG"; do
                echo "Notarizing $artifact ..."
                xcrun notarytool submit "$artifact" "${NOTARY[@]}" --wait --timeout 30m
                xcrun stapler staple "$artifact"
            done
        fi

        echo "=== Verification ==="
        codesign --verify --deep --strict --verbose=2 "$APP"
        spctl -a -vvv -t install "$APP" || true
        pkgutil --check-signature "$PKG" | head -4 || true
        shasum -a 256 "$DMG" "$PKG"
        echo "Done: $DMG and $PKG"
        ;;
    package)
        # Ad-hoc packaging for builds without a certificate.
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
        echo "Cleaned."
        ;;
    *)
        echo "Usage: ./build.sh [build|run|install|dist|package|check|clean]" >&2
        exit 1
        ;;
esac
