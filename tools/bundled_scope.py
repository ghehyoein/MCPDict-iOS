def include_table(meta):
    category = str(meta.get('音典分區', '')).split('－')[0]
    if category in {'歷史音', '現代標準漢語', '戲劇', '域外方音'}:
        return True
    return bool(meta.get('省') or meta.get('市')) and not any(meta.get(k) for k in ['縣', '鎮', '村', '自然村'])

