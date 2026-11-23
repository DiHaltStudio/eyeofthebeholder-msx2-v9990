"""Package the SD game directory and the two player manuals."""
import re
import shutil
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]


def package(version, game):
    if not re.fullmatch(r"\d+(?:\.\d+)+(?:-[A-Za-z0-9.-]+)?", version):
        sys.exit("Use a version such as 1.0 or 1.1-rc1.")
    for name in ("EOB.COM", "ES/EOB.BIN", "EN/EOB.BIN"):
        if not (game / name).is_file():
            sys.exit(f"Missing game file: {game / name}")
    output = ROOT / "release"
    output.mkdir(exist_ok=True)
    name = f"Eye-of-the-Beholder-MSX2-V9990-v{version}.zip"
    with TemporaryDirectory(dir=output) as work:
        work = Path(work)
        with ZipFile(work / name, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(game.rglob("*")):
                if path.is_file():
                    archive.write(path, Path("SD/EOB") / path.relative_to(game))
            archive.write(ROOT / "tools" / "sd-readme.txt", "README.txt")
        for lang in ("en", "es"):
            shutil.copyfile(ROOT / "docs" / "manual" / f"manual-{lang}.pdf", work / f"Manual-{lang.upper()}.pdf")
        for path in work.iterdir():
            path.replace(output / path.name)
    print(f"Created release/{name} and both manuals.")


if __name__ == "__main__":
    package(sys.argv[1], Path(sys.argv[2]))
