#!/usr/bin/env python3
"""conv_chargen.py - The character generation (src/chargen.asm, CHARGEN.OVL).

  build/CHARGEN.V9   the screen of the original (CCARGEN.CPS in Spanish,
                     CHARGEN.CPS in English, as ScummVM loads them) and, from
                     row CG_Y on (the shape cache of level 1, which is loaded
                     meanwhile), what the overlay copies from: the clean right
                     panel, the bottom of CCARGENB / CHARGENB (box frames,
                     button bodies and their labels) and the ten sparkles;
  build/CHARGEN.PAL  its 64 colours: the fixed part (portraits, fonts, the
                     pointer) and the colours of those pictures;
  build/chargen.inc  the places of those copies, colours, and the tables and
                     texts of the original (kEoBBaseChargen*, CharacterGenerator).
"""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eoblib as E
import conv_level as C
from conv_global import string_list, asm_string, GUI_COLOURS

BUILD = E.BUILD
CG_ROWS = 128                 # rows of the shape cache the overlay takes
PANEL = (144, 64, 160, 128)   # the right panel of the screen (dim 2)
BOTTOM = (0, 128, 248, 72)    # CCARGENB: box frames, buttons, labels
SPARKS = (0, 0, 320, 32)      # CCARGENB: the ten sparkle shapes
# GUI_EoB::_highlightColorTableVGA (the frame around the chosen box)
HIGHLIGHT = (0x0F, 0xB0, 0xB2, 0xB4, 0xB6, 0xB8, 0xBA, 0xBC, 0x0C, 0xBC, 0xBA, 0xB8, 0xB6, 0xB4, 0xB2, 0xB0)

# static tables of the engine (staticres_eob.cpp, chargen.cpp)
HP_INCR = (10, 4, 8, 6, 10, 10, 9, 10, 9, 10, 9, 9, 3, 1, 2, 2, 3, 3)
HP_CON_MOD = (-1, -3, -2, -2, -1, -1, -1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 6, 6, 7, 7)
CLASS_TYPE = (0, -1, -1, 5, -1, -1, 4, -1, -1, 1, -1, -1, 2, -1, -1, 3, -1, -1, 0,
              2, -1, 0, 3, -1, 0, 1, -1, 0, 1, 3, 3, 1, -1, 2, 3, -1, 0, 2, 1, 5,
              2, -1, 2, 1, -1)
DEX_AC_MOD = (5, 5, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, -1, -2, -3, -4, -4, -5, -5, -5, -6, -6)
RACE_MOD = (0, 0, 0, 0, 0, 0, 0, 0, 0, 1, -1, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 1, -1, 0, 1, -1, 0, 0, 0, -1, 0, 0, 1, 0, 0)
CLASS_MENU_MASKS = (0x003F, 0x07BB, 0x77FB, 0x00F1, 0x08F1, 0x00B1)
ALIGN_MENU_MASKS = (0x01FF, 0x0007, 0x0001, 0x01FF, 0x01FF, 0x01FE, 0x01FF, 0x01FE,
                    0x01FF, 0x01FE, 0x01FE, 0x01FE, 0x01FF, 0x0007, 0x01FF)
# CharacterGenerator::finish, EOB1: (item, inventory slot or -1: a free hand)
ITEM_LIST = (1, 17, 2, 17, 46, -1, 4, -1, 5, -1, 6, 2, 7, -1, 8, -1, 9, 21, 10, 2, 31, 2)
ITEM_LIST_INDEX = (4, 8, 0, -1, 4, 3, 0, -1, 4, 10, 0, 8, 3, 6, 1, -1, 2, 7, 0, -1,
                   4, 5, 0, -1, 4, 7, 0, 8, 4, 5, 0, 8, 4, 6, 8, 8, 4, 6, 5, 8,
                   3, 6, 5, -1, 2, 7, 5, 0, 4, 6, 7, 0, 4, 3, 7, 0, 2, 6, 7, 1)


def piece(img, rect, transparent):
    x, y, w, h = rect
    rows = []
    for r in range(y, y + h):
        row = list(img[r * 320 + x:r * 320 + x + w])
        if transparent:
            row = [None if v == 0 else v for v in row]
        rows.append(row)
    return rows


def level1_cache_row():
    d = (BUILD / "LEVEL1.LVL").read_bytes()
    vram = {}
    for line in (BUILD / "vram.inc").read_text().splitlines():
        if ":\tequ" in line:
            k, v = line.split(":\tequ")
            vram[k.strip()] = int(v)
    return struct.unpack_from("<H", d, vram["D_CACHEY"])[0]


def db(label, values, signed=False):
    vals = [str(E.signed8(v & 0xFF) if signed else v & 0xFF) for v in values]
    out = label + ":\n"
    for i in range(0, len(vals), 24):
        out += "\tdb " + ",".join(vals[i:i + 24]) + "\n"
    return out


def strings(f, label, items):
    f.write("%s:\tdw %s\n" % (label, ",".join("%s_%d" % (label, i) for i in range(len(items)))))
    for i, t in enumerate(items):
        f.write(asm_string("%s_%d" % (label, i), t, keep_cr=True))


