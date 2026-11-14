# SPDX-License-Identifier: AGPL-3.0-or-later
"""Editions and Version Auto within one (Silo Android #899, a port of DetailVersionSelectorTest and
PlaybackEditionsTest; silo-roku 7bb02a9 follows the same rule): Edition picks the cut, Auto picks
the best first-part file of that cut for the quality preference, the page opens on the last-played
edition (last_edition_key, then last_file_id), else the edition whose Auto file compares best
across cuts, and Play sends the shown file unless it is the last-played Auto file."""
import unittest

from brs import check_cases

FILES = ["components/common/Edition.brs", "tests/edition_io.brs", "components/common/Utils.brs"]


def fv(fid, resolution=None, key=None, raw=None, hdr=False, size=1, kind=None, part=None):
    v = {"file_id": str(fid), "hdr": hdr, "file_size": size}
    if resolution is not None:
        v["resolution"] = resolution
    if key is not None:
        v["edition_key"] = key
    if raw is not None:
        v["edition_raw"] = raw
    if kind is not None:
        v["presentation_kind"] = kind
        v["presentation_part_index"] = part
    return v


# The issue's example: Theatrical in 4K and 1080p, Extended in 1080p only.
T4K = fv(1, "2160p", "theatrical", "Theatrical")
T1080 = fv(2, "1080p", "theatrical", "Theatrical")
E1080 = fv(3, "1080p", "extended", "Extended")
VERSIONS = [E1080, T1080, T4K]


def detail(files=None, variants=None, last_file=None, last_key=None, position=0):
    ud = {"position_seconds": position}
    if last_file is not None:
        ud["last_file_id"] = str(last_file)
    if last_key is not None:
        ud["last_edition_key"] = last_key
    return {"versions": files if files is not None else VERSIONS, "playback_variants": variants or [], "user_data": ud}


def pick(name, want, pinned="", edition=None, quality="2160p", **kw):
    return (name, "EditionT_pick", [detail(**kw), str(pinned) if pinned else "", edition, quality], None if want is None else str(want))


def cut(fid, key, resolution, hdr=False, size=1):
    return fv(fid, resolution, key, key, hdr, size)


class Selection(unittest.TestCase):
    def test_editions_and_history(self):
        unnamed = fv(5, "720p")
        check_cases(self, FILES, [
            pick("nothing played opens on the edition holding the best file", 1),
            pick("a picked edition keeps Auto inside it, even when another cut is better", 3, edition="extended"),
            pick("the last-played edition opens with its best file", 3, last_file=3),
            pick("history picks the cut, the preference picks the file", 1, last_file=2),
            pick("a gone last file: its edition key still names the cut", 3, last_file=99, last_key="extended"),
            pick("the edition key wins over the last file's edition", 1, last_file=3, last_key="theatrical"),
            pick("a key no edition has falls back to the last file", 3, last_file=3, last_key="imax"),
            pick("a present empty key names the unnamed edition", 5, last_file=3, last_key="", files=VERSIONS + [unnamed]),
            pick("a pin wins", 2, pinned=2),
            pick("a pin wins over a picked edition", 2, pinned=2, edition="theatrical"),
            pick("no versions: nothing", None, files=[]),
        ])

    def test_sources(self):
        check_cases(self, FILES, [
            ("best", "EditionT_source", [detail(), "", None, "auto"], "best"),
            ("picked", "EditionT_source", [detail(), "", "extended", "auto"], "picked"),
            ("last edition", "EditionT_source", [detail(last_file=2, last_key="extended"), "", None, "auto"], "last_edition"),
            ("last file", "EditionT_source", [detail(last_file=3), "", None, "auto"], "last_file"),
            ("pinned", "EditionT_source", [detail(), "2", None, "auto"], "pinned"),
        ])

    def test_auto_ranking(self):
        sdr_big = fv(1, "1080p", size=9000)
        hdr_small = fv(2, "1080p", hdr=True, size=1000)
        sdr_small = fv(3, "1080p", size=1000)
        unknown = fv(1, None, size=9000)
        above = fv(2, "2160p")
        t720 = fv(4, "720p", "theatrical", "Theatrical")
        check_cases(self, FILES, [
            pick("HDR breaks a resolution tie", 2, files=[sdr_big, sdr_small, hdr_small]),
            pick("then the larger file", 1, files=[sdr_small, sdr_big]),
            pick("then list order", 3, files=[sdr_small, fv(1, "1080p", size=1000)]),
            pick("an unknown resolution is a last resort (capped)", 2, files=[unknown, above], quality="1080p"),
            pick("an unknown resolution is a last resort (auto)", 2, files=[unknown, above], quality="auto"),
            pick("a resolution the server does not rank is unknown", 1, files=[unknown, fv(3, "1440p")], quality="1080p"),
            pick("no file at the preference: the closest above", 4, edition="theatrical", quality="480p", files=VERSIONS + [t720]),
            pick("the preference caps Auto", 2, edition="theatrical", quality="720p"),
            pick("a preference naming no resolution reads as Auto", 1, edition="theatrical", quality="high"),
            pick("an older compound preference keeps its resolution", 2, edition="theatrical", quality="1080p-high"),
        ])

    def test_opening_edition(self):
        check_cases(self, FILES, [
            pick("a cut within the cap beats one only above it", 2, quality="1080p", files=[cut(1, "imax", "2160p"), cut(2, "extended", "720p")]),
            pick("above the cap, the closer cut wins", 2, quality="480p", files=[cut(1, "imax", "2160p"), cut(2, "extended", "720p")]),
            pick("same resolution: HDR first", 2, files=[cut(1, "theatrical", "1080p"), cut(2, "directors_cut", "1080p", hdr=True)]),
            pick("then theatrical over another cut, never file size", 2, files=[cut(1, "directors_cut", "1080p", size=9000), cut(2, "theatrical", "1080p")]),
            pick("the unnamed edition before theatrical", 2, files=[cut(1, "theatrical", "1080p"), fv(2, "1080p")]),
            pick("a standard edition before theatrical", 2, files=[cut(1, "theatrical", "1080p"), cut(2, "standard edition", "1080p")]),
            pick("a full tie keeps server order", 1, files=[cut(1, "extended", "1080p"), cut(2, "directors_cut", "1080p", size=9000)]),
        ])

    def test_parts(self):
        single4k = fv(20, "2160p", "final_cut", "Final Cut")
        cd1 = fv(11, "1080p", "final_cut", "Final Cut", kind="multipart_movie", part=1)
        cd2 = fv(12, "1080p", "final_cut", "Final Cut", kind="multipart_movie", part=2)
        variants = [
            {"variant_id": "final_cut|single", "edition_key": "final_cut", "part_count": 1,
             "parts": [{"part_index": 1, "versions": [single4k]}]},
            {"variant_id": "final_cut|multipart", "edition_key": "final_cut", "part_count": 2,
             "parts": [{"part_index": 1, "versions": [cd1]}, {"part_index": 2, "versions": [cd2]}]},
        ]
        files = [cd1, cd2, single4k]
        p1 = fv(10, "1080p", kind="multipart_movie", part=1)
        p2 = fv(11, "1080p", kind="multipart_movie", part=2)
        std = [{"variant_id": "standard", "part_count": 2, "parts": [
            {"part_index": 1, "default_file_id": "10", "versions": [p1]}, {"part_index": 2, "default_file_id": "11", "versions": [p2]}]}]
        check_cases(self, FILES, [
            pick("last played the first CD: the cut's best file wins", 20, last_file=11, files=files, variants=variants),
            pick("stopped in CD2: Resume keeps that part", 12, last_file=12, position=600, files=files, variants=variants),
            ("Start Over plays CD1", "EditionT_firstPart", [files, "12"], "11"),
            ("one Edition row for the cut, offering both presentations' first parts", "EditionT_list", [files, variants],
             [{"id": "final_cut", "label": "Final Cut", "files": ["11", "20"], "fileIds": ["11", "12", "20"]}]),
            pick("resume stays on a later part", 11, last_file=11, position=600, files=[p1, p2], variants=std),
            pick("also with the unnamed edition picked", 11, last_file=11, position=600, edition="", files=[p1, p2], variants=std),
            pick("no history: part 1", 10, files=[p1, p2], variants=std),
            pick("without variants a later part is still recognised", 11, last_file=11, position=600, files=[p1, p2]),
            pick("without variants Auto starts at part 1 even when part 2 is better", 10,
                 files=[p1, fv(11, "2160p", kind="multipart_movie", part=2)]),
            pick("finished on the last part (position reset): a rewatch starts at part 1", 10, last_file=11, position=0, files=[p1, p2]),
        ])


