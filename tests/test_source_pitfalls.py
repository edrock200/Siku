# SPDX-License-Identifier: AGPL-3.0-or-later
"""Static scans for real-device pitfalls that bsc and the simulator accept."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
STRING = re.compile(r'"(?:[^"]|"")*"')


def code_lines(path):
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        code = STRING.sub('""', line).split("'", 1)[0]
        yield n, code


class SourcePitfalls(unittest.TestCase):
    def test_no_indexed_function_result(self):
        """Pitfall 1: `f()[i]` is a syntax error on a Roku (bsc accepts it)."""
        hits = []
        for d in ("components", "source"):
            for p in sorted((ROOT / d).rglob("*.brs")):
                for n, code in code_lines(p):
                    if ")[" in code.replace(" ", ""):
                        hits.append("%s:%d: %s" % (p.relative_to(ROOT), n, code.strip()))
        self.assertEqual(hits, [], "index a variable, not a call result:\n" + "\n".join(hits))


if __name__ == "__main__":
    unittest.main()
