# SPDX-License-Identifier: AGPL-3.0-or-later
"""Skill pitfall 2: render-thread scripts must not create Task-only objects. brs-cli does not
enforce Roku's thread rules (a Roku answers "creating MAIN|TASK-only component failed on RENDER
thread" and the next line crashes). A script counts as render-thread when any component that does
not extend Task (directly or through its ancestors) includes it. Idea from Silo-Server/silo-roku,
AGPL-3.0 (scripts/check-thread-rules.js), whose hardware run stopped on one."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Roku's "BrightScript support" page: Task-only or Task/main-only objects (silo-roku's list), plus
# the ones Siku's skill records from its own device crashes.
TASK_ONLY = {"rourltransfer", "rofilesystem", "rochannelstore", "rodatagramsocket", "rostreamsocket",
             "rosocketaddress", "rofontregistry", "roaudioplayer", "rovideoplayer"}
CREATE = re.compile(r'CreateObject\(\s*"(ro[A-Za-z]+)"', re.I)


def components():
    out = {}
    for xml in (ROOT / "components").rglob("*.xml"):
        text = xml.read_text(encoding="utf-8")
        tag = re.search(r"<component\b[^>]*>", text)
        if not tag:
            continue
        name = re.search(r'\bname="([^"]+)"', tag.group(0))
        parent = re.search(r'\bextends="([^"]+)"', tag.group(0))
        scripts = [ROOT / u.replace("pkg:/", "") for u in re.findall(r'<script\b[^>]*\buri="([^"]+)"', text)]
        out[name.group(1)] = {"parent": parent.group(1) if parent else "", "scripts": scripts}
    return out


class ThreadRules(unittest.TestCase):
    def test_no_task_only_objects_on_render_thread(self):
        comps = components()

        def is_task(name, seen=()):
            if name == "Task":
                return True
            c = comps.get(name)
            if c is None or name in seen:
                return False
            return is_task(c["parent"], seen + (name,))

        def scripts(name, seen=()):
            c = comps.get(name)
            if c is None or name in seen:
                return []
            return c["scripts"] + scripts(c["parent"], seen + (name,))

        render = set()
        for name in comps:
            if not is_task(name):
                render.update(scripts(name))
        hits = []
        for path in sorted(render):
            if not path.exists():
                continue
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("'", 1)[0] if not line.lstrip().startswith("'") else ""
                for obj in CREATE.findall(code):
                    if obj.lower() in TASK_ONLY:
                        hits.append("%s:%d: %s" % (path.relative_to(ROOT), n, line.strip()))
        self.assertEqual(hits, [], "Task-only objects created by render-thread scripts:\n" + "\n".join(hits))


if __name__ == "__main__":
    unittest.main()
