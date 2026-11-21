#!/bin/bash
# One-time setup: creates a permanent code-signing identity for MacTerm+ builds.
#
# Why: builds signed "ad-hoc" get a new identity every time, so macOS forgets Keychain
# "Always Allow" choices and folder permissions after each update. Signing every build with
# the same certificate keeps those permissions across updates.
#
# The certificate lives in its own keychain file (~/.macterm-signing/), not in the login
# keychain, and no system trust settings are changed.
#
# KEEP ~/.macterm-signing SAFE AND BACKED UP. Releases must always be signed with this same
# certificate; a new one makes every user's Mac ask for permissions one more time.
set -euo pipefail

DIR="$HOME/.macterm-signing"
KC="$DIR/signing.keychain-db"
NAME="MacTerm+ Code Signing (Bairagi)"

if [ -f "$KC" ]; then
  echo "Signing identity already exists in $KC — nothing to do."
  exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
umask 077

# Random keychain password, stored next to it (readable only by you).
openssl rand -hex 24 > "$DIR/keychain-password"
PASS="$(cat "$DIR/keychain-password")"

cat > "$DIR/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
O = Bairagi
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -config "$DIR/cert.cnf" 2>/dev/null
P12PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -name "$NAME" \
  -out "$DIR/identity.p12" -passout "pass:$P12PASS" 2>/dev/null
echo "$P12PASS" > "$DIR/identity.p12.password"

security create-keychain -p "$PASS" "$KC"
security set-keychain-settings "$KC"            # no auto-lock timeout
security unlock-keychain -p "$PASS" "$KC"
security import "$DIR/identity.p12" -k "$KC" -P "$P12PASS" -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a dialog.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null
rm -f "$DIR/key.pem" "$DIR/cert.cnf"

echo "✓ Created signing identity “$NAME”"
echo "  Keychain: $KC"
echo "  Back up the folder $DIR (it contains the private key)."
