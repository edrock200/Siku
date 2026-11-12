# SPDX-License-Identifier: AGPL-3.0-or-later
"""Several accounts per server (components/common/Accounts.brs, Silo Android #795; adapted from
Silo-Server/silo-roku, AGPL-3.0, docs/spec.md 7.5): the layout-1 migration (pure and against the
registry), which account a save belongs to (server user id match), the list after a save (stash,
expiry, budget), Change Account's groups and the session an account restores."""
import json
import unittest

from brs import check_cases

FILES = ["components/common/Accounts.brs", "components/common/Session.brs", "components/common/Utils.brs"]
A = "https://a.example"
B = "http://b.local:8090"
NOW = 1800000000


def lower(v):
    """brs-cli keeps dot-assigned keys lower-case; compare case-insensitively."""
    if isinstance(v, dict):
        return {k.lower(): lower(x) for k, x in v.items()}
    if isinstance(v, list):
        return [lower(x) for x in v]
    return v


def session(url=A, token="acc-1", uid="u1", name="laura", account="", profile="p1"):
    return {"serverUrl": url, "serverOrigin": url, "serverName": "", "serverId": "", "accessToken": token,
            "refreshToken": "ref-" + token if token else "", "expiresAt": NOW + 3600,
            "user": {"id": uid, "username": name} if uid else {}, "profileId": profile, "profileToken": "",
            "profileName": "Laura", "profileAvatar": "", "deviceId": "dev", "accountId": account}


def entry(aid, url=A, uid="u1", name="laura", used=100, added=100, token=None, expired=False):
    e = {"id": aid, "url": url, "userid": uid, "username": name, "profiles": -1, "added": added, "used": used, "expired": expired}
    if token:
        e["session"] = {"accessToken": token, "refreshToken": "ref-" + token, "expiresAt": NOW, "user": {"id": uid, "username": name},
                        "profileId": "", "profileToken": "", "profileName": "", "profileAvatar": "", "serverOrigin": url}
    return e


def find(v, aid):
    for e in lower(v):
        if e["id"] == aid:
            return e
    return None


class Migration(unittest.TestCase):
    def test_layout1(self):
        servers = [{"url": A, "name": "Home", "id": "srv-a"},
                   {"url": B, "name": "Den", "id": "srv-b", "session": {"accessToken": "acc-b", "refreshToken": "ref-b", "expiresAt": 5,
                                                                       "user": {"id": "u7", "username": "sam"}, "profileId": "p-sam"}},
                   {"url": "https://c.example", "name": "Old", "id": ""}]
        f = "Accounts_migrateLayout"
        ids = ["id-1", "id-2", "id-3", "id-4"]
        active = session(account="")
        active.pop("accountId")
        check_cases(self, FILES, [
            ("the active session becomes an account", f, [servers, active, ids, NOW],
             lambda v: lower(v)["session"]["accountid"] == "id-1" and lower(v)["session"]["accesstoken"] == "acc-1"
             and find(v["accounts"], "id-1")["userid"] == "u1" and find(v["accounts"], "id-1")["url"] == A
             and "session" not in find(v["accounts"], "id-1")),
            ("a saved server's sign-in becomes an account with its tokens", f, [servers, active, ids, NOW],
             lambda v: find(v["accounts"], "id-2")["session"]["accesstoken"] == "acc-b" and find(v["accounts"], "id-2")["userid"] == "u7"
             and find(v["accounts"], "id-2")["username"] == "sam" and find(v["accounts"], "id-2")["used"] < NOW
             and find(v["accounts"], "id-2")["session"]["profileid"] == "p-sam"),
            ("servers lose their stored sign-ins, keep the rest", f, [servers, active, ids, NOW],
             lambda v: [e["url"] for e in v["servers"]] == [A, B, "https://c.example"] and all("session" not in e for e in v["servers"])
             and v["servers"][1]["name"] == "Den" and v["count"] == 2),
            ("a signed-out active session opens no account", f, [servers, session(token=""), ids, NOW],
             lambda v: lower(v)["session"]["accountid"] == "" and v["count"] == 1 and find(v["accounts"], "id-1")["url"] == B),
            ("no session at all", f, [servers, None, ids, NOW], lambda v: v["session"] is None and v["count"] == 1),
        ])

    def test_registry(self):
        """The whole migration in brs-cli's in-memory registry: written, read back, then the old slots go."""
        legacy = {"session": dict(session(), accountId=None), "servers": [
            {"url": A, "name": "Home", "id": "srv-a"},
            {"url": B, "name": "Den", "id": "srv-b", "session": {"accessToken": "acc-b", "refreshToken": "ref-b", "user": {"id": "u7"}}}]}
        legacy["session"].pop("accountId")
        check_cases(self, ["tests/accounts_io.brs"] + FILES, [
            ("layout 1 -> 2", "AccountsIo_migrate", [legacy], lambda v: v["line"].startswith("[siku-accounts] migration layout=1->2 accounts=2")
             and v["layout"] == 2 and len(v["accounts"]) == 2 and all("session" not in e for e in v["servers"])
             and lower(v["session"])["accountid"] != "" and lower(v["session"])["accesstoken"] == "acc-1"
             and any(lower(e).get("session", {}).get("accesstoken") == "acc-b" for e in v["accounts"])),
            ("layout 2 is left alone", "AccountsIo_migrateTwice", [legacy], lambda v: v["second"] == "" and len(v["accounts"]) == 2),
            ("a new Roku", "AccountsIo_migrate", [{}], lambda v: v["line"] == "" and v["layout"] == 2),
        ])


