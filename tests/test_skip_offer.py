# SPDX-License-Identifier: AGPL-3.0-or-later
"""SkipOffer (adapted from silo-roku 9b1bccc / #108): every skip pill (Skip Intro, Skip Recap, Skip
Credits, the Watch pill after an automatic skip) is a one-press pill with a 10 s timer that counts
only while playing; a press or Back resolves its range; a pill whose timer ran out comes back
without a timer while the controls show; Up Next and the panel hide it with its time held; intro
before recap before credits; automatic skips resolve their ranges and land past all of them."""
import unittest

from brs import check_cases

FILES = ["components/player/SkipOffer.brs", "components/player/MarkerTimeline.brs", "components/common/Utils.brs"]

ASK = {"mode": "ask", "credits": False}
ALWAYS = {"mode": "always", "credits": False}
NEVER = {"mode": "never", "credits": False}
AUTO_CREDITS = {"mode": "ask", "credits": True}


def mk(kind, s, e):
    return {"kind": kind, "start": s, "end": e}


INTRO = [mk("intro", 30, 90)]
RECAP_CREDITS = [mk("recap", 0, 60), mk("credits", 2800, 2990)]


def ev(t, now, controls=False, covered=False, **kw):
    e = {"type": t, "now": now, "controls": controls, "covered": covered}
    e.update(kw)
    return e


def play(now=0, **kw):
    return ev("player", now, state="playing", **kw)


def pos(seconds, now, **kw):
    return ev("position", now, seconds=seconds, **kw)


def view(r):
    return r["view"]


def low(d):
    """brs-cli returns AA keys lower-cased."""
    return {k.lower(): v for k, v in (d or {}).items()}


