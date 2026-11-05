import hashlib
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from export_variants import export


class VariantTests(unittest.TestCase):
    def test_export_is_bidirectional_without_transitive_merging(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            database = root / 'input.db'
            with closing(sqlite3.connect(database)) as db:
                db.execute('CREATE TABLE mcpdict(漢字 TEXT, 異體字 TEXT)')
                db.executemany('INSERT INTO mcpdict VALUES (?,?)', [('發', '发'), ('髮', '发')])
                db.commit()
            export(database, root / 'variants', 'a' * 40)
            graph = {}
            for path in (root / 'variants').glob('variants-[0-9]*.json'):
                graph.update(json.loads(path.read_text(encoding='utf-8')))
            self.assertEqual(set(graph['发']), {'發', '髮'})
            self.assertNotIn('發', graph)
            self.assertNotIn('髮', graph)

    def test_bundled_upstream_mapping_hashes_and_symmetry(self):
        folder = Path(__file__).resolve().parents[1] / 'App/VariantData'
        info = json.loads((folder / 'variants-source.json').read_text(encoding='utf-8'))
        graph = {}
        for name, digest in info['sha256'].items():
            content = (folder / name).read_bytes()
            self.assertEqual(hashlib.sha256(content).hexdigest(), digest)
            graph.update(json.loads(content))
        self.assertEqual(len(graph), info['characters'])
        for char, values in graph.items():
            self.assertEqual(len(values), len(set(values)))
            self.assertTrue(all(len(v) == 1 for v in values))
        self.assertIn('輸', graph['输'])


if __name__ == '__main__':
    unittest.main()
