# SPDX-License-Identifier: AGPL-3.0-or-later
"""Replays the buffering-quality conformance vectors against components/player/BufferingQuality.brs.

Usage:
  python3 tools/bq_vectors.py --vectors <path to vectors.json> [--brs-cli PATH]

vectors.json is the server's contract file (silo-server docs/design/schemas/buffering-quality/v1/
vectors.json; Silo Android vendors it as shared/src/commonTest/resources/playback/buffering-quality/
v1/vectors.json). It is not copied into this repository. Exits non-zero when a case fails.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vectors", required=True)
    ap.add_argument("--brs-cli", default=os.path.join(ROOT, "node_modules", ".bin", "brs-cli"))
    args = ap.parse_args()
    work = tempfile.mkdtemp(prefix="bq-vectors-")
    try:
        shutil.copy(args.vectors, os.path.join(work, "vectors.json"))
        # brs-cli takes the scripts by name relative to its pkg: root.
        for src in (os.path.join(ROOT, "tools", "bq_vectors", "run_vectors.brs"),
                    os.path.join(ROOT, "components", "player", "BufferingQuality.brs")):
            shutil.copy(src, work)
        out = subprocess.run([os.path.abspath(args.brs_cli), "-n", "-c", "0", "-r", ".", "run_vectors.brs", "BufferingQuality.brs"],
                             cwd=work, capture_output=True, text=True, timeout=600)
        text = out.stdout + out.stderr
        print("\n".join(line for line in text.splitlines() if "BQ-VECTORS" in line or "ERROR" in line or "rror" in line))
        ok = "BQ-VECTORS RESULT" in text and "BQ-VECTORS FAIL" not in text
        sys.exit(0 if ok else 1)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
