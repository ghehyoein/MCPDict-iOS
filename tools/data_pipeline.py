#!/usr/bin/env python3
"""Build iOS data from a Git checkout, never from an APK. Python 3.12+."""
from __future__ import annotations

import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys

SOURCE = "https://github.com/osfans/MCPDict"
SCHEMA = {"langs": {"字組", "語言", "讀音", "註釋"},
          "info": {"簡稱", "語言"}, "mcpdict": {"漢字"}}


def readonly(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)


def validate(path: Path) -> dict:
    with closing(readonly(path)) as db:
        if db.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            raise ValueError("SQLite quick_check failed")
        counts = {}
        for table, required in SCHEMA.items():
            actual = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
            if not required <= actual:
                raise ValueError(f"Unsupported schema: {table}: missing {required - actual}")
            counts[table] = db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
            if not counts[table]:
                raise ValueError(f"Empty table: {table}")
        sample = db.execute('SELECT 字組, 語言, 讀音 FROM langs WHERE langs MATCH ? LIMIT 5',
                            ('字組 : "中"',)).fetchall()
        if not sample:
            raise ValueError("FTS5 smoke test failed: 中")
        return {"counts": counts, "sample": sample}


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git(checkout: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(checkout), *args], text=True).strip()


def build(checkout: Path) -> Path:
    """Use upstream's own parsers and normalization rules at the pinned commit."""
    tools = checkout / "tools"
    # Same timestamp refresh as upstream CI; avoids stale generated TSV caches.
    for module in (tools / "tables").glob("*.py"):
        module.touch()
    (tools / "tables/output/_詳情.json").touch()
    subprocess.run([sys.executable, "make.py", "-c", "-i"], cwd=tools,
                   env={**os.environ, "PYTHONUTF8": "1"}, check=True)
    return checkout / "app/src/main/assets/databases/mcpdict.db"


def package(database: Path, output: Path, commit: str, repository: str) -> dict:
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Expected full upstream commit SHA")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Expected GitHub owner/repo")
    report = validate(database)
    digest = sha256(database)
    tag = f"data-{commit[:12]}-{digest[:12]}"
    output.mkdir(parents=True, exist_ok=True)
    target = output / "mcpdict.db"
    if target.resolve() != database.resolve():
        shutil.copy2(database, target)
    manifest = {
        "schemaVersion": 1, "version": tag, "sourceCommit": commit,
        "sourceRepository": SOURCE,
        "database": {"url": f"https://github.com/{repository}/releases/download/{tag}/mcpdict.db",
                     "size": target.stat().st_size, "sha256": digest},
    }
    for name, payload in [("manifest.json", manifest), ("validation.json", report)]:
        (output / name).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", type=Path, required=True)
    parser.add_argument("--repository", required=True, help="Your data-release owner/repo")
    parser.add_argument("--output", type=Path, default=Path("dist"))
    parser.add_argument("--existing-db", type=Path, help="Package an already built source database")
    args = parser.parse_args()
    checkout = args.checkout.resolve()
    origin = git(checkout, "remote", "get-url", "origin").removesuffix(".git").rstrip("/")
    if origin != SOURCE:
        raise ValueError(f"Unexpected source repository: {origin}")
    commit = git(checkout, "rev-parse", "HEAD")
    manifest = package(args.existing_db or build(checkout), args.output, commit, args.repository)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
