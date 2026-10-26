# SPDX-License-Identifier: AGPL-3.0-or-later
"""Runs the seek-preview cases (tools/trickplay_test/run_tests.brs) against
components/player/Trickplay.brs in brs-cli, without the simulator.

Usage:
  python3 tools/trickplay_test.py [--brs-cli PATH]
Exits non-zero when a case fails.
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
    ap.add_argument("--brs-cli", default=os.path.join(ROOT, "node_modules", ".bin", "brs-cli"))
    args = ap.parse_args()
    work = tempfile.mkdtemp(prefix="trickplay-test-")
    try:
        names = []
        for src in (os.path.join(ROOT, "tools", "trickplay_test", "run_tests.brs"),
                    os.path.join(ROOT, "components", "player", "Trickplay.brs"),
                    os.path.join(ROOT, "components", "common", "Utils.brs")):
            shutil.copy(src, work)
            names.append(os.path.basename(src))
        out = subprocess.run([os.path.abspath(args.brs_cli), "-n", "-c", "0", "-r", "."] + names,
                             cwd=work, capture_output=True, text=True, timeout=300)
        text = out.stdout + out.stderr
        print("\n".join(line for line in text.splitlines() if "TRICKPLAY-TESTS" in line or "got " in line or "rror" in line))
        ok = "TRICKPLAY-TESTS RESULT" in text and "TRICKPLAY-TESTS FAIL" not in text
        sys.exit(0 if ok else 1)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
