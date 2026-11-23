# Building the bilingual MSX game

| Tool | Use |
| --- | --- |
| GNU Make 4.3 or later, POSIX shell and standard Unix tools | Orchestrate the build |
| SjASM 0.42c (the Z80 assembler) | Assemble the launcher, engine and overlays |
| Python 3 and Pillow built with libimagequant | Convert graphics, sound sequences and level data |
| A C++ compiler and standard library | Build the AdLib conversion tool |
| pdfLaTeX, Babel (English and Spanish), Helvetica and the packages listed in `docs/manual/manual.tex` | Optional, to regenerate the PDFs |

Python must report `True` for `python3 -c 'from PIL import features; print(features.check_feature("libimagequant"))'`. Set `SJASM`, `PYTHON` and `CXX` on the make command line to select a different toolchain.

## Supply the original files

Use a copy of the Spanish VGA DOS release of the first *Eye of the Beholder* and the English VGA DOS release as input. Use the uppercase DOS filenames in the following folders. Git ignores the entire `third_party/` tree.

| Location | Required files |
| --- | --- |
| `third_party/dos-es/` | `EOBDATA1.PAK` through `EOBDATA6.PAK`, `LEVEL1.DRO` through `LEVEL12.DRO`, `CCARGEN.CPS`, `CCARGENB.CPS`, `EOBDATA.SAV`, `FONT6.FNT`, `FONT8.FNT` |
| `third_party/dos-en/` | English `EOBDATA3.PAK` and `EOBDATA6.PAK`. You may instead supply the loose `LEVEL1.INF`, `LEVEL2.INF`, `TEXT.DAT` and `ITEM.DAT` extracted from those two archives. If an archive is present the build uses it for its entries. |
| `third_party/scummvm/` | The pair `resource.h` and `kyra.dat` from the same ScummVM release. Use [`engines/kyra/resource/resource.h`](https://github.com/scummvm/scummvm/blob/v2.9.1/engines/kyra/resource/resource.h) and [`dists/engine-data/kyra.dat`](https://github.com/scummvm/scummvm/blob/v2.9.1/dists/engine-data/kyra.dat) from v2.9.1. |

For the Spanish edition, the whole installed game folder can also be used. Choose the standard VGA assets and the included starter save.

## Build and package

```sh
make inputs
make -j4
make release VERSION=1.0
```

1. The build extracts the English text overlay and reads the data tables for both languages locally.
2. The conversion tools apply the port's adaptations to the original data. For example, they merge the Spanish `.DRO` level scripts with the door shape data from the corresponding `.INF` files. They convert the graphics to V9990 layouts and prepare the runtime overlays, palettes, text and audio for both languages.
3. SjASM builds `EOB.COM` and the language-specific executables and overlays. The staging script places the shared data at the root of `build/SD/EOB` and the language files in `ES` and `EN`.
4. `make release` puts the SD game ZIP and the English and Spanish PDFs in `release/`. The ZIP can be unpacked on a computer and its `SD/EOB` folder copied to an existing bootable DOS card. See the installation instructions in the [README](../README.md).

Use `make manual` for new PDFs, `make help` for the available targets and `make clean` to remove generated game and release files.

## Playing in openMSX

The launcher uses the upgraded openMSX wrapper at `../openmsx_v9990_upgraded/run.sh` by default. Set `OPENMSX_RUN` to the wrapper's path if needed. Install the machine ROMs for the Philips NMS 8245 or the turbo R you intend to use, and Sunrise IDE firmware with Nextor. Supply `NEXTOR.SYS` and `COMMAND2.COM` under `third_party/dos/` for the first launch.

```sh
make run-msx2
make run-turbor
make run-msx2 SD_DIR=/path/to/unpacked/SD/EOB
```

With the default settings the launcher uses `SD/EOB` from an unpacked release or falls back to `build/SD/EOB`. It creates a writable player disk in `.eob-player/` and reuses it on subsequent runs to keep your saves. For a fresh or separate installation, set `EOB_PLAYER_DIR` to a new directory.
