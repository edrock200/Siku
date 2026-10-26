# SPDX-License-Identifier: AGPL-3.0-or-later
"""Runs the seek-preview cases (tools/trickplay_test/run_tests.brs) against
components/player/Trickplay.brs in brs-cli, without the simulator (through tools/brs_test.py).

Usage:
  python3 tools/trickplay_test.py [--brs-cli PATH]
Exits non-zero when a case fails.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brs_test  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--brs-cli", default=brs_test.BRS_CLI)
    args = ap.parse_args()
    brs_test.BRS_CLI = args.brs_cli
    text = brs_test.run_main(["tools/trickplay_test/run_tests.brs", "components/player/Trickplay.brs",
                              "components/common/Utils.brs"])
    print("\n".join(line for line in text.splitlines() if "TRICKPLAY-TESTS" in line or "got " in line or "rror" in line))
    ok = "TRICKPLAY-TESTS RESULT" in text and "TRICKPLAY-TESTS FAIL" not in text
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