class Resolve(unittest.TestCase):
    def test_resolve(self):
        f = "Accounts_resolveId"
        lst = [entry("a1", uid="u1"), entry("a2", uid="u2", name="sam"), entry("b1", url=B, uid="u1")]
        check_cases(self, FILES, [
            ("a refresh keeps its account", f, [lst, session(account="a1")], "a1"),
            ("a profile pick keeps its account", f, [lst, session(account="a2", uid="u2")], "a2"),
            ("a new sign-in finds the same server user", f, [lst, session(account="", uid="u2")], "a2"),
            ("an unknown user is a new account", f, [lst, session(account="", uid="u9")], ""),
            ("no user id never adopts one", f, [lst, session(account="", uid="")], ""),
            ("the same user on another server is another account", f, [lst, session(url="https://c.example", uid="u1")], ""),
            ("same user id, its own server", f, [lst, session(url=B, account="", uid="u1")], "b1"),
            ("an id from another server is not kept", f, [lst, session(url=B, account="a1", uid="u9")], ""),
            ("signed out with another server's id", f, [lst, session(url=B, account="a1", token="")], ""),
            ("signed out, its own expired account", f, [lst, session(account="a2", token="", uid="u2")], "a2"),
            ("no server", f, [lst, session(url="")], ""),
        ])


class Next(unittest.TestCase):
    def test_switch_and_expiry(self):
        f = "Accounts_next"
        lst = [entry("a1", used=50), entry("a2", uid="u2", name="sam", used=40, token="acc-sam")]
        sam = session(account="a2", uid="u2", name="sam", token="acc-sam")
        check_cases(self, FILES, [
            ("switching stashes the old account's sign-in", f, [lst, session(account="a1"), sam, NOW, False],
             lambda v: find(v, "a1")["session"]["accesstoken"] == "acc-1" and find(v, "a1")["session"]["profileid"] == "p1"
             and "session" not in find(v, "a2") and find(v, "a2")["used"] == NOW),
            ("the first write keeps the arriving account's copy", f, [lst, session(account="a1"), sam, NOW, True],
             lambda v: find(v, "a1")["session"]["accesstoken"] == "acc-1" and find(v, "a2")["session"]["accesstoken"] == "acc-sam"),
            ("a refresh changes nothing but the time", f, [lst, session(account="a1"), session(account="a1", token="acc-2"), NOW, False],
             lambda v: "session" not in find(v, "a1") and find(v, "a2")["session"]["accesstoken"] == "acc-sam"),
            ("an expired account stays, needing to sign in again", f, [lst, session(account="a1"), session(account="a1", token=""), NOW, False],
             lambda v: find(v, "a1")["expired"] is True and "session" not in find(v, "a1")),
            ("a signed-out account never comes back", f, [[entry("a2", uid="u2", token="acc-sam")], session(account="a1"),
                                                          session(account="", token=""), NOW, False],
             lambda v: find(v, "a1") is None and len(v) == 1),
            ("a new account is recorded with its server user", f, [lst, session(account="a1"), session(account="a3", uid="u3", name="max"), NOW, False],
             lambda v: find(v, "a3")["userid"] == "u3" and find(v, "a3")["username"] == "max" and find(v, "a3")["added"] == NOW
             and find(v, "a1")["session"]["accesstoken"] == "acc-1"),
            ("a phone's borrowed profile is never stashed", f, [lst, dict(session(account="a1"), temporary=True), sam, NOW, False],
             lambda v: "session" not in find(v, "a1")),
            ("signing in again clears Sign in again", f, [[entry("a1", expired=True)], session(account="a1", token=""), session(account="a1"), NOW, False],
             lambda v: find(v, "a1")["expired"] is False),
        ])

    def test_budget(self):
        big = "x" * 1500
        lst = [entry("old%d" % i, url=B, uid="u%d" % i, used=10 + i, token=big + str(i)) for i in range(9)]
        f = "Accounts_next"
        many = [entry("m%d" % i, uid="u%d" % i, used=i) for i in range(15)]
        check_cases(self, FILES, [
            ("least recently used accounts lose their sign-in first", f, [lst, None, session(account="a1"), NOW, False],
             lambda v: len(json.dumps(v)) <= 9200 and find(v, "a1") is not None and "session" not in find(v, "old0")
             and find(v, "old0")["expired"] is True and "session" in find(v, "old8") and len(v) == 10),
            ("at most twelve, the active one kept", f, [many, None, session(account="m0", uid="u0"), NOW, False],
             lambda v: len(v) == 12 and find(v, "m0") is not None and find(v, "m1") is None),
        ])


