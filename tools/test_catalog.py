from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from build_table_catalog import build_catalog
from data_pipeline import sha256, readonly


class CatalogTests(unittest.TestCase):
    def test_single_table_is_exact_and_classified(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            database = root / 'source.db'
            fields = ['語言', '簡稱', '地圖集二分區', '音典分區', '省', '市', '縣', '鎮', '村', '自然村', '字表來源']
            with closing(sqlite3.connect(database)) as db:
                db.execute('CREATE VIRTUAL TABLE info USING fts5(' + ','.join(fields) + ')')
                db.execute('CREATE VIRTUAL TABLE langs USING fts5(字組,語言,讀音,註釋)')
                db.execute('CREATE VIRTUAL TABLE mcpdict USING fts5(漢字)')
                db.execute('INSERT INTO info VALUES (' + ','.join('?' for _ in fields) + ')', ['杭州話語', '杭州', '吳語－太湖片－杭州小片', '藍青－浙江', '浙江', '杭州', '', '', '', '', 'fixture'])
                db.executemany('INSERT INTO langs VALUES (?,?,?,?)', [('中 忠', '杭州', 'test', 'note'), ('中', '別處', 'other', '')])
                db.commit()
            result = build_catalog(database, root / 'out', 'example/data', 'a' * 40, ['杭州', '杭州'], 'test-release')
            self.assertEqual(len(result['tables']), 1)
            table = result['tables'][0]
            self.assertEqual(table['atlas'], ['吳語', '太湖片', '杭州小片'])
            self.assertEqual(table['administrative'], ['浙江', '杭州'])
            path = root / 'out' / (table['id'] + '.db')
            self.assertEqual(sha256(path), table['sha256'])
            with closing(readonly(path)) as db:
                self.assertEqual(db.execute('SELECT * FROM langs').fetchall(), [('中 忠', '杭州', 'test', 'note')])
                self.assertEqual(db.execute('SELECT count(*) FROM mcpdict').fetchone()[0], 0)
            parsed = json.loads((root / 'out/catalog.json').read_text(encoding='utf-8'))
            self.assertEqual(parsed['tables'][0]['name'], '杭州')


if __name__ == '__main__':
    unittest.main()
