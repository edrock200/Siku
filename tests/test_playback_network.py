# SPDX-License-Identifier: AGPL-3.0-or-later
"""Playback over a flaky network: which Roku Video errors are a dropped connection (reconnect the
same route) and which go to the failure_recovery ladder, the reconnect back-off, the "finished"
that must be ignored, the durable stop's retry rules, playlist compaction and the origin check that
keeps the account token on the user's own server. Error strings are the ones Silo-Server/silo-roku
recorded on a Roku TV (docs/hardware-evidence.md, runs 2, 8, 14 and 15)."""
import unittest

from brs import check_cases, glob

REC = ["components/player/PlaybackRecovery.brs", "components/player/PlaybackErrors.brs",
       "components/player/PlaybackCaps.brs", "components/common/Settings.brs", "components/common/Utils.brs",
       "components/common/Content.brs"]
JOBS = ["components/common/PlaybackJobs.brs", "components/common/Utils.brs"]
SESSION = ["components/common/Session.brs", "components/common/Utils.brs"]


class ErrorKind(unittest.TestCase):
    def test_cases(self):
        k = "Recovery_errorKind"
        check_cases(self, REC, [
            ("-5 all bitrates last_err:961 (reset segments)", k,
             [-5, "", "buffer:loop:demux:Errors seen on all bitrates:last_err:961", None], "network"),
            ("-3 zero length playlist", k, [-3, "", "reader pick stream error:bad:mpr zero length playlist", None], "network"),
            ("-3 transfer error from the peer", k,
             [-3, "", "Transfer error: Failure when receiving data from the peer", None], "network"),
            ("-3 server returned nothing", k, [-3, "", "Server returned nothing (no headers, no data)", None], "network"),
            ("-1 is a network error", k, [-1, "", "", None], "network"),
            ("-2 timeout", k, ["-2", "", "", None], "network"),
            ("-5 refused segment with a 401 is http", k,
             [-5, "", "buffer:loop:demux:Errors seen on all bitrates:last_err:401:", None], "http"),
            ("-1 with a 502 after the url is a server error", k,
             [-1, "", "reader pick stream error:HTTP error:Transfer error: HTTP response code said error response code:(<url>):502:", None], "server"),
            ("http response code said error without a status", k,
             [-3, "", "Transfer error: HTTP response code said error", None], "http"),
            ("errorInfo http category with errcode", k, [-1, "", "", {"category": "http", "errcode": 404}], "http"),
            ("errorInfo network category", k, [-3, "", "", {"category": "network", "dbgmsg": ""}], "network"),
            ("dbgmsg carries the transport text", k,
             [-5, "", "", {"category": "mediaerror", "dbgmsg": "connection reset by peer"}], "network"),
            ("a decoder error stays media", k, [-5, "", "decoder:video:unsupported profile", None], "media"),
            ("playlist too large is not a dropped connection", k,
             [-3, "", "reader pick stream error:bad:mpr playlist file is too large.", None], "media"),
            ("no code, no text", k, [None, "", "", None], "media"),
        ])

    def test_too_large(self):
        t = "Recovery_playlistTooLarge"
        check_cases(self, REC, [
            ("Roku's refusal", t, ["", "reader pick stream error:bad:mpr playlist file is too large.", None], True),
            ("in errorInfo", t, ["", "", {"dbgmsg": "mpr playlist file is too large"}], True),
            ("another error", t, ["", "mpr zero length playlist", None], False),
        ])


class Reconnect(unittest.TestCase):
    def test_delays(self):
        d = "Recovery_reconnectDelay"
        check_cases(self, REC, [("try %d" % n, d, [n], v) for n, v in
                                [(1, 0), (2, 1), (3, 2), (4, 4), (5, 8), (6, 15), (7, 15), (12, 15)]])

    def test_debug_spec(self):
        s = "Recovery_debugSpec"
        check_cases(self, REC, [
            ("a code", s, ["-5"], {"code": -5, "text": "debugVideoError", "limit": 0}),
            ("net", s, ["net"], lambda v: v["code"] == -5 and "last_err:961" in v["text"] and v["limit"] == 0),
            ("net:3", s, ["net:3"], lambda v: v["code"] == -5 and v["limit"] == 3),
            ("drop", s, ["drop"], lambda v: v["code"] == -3 and "zero length playlist" in v["text"]),
            ("large", s, ["LARGE"], lambda v: "too large" in v["text"]),
            ("off", s, [""], None),
            ("garbage", s, ["abc"], None),
        ])

    def test_allowed(self):
        a = "Recovery_reconnectAllowed"

        def rec(**kw):
            r = {"outageSpent": False, "attemptPlayed": False, "outageAt": -1.0}
            r.update(kw)
            return {"m": {"rec": r}}
        check_cases(self, REC, [
            ("a dropped connection", a, ["network"], True, rec()),
            ("not after an outage ran out", a, ["network"], False, rec(outageSpent=True)),
            ("a 5xx before the first frame goes to the ladder", a, ["server"], False, rec()),
            ("a 5xx once the attempt played", a, ["server"], True, rec(attemptPlayed=True)),
            ("a 5xx during an outage", a, ["server"], True, rec(outageAt=3.0)),
            ("an http refusal never", a, ["http"], False, rec(attemptPlayed=True)),
        ])