class Editions(unittest.TestCase):
    def test_list(self):
        check_cases(self, FILES, [
            ("one edition per key in first-appearance order, labelled by raw name", "EditionT_list", [VERSIONS, []],
             [{"id": "extended", "label": "Extended", "files": ["3"], "fileIds": ["3"]},
              {"id": "theatrical", "label": "Theatrical", "files": ["2", "1"], "fileIds": ["1", "2"]}]),
            ("a key without a raw name reads as words; blank and missing keys are one unnamed edition", "EditionT_list",
             [[fv(1, "1080p", "directors_cut"), fv(2, "1080p", " "), fv(3, "720p"), fv(4, "720p", "imax")], []],
             [{"id": "directors_cut", "label": "Directors Cut", "files": ["1"], "fileIds": ["1"]},
              {"id": "", "label": "", "files": ["2", "3"], "fileIds": ["2", "3"]},
              {"id": "imax", "label": "IMAX", "files": ["4"], "fileIds": ["4"]}]),
            ("variants give the order and drop files no version lists", "EditionT_list",
             [VERSIONS, [{"variant_id": "t", "edition_key": "theatrical", "edition_raw": "Theatrical Cut", "parts": [
                 {"part_index": 1, "versions": [T4K, T1080]}]},
                 {"variant_id": "e", "edition_key": "extended", "parts": [{"part_index": 1, "versions": [E1080, fv(9, "720p")]}]}]],
             [{"id": "theatrical", "label": "Theatrical Cut", "files": ["2", "1"], "fileIds": ["1", "2"]},
              {"id": "extended", "label": "Extended", "files": ["3"], "fileIds": ["3", "9"]}]),
        ])

    def test_play_file_id(self):
        shown = fv(7, "1080p")
        check_cases(self, FILES, [
            ("a pin is sent", "Edition_playFileId", [shown, True, False, "7"], "7"),
            ("a file whose tracks were picked is sent", "Edition_playFileId", [shown, False, True, "7"], "7"),
            ("an Auto file that is not the last played is sent", "Edition_playFileId", [shown, False, False, "3"], "7"),
            ("the last-played Auto file is left to the player", "Edition_playFileId", [shown, False, False, "7"], ""),
            ("nothing shown, nothing sent", "Edition_playFileId", [None, True, True, "7"], ""),
        ])


if __name__ == "__main__":
    unittest.main()
