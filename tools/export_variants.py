"""Export direct, bidirectional variants from an upstream-built MCPDict database.
No pronunciations or language tables are included. Regenerate after data_pipeline.py.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import sqlite3


def export(database: Path, destination: Path, commit: str):
    graph = defaultdict(set)
    with sqlite3.connect(f'{database.resolve().as_uri()}?mode=ro', uri=True) as db:
        for char, variants in db.execute('SELECT 漢字, 異體字 FROM mcpdict WHERE 異體字 IS NOT NULL'):
            if len(char) != 1:
                continue
            for variant in variants.split():
                if len(variant) == 1 and variant != char:
                    graph[char].add(variant)
                    graph[variant].add(char)
    destination.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for index in range(16):
        shard = {char: sorted(values) for char, values in sorted(graph.items()) if ord(char) % 16 == index}
        content = json.dumps(shard, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        name = f'variants-{index}.json'
        (destination / name).write_bytes(content)
        hashes[name] = hashlib.sha256(content).hexdigest()
    info = {'sourceRepository': 'https://github.com/osfans/MCPDict', 'sourceCommit': commit,
            'sourceField': 'mcpdict.異體字', 'algorithm': 'direct bidirectional relations; no transitive closure',
            'characters': len(graph), 'links': sum(map(len, graph.values())), 'sha256': hashes}
    (destination / 'variants-source.json').write_text(json.dumps(info, indent=2, ensure_ascii=False), encoding='utf-8')
    return info


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('database', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    print(json.dumps(export(args.database, args.destination, args.commit), ensure_ascii=False))