class Finished(unittest.TestCase):
    def test_refusal(self):
        f = "Recovery_finishedRefusal"

        def ctx(replanPending=False, reanchorBusy=False, **kw):
            r = {"errorSeen": False, "inFlight": False, "waiting": False, "outageAt": -1.0, "everPlayed": True}
            r.update(kw)
            return {"m": {"rec": r, "replanPending": replanPending, "reanchorBusy": reanchorBusy}}
        check_cases(self, REC, [
            ("the end of a plan that played", f, [], "", ctx()),
            ("right after an error", f, [], "after_error", ctx(errorSeen=True)),
            ("a recovery replan in flight", f, [], "replanning", ctx(inFlight=True)),
            ("a viewer's replan in flight", f, [], "replanning", ctx(replanPending=True)),
            ("a reconnect scheduled", f, [], "reconnecting", ctx(waiting=True)),
            ("an outage being reconnected", f, [], "reconnecting", ctx(outageAt=12.0)),
            ("a seek re-anchor in flight", f, [], "reanchoring", ctx(reanchorBusy=True)),
            ("content that never played", f, [], "never_played", ctx(everPlayed=False)),
        ])


class StopJobs(unittest.TestCase):
    def test_rules(self):
        check_cases(self, JOBS, [
            ("no answer is retried", "PlaybackJobs_retriable", [0], True),
            ("503 is retried", "PlaybackJobs_retriable", [503], True),
            ("429 is retried", "PlaybackJobs_retriable", [429], True),
            ("200 is done", "PlaybackJobs_retriable", [200], False),
            ("404 is done (the session is gone)", "PlaybackJobs_retriable", [404], False),
            ("401 is not retried", "PlaybackJobs_retriable", [401], False),
            ("a string status", "PlaybackJobs_retriable", ["502"], True),
        ] + [("delay after try %d" % n, "PlaybackJobs_retryDelay", [n], v) for n, v in
             [(1, 2), (2, 4), (3, 8), (4, 16), (5, 30), (7, 30)]] + [
            ("identity", "PlaybackJobs_identity", [{"serverUrl": "http://a:1", "profileId": "p1"}], "http://a:1|p1"),
            ("no session", "PlaybackJobs_identity", [None], ""),
            ("eight tries at most", "PlaybackJobs_maxTries", [], 8),
            ("204 landed", "PlaybackJobs_isLanded", [204], True),
            ("a string 200 landed", "PlaybackJobs_isLanded", ["200"], True),
            ("404 did not land (pages need no re-read)", "PlaybackJobs_isLanded", [404], False),
            ("no answer did not land", "PlaybackJobs_isLanded", [0], False),
        ])


class SameOrigin(unittest.TestCase):
    def test_cases(self):
        o = "Url_sameOrigin"
        check_cases(self, SESSION, [
            ("same origin", o, ["http://silo.lan:8097/api/v2/stream/x.m3u8?st=1", "http://silo.lan:8097"], True),
            ("case and default port", o, ["HTTPS://Silo.Example.com:443/a", "https://silo.example.com"], True),
            ("http default port", o, ["http://silo.lan/a", "http://silo.lan:80"], True),
            ("a proxy node", o, ["https://proxy-1.example.net/media/x.m3u8", "https://silo.example.com"], False),
            ("another port", o, ["http://silo.lan:9000/a", "http://silo.lan:8097"], False),
            ("http vs https", o, ["http://silo.example.com/a", "https://silo.example.com"], False),
            ("lookalike host", o, ["https://silo.example.com.evil.net/a", "https://silo.example.com"], False),
            ("userinfo trick", o, ["https://silo.example.com@evil.net/a", "https://silo.example.com"], False),
            ("query only", o, ["http://silo.lan:8097?x=1", "http://silo.lan:8097"], True),
            ("ipv6", o, ["http://[fe80::1]:8097/a", "http://[fe80::1]:8097"], True),
            ("ipv6 default port", o, ["http://[fe80::1]/a", "http://[fe80::1]:80"], True),
            ("relative never", o, ["/api/v2/stream", "http://silo.lan"], False),
            ("no origin", o, ["http://silo.lan/a", ""], False),
        ])


