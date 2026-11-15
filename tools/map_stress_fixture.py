"""Generate test-only readings for every geocoded point in the pinned catalog.

Prefer all readings of 一; for tables without 一 use their first complete entry.
The fixture is not shipped in the app and does not change the bundled scope.
"""
import json
import sys
from pathlib import Path

source, catalog_path, output = map(Path, sys.argv[1:])
catalog = json.loads(catalog_path.read_text())
readings = {}
fallbacks = 0
for table in catalog['tables']:
    if not table.get('location'):
        continue
    matches, first = [], None
    with (source / 'tools/tables/output' / (table['name'] + '.tsv')).open(encoding='utf-8') as file:
        for line in file:
            if not line.strip() or line.startswith('#'):
                continue
            fields = line.rstrip('\r\n').split('\t')
            if len(fields) < 2:
                continue
            text = '\t'.join(fields[1:])
            if first is None:
                first = text
            if '一' in fields[0]:
                matches.append(text)
    if matches or first:
        readings[table['id']] = '\n'.join(dict.fromkeys(matches or [first]))
        fallbacks += not bool(matches)
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(readings, ensure_ascii=False), encoding='utf-8')
print(f'MAP_FIXTURE source={catalog["sourceCommit"]} points={len(readings)} first_entry_fallbacks={fallbacks}')