class Groups(unittest.TestCase):
    def test_groups(self):
        servers = [{"url": B, "name": "Den"}, {"url": A, "name": "Home"}, {"url": "https://c.example", "name": "Empty"}]
        lst = [entry("a2", uid="u2", added=20), entry("a1", added=10), entry("b1", url=B)]
        f = "Accounts_groups"
        check_cases(self, FILES, [
            ("the active server first, then by last use", f, [servers, lst, A, "a1"],
             lambda v: [g["server"]["url"] for g in v] == [A, B, "https://c.example"]),
            ("accounts in the order added, the open one current", f, [servers, lst, A, "a1"],
             lambda v: [c["account"]["id"] for c in v[0]["accounts"]] == ["a1", "a2"] and v[0]["accounts"][0]["current"] is True
             and v[0]["accounts"][1]["current"] is False and v[2]["accounts"] == []),
            ("nothing current with no account open", f, [servers, lst, A, ""],
             lambda v: not any(c["current"] for g in v for c in g["accounts"])),
            ("profile count", "Accounts_profileLine", [3], "3 profiles"),
            ("one profile", "Accounts_profileLine", [1], "1 profile"),
            ("not read yet", "Accounts_profileLine", [-1], ""),
            ("badge: sign in again wins", "Accounts_badge", [entry("x", expired=True), True], "SIGN IN AGAIN"),
            ("badge: current", "Accounts_badge", [entry("x"), True], "CURRENT"),
            ("badge: none", "Accounts_badge", [entry("x"), False], ""),
        ])

    def test_lookups(self):
        lst = [entry("a1", used=50, token="t1"), entry("a2", uid="u2", used=90, expired=True), entry("a3", uid="u3", used=70, token="t3")]
        check_cases(self, FILES, [
            ("a server opens its latest signed-in account", "Accounts_latestOn", [lst, A, ""], lambda v: v["id"] == "a3"),
            ("else its latest one", "Accounts_latestOn", [[entry("a2", expired=True)], A, ""], lambda v: v["id"] == "a2"),
            ("none", "Accounts_latestOn", [lst, B, ""], None),
            ("another account has a session", "Accounts_anotherSignedIn", [lst, session(account="a1", token="")], True),
            ("only the open one", "Accounts_anotherSignedIn", [[entry("a1", token="t1")], session(account="a1", token="")], False),
            ("same user signing in again replaces its stored session", "Accounts_replacedToken", [lst, session(account="a2", uid="u2"), session(uid="u3", token="new")], "t3"),
            ("the open account's own session", "Accounts_replacedToken", [[], session(account="a1", token="old"), session(token="new")], "old"),
            ("another user replaces nothing", "Accounts_replacedToken", [lst, session(account="a1", token="old"), session(uid="u9", token="new")], ""),
            ("the replaced stored sign-in carries its refresh token (Api_revoke refreshes an expired one)", "Accounts_replacedSignIn",
             [lst, session(account="a2", uid="u2"), session(uid="u3", token="new")],
             lambda v: lower(v) == {"accesstoken": "t3", "refreshtoken": "ref-t3", "expiresat": NOW}),
            ("the open account's own sign-in", "Accounts_replacedSignIn", [[], session(account="a1", token="old"), session(token="new")],
             lambda v: lower(v)["refreshtoken"] == "ref-old" and lower(v)["expiresat"] == NOW + 3600),
            ("a phone's borrowed session is never replaced", "Accounts_replacedSignIn",
             [[], dict(session(account="a1", token="old"), temporary=True), session(token="new")], None),
            ("nothing replaced", "Accounts_replacedSignIn", [lst, session(account="a1", token="old"), session(uid="u9", token="new")], None),
        ])

    def test_saved_servers_only(self):
        """Servers dropped past the 6-server limit by older builds left accounts nobody can see:
        the launch rule counts only accounts on saved servers, and they are forgotten."""
        lst = [entry("a1", token="t1"), entry("a2", url=B, uid="u2", token="t2"), entry("a3", url="https://gone.example", uid="u3", token="t3")]
        servers = [{"url": A, "name": "", "id": ""}, {"url": B, "name": "", "id": ""}]
        check_cases(self, FILES, [
            ("an account on a dropped server is not counted", "Accounts_onSavedServers", [lst, servers, A],
             lambda v: [e["id"] for e in v] == ["a1", "a2"]),
            ("the open session's server counts as saved", "Accounts_onSavedServers", [lst, [], "https://gone.example"],
             lambda v: [e["id"] for e in v] == ["a3"]),
            ("unsaved servers, once each", "Accounts_unsavedServers", [lst + [entry("a4", url="https://gone.example", uid="u4")], servers, ""],
             ["https://gone.example"]),
            ("all saved", "Accounts_unsavedServers", [lst[:2], servers, ""], []),
            ("without the accounts of the given servers", "Accounts_onServersOtherThan", [lst, [B, "https://gone.example"]],
             lambda v: [e["id"] for e in v] == ["a1"]),
        ])

    def test_rotated_tokens(self):
        """A refresh that finished after the session moved on: the account holding the used
        refresh token keeps the rotated pair (AuthTask.saveTokens)."""
        lst = [entry("a1", token="t1"), entry("a2", uid="u2", token="t2")]
        f = "Accounts_withRotatedTokens"
        check_cases(self, FILES, [
            ("the stashed account gets the new pair", f, [lst, "ref-t2", "acc-new", "ref-new", NOW + 7200],
             lambda v: v["found"] and lower(v["list"][1]["session"])["accesstoken"] == "acc-new"
             and lower(v["list"][1]["session"])["refreshtoken"] == "ref-new" and lower(v["list"][1]["session"])["expiresat"] == NOW + 7200
             and lower(v["list"][0]["session"])["accesstoken"] == "t1"),
            ("a refresh answer without a new refresh token keeps the old one", f, [lst, "ref-t2", "acc-new", "", NOW],
             lambda v: lower(v["list"][1]["session"])["refreshtoken"] == "ref-t2"),
            ("a signed-out account is not brought back", f, [lst, "ref-gone", "acc-new", "ref-new", NOW],
             lambda v: not v["found"] and len(v["list"]) == 2),
            ("an empty used token matches nothing", f, [[entry("a9")], "", "acc", "ref", NOW], lambda v: not v["found"]),
        ])


