"""Build the overview from the pinned Guangyun source in book order.

The normalized pronunciation table omits the original xiaoyun numbers.
Keep the source spellings (including editorial annotations) for display.
"""
import csv
import json
import re


def build_guangyun(checkout, output):
    groups = {}
    with (checkout / "tools/tables/data/廣韻.tsv").open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
            position = row["切韻音系描述"]
            initial, openness, division, subclass, rhyme, tone = re.fullmatch(
                r"(.)([開合]?)([一二三四])([ABC]?)(.)([平上去入])", position
            ).groups()
            number, title, fanqie = (row[k] for k in ("小韻號", "廣韻韻目", "反切或直音"))
            key = (number, position, title, fanqie, row["攝"])
            if key not in groups:
                groups[key] = dict(number=number, title=title, fanqie=fanqie,
                                   position=position, she=row["攝"], rhyme=rhyme, initial=initial,
                                   openness=openness, division=division, subclass=subclass,
                                   tone=tone, characters=[])
            groups[key]["characters"].append(row["字頭"])
    (output / "guangyun-overview.json").write_text(
        json.dumps(list(groups.values()), ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
