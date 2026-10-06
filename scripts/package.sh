#!/bin/sh
# Builds out/soku.zip for side-loading onto a Roku in developer mode.
set -e
cd "$(dirname "$0")/.."
mkdir -p out
rm -f out/soku.zip
zip -qrD out/soku.zip manifest source components images $( [ -d fonts ] && ls fonts | grep -q . && echo fonts ) -x '*.DS_Store'
echo "Wrote out/soku.zip"
