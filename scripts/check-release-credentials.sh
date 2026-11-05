#!/bin/bash
# Checks a release's signing and notarization credentials before anything is
# packaged, and prints the signing identity on stdout as identity=<name>, with
# everything else on stderr, so stdout can go to $GITHUB_OUTPUT. It stops on a
# missing identity, an expired certificate or a rejected App Store Connect API key,
# and warns when the certificate has under 30 days left.
#
#   check-release-credentials.sh --keychain <file> --key <p8-file> --key-id <id>
#                                --issuer <id>

set -euo pipefail

warn_days=30
keychain="" key="" key_id="" issuer=""

die() {
  echo "::error::$1" >&2
  exit 1
}

while (( $# > 0 )); do
  case "$1" in
    --keychain) keychain="${2-}"; shift 2 ;;
    --key) key="${2-}"; shift 2 ;;
    --key-id) key_id="${2-}"; shift 2 ;;
    --issuer) issuer="${2-}"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done
for required in keychain key key_id issuer; do
  [[ -n "${!required}" ]] || die "--${required//_/-} is required"
done

identity="$(security find-identity -v -p codesigning "$keychain" |
  sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -n 1)"
[[ -n "$identity" ]] ||
  die "No Developer ID Application identity in $keychain. Check DEVELOPER_ID_CERT_P12_BASE64 and DEVELOPER_ID_CERT_PASSWORD, and that the .p12 holds its private key."
echo "Signing identity: $identity" >&2

expiry="$(security find-certificate -c "$identity" -p "$keychain" 2>/dev/null |
  openssl x509 -noout -enddate 2>/dev/null | cut -d = -f 2 || true)"
expiry_epoch="$(LC_ALL=C date -j -f '%b %e %T %Y %Z' "$expiry" +%s 2>/dev/null || echo 0)"
if (( expiry_epoch > 0 )); then
  days=$(( (expiry_epoch - $(date +%s)) / 86400 ))
  now="$(date +%s)"
  if (( expiry_epoch <= now )); then
    die "The signing certificate expired on $expiry. Create a new Developer ID Application certificate and update DEVELOPER_ID_CERT_P12_BASE64 and DEVELOPER_ID_CERT_PASSWORD."
  elif (( days < warn_days )); then
    echo "::warning::The signing certificate expires in $days days ($expiry). Renew it before the next release." >&2
  else
    echo "Certificate expires in $days days ($expiry)" >&2
  fi
else
  echo "::warning::Could not read the signing certificate's expiry ('$expiry')." >&2
fi

if ! xcrun notarytool history --key "$key" --key-id "$key_id" --issuer "$issuer" >/dev/null 2>&1; then
  die "Apple rejected the App Store Connect API key. Check AC_API_KEY_P8_BASE64, AC_API_KEY_ID and AC_API_ISSUER_ID, and that the key hasn't been revoked."
fi
echo "App Store Connect API key accepted" >&2

echo "identity=$identity"
