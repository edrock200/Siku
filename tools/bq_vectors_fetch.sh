#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Downloads the buffering-quality conformance vectors (Silo's contract file
# docs/design/schemas/buffering-quality/v1/vectors.json) at a pinned silo-server commit and checks
# them against a recorded SHA-256, so CI and the release workflow test the same cases and a change
# on silo-server's main branch cannot change or break a build without a commit here.
#
#   tools/bq_vectors_fetch.sh <output path>
#   python3 tools/bq_vectors.py --vectors <output path>
#
# To move to newer vectors: set BQ_VECTORS_COMMIT to a silo-server commit, put the file's
# `sha256sum` in BQ_VECTORS_SHA256, and run tools/bq_vectors.py against it before committing.
set -euo pipefail

BQ_VECTORS_COMMIT=0b579aa6192d49d7e8e0921dde5e955ac29ce302  # silo-server, 2026-11-11
BQ_VECTORS_SHA256=d7377eff095212770fd702f81d6376ba747955bdeeb2fed714f79d9663a629b2

out="${1:?usage: tools/bq_vectors_fetch.sh <output path>}"
curl -fsSL --retry 3 -o "$out" \
  "https://raw.githubusercontent.com/Silo-Server/silo-server/${BQ_VECTORS_COMMIT}/docs/design/schemas/buffering-quality/v1/vectors.json"
echo "${BQ_VECTORS_SHA256}  ${out}" | sha256sum -c --quiet - || {
  echo "::error::bq vectors at silo-server ${BQ_VECTORS_COMMIT} do not match the recorded SHA-256" >&2
  exit 1
}
echo "bq vectors: silo-server ${BQ_VECTORS_COMMIT}"
