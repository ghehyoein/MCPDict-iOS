"""Split selected source-built tables into independently downloadable SQLite packages."""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import re
import sqlite3

from data_pipeline import readonly, sha256, SOURCE


def build_catalog(database: Path, output: Path, repository: str, commit: str, languages: list[str], tag: str):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository) or not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Invalid source or repository')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', tag):
        raise ValueError('Invalid release tag')
    output.mkdir(parents=True, exist_ok=True)
    entries = []
    with closing(readonly(database)) as source:
        source.row_factory = sqlite3.Row
        schemas = {name: source.execute('SELECT sql FROM sqlite_master WHERE name=?', (name,)).fetchone()[0] for name in ('langs', 'info', 'mcpdict')}
        for language in dict.fromkeys(languages):
            metadata = source.execute('SELECT * FROM info WHERE 簡稱=?', (language,)).fetchone()
            if metadata is None:
                raise ValueError(f'Missing language: {language}')
            identity = hashlib.sha256(language.encode()).hexdigest()[:24]
            destination = output / (identity + '.db')
            if destination.exists():
                raise FileExistsError(destination)
            with closing(sqlite3.connect(destination)) as db:
                for sql in schemas.values():
                    db.execute(sql)
                # Keep exactly the upstream grouped readings, notes, tokenizer and metadata.
                expr = '語言 : "' + language.replace('"', '""') + '"'
                rows = source.execute('SELECT 字組, 語言, 讀音, 註釋 FROM langs WHERE langs MATCH ? AND 語言=? ORDER BY rowid', (expr, language))
                db.executemany('INSERT INTO langs VALUES (?,?,?,?)', (tuple(row) for row in rows))
                db.execute('INSERT INTO info VALUES (' + ','.join('?' for _ in metadata) + ')', tuple(metadata))
                count = db.execute('SELECT count(*) FROM langs').fetchone()[0]
                if count == 0:
                    raise ValueError(f'No readings: {language}')
                db.commit()
                if db.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
                    raise ValueError('Shard quick_check failed')
            def path(key):
                return [part.strip() for part in (metadata[key] or '').split('－') if part.strip()] or ['未分類']
            admin = [metadata[key] for key in ('省', '市', '縣', '鎮', '村', '自然村') if metadata[key]] or ['未標註行政區']
            entries.append({'id': identity, 'name': language, 'fullName': metadata['語言'] or language,
                            'atlas': path('地圖集二分區'), 'dictionary': path('音典分區'), 'administrative': admin,
                            'source': metadata['字表來源'] or '', 'sourceCommit': commit,
                            'recordCount': count, 'size': destination.stat().st_size,
                            'sha256': sha256(destination),
                            'url': f'https://github.com/{repository}/releases/download/{tag}/{identity}.db'})
    catalog = {'schemaVersion': 1, 'version': tag, 'sourceRepository': SOURCE, 'sourceCommit': commit,
               'scope': '試驗目錄：僅含所列字表，並非上游全部資料；不含通用漢字字書資料。', 'tables': entries}
    (output / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return catalog


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--languages', nargs='+', default=['普通話', '廣州', '杭州'])
    args = parser.parse_args()
    result = build_catalog(args.database, args.output, args.repository, args.commit, args.languages, args.tag)
    print(json.dumps({'tables': len(result['tables']), 'bytes': sum(x['size'] for x in result['tables'])}))
