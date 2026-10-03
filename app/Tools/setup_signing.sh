#!/bin/zsh
# Crée une fois l'identité de signature locale de Classeur, dans un trousseau dédié.
# Une identité stable garde les autorisations macOS (accès complet au disque, automatisation)
# d'une reconstruction à l'autre. Le trousseau de session n'est pas modifié.
set -euo pipefail

SECRETS="$HOME/Library/Application Support/Classeur/secrets"
KEYCHAIN="$HOME/Library/Keychains/classeur-signature.keychain-db"
IDENTITY="Classeur Local Signing"
mkdir -p "$SECRETS"
chmod 700 "$SECRETS"

if [[ ! -f "$SECRETS/signature-keychain" ]]; then
  ( umask 077; openssl rand -hex 24 > "$SECRETS/signature-keychain" )
fi
PASSWORD="$(cat "$SECRETS/signature-keychain")"

if [[ ! -f "$KEYCHAIN" ]]; then
  security create-keychain -p "$PASSWORD" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"
fi
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"

if ! security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  WORK="$(mktemp -d)"
  trap 'command rm -rf "$WORK"' EXIT
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -subj "/CN=$IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
  P12PASS="$(openssl rand -hex 12)"
  openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/id.p12" -passout "pass:$P12PASS" 2>/dev/null \
    || openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/id.p12" -passout "pass:$P12PASS"
  security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
fi
echo "$KEYCHAIN"
