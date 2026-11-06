# SPDX-License-Identifier: AGPL-3.0-or-later
"""tools/mock_server.py: no function assigns a local named like a module-level function it also calls.
Python then treats the name as local in the whole function, and every call fails with UnboundLocalError
(`detail` in route() broke every catalog item read in v0.1.23, v0.1.33 and v0.1.41)."""
import ast
import os
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class MockShadowing(unittest.TestCase):
    def test_no_local_shadows_a_called_module_function(self):
        src = open(os.path.join(ROOT, "tools", "mock_server.py")).read()
        tree = ast.parse(src)
        module_funcs = {n.name for n in tree.body if isinstance(n, ast.FunctionDef)}
        problems = []
        for fn in ast.walk(tree):
            if not isinstance(fn, ast.FunctionDef):
                continue
            stored, called = set(), set()
            for node in ast.walk(fn):
                if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store):
                    stored.add(node.id)
                elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                    called.add(node.func.id)
            for name in sorted(stored & called & module_funcs):
                problems.append("%s() assigns local %r" % (fn.name, name))
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
