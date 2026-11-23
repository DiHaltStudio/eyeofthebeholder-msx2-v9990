#!/usr/bin/env python3
"""Expand the extracted EOB1 save tables without changing their rules."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
tables = json.loads((root / "build/eob_tables.json").read_text())["0x3001"]
def data(name):
    return tables["kEoBBase" + name]["data"]

lines = ["; Generated from build/eob_tables.json by tools/gen_rules_tables.py",
         "; Four class groups, five saving-throw types, levels 0..31.",
         "FX_SAVE_TABLE:"]
for group in range(4):
    source = data(f"SaveThrowTable{group + 1}")
    for kind in range(5):
        row = [source[min(level, data("SaveThrwLvlIndex")[group])
                      // data("SaveThrwModDiv")[group]
                      + kind * data("SaveThrwModExt")[group]]
               for level in range(32)]
        lines.append(" db " + ",".join(map(str, row)))
for folder in ("build", "build/en"):
    path = root / folder / "rules.inc"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")
