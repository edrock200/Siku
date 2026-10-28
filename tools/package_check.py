# SPDX-License-Identifier: AGPL-3.0-or-later
"""Checks the side-loadable channel (out/siku.zip) before it is installed or released.

Usage:  npm run package && python3 tools/package_check.py [out/siku.zip]

What it checks (the idea follows ManavA/silo-roku's tests/test_channel_integrity.py, AGPL-3.0):
  - the manifest: title and version keys, and every channel poster / splash image it names is in
    the zip at the size Roku requires (posters FHD 540x405, HD 290x218, SD 246x140; splash screens
    1920x1080, 1280x720, 720x480);
  - only channel files: manifest, source/, components/, images/, fonts/ (no .env, keys, keystores,
    editor or OS litter);
  - no private-key blocks, Discord webhook URLs or hard-coded token values in any text file;
  - BrightScript and XML under source/ and components/: no LAN or loopback URLs (except the
    allowlisted ones below, each with its reason), no Silo v1 API or /health route, and every
    file carries the SPDX-License-Identifier: AGPL-3.0-or-later header;
  - BrightScript under source/ and components/: no function result indexed directly (`f()[i]`),
    a syntax error on a Roku that BrighterScript accepts (roku-brightscript skill, pitfall 1).
Exits non-zero and lists every problem when a check fails.
"""
import os
import re
import struct
import sys
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SPDX = "SPDX-License-Identifier: AGPL-3.0-or-later"
SIZES = {
    "mm_icon_focus_fhd": (540, 405), "mm_icon_focus_hd": (290, 218), "mm_icon_focus_sd": (246, 140),
    "splash_screen_fhd": (1920, 1080), "splash_screen_hd": (1280, 720), "splash_screen_sd": (720, 480),
}
REQUIRED_KEYS = ["title", "major_version", "minor_version", "build_version"]
TOP_LEVEL = {"manifest", "source", "components", "images", "fonts"}
TEXT_EXT = (".brs", ".xml", ".json", ".txt", ".md", ".csv", ".bs", "manifest")
SECRET_NAMES = re.compile(r"(^|/)(\.env(\..*)?|\.npmrc|\.netrc|id_(rsa|dsa|ecdsa|ed25519)(\.pub)?|.*\.(pem|key|p12|pfx|jks|keystore|crt|der))$", re.I)
LITTER = re.compile(r"(^|/)(\.DS_Store|Thumbs\.db|\.git(/|$)|node_modules/|__pycache__/|.*~$|.*\.swp$)")
PRIVATE_KEY = re.compile(r"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----")
WEBHOOK = re.compile(r"discord(?:app)?\.com/api/webhooks/\d+/[\w-]+", re.I)
# A literal token value (`token=abc123...`, `Bearer eyJ...`); building one from a variable
# (`"token=" + s.accessToken`) is fine.
TOKEN_VALUE = re.compile(r"(?:[?&\"']token=[A-Za-z0-9._~+/-]{6,}|Bearer [A-Za-z0-9._~+/-]{16,})")
LAN_URL = re.compile(r"https?://(?:127\.\d+\.\d+\.\d+|localhost|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|"
                     r"172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+|169\.254\.\d+\.\d+|0\.0\.0\.0|\[::1?\])", re.I)
V1 = re.compile(r"/api/v1\b|[\"'/]health\b")
# A call's result indexed directly: `f()[i]` / `f(x) [i]` (pitfall 1).
CALL_INDEX = re.compile(r"\)\s*\[")
STRING_LITERAL = re.compile(r'"(?:[^"]|"")*"')


def brs_code(line):
    """The code part of a BrightScript line: string literals blanked, the ' comment dropped."""
    code = STRING_LITERAL.sub('""', line)
    cut = code.find("'")
    if cut >= 0:
        code = code[:cut]
    if re.match(r"\s*rem\b", code, re.I):
        return ""
    return code
# (file, text on the line) -> reason. Keep this list short and explained.
LAN_ALLOW = {
    ("components/tasks/YouTubeLaunchTask.brs", "http://127.0.0.1:8060/launch/"):
        "ECP on the Roku itself (port 8060) to hand a trailer to the YouTube channel",
    ("components/MainScene.brs", 's.serverUrl = "http://127.0.0.1:" + port'):
        "debugSession=mock deep link: the simulator's mock server",
}


def image_size(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i < len(data) - 9:
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return (w, h)
            seg = struct.unpack(">H", data[i + 2:i + 4])[0]
            i += 2 + seg
    return None


def check(zip_path):
    problems = []
    if not os.path.isfile(zip_path):
        return ["%s does not exist (run npm run package)" % zip_path]
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if not n.endswith("/")]
        files = {n: z.read(n) for n in names}

    if "manifest" not in files:
        problems.append("manifest is missing from the zip root")
    if "source/main.brs" not in files:
        problems.append("source/main.brs is missing")

    manifest = {}
    for line in files.get("manifest", b"").decode("utf-8", "replace").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            manifest[k.strip()] = v.strip()
    for k in REQUIRED_KEYS:
        if not manifest.get(k):
            problems.append("manifest: %s is missing" % k)
    for key, want in SIZES.items():
        ref = manifest.get(key)
        if not ref:
            problems.append("manifest: %s is missing" % key)
            continue
        path = ref.replace("pkg:/", "", 1)
        if path not in files:
            problems.append("manifest: %s points at %s, which is not in the zip" % (key, ref))
            continue
        got = image_size(files[path])
        if got != want:
            problems.append("%s (%s) is %s, Roku wants %dx%d" % (path, key, "x".join(map(str, got)) if got else "unreadable", *want))

    for n, data in files.items():
        top = n.split("/", 1)[0]
        if top not in TOP_LEVEL:
            problems.append("unexpected file in the package: %s" % n)
        if SECRET_NAMES.search(n):
            problems.append("secret-looking file in the package: %s" % n)
        if LITTER.search(n):
            problems.append("stray file in the package: %s" % n)
        if not (n.endswith(TEXT_EXT) or n == "manifest"):
            if PRIVATE_KEY.search(data.decode("latin-1")):
                problems.append("%s contains a private key block" % n)
            continue
        text = data.decode("utf-8", "replace")
        if PRIVATE_KEY.search(text):
            problems.append("%s contains a private key block" % n)
        if WEBHOOK.search(text):
            problems.append("%s contains a Discord webhook URL" % n)
        for i, line in enumerate(text.splitlines(), 1):
            if TOKEN_VALUE.search(line):
                problems.append("%s:%d has a literal token value" % (n, i))
        if not (n.startswith(("source/", "components/")) and n.endswith((".brs", ".xml"))):
            continue
        head = "\n".join(text.splitlines()[:60])
        if SPDX not in head:
            problems.append("%s has no '%s' header" % (n, SPDX))
        for i, line in enumerate(text.splitlines(), 1):
            if LAN_URL.search(line) and not any(n == f and frag in line for (f, frag) in LAN_ALLOW):
                problems.append("%s:%d has a LAN/loopback URL: %s" % (n, i, line.strip()[:100]))
            if V1.search(line):
                problems.append("%s:%d names the v1 API or /health: %s" % (n, i, line.strip()[:100]))
            if n.endswith(".brs") and CALL_INDEX.search(brs_code(line)):
                problems.append("%s:%d indexes a function result directly (a Roku syntax error; assign it first): %s" % (n, i, line.strip()[:100]))
    return problems


def main():
    zip_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "out", "siku.zip")
    problems = check(zip_path)
    for p in problems:
        print("FAIL " + p)
    print("package check: %s, %d problem(s)" % (os.path.relpath(zip_path), len(problems)))
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
