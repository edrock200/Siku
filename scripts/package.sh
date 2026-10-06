#!/bin/sh
# Builds out/siku.zip for side-loading onto a Roku in developer mode.
set -e
cd "$(dirname "$0")/.."
mkdir -p out
rm -f out/siku.zip
zip -qrD out/siku.zip manifest source components images $( [ -d fonts ] && ls fonts | grep -q . && echo fonts ) -x '*.DS_Store'
echo "Wrote out/siku.zip"