class SkipOffer(unittest.TestCase):
    def test_cases(self):
        run = "SkipOffer_run"
        check_cases(self, FILES, [
            ("entering an intro while playing offers a timed pill", run,
             [INTRO, ASK, [play(0), pos(31, 0)]],
             lambda r: view(r)["kind"] == "intro" and view(r)["timed"] and view(r)["progress"] == 0
             and any("skip pill offered kind=intro" in x for x in r["log"])),
            ("nothing is offered before playback first plays", run,
             [INTRO, ASK, [pos(31, 0), ev("player", 0, state="buffering")]],
             lambda r: view(r) is None),
            ("the fill grows with playing time", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("tick", 2500)]],
             lambda r: abs(view(r)["progress"] - 0.25) < 0.001),
            ("paused time does not count", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("player", 2000, state="paused"), ev("tick", 60000)]],
             lambda r: abs(view(r)["progress"] - 0.2) < 0.001),
            ("a rebuffer keeps the timer running 1.5 s only", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("player", 1000, state="buffering"), ev("tick", 9000)]],
             lambda r: abs(view(r)["progress"] - 0.25) < 0.001),
            ("10 s of playing time out the pill, the range stays unresolved", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("tick", 10000)]],
             lambda r: view(r) is None and r["resolved"] == {} and len(r["expired"]) == 1
             and any("skip pill timed out kind=intro" in x for x in r["log"])),
            ("it does not come back by itself with the controls hidden", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("tick", 10000), pos(40, 11000)]],
             lambda r: view(r) is None),
            ("with the controls up it comes back without a timer", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("tick", 10000), ev("sync", 11000, controls=True)]],
             lambda r: view(r)["timed"] is False and view(r)["progress"] == 0
             and any("skip pill returned kind=intro" in x for x in r["log"])),
            ("timing out with the controls up leaves the untimed pill", run,
             [INTRO, ASK, [play(0), pos(31, 0, controls=True), ev("tick", 10000, controls=True)]],
             lambda r: view(r)["timed"] is False),
            ("the returned pill goes as the controls hide", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("tick", 10000), ev("sync", 11000, controls=True), ev("sync", 12000)]],
             lambda r: view(r) is None),
            ("OK on the returned pill still skips and resolves", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("tick", 10000), ev("sync", 11000, controls=True),
                           ev("press", 12000, controls=True)]],
             lambda r: r["out"] == [{"type": "seek", "seconds": 90, "auto": False}] and len(r["resolved"]) == 1),
            ("Back does not reach the returned pill", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("tick", 10000), ev("sync", 11000, controls=True),
                           ev("back", 12000, controls=True)]],
             lambda r: r["out"] == [] and view(r)["timed"] is False),
            ("leaving the range and coming back offers a full timer", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("tick", 10000), pos(100, 11000), pos(40, 12000)]],
             lambda r: view(r)["timed"] and view(r)["progress"] == 0 and r["expired"] == {}),
            ("a press seeks to the end and resolves the range", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("press", 1000)]],
             lambda r: r["out"] == [{"type": "seek", "seconds": 90, "auto": False}] and view(r) is None
             and any("resolved kind=intro range=30-90 by=press" in x for x in r["log"])),
            ("a resolved range is never offered again", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("press", 1000), pos(90, 2000), ev("seek", 3000, seconds=35), pos(35, 3500)]],
             lambda r: view(r) is None),
            ("Back on the timed pill resolves it without seeking", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("back", 1000), pos(33, 2000)]],
             lambda r: r["out"] == [{"type": "consumed"}] and view(r) is None and len(r["resolved"]) == 1),
            ("a press at the deadline acts on the pill", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("press", 10050)]],
             lambda r: r["out"] == [{"type": "seek", "seconds": 90, "auto": False}]),
            ("Back at the deadline still resolves", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("back", 10050)]],
             lambda r: r["out"] == [{"type": "consumed"}] and len(r["resolved"]) == 1),
            ("covered: hidden with its time held, back with the time left", run,
             [INTRO, ASK, [play(0), pos(31, 0), ev("sync", 4000, covered=True), ev("tick", 30000, covered=True),
                           ev("sync", 31000)]],
             lambda r: r["views"][3] is None and abs(view(r)["progress"] - 0.4) < 0.001),
            ("no new offer while covered", run,
             [INTRO, ASK, [play(0), pos(31, 0, covered=True)]],
             lambda r: view(r) is None),
            ("Skip Recap and Skip Credits are timed too", run,
             [RECAP_CREDITS, ASK, [play(0), pos(2, 0), ev("tick", 10000), pos(2801, 20000)]],
             lambda r: r["views"][1]["kind"] == "recap" and r["views"][1]["timed"] and r["views"][2] is None
             and view(r)["kind"] == "credits" and view(r)["timed"]),
            ("intro first: the recap waits, then starts its full timer", run,
             [[mk("recap", 0, 120), mk("intro", 30, 90)], ASK,
              [play(0), pos(31, 0), ev("press", 1000), pos(90, 1500)]],
             lambda r: r["views"][1]["kind"] == "intro" and r["views"][2]["kind"] == "recap" and r["views"][2]["progress"] == 0),
            ("with the intro timed out and the controls hidden the recap is offered", run,
             [[mk("recap", 0, 120), mk("intro", 30, 90)], ASK,
              [play(0), pos(31, 0), ev("tick", 10000), pos(32, 10500)]],
             lambda r: view(r)["kind"] == "recap" and view(r)["timed"]),
            ("a returning intro hides the recap with its time held", run,
             [[mk("recap", 0, 120), mk("intro", 30, 90)], ASK,
              [play(0), pos(31, 0), ev("tick", 10000), pos(32, 10500), ev("tick", 13500),
               ev("sync", 14000, controls=True), ev("tick", 20000, controls=True), ev("sync", 21000)]],
             lambda r: r["views"][5]["kind"] == "intro" and r["views"][5]["timed"] is False
             and r["views"][6]["kind"] == "intro" and view(r)["kind"] == "recap" and abs(view(r)["progress"] - 0.4) < 0.001),
            ("the expired record clears when playback moves to another range", run,
             [[mk("intro", 30, 90), mk("credits", 2800, 2990)], ASK,
              [play(0), pos(31, 0), ev("tick", 10000), ev("seek", 11000, seconds=2810), pos(2810, 11500),
               ev("press", 12000), pos(2990, 12500), ev("seek", 13000, seconds=40), pos(40, 13500)]],
             lambda r: r["views"][7]["kind"] == "intro" and r["views"][7]["timed"] and r["views"][7]["progress"] == 0),
            ("always skips the intro, resolves it and offers Watch Intro", run,
             [INTRO, ALWAYS, [play(0), pos(31, 0)]],
             lambda r: r["out"] == [{"type": "seek", "seconds": 90, "auto": True}] and view(r)["watch"]
             and view(r)["kind"] == "intro" and len(r["resolved"]) == 1),
            ("Watch Intro seeks back to the start and the intro plays through", run,
             [INTRO, ALWAYS, [play(0), pos(31, 0), pos(90, 500), ev("press", 1000), pos(30, 1500), pos(45, 16000)]],
             lambda r: r["out"][1] == {"type": "seek", "seconds": 30, "auto": False} and len(r["out"]) == 2
             and view(r) is None),
            ("the Watch pill times out after 10 s", run,
             [INTRO, ALWAYS, [play(0), pos(31, 0), pos(90, 500), ev("tick", 10500)]],
             lambda r: r["views"][2]["watch"] and view(r) is None),
            ("Back hides the Watch pill", run,
             [INTRO, ALWAYS, [play(0), pos(31, 0), ev("back", 1000)]],
             lambda r: r["out"][-1] == {"type": "consumed"} and view(r) is None),
            ("overlapping automatic skips land past every range", run,
             [[mk("recap", 0, 60), mk("intro", 50, 120)], ALWAYS, [play(0), pos(55, 0)]],
             lambda r: r["out"] == [{"type": "seek", "seconds": 120, "auto": True}] and len(r["resolved"]) == 2),
            ("auto-skipped credits are not offered after a seek back", run,
             [RECAP_CREDITS, AUTO_CREDITS, [play(0), pos(2801, 0), pos(2990, 500), ev("back", 600),
                                            ev("seek", 1000, seconds=2850), pos(2850, 1500)]],
             lambda r: view(r) is None and r["out"][0] == {"type": "seek", "seconds": 2990, "auto": True}),
            ("never offers no intro or recap pill", run,
             [[mk("intro", 30, 90), mk("recap", 0, 20)], NEVER, [play(0), pos(5, 0), pos(31, 1000)]],
             lambda r: all(v is None for v in r["views"])),
            ("a stale position after a seek is ignored", run,
             [INTRO, ASK, [play(0), pos(10, 0), ev("seek", 1000, seconds=200), pos(40, 1500), pos(200, 2000)]],
             lambda r: all(v is None for v in r["views"])),
            ("a stale position is believed after 5 s", run,
             [INTRO, ASK, [play(0), pos(10, 0), ev("seek", 1000, seconds=200), pos(40, 6500)]],
             lambda r: view(r)["kind"] == "intro"),
            ("the last second of a range offers nothing", run,
             [INTRO, ASK, [play(0), pos(89.5, 0)]],
             lambda r: view(r) is None),
            ("loose events (missing flags) do not throw", run,
             [INTRO, ASK, [{"type": "player", "state": "playing"}, {"type": "position", "seconds": 31}]],
             lambda r: view(r)["kind"] == "intro"),
        ])


if __name__ == "__main__":
    unittest.main()
