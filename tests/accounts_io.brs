' SPDX-License-Identifier: AGPL-3.0-or-later
' Test driver for Accounts_migrate in brs-cli's in-memory registry (tests/test_accounts.py).

sub AccountsIo_seed(legacy as object)
    for each k in ["session", "servers", "accounts", "layout"]
        Registry_delete(k)
    end for
    if legacy.session <> invalid then Registry_write("session", legacy.session)
    if legacy.servers <> invalid then Registry_write("servers", legacy.servers)
end sub

function AccountsIo_state(line as string) as object
    return { "line": line, "layout": Accounts_layout(), "accounts": Accounts_list(), "servers": Registry_read("servers", []), "session": Registry_read("session") }
end function

function AccountsIo_migrate(legacy as object) as object
    AccountsIo_seed(legacy)
    return AccountsIo_state(Accounts_migrate())
end function

function AccountsIo_migrateTwice(legacy as object) as object
    AccountsIo_seed(legacy)
    Accounts_migrate()
    return { "second": Accounts_migrate(), "accounts": Accounts_list() }
end function
