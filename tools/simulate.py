"""Runs the channel headlessly in brs-cli (github.com/lvcabral/brs-engine) and takes snapshots.

Usage:
  python3 tools/simulate.py --steps "wait:3,snap:start,down,ok,wait:2,snap:after" [--brs-cli PATH]

Steps (comma separated):
  wait:N        sleep N seconds
  snap:NAME     save the screen to out/sim/NAME.png
  up/down/left/right/ok/back/play/rev/fwd/options/home   press a remote key
  text:abc      type characters (for keyboards)
Writes the app console log to out/sim/console.log.
The package it runs is built with bs_const DEBUG=true (its own copy of the manifest), so the debug*
deep-link parameters (--deep-link "debugSession=mock,...") work; release packages (npm run package)
keep DEBUG=false and ignore them. --release-flags runs with the manifest's DEBUG=false instead.
Requires: npm i brs-node (provides brs-cli). Remote mapping per brs-engine docs/remote-control.md.
"""
import argparse
import os
import pty
import select
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "out", "sim")

KEYS = {
    # Terminal sequences mapped by brs-cli to Roku remote keys.
    "up": "\x1b[A", "down": "\x1b[B", "right": "\x1b[C", "left": "\x1b[D",
    "ok": "\r", "back": "\x1b[3~", "home": "\x1bOQ", "play": "\x1b[F",
    "rev": "\x1b[5~", "fwd": "\x1b[6~", "options": "\x1b[2~", "replay": "\x7f",
}


def debug_manifest(text, debug=True):
    """The manifest with bs_const DEBUG set to `debug` (other constants kept, the line added if missing)."""
    value = "true" if debug else "false"
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("bs_const="):
            consts = [c for c in line[len("bs_const="):].split(";") if c.strip()]
            consts = [c for c in consts if c.split("=")[0].strip().upper() != "DEBUG"]
            lines[i] = "bs_const=" + ";".join(consts + ["DEBUG=" + value])
            break
    else:
        lines.append("bs_const=DEBUG=" + value)
    return "\n".join(lines) + "\n"


def main():
    global OUT
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", required=True)
    ap.add_argument("--brs-cli", default=shutil.which("brs-cli") or "brs-cli")
    ap.add_argument("--out", default=OUT, help="snapshot/log folder (use your own when running in parallel)")
    ap.add_argument("--deep-link", default="", help="e.g. debugScreen=SettingsScreen")
    ap.add_argument("--release-flags", action="store_true",
                    help="keep the manifest's bs_const (DEBUG=false): run what a release build does, debug* links ignored")
    args = ap.parse_args()
    OUT = os.path.abspath(args.out)
    # The child chdirs into OUT before exec, so a relative --brs-cli path would no longer resolve.
    if os.path.exists(args.brs_cli):
        args.brs_cli = os.path.abspath(args.brs_cli)
    os.makedirs(OUT, exist_ok=True)
    log = open(os.path.join(OUT, "console.log"), "wb")
    zip_path = os.path.join(OUT, "siku.zip")

    if os.path.exists(zip_path):
        os.remove(zip_path)
    subprocess.run(["sh", "-c", "cd '%s' && zip -qrD '%s' source components images locale fonts -x '*.DS_Store'" % (ROOT, zip_path)], check=True)
    # The simulator's copy of the manifest compiles the developer aids in (bs_const DEBUG=true: the
    # debug* deep-link parameters in MainScene.handleDeepLink). The release package
    # (npm run package) keeps the manifest's DEBUG=false; tools/package_check.py insists on it.
    staged = os.path.join(OUT, "manifest")
    with open(os.path.join(ROOT, "manifest"), encoding="utf-8") as f:
        text = debug_manifest(f.read(), not args.release_flags)
    with open(staged, "w", encoding="utf-8") as f:
        f.write(text)
    subprocess.run(["zip", "-qjD", zip_path, staged], check=True)
    args.app = zip_path
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(OUT)
        cmd = [args.brs_cli, args.app, "-s", "-c", "0", "-y"]
        if args.deep_link:
            cmd += ["-k", args.deep_link]
        os.execvp(args.brs_cli, cmd)

    def pump(seconds):
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    return False
                log.write(data)
                log.flush()
        return True

    pump(1.5)
    for step in [s.strip() for s in args.steps.split(",") if s.strip()]:
        if step.startswith("wait:"):
            pump(float(step[5:]))
        elif step.startswith("snap:"):
            name = step[5:]
            # brs-cli saves every snapshot as <zip name>.png; on a busy host it can take several
            # seconds, and one that landed late used to fail every later snap (same file name).
            # Compare modification times and wait up to 8 s.
            before = {f: os.path.getmtime(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".png")}
            os.write(fd, b"\x13")  # Ctrl+S
            new = []
            for _ in range(16):
                pump(0.5)
                new = [f for f in os.listdir(OUT) if f.endswith(".png")
                       and before.get(f) != os.path.getmtime(os.path.join(OUT, f))]
                if new:
                    pump(0.5)  # let the file finish writing
                    break
            if new:
                os.replace(os.path.join(OUT, new[0]), os.path.join(OUT, name + ".png"))
                print("snapshot", name)
            else:
                print("snapshot failed", name)
        elif step.startswith("text:"):
            for ch in step[5:]:
                os.write(fd, ch.encode())
                pump(0.15)
        elif step in KEYS:
            os.write(fd, KEYS[step].encode())
            pump(0.6)
        else:
            print("unknown step", step)
    os.write(fd, b"\x03")
    pump(0.5)
    try:
        os.kill(pid, 9)
    except OSError:
        pass
    log.close()


if __name__ == "__main__":
    main()
