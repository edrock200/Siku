' SPDX-License-Identifier: AGPL-3.0-or-later
' Auto description translation of a series page's shown season (Silo Android TV
' TvItemDetailViewModel.translateShownSeasonEpisodes + DescriptionTranslationController, and #822's
' isEpisodeDescriptionTranslating). With the profile's metadata AI on-view mode `auto`
' (GET /api/v2/capabilities/metadata-ai), a series page whose shown season lists episodes still
' reporting `pending_translation_language` starts that season's job once per (season, language):
' POST /api/v2/catalog/items/{season content_id}/translate-description, then re-reads the season's
' episodes on a bounded backoff until none reports a pending language. There is no job-status route
' for this flow. While the job runs, an episode that still reports a pending language shows
' "Translating description…"; once its text arrives, the "Translated by AI" mark. Pure functions,
' host-tested in tests/test_episode_translation.py. Needs Utils.brs.

' The capability's on-view mode: "auto" | "button" | "off" (anything unknown, or a capability that is
' not available, reads as off).
function EpTr_onView(data as dynamic) as string
    if Type(data) <> "roAssociativeArray" then return "off"
    if Str_orEmpty(data.state) <> "available" then return "off"
    v = LCase(Str_orEmpty(data.on_view))
    if v = "auto" or v = "button" then return v
    return "off"
end function

' The first non-blank pending language among episode rows (pendingEpisodeTranslationLanguage), "" for none.
function EpTr_pendingLanguage(episodes as dynamic) as string
    for each ep in Arr_or(episodes)
        if Type(ep) = "roAssociativeArray" then
            v = Str_orEmpty(ep.pending_translation_language).Trim()
            if v <> "" then return v
        end if
    end for
    return ""
end function

' isEpisodeDescriptionTranslating: the shown season's job runs and the episode still reports a
' pending language. A job for another season, or an episode whose text already arrived, shows nothing.
function EpTr_isTranslating(pendingLanguage as dynamic, shownSeasonId as dynamic, translatingId as dynamic) as boolean
    if Str_orEmpty(pendingLanguage).Trim() = "" then return false
    t = Str_orEmpty(translatingId)
    return t <> "" and t = Str_orEmpty(shownSeasonId)
end function

' What an episode card shows under its caption: "translating" ("Translating description…"),
' "translated" (the "Translated by AI" glyph) or "" (nothing). The progress hides the mark.
function EpTr_label(translating as boolean, machineTranslated as boolean, hasSynopsis as boolean) as string
    if translating then return "translating"
    if machineTranslated and hasSynopsis then return "translated"
    return ""
end function

' The 202 receipt starts work only when it names this item and is not a reused failed or cancelled
' job (the server reuses a failed job for fifteen minutes).
function EpTr_jobAccepted(data as dynamic, contentId as string) as boolean
    if Type(data) <> "roAssociativeArray" then return false
    st = LCase(Str_orEmpty(data.status))
    if st = "failed" or st = "canceled" or st = "cancelled" then return false
    if Str_orEmpty(data.content_id) <> "" and Str_orEmpty(data.content_id) <> contentId then return false
    return true
end function

' Seconds before each re-read (Apple's opening backoff held at 5 s, about 50 s in all).
function EpTr_backoff() as object
    return [1, 2, 3, 4, 5, 5, 5, 5, 5, 5, 5]
end function

' Copies a re-read episode's description fields onto the row shown (withTranslatedDescription), so
' progress and other personal state stay as they are.
function EpTr_merge(shown as object, fresh as dynamic) as object
    out = AA_copy(shown)
    if Type(fresh) <> "roAssociativeArray" then return out
    out["overview"] = fresh.overview
    out["machine_translated_fields"] = fresh.machine_translated_fields
    out["pending_translation_language"] = fresh.pending_translation_language
    return out
end function
