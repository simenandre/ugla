#!/bin/bash
# One-time Developer ID setup for signed + notarized releases. Creates a CSR,
# helps you get the Developer ID Application certificate, packages it as .p12,
# and sets the GitHub Actions secrets used by .github/workflows/release.yml.
# Adapted from loggie-macos.
#
# ffmpeg is fetched by CI from this repo's pinned `vendor-ffmpeg` release (see
# README). Create it once with your trusted static ffmpeg binaries:
#   gh release create vendor-ffmpeg --repo simenandre/open-philip-babymonitor \
#     --title "Vendored ffmpeg (static)" --latest=false ffmpeg-arm64 ffmpeg-amd64
set -euo pipefail

REPO="simenandre/open-philip-babymonitor"
CSR_FILE="UglaDeveloperID.certSigningRequest"
CERT_FILE="developerID_application.cer"
P12_FILE="DeveloperID.p12"

echo "=== Ugla code signing setup ==="
read -rp "Apple Developer email: " APPLE_EMAIL

cat > csr.conf <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
[dn]
emailAddress = ${APPLE_EMAIL}
CN = ${APPLE_EMAIL}
C = NO
EOF
openssl req -new -newkey rsa:2048 -nodes -keyout bm-signing.key -out "$CSR_FILE" -config csr.conf 2>/dev/null
rm -f csr.conf
echo "Created $CSR_FILE"
echo
echo "1. Open https://developer.apple.com/account/resources/certificates/add"
echo "2. Choose 'Developer ID Application', upload $(pwd)/$CSR_FILE"
echo "3. Download the certificate here as $CERT_FILE"
open "https://developer.apple.com/account/resources/certificates/add" || true
read -rp "Press Enter once $CERT_FILE is downloaded here... "
[ -f "$CERT_FILE" ] || { echo "Error: $CERT_FILE not found"; exit 1; }

read -rsp "Choose a password for the .p12: " P12_PASSWORD; echo
openssl x509 -inform DER -in "$CERT_FILE" -out cert.pem 2>/dev/null || cp "$CERT_FILE" cert.pem
openssl pkcs12 -export -out "$P12_FILE" -inkey bm-signing.key -in cert.pem -passout "pass:${P12_PASSWORD}"
rm -f cert.pem bm-signing.key

read -rp "Apple Team ID: " TEAM_ID
echo "Create an app-specific password at https://account.apple.com (Sign-In & Security)"
open "https://account.apple.com/" || true
read -rsp "App-specific password: " APP_PASSWORD; echo

echo "Setting GitHub secrets on ${REPO}..."
base64 -i "$P12_FILE" | gh secret set DEVELOPER_ID_APPLICATION_P12 --repo "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set DEVELOPER_ID_APPLICATION_P12_PASSWORD --repo "$REPO"
printf '%s' "$APPLE_EMAIL"  | gh secret set APPLE_ID --repo "$REPO"
printf '%s' "$APP_PASSWORD" | gh secret set APPLE_ID_PASSWORD --repo "$REPO"
printf '%s' "$TEAM_ID"      | gh secret set APPLE_TEAM_ID --repo "$REPO"
rm -f "$CSR_FILE" "$P12_FILE"

echo
echo "Done. Next: create the vendor-ffmpeg release (see top of this script),"
echo "then push a tag:  git tag v1.0.0 && git push --tags"
