# SPDX-License-Identifier: AGPL-3.0-or-later
"""tools/package_check.py finds what it is meant to find (on a synthetic zip)."""
import os
import struct
import sys
import tempfile
import unittest
import zipfile
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import package_check  # noqa: E402

HDR = "' " + package_check.SPDX + "\n"


def png(w, h):
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    chunk = b"IHDR" + ihdr
    return (b"\x89PNG\r\n\x1a\n" + struct.pack(">I", len(ihdr)) + chunk
            + struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF))


MANIFEST = "\n".join([
    "title=Siku", "major_version=0", "minor_version=1", "build_version=1",
    "mm_icon_focus_fhd=pkg:/images/p_fhd.png", "mm_icon_focus_hd=pkg:/images/p_hd.png",
    "mm_icon_focus_sd=pkg:/images/p_sd.png", "splash_screen_fhd=pkg:/images/s_fhd.png",
    "splash_screen_hd=pkg:/images/s_hd.png", "splash_screen_sd=pkg:/images/s_sd.png"]) + "\n"


def good_files():
    return {
        "manifest": MANIFEST,
        "source/main.brs": HDR + "sub Main()\nend sub\n",
        "components/A.brs": HDR + 'x = "http://silo.example/api/v2/x"\n',
        "components/A.xml": '<?xml version="1.0"?>\n<!-- ' + package_check.SPDX + ' -->\n<component name="A" />\n',
        "images/p_fhd.png": png(540, 405), "images/p_hd.png": png(290, 218), "images/p_sd.png": png(246, 140),
        "images/s_fhd.png": png(1920, 1080), "images/s_hd.png": png(1280, 720), "images/s_sd.png": png(720, 480),
    }


def build(files):
    fd, path = tempfile.mkstemp(suffix=".zip")
    os.close(fd)
    with zipfile.ZipFile(path, "w") as z:
        for n, data in files.items():
            z.writestr(n, data)
    return path


class PackageCheck(unittest.TestCase):
    def problems(self, **changes):
        files = good_files()
        for k, v in changes.items():
            k = k.replace("__", "/").replace("_DOT_", ".")
            if v is None:
                files.pop(k, None)
            else:
                files[k] = v
        path = build(files)
        try:
            return package_check.check(path)
        finally:
            os.remove(path)

    def assertFinds(self, needle, problems):
        self.assertTrue(any(needle in p for p in problems), "%r not in %r" % (needle, problems))

    def test_clean(self):
        self.assertEqual(self.problems(), [])

    def test_findings(self):
        self.assertFinds("p_hd.png", self.problems(images__p_hd_DOT_png=png(336, 210)))
        self.assertFinds("splash_screen_sd is missing",
                         self.problems(manifest=MANIFEST.replace("splash_screen_sd=pkg:/images/s_sd.png\n", "")))
        self.assertFinds("secret-looking", self.problems(**{"components/_DOT_env": "A=1"}))
        self.assertFinds("unexpected file", self.problems(**{"out/x.txt": "x"}))
        self.assertFinds("private key", self.problems(**{"components/k.brs": HDR + "' -----BEGIN RSA PRIVATE KEY-----\n"}))
        self.assertFinds("webhook", self.problems(**{"components/w.brs": HDR + "' https://discord.com/api/webhooks/123/abc-DEF\n"}))
        self.assertFinds("literal token", self.problems(**{"components/t.brs": HDR + 'u = "x?token=abcdef123456"\n'}))
        self.assertEqual(self.problems(**{"components/t.brs": HDR + 'u = u + "&token=" + s.accessToken\n'}), [])
        self.assertFinds("LAN/loopback", self.problems(**{"components/l.brs": HDR + 'u = "http://192.168.1.20:8097"\n'}))
        self.assertFinds("LAN/loopback", self.problems(**{"components/l.brs": HDR + 'u = "http://localhost:8097"\n'}))
        self.assertFinds("v1 API", self.problems(**{"components/v.brs": HDR + 'Api_get("/api/v1/items")\n'}))
        self.assertFinds("v1 API", self.problems(**{"components/v.brs": HDR + 'p = "/health"\n'}))
        self.assertFinds("header", self.problems(**{"components/n.brs": "sub x()\nend sub\n"}))


if __name__ == "__main__":
    unittest.main()
