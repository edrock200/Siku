#!/bin/sh
# Uploads out/siku.zip to a Roku in developer mode.
# Usage: ROKU_IP=192.168.1.50 npm run deploy        (asks for the developer password, not echoed)
#        ROKU_IP=192.168.1.50 ROKU_PASSWORD=secret npm run deploy
# The installer's answer is saved to out/deploy-response.html (readable by you only) so a compile
# error the Roku reports is kept; it is also printed. The full log is on telnet <roku-ip> 8085.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -e
cd "$(dirname "$0")/.."
: "${ROKU_IP:?Set ROKU_IP to your Roku's IP address or host name}"

# A bare host or IPv4 address only: no scheme, port, path, user or shell characters.
case "$ROKU_IP" in
  *[!A-Za-z0-9.-]* | "" | .* | -*)
    echo "ROKU_IP must be a host name or IP address (got: $ROKU_IP)" >&2
    exit 2 ;;
esac

if [ -z "${ROKU_PASSWORD:-}" ]; then
  if [ ! -t 0 ]; then
    echo "Set ROKU_PASSWORD, or run from a terminal to be asked for it" >&2
    exit 2
  fi
  printf "Developer password for rokudev@%s: " "$ROKU_IP" >&2
  stty -echo
  trap 'stty echo' EXIT INT TERM
  read -r ROKU_PASSWORD
  stty echo
  trap - EXIT INT TERM
  printf "\n" >&2
fi

# Is the developer web installer there at all?
if ! curl -s -o /dev/null --connect-timeout 5 "http://${ROKU_IP}/"; then
  echo "No answer from http://${ROKU_IP}/ - is the Roku on, reachable and in developer mode?" >&2
  exit 3
fi

sh scripts/package.sh
mkdir -p out
RESPONSE=out/deploy-response.html
umask 077
rm -f "$RESPONSE"
# The password goes to curl through a config on stdin, not the command line (visible in ps).
status=$(printf 'user = "rokudev:%s"\n' "$ROKU_PASSWORD" | curl -sS --digest --config - \
  -F "mysubmit=Install" -F "archive=@out/siku.zip" \
  -o "$RESPONSE" -w '%{http_code}' "http://${ROKU_IP}/plugin_install") || status=000
chmod 600 "$RESPONSE" 2>/dev/null || true

if [ "$status" = "401" ]; then
  echo "The Roku refused the password (HTTP 401)." >&2
  exit 4
fi
messages=$(grep -o '<font color="red">[^<]*' "$RESPONSE" 2>/dev/null | sed 's/<font color="red">//' || true)
[ -n "$messages" ] && echo "$messages"
if [ "$status" != "200" ]; then
  echo "Install failed (HTTP $status). The Roku's answer is in $RESPONSE" >&2
  exit 5
fi
if echo "$messages" | grep -qi "fail\|error"; then
  echo "The Roku reported a problem. Its answer is in $RESPONSE; telnet ${ROKU_IP} 8085 shows the compile log." >&2
  exit 6
fi
echo "Deployed to ${ROKU_IP} (installer answer saved in $RESPONSE)"
