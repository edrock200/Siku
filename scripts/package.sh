#!/bin/sh
# Builds out/siku.zip for side-loading onto a Roku in developer mode.
# SIKU_DEBUG=1 (npm run package:dev) packages a development build: the manifest gets
# bs_const=DEBUG=true, which turns on the debug deep links (debugSession, debugScreen, ...).
# Release builds keep DEBUG=false and ignore them.
set -e
cd "$(dirname "$0")/.."
mkdir -p out
rm -f out/siku.zip
if [ "${SIKU_DEBUG:-0}" = "1" ]; then
  zip -qrD out/siku.zip source components images $( [ -d fonts ] && ls fonts | grep -q . && echo fonts ) -x '*.DS_Store'
  rm -rf out/manifest-dev && mkdir -p out/manifest-dev
  sed 's/^bs_const=DEBUG=false$/bs_const=DEBUG=true/' manifest > out/manifest-dev/manifest
  grep -q '^bs_const=DEBUG=true$' out/manifest-dev/manifest || { echo "manifest has no bs_const=DEBUG=false line" >&2; exit 1; }
  zip -qj out/siku.zip out/manifest-dev/manifest
  echo "Wrote out/siku.zip (development build, debug deep links on)"
else
  zip -qrD out/siku.zip manifest source components images $( [ -d fonts ] && ls fonts | grep -q . && echo fonts ) -x '*.DS_Store'
  echo "Wrote out/siku.zip"
fi
