# SPDX-License-Identifier: AGPL-3.0-or-later
"""AudioResume.brs: the on-device audiobook resume record keeps the stretches of a book the
server's resume thresholds drop (under 5 %, over 90 %), and yields to a position another device
wrote."""
import unittest

from brs import check_cases

FILES = ["tests/audio_resume_io.brs", "components/player/AudioResume.brs", "components/common/Utils.brs"]
A = "http://silo.example:8097|p1"
B = "http://silo.example:8097|p2"


def put(book, position, base, identity=A, total=36000):
    return {"op": "put", "identity": identity, "id": book, "position": position, "total": total, "base": base}


def pos(book, server, identity=A):
    return {"op": "position", "identity": identity, "id": book, "server": server}


class AudioResume(unittest.TestCase):
    def test_server_after(self):
        c = "AudioResume_serverAfter"
        check_cases(self, FILES, [
            ("under 5 % keeps what the server held", c, [600, 36000, 7200], 7200),
            ("the middle is stored", c, [18000, 36000, 7200], 18000),
            ("over 90 % is finished at 0", c, [34000, 36000, 18000], 0),
            ("unknown total: as sent", c, [50, 0, 10], 50),
        ])

    def test_records(self):
        many = [put("b%d" % i, 100 + i, 0) for i in range(14)]
        check_cases(self, FILES, [
            ("the record wins while the server holds its base", "AudioResumeIo_run",
             [[put("b1", 600, 7200), pos("b1", 7200), pos("b1", 7201.5)]], [1, 600, 600]),
            ("another device moved the book: the server wins", "AudioResumeIo_run",
             [[put("b1", 600, 7200), pos("b1", 9000)]], [1, -1]),
            ("no record", "AudioResumeIo_run", [[pos("b1", 0)]], [-1]),
            ("per profile", "AudioResumeIo_run",
             [[put("b1", 600, 0), pos("b1", 0, identity=B)]], [1, -1]),
            ("a put replaces the book's record", "AudioResumeIo_run",
             [[put("b1", 600, 0), put("b1", 900, 0), pos("b1", 0)]], [1, 1, 900]),
            ("cleared at the end of the book", "AudioResumeIo_run",
             [[put("b1", 600, 0), put("b2", 60, 0), {"op": "clear", "identity": A, "id": "b1"}, pos("b1", 0), pos("b2", 0)]],
             [1, 2, 1, -1, 60]),
            ("keeps the newest 12 books", "AudioResumeIo_run",
             [many + [pos("b0", 0), pos("b1", 0), pos("b2", 0), pos("b13", 0)]],
             list(range(1, 13)) + [12, 12, -1, -1, 102, 113]),
        ])


if __name__ == "__main__":
    unittest.main()
