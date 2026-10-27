#!/bin/bash

# Description:
#   Offers a file for download on one of the Grav sites on prod25, through the
#   secure-download plugin: every recipient gets a personal link, and opening it
#   mails a one-time code to that recipient's address, so a forwarded link is useless.
#
#   The file goes from this machine TO prod25 (never the other way round), lands
#   outside the webroot in /var/www/html/<site>/downloads, and its sha256 is checked
#   after the transfer. For every recipient a Thunderbird compose window opens with
#   that recipient's link; you check and send the mail yourself. One mail to all
#   recipients is deliberately not offered: they would see each other's links.
#
#   ./grav-download.sh add meliton.nl jaarstukken-2025.pdf klant@voorbeeld.nl boekhouder@voorbeeld.nl
#   ./grav-download.sh share meliton.nl 953615ed660b1978 collega@voorbeeld.nl
#   ./grav-download.sh links meliton.nl
#   ./grav-download.sh revoke meliton.nl cd0e1d04
#
#   See Deploy-Grav.md (www_meliton/trunk/deploy) for the plugin and the server side.

# Version, bumped on every change (see README.md).
#   1.0  first version
VERSION="1.0"

HOST="prod25.digitect.nl"
SITES="meliton.nl digitect.nl digitecttest.nl"

usage() {
  echo "Usage: $0 add    SITE FILE EMAIL... [-d DAYS] [-m MAX] [-n NAME] [-l nl|en] [-f FROM]"
  echo "       $0 share  SITE FILE_ID EMAIL... [-d DAYS] [-m MAX] [-l nl|en] [-f FROM]"
  echo "       $0 links  SITE"
  echo "       $0 revoke SITE LINK_ID"
  echo "       $0 purge  SITE"
  echo
  echo "  SITE     one of: $SITES"
  echo "  -d DAYS  days the links stay valid (default: the plugin setting, 14)"
  echo "  -m MAX   downloads per recipient (default: the plugin setting, 3)"
  echo "  -n NAME  file name the recipient sees (default: the local file name)"
  echo "  -l LANG  language of the mail text: nl (default) or en"
  echo "  -f FROM  Thunderbird identity to send from (default: the default identity)"
  echo "  -h       this help;  -V  version"
  exit 1
}

die() { echo "ERROR: $*" >&2; exit 1; }

# Runs the plugin CLI on prod25 as www-data. The arguments are quoted for the remote shell.
plugin() {
  local site=$1; shift
  local args="" a
  for a in "$@"; do args+=" $(printf '%q' "$a")"; done
  ssh "$HOST" "cd /var/www/html/$site/htdocs && sudo -n -u www-data php bin/plugin secure-download$args"
}

# Escapes text for use in the HTML mail.
html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' <<<"$1"; }

# Opens a compose window for one recipient. Arguments: site email url expiry filename
compose() {
  local site=$1 email=$2 url=$3 expiry=$4 html subject
  local name; name=$(html_escape "$5")
  html=$(mktemp --suffix=.html)
  if [ "$LANG_MAIL" = en ]; then
    subject="Download: $(tr -d "\047," <<<"$5")"
    cat > "$html" <<EOT
<html><body style="font-family: Arial, sans-serif; font-size: 12pt;">
<p>Dear Sir or Madam,</p>
<p>You can download the file <b>$name</b> via the personal link below. When you open the link, we first send a code to this email address ($email); you enter that code on the page.</p>
<p><a href="$url">$url</a></p>
<p>The link is valid until $expiry and only works for you. Please do not forward it; if a colleague also needs the file, let us know and we will send them their own link.</p>
<p>Kind regards,</p>
</body></html>
EOT
  else
    subject="Download: $(tr -d "\047," <<<"$5")"
    cat > "$html" <<EOT
<html><body style="font-family: Arial, sans-serif; font-size: 12pt;">
<p>Geachte heer, mevrouw,</p>
<p>Via de persoonlijke link hieronder kunt u het bestand <b>$name</b> downloaden. Als u de link opent, sturen we eerst een code naar dit e-mailadres ($email); die vult u op de pagina in.</p>
<p><a href="$url">$url</a></p>
<p>De link is geldig tot en met $expiry en werkt alleen voor u. Stuur hem dus niet door; heeft een collega het bestand ook nodig, laat het ons weten, dan krijgt die een eigen link.</p>
<p>Met vriendelijke groet,</p>
</body></html>
EOT
  fi
  local spec="to='$email',subject='$subject',message='$html',format=html"
  [ -n "$FROM" ] && spec="from='$FROM',$spec"
  thunderbird -compose "$spec" >/dev/null 2>&1 &
  echo "  compose window opened for $email"
  # Thunderbird reads the file after starting; remove it once that has surely happened.
  ( sleep 60; rm -f "$html" ) &
}

