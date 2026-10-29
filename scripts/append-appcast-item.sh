#!/bin/bash
# Inserts a new <item> at the top of the Sparkle appcast, preserving the rest of
# the file byte for byte.
#
# The signature and length come from Sparkle's sign_update. Each --delta adds a
# delta update from an earlier build:
#
#   --delta FROM_BUILD,URL,SIGNATURE,LENGTH     (up to three)
#
# Adapted from Front Row's scripts/append-appcast-item.sh (GPLv3).

set -euo pipefail

appcast="" version="" build="" url="" signature="" length="" notes=""
pub_date="" minimum_system_version=""
deltas=()
max_deltas=3

die() {
  echo "append-appcast-item: $1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --appcast) appcast="${2-}"; shift 2 ;;
    --version) version="${2-}"; shift 2 ;;
    --build) build="${2-}"; shift 2 ;;
    --url) url="${2-}"; shift 2 ;;
    --signature) signature="${2-}"; shift 2 ;;
    --length) length="${2-}"; shift 2 ;;
    --notes) notes="${2-}"; shift 2 ;;
    --pub-date) pub_date="${2-}"; shift 2 ;;
    --minimum-system-version) minimum_system_version="${2-}"; shift 2 ;;
    --delta) deltas+=("${2-}"); shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

for required in appcast version build url signature length notes pub_date minimum_system_version; do
  [[ -n "${!required}" ]] || die "--${required//_/-} is required"
done

[[ -f "$appcast" ]] || die "appcast not found: $appcast"
[[ -f "$notes" ]] || die "notes file not found: $notes"

# Every value below is interpolated into XML, and a value like `1" x="2` yields
# well-formed XML with a bogus attribute, so the check downstream would not
# catch it. Two-part versions are accepted so older entries can be amended.
[[ "$build" =~ ^[0-9]+$ ]] || die "build must be a whole number, got '$build'"
[[ "$length" =~ ^[0-9]+$ ]] || die "length must be a whole number, got '$length'"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "version must be X.Y or X.Y.Z, got '$version'"
[[ "$minimum_system_version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] ||
  die "minimum system version must be numeric, got '$minimum_system_version'"
[[ "$signature" =~ ^[A-Za-z0-9+/=]+$ ]] || die "signature must be base64, got '$signature'"

# Anything that could close an attribute or open an element.
markup='["<>&]'

[[ "$url" == https://* ]] || die "url must be an https URL, got '$url'"
[[ ! "$url" =~ $markup ]] || die "url must not contain quotes or markup, got '$url'"
[[ ! "$url" =~ [[:space:]] ]] || die "url must not contain whitespace, got '$url'"
[[ ! "$pub_date" =~ $markup ]] || die "pub date must not contain quotes or markup, got '$pub_date'"

(( ${#deltas[@]} <= max_deltas )) || die "at most $max_deltas deltas are allowed, got ${#deltas[@]}"

# Each delta is FROM_BUILD,URL,SIGNATURE,LENGTH, validated like the full update.
delta_xml=""
seen_from=" "
for delta in ${deltas[@]+"${deltas[@]}"}; do
  IFS=, read -r d_from d_url d_signature d_length d_extra <<<"$delta"
  [[ -z "${d_extra-}" ]] || die "delta must be FROM_BUILD,URL,SIGNATURE,LENGTH, got '$delta'"
  [[ "$d_from" =~ ^[0-9]+$ ]] || die "delta build must be a whole number, got '$d_from'"
  (( d_from < build )) || die "delta build $d_from must be lower than the new build $build"
  [[ "$seen_from" != *" $d_from "* ]] || die "duplicate delta from build $d_from"
  seen_from+="$d_from "
  [[ "$d_url" == https://* ]] || die "delta url must be an https URL, got '$d_url'"
  [[ ! "$d_url" =~ $markup ]] || die "delta url must not contain quotes or markup, got '$d_url'"
  [[ ! "$d_url" =~ [[:space:]] ]] || die "delta url must not contain whitespace, got '$d_url'"
  [[ "$d_signature" =~ ^[A-Za-z0-9+/=]+$ ]] || die "delta signature must be base64, got '$d_signature'"
  [[ "$d_length" =~ ^[0-9]+$ ]] || die "delta length must be a whole number, got '$d_length'"
  delta_xml+="
        <enclosure
          url=\"$d_url\"
          sparkle:deltaFrom=\"$d_from\"
          sparkle:edSignature=\"$d_signature\"
          length=\"$d_length\"
          type=\"application/octet-stream\" />"
done
if [[ -n "$delta_xml" ]]; then
  delta_xml="
      <sparkle:deltas>$delta_xml
      </sparkle:deltas>"
fi

# A CDATA terminator inside the notes would close the section early and corrupt
# the feed.
if grep -qF ']]>' "$notes"; then
  die "notes file contains ']]>', which would terminate the CDATA section: $notes"
fi

# Sparkle picks updates by CFBundleVersion. A build number that does not exceed
# the newest entry is never offered, so refuse rather than publish a dud.
newest="$(grep -o '<sparkle:version>[0-9]*</sparkle:version>' "$appcast" |
  grep -o '[0-9]*' | sort -n | tail -1)"
if [[ -n "$newest" ]] && (( build <= newest )); then
  die "build $build does not exceed the newest entry in the appcast ($newest)"
fi

notes_body="$(cat "$notes")"

item="$(
  cat <<XML

    <item>
      <title>New Version Available</title>
      <link>https://github.com/itsjoshpark/Clair</link>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version ($build)</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum_system_version</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/itsjoshpark/Clair/releases/tag/v$version</sparkle:fullReleaseNotesLink>
      <pubDate>$pub_date</pubDate>
      <enclosure
        url="$url"
        sparkle:edSignature="$signature"
        length="$length"
        type="application/octet-stream" />$delta_xml
      <description><![CDATA[
$notes_body
      ]]>
      </description>
    </item>
XML
)"

grep -q '</language>' "$appcast" || die "no <language> element to anchor insertion: $appcast"

# Write to a temp file and move into place, so a failure never leaves a
# half-written feed.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

ITEM="$item" awk '
  { print }
  !inserted && /<\/language>/ { print ENVIRON["ITEM"]; inserted = 1 }
' "$appcast" >"$tmp"

python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])" "$tmp" ||
  die "the resulting appcast is not well-formed XML; leaving $appcast unchanged"

mv "$tmp" "$appcast"
trap - EXIT

echo "Added $version ($build) to $appcast"
