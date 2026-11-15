"""Copy pinned upstream TSVs into the opt-in simulator test bundle only."""
import json
import pathlib
import subprocess
import sys

source, catalog_file, output = map(pathlib.Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
catalog = json.loads(catalog_file.read_text())
for table in catalog["tables"]:
    # Read Git blobs so checkout line-ending settings cannot invalidate hashes.
    data = subprocess.check_output([
        "git", "-C", str(source), "show",
        catalog["sourceCommit"] + ":tools/tables/output/" + table["name"] + ".tsv",
    ])
    (output / (table["id"] + ".tsv")).write_bytes(data)
(output / "download-stress-enabled.txt").write_text(str(len(catalog["tables"])))
print(f"Prepared {len(catalog['tables'])} download test tables")
