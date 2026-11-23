"""Locate the DOS inputs and extract the English overlay into build/."""
import sys
from pathlib import Path

from eoblib import ROOT, read_pak

INPUTS = ROOT / "third_party"
SPANISH = INPUTS / "dos-es"
ENGLISH = INPUTS / "dos-en"
SCUMMVM = INPUTS / "scummvm"
ENGLISH_MEMBERS = {
    "EOBDATA3.PAK": ("LEVEL1.INF", "LEVEL2.INF", "TEXT.DAT"),
    "EOBDATA6.PAK": ("ITEM.DAT",),
}


def check():
    spanish_names = (
        *(f"EOBDATA{number}.PAK" for number in range(1, 7)),
        *(f"LEVEL{number}.DRO" for number in range(1, 13)),
        "CCARGEN.CPS", "CCARGENB.CPS", "EOBDATA.SAV", "FONT6.FNT", "FONT8.FNT",
    )
    missing = [SPANISH / name for name in spanish_names if not (SPANISH / name).is_file()]
    missing += [SCUMMVM / name for name in ("resource.h", "kyra.dat") if not (SCUMMVM / name).is_file()]
    for archive, names in ENGLISH_MEMBERS.items():
        if not (ENGLISH / archive).is_file() and not all((ENGLISH / name).is_file() for name in names):
            missing.append(ENGLISH / archive)
    if missing:
        print("Missing build inputs. See docs/BUILDING.md for the required editions and files.", file=sys.stderr)
        for path in missing:
            print(f"  {path.relative_to(ROOT)}", file=sys.stderr)
        sys.exit(1)


def extract_english():
    data = {}
    for archive, names in ENGLISH_MEMBERS.items():
        path = ENGLISH / archive
        if path.is_file():
            entries = read_pak(path)
            for name in names:
                if name not in entries:
                    sys.exit(f"{path.relative_to(ROOT)} has no {name}. See docs/BUILDING.md.")
                data[name] = entries[name]
        else:
            data.update((name, (ENGLISH / name).read_bytes()) for name in names)
    output = ROOT / "build" / "pc_en"
    output.mkdir(parents=True, exist_ok=True)
    for name, raw in data.items():
        (output / name).write_bytes(raw)


if __name__ == "__main__":
    if sys.argv[1:] == ["check"]:
        check()
    elif sys.argv[1:] == ["english"]:
        extract_english()
    else:
        sys.exit("Usage: prepare_inputs.py check|english")
