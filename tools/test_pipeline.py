import json
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest

from data_pipeline import package, sha256, validate
from query import search


class DataContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "test.db"
        with closing(sqlite3.connect(self.path)) as db:
            db.executescript('''
                CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋, tokenize='unicode61 remove_diacritics 0');
                CREATE VIRTUAL TABLE info USING fts5(簡稱, 語言);
                CREATE VIRTUAL TABLE mcpdict USING fts5(漢字);
                INSERT INTO info VALUES ('普通話', '普通話');
                INSERT INTO mcpdict VALUES ('中');
            ''')
            db.executemany("INSERT INTO langs VALUES (?, ?, ?, ?)", [
                ("中 忠", "普通話", "zhong1", "中心"),
                ("中 仲", "普通話", "zhong4", "命中"),
                ("中", "測試方言", "tung1", "測試"),
                ("𰻞", "測試方言", "biang", "擴展字"),
            ])
            db.commit()

    def test_character_group_and_exact_language(self):
        rows = search(self.path, "中", language="普通話")
        self.assertEqual([x["讀音"] for x in rows], ["zhong1", "zhong4"])
        self.assertEqual([x["字組"] for x in rows], ["中", "中"])
        self.assertEqual(search(self.path, "zhong1", mode="pronunciation")[0]["字組"], "中 忠")
        self.assertEqual(search(self.path, "中", language="普通話' OR 1=1 --"), [])

    def test_unicode_and_multi_character(self):
        self.assertEqual(search(self.path, "U+4E2D"), search(self.path, "中"))
        self.assertEqual(len(search(self.path, "中𰻞")), 4)
        self.assertEqual(len(search(self.path, "𰻞")), 1)

    def test_fts_syntax_is_literal(self):
        self.assertEqual(search(self.path, 'x" OR "zhong1', mode="pronunciation"), [])
        self.assertEqual(len(search(self.path, "zhong1", mode="pronunciation")), 1)
        self.assertEqual(len(search(self.path, "中", offset=2)), 1)

    def test_manifest_hash_and_schema(self):
        out = Path(self.temp.name) / "out"
        manifest = package(self.path, out, "a" * 40, "example/data")
        self.assertEqual(manifest["database"]["sha256"], sha256(out / "mcpdict.db"))
        self.assertEqual(manifest["database"]["size"], self.path.stat().st_size)
        self.assertEqual(json.loads((out / "validation.json").read_text(encoding="utf-8"))["counts"]["langs"], 4)
        with closing(sqlite3.connect(self.path)) as db:
            db.execute("DROP TABLE info")
        with self.assertRaises(ValueError):
            validate(self.path)


if __name__ == "__main__":
    unittest.main()