# Turns the LINK lines of the plugin output into compose windows. Argument: site, name
handle_links() {
  local site=$1 name=$2 line
  while read -r kind id email expiry url; do
    [ "$kind" = LINK ] || continue
    echo "LINK $id $email valid until $expiry"
    compose "$site" "$email" "$url" "$expiry" "$name"
  done
}

[ "$1" = "-V" ] && { echo "$VERSION"; exit 0; }
[ $# -lt 2 ] && usage
CMD=$1; SITE=$2; shift 2
[[ " $SITES " == *" $SITE "* ]] || die "unknown site '$SITE' (choose from: $SITES)"

DAYS=""; MAX=""; NAME=""; LANG_MAIL="nl"; FROM=""; POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -d) DAYS=$2; shift 2 ;;
    -m) MAX=$2; shift 2 ;;
    -n) NAME=$2; shift 2 ;;
    -l) LANG_MAIL=$2; shift 2 ;;
    -f) FROM=$2; shift 2 ;;
    -h) usage ;;
    -*) die "unknown option $1" ;;
    *) POS+=("$1"); shift ;;
  esac
done
[[ "$LANG_MAIL" == nl || "$LANG_MAIL" == en ]] || die "-l must be nl or en"

OPTS=()
[ -n "$DAYS" ] && OPTS+=(--dagen "$DAYS")
[ -n "$MAX" ] && OPTS+=(--max "$MAX")

case "$CMD" in
  add)
    [ ${#POS[@]} -ge 2 ] || usage
    FILE=${POS[0]}; EMAILS=("${POS[@]:1}")
    [ -f "$FILE" ] || die "file not found: $FILE"
    NAME=${NAME:-$(basename "$FILE")}
    for e in "${EMAILS[@]}"; do [[ "$e" == *@*.* ]] || die "not an email address: $e"; done

    echo "Computing sha256 of $FILE ..."
    SHA=$(sha256sum "$FILE" | cut -d' ' -f1)
    # A random prefix keeps two uploads with the same name apart in incoming/.
    REMOTE="$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')-$(basename "$FILE" | tr -c 'A-Za-z0-9._-' '_')"
    INCOMING="/var/www/html/$SITE/downloads/incoming"

    # incoming/ must belong to www-data, otherwise the plugin cannot move the file away.
    ssh "$HOST" "sudo -n -u www-data mkdir -p -m 700 $INCOMING" || die "cannot prepare $INCOMING"
    echo "Sending to $HOST ..."
    rsync --partial --progress --rsync-path="sudo -n rsync" --chown=www-data:www-data --chmod=F600 \
      "$FILE" "$HOST:$INCOMING/$REMOTE" || die "transfer failed"

    E_ARGS=(); for e in "${EMAILS[@]}"; do E_ARGS+=(-e "$e"); done
    OUT=$(plugin "$SITE" add "$REMOTE" "${E_ARGS[@]}" "${OPTS[@]}" --naam "$NAME" --sha256 "$SHA") \
      || { echo "$OUT"; die "the plugin refused the file (see above)"; }
    echo "$OUT" | grep '^BESTAND' | awk '{print "FILE " $2 " (" $3 " bytes, sha256 ok)"}'
    echo "$OUT" | handle_links "$SITE" "$NAME"
    ;;
  share)
    [ ${#POS[@]} -ge 2 ] || usage
    FILE_ID=${POS[0]}; EMAILS=("${POS[@]:1}")
    NAME=${NAME:-$(plugin "$SITE" links | awk -v id="$FILE_ID" '$1 == id {sub(/^[^ ]+  /, ""); sub(/  \(.*$/, ""); print; exit}')}
    [ -n "$NAME" ] || die "unknown file id: $FILE_ID"
    E_ARGS=(); for e in "${EMAILS[@]}"; do E_ARGS+=(-e "$e"); done
    OUT=$(plugin "$SITE" share "$FILE_ID" "${E_ARGS[@]}" "${OPTS[@]}") || { echo "$OUT"; die "share failed"; }
    echo "$OUT" | handle_links "$SITE" "$NAME"
    ;;
  links)  plugin "$SITE" links ;;
  revoke) [ ${#POS[@]} -eq 1 ] || usage; plugin "$SITE" revoke "${POS[0]}" ;;
  purge)  plugin "$SITE" purge ;;
  *) usage ;;
esac
