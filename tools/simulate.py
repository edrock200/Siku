"""Runs the channel headlessly in brs-cli (github.com/lvcabral/brs-engine) and takes snapshots.

Usage:
  python3 tools/simulate.py --steps "wait:3,snap:start,down,ok,wait:2,snap:after" [--brs-cli PATH]

Steps (comma separated):
  wait:N        sleep N seconds
  snap:NAME     save the screen to out/sim/NAME.png
  up/down/left/right/ok/back/play/rev/fwd/options/home   press a remote key
  text:abc      type characters (for keyboards)
Writes the app console log to out/sim/console.log.
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


def main():
    global OUT
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", required=True)
    ap.add_argument("--brs-cli", default=shutil.which("brs-cli") or "brs-cli")
    ap.add_argument("--out", default=OUT, help="snapshot/log folder (use your own when running in parallel)")
    ap.add_argument("--deep-link", default="", help="e.g. debugScreen=SettingsScreen")
    args = ap.parse_args()
    OUT = os.path.abspath(args.out)
    os.makedirs(OUT, exist_ok=True)
    log = open(os.path.join(OUT, "console.log"), "wb")
    zip_path = os.path.join(OUT, "siku.zip")

    subprocess.run(["sh", "-c", "cd '%s' && zip -qrD '%s' manifest source components images fonts -x '*.DS_Store'" % (ROOT, zip_path)], check=True)
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
            before = set(os.listdir(OUT))
            os.write(fd, b"\x13")  # Ctrl+S
            pump(1.5)
            new = [f for f in set(os.listdir(OUT)) - before if f.endswith(".png")]
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
