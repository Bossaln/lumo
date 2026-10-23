#!/bin/bash
# Erstellt einmalig ein eigenes Zertifikat „notchai Signing“ zum Signieren von notchai (kostenlos, ohne
# Apple-Konto). Damit tragen alle Versionen dieselbe Signatur, und macOS behält Freigaben wie „Bedienungshilfen“
# über Updates hinweg. Apple kennt das Zertifikat nicht; die Gatekeeper-Sperre nimmt die Homebrew-Installation weg.
#
# Das Skript
#   1. erzeugt Schlüssel und Zertifikat (10 Jahre gültig) in ./signing (nie einchecken, steht in .gitignore),
#   2. legt beides in deinen Anmelde-Schlüsselbund, damit auch eigene Builds (scripts/build-app.sh) damit signieren,
#   3. hinterlegt es als GitHub-Secrets NOTCHAI_CERT_P12 und NOTCHAI_CERT_PASSWORD für den Release-Workflow
#      (mit der GitHub-Kommandozeile `gh`; ohne sie steht am Ende, was du von Hand eintragen musst).
#
# Aufruf auf dem Mac, im notchai-Ordner: scripts/create-signing-certificate.sh
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="notchai Signing"
DIR="signing"
# LibreSSL von macOS: Ihre .p12-Dateien kann `security import` lesen (OpenSSL 3 bräuchte -legacy).
OPENSSL=/usr/bin/openssl

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "Im Schlüsselbund gibt es „$NAME“ schon. Ein neues Zertifikat würde die Freigaben wieder zurücksetzen."
  echo "Abbruch. Zum Neuanlegen erst das alte in der Schlüsselbundverwaltung löschen."
  exit 1
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
cat > "$DIR/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

echo "== Zertifikat erzeugen"
$OPENSSL req -x509 -newkey rsa:3072 -nodes -days 3650 -sha256 \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -config "$DIR/cert.cnf"
PASSWORD="$($OPENSSL rand -base64 24)"
$OPENSSL pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -name "$NAME" \
  -out "$DIR/notchai-signing.p12" -passout "pass:$PASSWORD"
printf '%s' "$PASSWORD" > "$DIR/password.txt"
chmod 600 "$DIR"/*
rm -f "$DIR/key.pem"

echo "== In den Anmelde-Schlüsselbund legen"
security import "$DIR/notchai-signing.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$PASSWORD" -T /usr/bin/codesign

REPO="$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
REPO="${REPO:-Bossaln/notchai}"
echo "== GitHub-Secrets für $REPO"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  base64 -i "$DIR/notchai-signing.p12" | gh secret set NOTCHAI_CERT_P12 --repo "$REPO"
  printf '%s' "$PASSWORD" | gh secret set NOTCHAI_CERT_PASSWORD --repo "$REPO"
  echo "Secrets gesetzt."
else
  base64 -i "$DIR/notchai-signing.p12" > "$DIR/notchai-signing.p12.base64"
  echo "Die GitHub-Kommandozeile fehlt (brew install gh, dann gh auth login) – oder trag die Secrets von Hand ein:"
  echo "  GitHub › $REPO › Settings › Secrets and variables › Actions › New repository secret"
  echo "  NOTCHAI_CERT_P12      = Inhalt von $DIR/notchai-signing.p12.base64"
  echo "  NOTCHAI_CERT_PASSWORD = Inhalt von $DIR/password.txt"
fi

echo
echo "Fertig. Wichtig: Sichere $DIR/notchai-signing.p12 und $DIR/password.txt (zum Beispiel im Passwort-Manager)."
echo "Geht das Zertifikat verloren, müssen alle Nutzer ihre Freigaben nach dem nächsten Update einmal neu erteilen."
