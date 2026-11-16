#!/bin/bash
# Crea nel portachiavi di login un certificato autofirmato per firmare Copy8.
# Con una firma sempre uguale macOS ricorda i permessi (Accessibilità, accesso agli appunti)
# anche dopo ogni ricompilazione. Vale solo su questo Mac: per distribuire l'app ad altri
# senza avvisi serve un certificato Developer ID di Apple.
# Per rimuoverlo: security delete-identity -c "Copy8 Local Signing"
set -euo pipefail

NAME="${1:-Copy8 Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Il certificato \"$NAME\" esiste già."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=$(openssl rand -hex 16)

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/identity.p12" \
    -passout "pass:$PASS" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Creato il certificato \"$NAME\" nel portachiavi di login."
