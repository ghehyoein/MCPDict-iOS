#!/usr/bin/env python3
"""Python reference query/CLI; same FTS expression contract as the iOS reader."""
import argparse
from contextlib import closing
import json
from pathlib import Path
from data_pipeline import readonly

FIELDS = {"character": "字組", "pronunciation": "讀音", "note": "註釋"}


def expression(text: str, mode: str = "character") -> str:
    text = text.strip()
    if not text:
        raise ValueError("Empty search")
    if mode == "character" and text.upper().startswith("U+"):
        try:
            code = int(text[2:], 16)
            if 0 <= code <= 0x10FFFF and not 0xD800 <= code <= 0xDFFF:
                text = chr(code)
        except ValueError:
            pass
    terms = [c for c in text if not c.isspace()] if mode == "character" else [text]
    quoted = ['"' + term.replace('"', '""') + '"' for term in terms]
    return FIELDS[mode] + " : (" + " OR ".join(quoted) + ")"


def search(database: Path, text: str, mode="character", language="", offset=0):
    sql = "SELECT rowid AS id, 字組, 語言, 讀音, 註釋 FROM langs WHERE langs MATCH ?"
    parameters = [expression(text, mode)]
    if language:
        sql += " AND 語言 = ?"
        parameters.append(language)
    sql += " ORDER BY rowid LIMIT 100 OFFSET ?"
    parameters.append(max(0, offset))
    with closing(readonly(database)) as db:
        cursor = db.execute(sql, parameters)
        columns = [item[0] for item in cursor.description]
        rows = [dict(zip(columns, row)) for row in cursor]
        if mode == "character":
            normalized = text.strip()
            if normalized.upper().startswith("U+"):
                try:
                    normalized = chr(int(normalized[2:], 16))
                except (ValueError, OverflowError):
                    pass
            requested = set(normalized)
            for row in rows:
                row["字組"] = " ".join(c for c in row["字組"].split() if c in requested)
        return rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("text")
    parser.add_argument("--mode", choices=FIELDS, default="character")
    parser.add_argument("--language", default="")
    args = parser.parse_args()
    print(json.dumps(search(args.database, args.text, args.mode, args.language), ensure_ascii=False, indent=2))
