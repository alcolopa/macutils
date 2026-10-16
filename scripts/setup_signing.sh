#!/bin/bash
# Creates a local self-signed code-signing identity ("MacUtils Local Signing") in your login keychain.
# Signing every build with the same identity gives the app a stable identity, so macOS keeps the
# Accessibility permission across rebuilds instead of asking again after each one.
set -euo pipefail
NAME="MacUtils Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Identity \"$NAME\" already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/openssl.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
# OpenSSL 3 needs -legacy so macOS can read the bundle; LibreSSL (macOS default) doesn't have the flag.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:macutils >/dev/null 2>&1 \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:macutils >/dev/null 2>&1
security import "$TMP/id.p12" -k "$KEYCHAIN" -P macutils -T /usr/bin/codesign >/dev/null
echo "Created identity \"$NAME\"."