class Compaction(unittest.TestCase):
    def test_hls_features(self):
        f = "PlaybackCaps_hlsFeatures"

        def server(features, deliveries=None):
            g = glob()
            g["playbackCaps"] = {"features": features, "deliveries": deliveries or []}
            return {"global": g}
        check_cases(self, REC, [
            ("advertised", f, [], ["hls", "hls_variable_substitution_v1"], server(["hls_variable_substitution_v1"])),
            ("not advertised", f, [], ["hls"], server(["hls_copy_mpegts_v1"])),
            ("with the TS copy", f, [], ["hls", "hls_copy_mpegts_v1", "hls_variable_substitution_v1"],
             server(["hls_copy_mpegts_v1", "hls_variable_substitution_v1"], ["server_remux_hls"])),
        ])


if __name__ == "__main__":
    unittest.main()


class EarlyEnd(unittest.TestCase):
    """A "finished" well short of the file's end (adapted from silo-roku f5078a0, tvOS's
    isBeforeNaturalEnd): more than 8 s and 1.5% short of source.duration_seconds; the first one at a
    point reconnects there, a second within 10 s of it is the end."""

    def test_rule(self):
        e = "Recovery_endedEarly"
        a = "Recovery_earlyEndAction"
        check_cases(self, REC, [
            ("half way through a film is early", e, [3000, 6000], True),
            ("the credits' last seconds are the end", e, [5995, 6000], False),
            ("9 s short of a short clip is not 1.5% short", e, [591, 600], False),
            ("10 s short of a 20-minute episode is under 1.5%: the end", e, [1190, 1200], False),
            ("19 s short of a 20-minute episode is early", e, [1181, 1200], True),
            ("8 s short is the end", e, [1192, 1200], False),
            ("no duration: the end", e, [100, 0], False),
            ("a string duration is read", e, [100, "3600"], True),
            ("no position: the end", e, [None, 3600], False),
            ("the first early end resumes", a, [1500, -1], "resume"),
            ("another point resumes again", a, [2500, 1500], "resume"),
            ("the same point again is the end", a, [1504, 1500], "end"),
        ])


RIO = REC + ["tests/recovery_io.brs"]


def ticks(start, seconds, step=1):
    """Watchdog readings of steady playback from start for seconds."""
    return [["tick", start + i * step, start + (i + 1) * step] for i in range(seconds)]


class RetryWindow(unittest.TestCase):
    """Reconnect windows renew after sustained playback (Silo Android #993, a port of
    DirectPlayRetryWindowTest): a plan that plays again holds the outage until 20 s of playback;
    a drop before that continues it (start and tries kept, so it still runs out after 2 minutes),
    a drop after it opens a fresh window."""

    def test_progress_gain(self):
        g = "Recovery_progressGain"
        check_cases(self, REC, [
            ("a second of playback", g, [100, 101], 1.0),
            ("no movement", g, [100, 100], 0.0),
            ("a jump back", g, [100, 90], 0.0),
            ("a seek forward", g, [100, 400], 0.0),
            ("no earlier reading", g, [-1, 5], 0.0),
            ("strings are read", g, ["100", "102"], 2.0),
        ])

    def test_later_outage_gets_a_fresh_window_after_sustained_playback(self):
        steps = [["drop", 0], ["play", 5]] + ticks(1000, 20) + [["drop", 660], ["drop", 690], ["drop", 779], ["drop", 780]]
        want = ["new:1", "held"] + [""] * 19 + ["renewed", "new:1", "open:2", "open:3", "gave_up"]
        check_cases(self, RIO, [("renewed after 20 s", "RecoveryT_run", [steps], want)])

    def test_a_drop_under_20_s_continues_the_outage(self):
        steps = [["drop", 0], ["drop", 1], ["play", 4]] + ticks(1000, 19) + [["drop", 40]]
        want = ["new:1", "open:2", "held"] + [""] * 19 + ["continued:3"]
        check_cases(self, RIO, [("19 s is not enough", "RecoveryT_run", [steps], want)])

    def test_frequent_cuts_exhaust_the_window_even_when_they_play(self):
        steps, want = [], []
        for i in range(8):
            steps += [["drop", i * 15], ["play", i * 15 + 2]] + ticks(i * 100, 5)
            want += ["new:1" if i == 0 else "continued:%d" % (i + 1), "held"] + [""] * 5
        steps.append(["drop", 120])
        want.append("gave_up")
        check_cases(self, RIO, [("cuts every 15 s run out after 2 minutes", "RecoveryT_run", [steps], want)])

    def test_seeks_and_stalls_do_not_count(self):
        steps = [["drop", 0], ["play", 3], ["tick", 100, 600], ["tick", 600, 300], ["tick", 300, 300]] + ticks(300, 19) + [["drop", 60]]
        want = ["new:1", "held", "", "", ""] + [""] * 19 + ["continued:2"]
        check_cases(self, RIO, [("only steady playback renews", "RecoveryT_run", [steps], want)])

    def test_playing_without_an_outage_holds_nothing(self):
        steps = [["play", 0]] + ticks(0, 25) + [["drop", 30]]
        want = [""] + [""] * 25 + ["new:1"]
        check_cases(self, RIO, [("no outage, no hold", "RecoveryT_run", [steps], want)])