def main():
    gd = E.GameData()
    es = E.LANG == "es"
    screen = gd.cps("CCARGEN.CPS" if es else "CHARGEN.CPS")
    parts = gd.cps("CCARGENB.CPS" if es else "CHARGENB.CPS")
    vga = gd.palette("EOBPAL.COL")

    cg_y = level1_cache_row()
    assert cg_y + CG_ROWS + 96 <= 1000, "chargen: no room in the shape cache of level 1"

    srows = [list(screen[y * 320:(y + 1) * 320]) for y in range(200)]
    panel = piece(screen, PANEL, False)
    bottom = piece(parts, BOTTOM, True)
    sparks = piece(parts, SPARKS, True)
    hl_row = [list(HIGHLIGHT)]
    pal, lut = C.build_palette(vga, [srows, bottom, sparks, hl_row])
    with open(BUILD / "CHARGEN.PAL", "wb") as f:
        for c in pal:
            f.write(bytes(c))

    recs = []
    px = C.to_pixels(srows, lut)
    for r in range(200):
        recs.append(((C.SCREEN_Y + r) * C.IMG_W + C.SCREEN_X, px[r * 320:(r + 1) * 320]))
    places = (("CG_PANEL", 0, 0, panel), ("CG_BOTTOM", 160, 0, bottom), ("CG_SPARKS", 160, 72, sparks))
    for name, x, y, rows in places:
        p = C.to_pixels(rows, lut)
        w = len(rows[0])
        for r in range(len(rows)):
            recs.append(((cg_y + y + r) * C.IMG_W + x, p[r * w:(r + 1) * w]))
    C.write_v9(BUILD / "CHARGEN.V9", recs)

    with open(BUILD / "chargen.inc", "w") as f:
        f.write("; chargen.inc - generated by tools/conv_chargen.py\n")
        f.write("CG_Y:\tequ %d\t\t; the rows CG_Y .. CG_Y + CG_ROWS - 1 (shape cache of level 1)\n" % cg_y)
        f.write("CG_ROWS:\tequ %d\n" % CG_ROWS)
        for name, x, y, rows in places:
            f.write("%s_X:\tequ %d\n%s_Y:\tequ %d\n" % (name, x, name, cg_y + y))
        f.write(db("CG_HILITE", [lut[v] for v in HIGHLIGHT]))
        f.write("CG_HILITE_N:\tequ %d\n" % len(HIGHLIGHT))
        f.write("CG_C_LIGHTBLUE:\tequ %d\n" % lut[GUI_COLOURS["lightblue"]])
        # texts
        strings(f, "CG_S1", string_list(gd, "kEoBBaseChargenStrings1"))
        s2 = string_list(gd, "kEoBBaseChargenStrings2")
        f.write(asm_string("CG_RACE_T", s2[8]))
        f.write(asm_string("CG_CLASS_T", s2[9]))
        f.write(asm_string("CG_ALIGN_T", s2[10]))
        f.write(asm_string("CG_NAME_T", s2[11]))
        strings(f, "CG_STAT", string_list(gd, "kEoBBaseChargenStatStrings")[:6])
        strings(f, "CG_RACE", string_list(gd, "kEoBBaseChargenRaceSexStrings"))
        strings(f, "CG_CLASS", string_list(gd, "kEoBBaseChargenClassStrings")[:15])
        strings(f, "CG_ALIGN", string_list(gd, "kEoBBaseChargenAlignmentStrings"))
        f.write(asm_string("CG_ENTER", string_list(gd, "kEoBBaseChargenEnterGameStrings")[0], keep_cr=True))
        # tables
        f.write(db("CG_START_LEVELS", gd.table("kEoBBaseChargenStartLevels")))
        f.write(db("CG_CLASS_MIN", gd.table("kEoBBaseChargenClassMinStats")))
        f.write(db("CG_RACE_MIN", gd.table("kEoBBaseChargenRaceMinStats")))
        mx = gd.table("kEoBBaseChargenRaceMaxStats")      # big-endian u16: ext << 8 | value
        f.write("; per race 6 x (maximum, exceptional strength)\n")
        f.write(db("CG_RACE_MAX", [mx[i + 1 - k] for i in range(0, len(mx), 2) for k in (0, 1)]))
        f.write(db("CG_RACE_MOD", RACE_MOD, signed=True))
        f.write("CG_CLASS_MASKS:\tdw %s\n" % ",".join(str(v) for v in CLASS_MENU_MASKS))
        f.write("CG_ALIGN_MASKS:\tdw %s\n" % ",".join(str(v) for v in ALIGN_MENU_MASKS))
        f.write(db("CG_HP_INCR", HP_INCR))
        f.write(db("CG_HP_CON", HP_CON_MOD, signed=True))
        f.write(db("CG_CLASS_TYPE", CLASS_TYPE, signed=True))
        f.write(db("CG_DEX_AC", DEX_AC_MOD, signed=True))
        f.write(db("CG_ITEMS", ITEM_LIST, signed=True))
        f.write(db("CG_ITEMS_IDX", ITEM_LIST_INDEX, signed=True))
    print("chargen: cache rows from %d, %d colours" % (cg_y, len(pal)))


if __name__ == "__main__":
    main()
