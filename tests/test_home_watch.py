# SPDX-License-Identifier: AGPL-3.0-or-later
"""Home's watch state (HomeWatch.brs; Silo Android #1009, Silo's Roku app c1841ae / #102): the
events socket's URL, protocols and ticket checks, which frames count, what a closed socket means,
the reconnect back-off, transient failures and refresh retries, and the event debounce."""
import json
import unittest

from brs import check_cases

FILES = ["components/common/HomeWatch.brs", "components/common/Utils.brs"]


def ticket(**over):
    body = {"ticket": "T0k-en_1.~", "expires_in": 30, "max_connection_seconds": 300, "protocol": "silo.events.v2"}
    body.update(over)
    return body


def event(change="watched", profile="p1", channel="user_state", name="user_state.changed"):
    return json.dumps({"type": "event", "channel": channel, "event": name, "event_id": "e1",
                       "timestamp": "2026-11-20T10:00:00Z",
                       "data": {"profile_id": profile, "content_id": "movie:x", "series_id": "", "change": change}})


class Socket(unittest.TestCase):
    def test_url_and_protocols(self):
        u = "HomeWatch_socketUrl"
        check_cases(self, FILES, [
            ("https becomes wss", u, ["https://silo.example"], "wss://silo.example/api/v2/events/ws?channels=user_state"),
            ("http keeps a path prefix, drops trailing slashes", u, ["http://h:8097/silo//"], "ws://h:8097/silo/api/v2/events/ws?channels=user_state"),
            ("upper-case scheme", u, ["HTTPS://h"], "wss://h/api/v2/events/ws?channels=user_state"),
            ("not http", u, ["ftp://h"], ""),
            ("no host", u, ["https://"], ""),
            ("missing", u, [None], ""),
            ("protocols in order", "HomeWatch_protocols", ["abc"], "silo.events.v2, silo.ticket.abc"),
        ])

    def test_ticket(self):
        t = "HomeWatch_ticket"
        check_cases(self, FILES, [
            ("a good ticket", t, [ticket()], "T0k-en_1.~"),
            ("another protocol", t, [ticket(protocol="silo.room.v2")], ""),
            ("expires too late", t, [ticket(expires_in=31)], ""),
            ("already expired", t, [ticket(expires_in=0)], ""),
            ("connection too long", t, [ticket(max_connection_seconds=301)], ""),
            ("lifetime as a string", t, [ticket(max_connection_seconds="300")], ""),
            ("not a header token", t, [ticket(ticket="a b")], ""),
            ("comma would split the protocol list", t, [ticket(ticket="a,b")], ""),
            ("empty", t, [ticket(ticket="")], ""),
            ("a number", t, [ticket(ticket=12)], ""),
            ("no body", t, [None], ""),
            ("lifetime", "HomeWatch_lifetime", [ticket(max_connection_seconds=120)], 120),
            ("lifetime fallback", "HomeWatch_lifetime", [{}], 300),
        ])

    def test_ticket_verdict(self):
        v = "HomeWatch_ticketVerdict"
        check_cases(self, FILES, [
            ("older server", v, [404], "unsupported"),
            ("method not allowed", v, [405], "unsupported"),
            ("refused for this profile", v, [403], "unsupported"),
            ("unusable 200", v, [200], "unsupported"),
            ("no answer", v, [0], "retry"),
            ("server error", v, [503], "retry"),
            ("rate limited", v, [429], "retry"),
            ("token refresh did not help", v, [401], "retry"),
        ])


