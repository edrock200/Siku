' SPDX-License-Identifier: AGPL-3.0-or-later
' Test driver for AudioResume.brs in brs-cli (tests/test_audio_resume.py): runs registry steps
' from an empty record and returns what each read answered.

function AudioResumeIo_run(steps as object) as object
    Registry_delete("audiobookResume")
    out = []
    for each st in steps
        if st.op = "put" then
            AudioResume_put(st.identity, st.id, { position: st.position, total: st.total, base: st.base })
            out.Push(AudioResume_all().Count())
        else if st.op = "clear" then
            AudioResume_clear(st.identity, st.id)
            out.Push(AudioResume_all().Count())
        else if st.op = "position" then
            out.Push(AudioResume_position(st.identity, st.id, st.server))
        end if
    end for
    return out
end function
