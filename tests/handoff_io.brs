' SPDX-License-Identifier: AGPL-3.0-or-later
' Test driver for HandoffAddress.brs in brs-cli (tests/test_handoff_address.py): plans an offer the
' way RemoteControl.resolveHandoffAddress does, answers each probe from `answers` (url ->
' {state, id}; an address missing from it never answers), and judges as the probes would land.

function HandoffIo_choose(offer as object, own as dynamic, remembered as dynamic, answers as object, final as boolean) as object
    plan = HandoffAddr_plan(offer, own, remembered)
    probed = []
    for each c in plan.candidates
        probed.Push(c.url)
    end for
    if plan.expected = "" then return { url: plan.offered, kind: "phone", failure: "", done: true, probed: probed }
    got = []
    for each c in plan.candidates
        a = invalid
        for each k in answers
            if k = c.url then a = answers[k]
        end for
        got.Push(a)
    end for
    r = HandoffAddr_judge(plan.candidates, got, plan.offered, plan.expected, final)
    return { url: r.url, kind: r.kind, failure: r.failure, done: r.done, probed: probed }
end function