class Frames(unittest.TestCase):
    def test_frame(self):
        f = "HomeWatch_frame"
        check_cases(self, FILES, [
            ("subscribed to user_state", f, ['{"type":"subscribed","channels":["user_state"],"rejected":[]}', "p1"], {"kind": "subscribed", "change": ""}),
            ("user_state rejected", f, ['{"type":"subscribed","channels":[],"rejected":[{"channel":"user_state","code":"not_allowed"}]}', "p1"], {"kind": "rejected", "change": ""}),
            ("subscribed to something else", f, ['{"type":"subscribed","channels":["catalog"]}', "p1"], {"kind": "", "change": ""}),
            ("this profile's change", f, [event("watched"), "p1"], {"kind": "changed", "change": "watched"}),
            ("progress", f, [event("Progress"), "p1"], {"kind": "changed", "change": "progress"}),
            ("another profile", f, [event("watched", "p2"), "p1"], {"kind": "", "change": ""}),
            ("unknown active profile refreshes", f, [event("watched", "p2"), ""], {"kind": "changed", "change": "watched"}),
            ("another channel", f, [event(channel="catalog", name="catalog.item.changed"), "p1"], {"kind": "", "change": ""}),
            ("another event", f, [event(name="account.capabilities_changed"), "p1"], {"kind": "", "change": ""}),
            ("event without data", f, ['{"type":"event","channel":"user_state","event":"user_state.changed"}', "p1"], {"kind": "", "change": ""}),
            ("access changed", f, ['{"type":"access_changed"}', "p1"], {"kind": "access_changed", "change": ""}),
            ("hello", f, ['{"type":"hello","available_channels":["user_state"]}', "p1"], {"kind": "", "change": ""}),
            ("snapshot", f, ['{"type":"snapshot","channel":"user_state","data":null}', "p1"], {"kind": "", "change": ""}),
            ("broken json", f, ['{"type":"event"', "p1"], {"kind": "", "change": ""}),
            ("not text", f, [None, "p1"], {"kind": "", "change": ""}),
        ])


class Lifecycle(unittest.TestCase):
    def test_after_close(self):
        a = "HomeWatch_afterClose"
        check_cases(self, FILES, [
            ("no roWebSocket", a, ["unsupported"], "stop"),
            ("wrong protocol", a, ["protocol"], "stop"),
            ("rejected", a, ["rejected"], "stop"),
            ("hidden", a, ["shutdown"], "stop"),
            ("session changed", a, ["owner"], "stop"),
            ("planned end", a, ["max_age"], "now"),
            ("access changed", a, ["access_changed"], "now"),
            ("dropped", a, ["closed_by_server"], "backoff"),
            ("quiet", a, ["quiet"], "backoff"),
            ("never opened", a, ["timeout"], "backoff"),
            ("no subscription", a, ["no_subscribe"], "backoff"),
            ("error", a, ["error"], "backoff"),
        ])

    def test_backoff(self):
        b = "HomeWatch_nextBackoff"
        check_cases(self, FILES, [
            ("from nothing", b, [0], 1), ("1 -> 2", b, [1], 2), ("8 -> 16", b, [8], 16),
            ("16 -> 30", b, [16], 30), ("capped", b, [30], 30),
        ])


class Refresh(unittest.TestCase):
    def test_transient(self):
        t = "HomeWatch_isTransient"
        check_cases(self, FILES, [
            ("no answer", t, [0], True), ("timeout", t, [408], True), ("rate limited", t, [429], True),
            ("server error", t, [500], True), ("bad gateway", t, [502], True), ("gateway timeout", t, [504], True),
            ("status as a string", t, ["503"], True),
            ("gone", t, [404], False), ("refused", t, [403], False), ("unauthorized", t, [401], False),
            ("validation", t, [422], False),
        ])

    def test_retry_delay(self):
        r = "HomeWatch_retryDelay"
        check_cases(self, FILES, [
            ("first retry", r, [0], 1), ("second", r, [1], 2), ("third", r, [2], 4), ("no fourth", r, [3], -1),
            ("negative", r, [-1], -1),
        ])

    def test_event_delay(self):
        d = "HomeWatch_eventDelay"
        check_cases(self, FILES, [
            ("watched: debounce", d, [False, 500], 2),
            ("progress right after a read", d, [True, 1000], 29),
            ("progress 20 s after a read", d, [True, 20000], 10),
            ("progress long after a read", d, [True, 90000], 2),
            ("progress before any read", d, [True, -1], 2),
            ("poll interval", "HomeWatch_pollSeconds", [], 120),
        ])


if __name__ == "__main__":
    unittest.main()
