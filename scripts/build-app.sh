#!/bin/bash
# Compila Copy8 in release e crea build/Copy8.app, firmata.
# Uso: scripts/build-app.sh             → crea build/Copy8.app
#      scripts/build-app.sh --dmg       → crea anche build/Copy8-<versione>.dmg
#      scripts/build-app.sh --notarize  → crea il DMG, lo fa autenticare da Apple e ci aggancia il ticket
#      scripts/build-app.sh --install   → la copia anche in /Applications
#
# Firma, in ordine di preferenza:
#   1. l'identità in $COPY8_SIGN_ID, se impostata;
#   2. un certificato "Developer ID Application" nel portachiavi: è quella per distribuire l'app;
#   3. "Copy8 Local Signing" (scripts/make-signing-cert.sh): stabile, ma vale solo su questo Mac;
#   4. firma ad-hoc, che cambia a ogni compilazione.
#
# L'autenticazione usa un profilo di notarytool salvato nel portachiavi, di default "Copy8"
# (cambia nome con $COPY8_NOTARY_PROFILE). Va creato una volta, vedi il README.
set -euo pipefail
cd "$(dirname "$0")/.."

MAKE_DMG=0
NOTARIZE=0
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --dmg) MAKE_DMG=1 ;;
        --notarize) MAKE_DMG=1; NOTARIZE=1 ;;
        --install) INSTALL=1 ;;
        *) echo "Opzione sconosciuta: $arg" >&2; exit 1 ;;
    esac
done

identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
# Il certificato autofirmato non è "valido" per macOS (CSSMERR_TP_NOT_TRUSTED) e con -v non compare,
# ma codesign lo usa lo stesso: va cercato nell'elenco completo.
all_identities=$(security find-identity -p codesigning 2>/dev/null || true)
if [ -n "${COPY8_SIGN_ID:-}" ]; then
    SIGN_ID="$COPY8_SIGN_ID"
elif DEV_ID=$(grep -o '"Developer ID Application: [^"]*"' <<<"$identities" | head -n 1 | tr -d '"') && [ -n "$DEV_ID" ]; then
    SIGN_ID="$DEV_ID"
elif grep -q '"Copy8 Local Signing"' <<<"$all_identities"; then
    SIGN_ID="Copy8 Local Signing"
else
    SIGN_ID="-"
fi
DEVELOPER_ID=0
[[ "$SIGN_ID" == "Developer ID Application:"* ]] && DEVELOPER_ID=1

NOTARY_PROFILE="${COPY8_NOTARY_PROFILE:-Copy8}"
if [ "$NOTARIZE" = 1 ]; then
    if [ "$DEVELOPER_ID" = 0 ]; then
        echo "Per l'autenticazione serve un certificato \"Developer ID Application\" nel portachiavi." >&2
        exit 1
    fi
    # Controlla subito il profilo, per non scoprirlo dopo la compilazione.
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "Profilo di notarytool \"$NOTARY_PROFILE\" mancante o non valido. Crealo con:" >&2
        echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <Apple ID> --team-id <Team ID>" >&2
        exit 1
    fi
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Copy8"

APP=build/Copy8.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Copy8"
cp Support/Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
    rm -rf build/AppIcon.iconset
    swiftc -O scripts/make-icon.swift -o build/make-icon
    build/make-icon build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Support/EightWaveLogo.png "$APP/Contents/Resources/EightWaveLogo.png"

# macOS lega i permessi (Accessibilità) alla firma: con un certificato stabile restano validi
# tra una compilazione e l'altra. Developer ID richiede anche hardened runtime e timestamp,
# senza i quali Apple rifiuta l'autenticazione.
if [ "$DEVELOPER_ID" = 1 ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
    codesign --force --sign "$SIGN_ID" "$APP"
fi
codesign --verify --strict "$APP"
if [ "$SIGN_ID" = "-" ]; then
    echo "Creato $APP, firma ad-hoc (per una firma stabile: scripts/make-signing-cert.sh)"
else
    echo "Creato $APP, firmata con \"$SIGN_ID\""
fi

if [ "$MAKE_DMG" = 1 ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
    DMG="build/Copy8-$VERSION.dmg"
    STAGE=build/dmg
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "Copy8" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    if [ "$DEVELOPER_ID" = 1 ]; then
        codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
    fi
    echo "Creato $DMG"

    if [ "$NOTARIZE" = 1 ]; then
        # Apple autentica il DMG e tutto quello che contiene; il ticket va agganciato al DMG,
        # il contenitore più esterno, così Gatekeeper lo verifica anche senza rete.
        echo "Invio $DMG ad Apple per l'autenticazione (di solito pochi minuti)…"
        RESULT=build/notarization.plist
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
            --output-format plist >"$RESULT" || true
        STATUS=$(plutil -extract status raw -o - "$RESULT" 2>/dev/null || echo "sconosciuto")
        SUBMISSION=$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || echo "")
        if [ "$STATUS" != "Accepted" ]; then
            echo "Autenticazione non riuscita (stato: $STATUS)." >&2
            if [ -n "$SUBMISSION" ]; then
                xcrun notarytool log "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" >&2 || true
            else
                cat "$RESULT" >&2
            fi
            exit 1
        fi
        xcrun stapler staple "$DMG"
        spctl --assess --type open --context context:primary-signature "$DMG"
        echo "Autenticato da Apple: $DMG è pronto da distribuire"
    elif [ "$DEVELOPER_ID" = 1 ]; then
        echo "Nota: il DMG è firmato ma non autenticato da Apple. Per distribuirlo usa --notarize."
    fi
fi

if [ "$INSTALL" = 1 ]; then
    pkill -x Copy8 2>/dev/null || true
    rm -rf /Applications/Copy8.app
    cp -R "$APP" /Applications/
    echo "Installato in /Applications/Copy8.app"
fi
