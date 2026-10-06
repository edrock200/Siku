#!/bin/sh
# Uploads out/siku.zip to a Roku in developer mode.
# Usage: ROKU_IP=192.168.1.50 ROKU_PASSWORD=secret npm run deploy
set -e
cd "$(dirname "$0")/.."
: "${ROKU_IP:?Set ROKU_IP to your Roku's IP address}"
: "${ROKU_PASSWORD:?Set ROKU_PASSWORD to your developer password}"
sh scripts/package.sh
curl -sS --fail --digest --user "rokudev:${ROKU_PASSWORD}" \
  -F "mysubmit=Install" -F "archive=@out/siku.zip" \
  "http://${ROKU_IP}/plugin_install" | grep -o '<font color="red">[^<]*' | sed 's/<font color="red">//' || true
echo "Deployed to ${ROKU_IP}"
