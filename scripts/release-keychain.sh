#!/bin/bash
# Creates and removes the temporary signing keychain of a release job (change 1
# design D11). The runner works as the owner's own macOS user, so the job leaves
# the owner's keychains alone: it never changes the default keychain or writes to
# the login keychain, and removing this one restores the search list as it was.
#
#   release-keychain.sh create <keychain> <saved-search-list>
#   release-keychain.sh delete <keychain> <saved-search-list>
#
# create reads DEVELOPER_ID_CERT_P12_BASE64 and DEVELOPER_ID_CERT_PASSWORD from the
# environment. Passwords reach `security` only through stdin, using its interactive
# mode, and the keychain's own password is random and lasts only for this command.
# delete does nothing for what's already gone, so it's safe after a failed create.

set -euo pipefail
set +x

die() {
  echo "release-keychain: $1" >&2
  exit 1
}

[[ $# -eq 3 && -n "$2" && -n "$3" ]] || die "usage: release-keychain.sh create|delete <keychain> <saved-search-list>"
action="$1" keychain="$2" saved="$3"

# Quotes a value for `security -i`, which reads a double-quoted word with backslash
# escapes.
quoted() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

# Prints the saved search list's paths, one per line. `security` prints each one
# indented and in double quotes.
saved_paths() {
  sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' "$saved"
}

create() {
  [[ -n "${DEVELOPER_ID_CERT_P12_BASE64-}" ]] || die "DEVELOPER_ID_CERT_P12_BASE64 is not set"
  [[ -n "${DEVELOPER_ID_CERT_PASSWORD-}" ]] || die "DEVELOPER_ID_CERT_PASSWORD is not set"
  [[ ! -e "$keychain" ]] || die "$keychain already exists"

  umask 077
  local password p12
  password="$(openssl rand -hex 32)"
  if [[ -n "${GITHUB_ACTIONS-}" ]]; then
    echo "::add-mask::$password"
  fi
  p12="$(mktemp "$(dirname "$keychain")/developer-id.XXXXXX")"
  # shellcheck disable=SC2064 # The path is fixed now, on purpose.
  trap "rm -f '$p12'" EXIT
  printf '%s' "$DEVELOPER_ID_CERT_P12_BASE64" | base64 -D >"$p12" || die "the certificate isn't valid base64"
  [[ -s "$p12" ]] || die "the certificate decoded to an empty file"

  # Saved first, so delete can restore it however far this gets.
  security list-keychains -d user >"$saved"

  {
    printf 'create-keychain -p %s %s\n' "$(quoted "$password")" "$(quoted "$keychain")"
    printf 'unlock-keychain -p %s %s\n' "$(quoted "$password")" "$(quoted "$keychain")"
    printf 'import %s -k %s -P %s -T /usr/bin/codesign\n' \
      "$(quoted "$p12")" "$(quoted "$keychain")" "$(quoted "$DEVELOPER_ID_CERT_PASSWORD")"
    printf 'set-key-partition-list -S apple-tool:,apple:,codesign: -s -k %s %s\n' \
      "$(quoted "$password")" "$(quoted "$keychain")"
  } | security -i >/dev/null

  # Six hours, with no lock on sleep: notarization can take a while.
  security set-keychain-settings -t 21600 "$keychain"

  local paths=("$keychain") path
  while IFS= read -r path; do
    paths+=("$path")
  done < <(saved_paths)
  security list-keychains -d user -s "${paths[@]}"

  # Interactive mode's exit status says nothing about its commands, so this is the
  # check that they worked.
  security find-identity -v -p codesigning "$keychain" | grep -q '"Developer ID Application' ||
    die "no Developer ID Application identity in the keychain. Check DEVELOPER_ID_CERT_P12_BASE64 and DEVELOPER_ID_CERT_PASSWORD."
}

delete() {
  local status=0
  if [[ -f "$saved" ]]; then
    local paths=() path
    while IFS= read -r path; do
      paths+=("$path")
    done < <(saved_paths)
    security list-keychains -d user -s ${paths[@]+"${paths[@]}"} || status=1
  fi
  if [[ -e "$keychain" ]]; then
    security delete-keychain "$keychain" || status=1
  fi
  if (( status != 0 )); then
    die "couldn't restore the search list or delete $keychain"
  fi
  rm -f "$saved"
}

case "$action" in
  create) create ;;
  delete) delete ;;
  *) die "unknown action '$action'" ;;
esac
