"""Reproduce Android's -c character ranking from its normalized table snapshot.

The first 5,000 entries are ranked by occurrence in homophone groups; remaining
entries use field coverage and the upstream Unihan Taiwan ordering. No APK data.
"""
import json
from collections import Counter, defaultdict
from pathlib import Path


def build_guess_characters(checkout, output):
    source = checkout / 'tools/tables/output'
    details = json.loads((source / '_詳情.json').read_text())
    frequency = Counter()
    # Preserve upstream catalog traversal order for equal-frequency characters.
    for name in details:
        file = source / (name + '.tsv')
        if not file.exists():
            continue
        groups = defaultdict(set)
        for line in file.read_text().splitlines():
            if not line or line.startswith('#'):
                continue
            columns = line.split('\t')
            if len(columns) < 2:
                continue
            groups[columns[1]].update(c for c in columns[0] if is_character(c))
        for chars in groups.values():
            for char in sorted(chars):
                frequency[char] += 1
    fields = defaultdict(set)
    books = '說文 集韻 康熙 匯纂 漢大'.split()
    for field in books + '異體字 字形變體 字形描述 部件檢索 兩分 總筆畫數 部首餘筆 五筆畫 五筆86 五筆98 五筆06 倉頡三代 倉頡五代 倉頡六代 山人 分類'.split():
        file = source / (field + '.tsv')
        if not file.exists():
            continue
        for line in file.read_text().splitlines():
            if not line or line.startswith('#'):
                continue
            char = line.split('\t', 1)[0]
            if len(char) == 1:
                fields[char].add(field)
                if field in books:
                    fields[char].add('分類')
    order = {}
    for line in (checkout / 'tools/tables/data/Unihan_IRGSources.txt').read_text().splitlines():
        if not line.startswith('U+'):
            continue
        code, key, value = line.split('\t', 2)
        if key == 'kIRG_TSource':
            order[chr(int(code[2:], 16))] = [int(v, 16) for v in value.lstrip('T').replace('U', '100').split('-')]
    frequent = ['□'] + [char for char, _ in frequency.most_common(5000)]
    ranks = {char: index for index, char in enumerate(frequent)}
    result = sorted(fields, key=lambda c: (ranks.get(c, 0xffff), -len(fields[c]), order.get(c, [0x100, ord(c)])))
    if len(result) < 6000:
        raise ValueError('Incomplete guess-character corpus')
    (output / 'guess-characters.json').write_text(json.dumps(result[:6000], ensure_ascii=False))


def is_character(c):
    n = ord(c)
    compatibility = (0xF900 <= n < 0xFB00 and c not in '﨎﨏﨑﨓﨔﨟﨡﨣﨤﨧﨨﨩') or 0x2F800 <= n < 0x2FA20
    return 0x3400 <= n < 0xA000 or n in (0x25A1, 0x3007) or 0xF900 <= n < 0xFB00 or (0x20000 <= n <= 0x3347F and not compatibility)
