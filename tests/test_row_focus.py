# SPDX-License-Identifier: AGPL-3.0-or-later
"""Silo Android #803: when a Home refresh replaces a row's cards, focus stays on the same card, else
in Continue Watching / Next Up on the same show (its next episode), else on the same place
(RowFocus.brs); and a card menu left open closes when the card it was opened on changed
(CardActions_targetCurrent, HomeCardActions.brs)."""
import unittest

from brs import check_cases

FILES = ["components/common/RowFocus.brs", "components/widgets/HomeCardActions.brs", "components/common/Utils.brs"]

CARDS = [{"contentId": "m1", "seriesId": ""}, {"contentId": "b-e3", "seriesId": "b"},
         {"contentId": "a-e2", "seriesId": "a"}, {"contentId": "siku:explore-all", "seriesId": ""}]


def at(index, how):
    return lambda v: v == {"index": index, "how": how}


class RowFocus(unittest.TestCase):
    def test_index(self):
        f = "RowFocus_index"
        check_cases(self, FILES, [
            ("the same card", f, [{"contentId": "a-e2", "seriesId": "a", "item": 0}, CARDS, True], at(2, "card")),
            ("the show's next episode, moved", f, [{"contentId": "a-e1", "seriesId": "a", "item": 0}, CARDS, True],
             at(2, "series")),
            ("outside progress rows, by place", f, [{"contentId": "a-e1", "seriesId": "a", "item": 1}, CARDS, False],
             at(1, "position")),
            ("the show left the row", f, [{"contentId": "c-e1", "seriesId": "c", "item": 9}, CARDS, True],
             at(3, "position")),
            ("a movie that left", f, [{"contentId": "m9", "seriesId": "", "item": 1}, CARDS, True], at(1, "position")),
            ("empty row", f, [{"contentId": "a-e1", "seriesId": "a", "item": 2}, [], True], at(0, "first")),
            ("no key", f, [None, CARDS, True], at(0, "first")),
        ])

    def test_menu_target(self):
        f = "CardActions_targetCurrent"
        rows = [{"id": "continue_watching", "items": [{"content_id": "a-e2"}, {"content_id": "m1"}]}]
        tgt = lambda r, i, rid, cid: {"rowIndex": r, "itemIndex": i, "rowId": rid, "card": {"content_id": cid}}  # noqa: E731
        check_cases(self, FILES, [
            ("same card, same place", f, [rows, tgt(0, 1, "continue_watching", "m1")], True),
            ("next episode replaced it", f, [rows, tgt(0, 0, "continue_watching", "a-e1")], False),
            ("another row now", f, [rows, tgt(0, 1, "next_up", "m1")], False),
            ("the row got shorter", f, [rows, tgt(0, 5, "continue_watching", "m1")], False),
            ("the row is gone", f, [rows, tgt(3, 0, "continue_watching", "m1")], False),
            ("no target", f, [rows, None], False),
        ])


if __name__ == "__main__":
    unittest.main()