class Restore(unittest.TestCase):
    def test_from_account(self):
        srv = {"url": B, "name": "Den", "id": "srv-b"}
        f = "Session_fromAccount"
        check_cases(self, FILES, [
            ("an account with its sign-in", f, [srv, entry("b1", url=B, token="tb"), "dev", False],
             lambda v: lower(v)["accountid"] == "b1" and lower(v)["accesstoken"] == "tb" and lower(v)["serverurl"] == B),
            ("an expired account keeps who it was", f, [srv, entry("b1", url=B, name="sam", expired=True), "dev", True],
             lambda v: lower(v)["accountid"] == "b1" and lower(v)["accesstoken"] == "" and lower(v)["user"]["username"] == "sam"),
            ("no account: the server alone", f, [srv, None, "dev", True],
             lambda v: lower(v)["accountid"] == "" and lower(v)["accesstoken"] == "" and lower(v)["serverid"] == "srv-b"),
            ("a new sign-in clears the account id", "Session_withTokens", [session(account="a1"), {"access_token": "n", "user": {"id": "u2"}}],
             lambda v: lower(v)["accountid"] == ""),
            ("a refresh keeps it", "Session_withTokens", [session(account="a1"), {"access_token": "n"}], lambda v: lower(v)["accountid"] == "a1"),
            ("another account purges the Home cache", "Session_homeCachePurgeReason", [session(account="a1"), session(account="a2")], "account"),
        ])


class HomeCacheOwner(unittest.TestCase):
    def test_owner(self):
        files = ["components/common/HomeCache.brs", "components/common/Utils.brs"]
        check_cases(self, files, [
            ("keyed by the local account id", "HomeCache_ownerSource", [session(account="a1")], lambda v: json.loads(v)[-1] == "a1"),
            ("two accounts, two caches", "HomeCache_ownerSource", [session(account="a2")], lambda v: json.loads(v)[-1] == "a2"),
        ])


if __name__ == "__main__":
    unittest.main()
