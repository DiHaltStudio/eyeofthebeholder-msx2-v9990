#!/usr/bin/env python3
"""conv_global.py - Data shared by all the levels.

  * the fixed part of the palette (entries 2..FIXED_N+1): user interface,
    portraits, item icons, fonts; computed once so that every level shows
    the interface with the same colours (build/fixed.json);
  * UI.V9: the playfield frame (PLAYFLD.CPS) written to the screen rows;
  * GLOBAL.SHP + GLOBAL.DAT: RAM shapes used by the interface (portraits,
    item icons, character box templates), ids GLOBAL_ID + n;
  * PARTY.DAT: the characters of the original save file (EOBDATA.SAV) with
    the starting equipment that character generation gives (new game);
  * ITEMS.DAT: the item table at the start of a new game (ITEM.DAT plus the
    copies made for the party), ITEM_MAX records of I_SIZE bytes;
  * ITEMNAME.DAT: the item names (ASCIIZ, one after the other);
  * floor item shapes: ITEML1 / ITEMS1 in 4 sizes, cropped to their pixels
    (itemshp.inc gives the crop offsets and the original sizes);
  * font.inc / gui.inc: FONT6 glyphs and the interface colours/coordinates.

GLOBAL.DAT: u16 number of shapes, then 8 bytes per shape:
  vx = address in page 2 (8000h + offset), vy = FFFEh, w, h, segment, 0
The global segments come first in SEGTAB; the level shapes follow them.
"""
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eoblib as E
import conv_level as C

BUILD = C.BUILD
GLOBAL_ID = 512
NUM_FACES = 44
NPC_FACES = 9                 # OUTTAKE.CPS portraits of the NPCs (portrait -1..-9)
NUM_ICONS = 89

# KyraRpgGUISettings (EoBEngine::_guiSettingsVGA): VGA colour indexes
GUI_COLOURS = dict(frame1=135, frame2=130, fill=132, sfill=180, bargraph=133,
                   warn1=17, warn2=23, warnfill=20,
                   white=15, lightred=6, darkred=8, lightblue=9, blue=2, darkblue=11,
                   yellow=5, lightgreen=4, darkgreen=3, purple=1, brown=7, black=12,
                   inact1=184, inact2=177, inactfill=180)

CLASS_TYPE_DB = "0,-1,-1,5,-1,-1,4,-1,-1,1,-1,-1,2,-1,-1,3,-1,-1,0,2,-1,0,3,-1,0,1,-1,0,1,3,3,1,-1,2,3,-1,0,2,1,5,2,-1,2,1,-1"

# party record in PARTY.DAT (128 bytes)
P_FLAGS, P_NAME, P_HP, P_HPMAX, P_FACE, P_CLASS, P_FOOD, P_AC = 0, 1, 12, 13, 14, 17, 18, 19
P_STR, P_STREXT, P_DEX, P_LEVEL, P_RACE = 20, 21, 22, 23, 24
P_STATUS0, P_STATUS1, P_TIMER0, P_TIMER1, P_DISABLED, P_DAMAGE, P_DMGTIMER = 33, 34, 35, 36, 37, 38, 39
P_CON = 25                 # constitution
P_EXP = 40                 # 3 x u32 experience (one per class of a multi-class)
P_LEVELS = 52              # 3 class levels
P_INV = 64                 # 27 x u16 item numbers (0, 1 the hands, 17 armour ...)
P_EFFECT = 118             # u32 spell effect flags
P_EFFREM = 122             # armor spell: hits it still takes (effectsRemainder[0])
P_MKNOWN = 123             # u32 the mage spells the character knows (mageSpellsAvailableFlags)
P_WIS = 26                 # wisdom
P_AID = 28                 # hit points of the aid spell (effectsRemainder[3])
P_ALIGN = 29               # alignment
P_CHA = 30                 # charisma
P_INT = 27                 # intelligence
P_SIZE = 128

# item record in ITEMS.DAT (EoBItem)
ITEM_MAX, I_SIZE = 500, 14
I_NAMEUNID, I_NAMEID, I_FLAGS, I_ICON, I_TYPE, I_POS, I_BLOCK, I_NEXT, I_PREV, I_LEVEL, I_VALUE = \
    0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 13
ITEM_FMT = "<BBBbbbhhhBb"

LARGE_N, SMALL_N = 14, 23     # floor item shapes of ITEML1 / ITEMS1
THROWN_N = 12                 # flying object shapes of THROWN (after the item shapes)


def main():
    gd = E.GameData()
    BUILD.mkdir(exist_ok=True)
    vgapal = gd.palette("BRICK.PAL")      # the interface indexes are the same in all level palettes

    shapes = []   # (name, rows)
    faces = gd.cps("CHARGENA.CPS")
    for i in range(NUM_FACES):
        rows = C.crop_rows(faces, (i % 10) * 32, (i // 10) * 32, 32, 32)
        shapes.append(("face%d" % i, opaque(rows)))
    outtake = gd.cps("OUTTAKE.CPS")
    for i in range(NPC_FACES):
        shapes.append(("face%d" % (NUM_FACES + i), opaque(C.crop_rows(outtake, i * 32, 160, 32, 32))))
    icons = gd.cps("ITEMICN.CPS")
    for i in range(NUM_ICONS):
        shapes.append(("icon%d" % i, C.crop_rows(icons, (i % 20) * 16, (i // 20) * 16, 16, 16)))
    inv = gd.cps("INVENT.CPS")
    shapes.append(("box0", opaque(C.crop_rows(inv, 176, 168, 64, 24))))
    shapes.append(("box1", opaque(C.crop_rows(inv, 240, 168, 64, 26))))
    thrown = gd.cps("THROWN.CPS")
    shapes.append(("redsplat", C.crop_rows(thrown, 128, 144, 40, 24)))
    shapes.append(("greensplat", C.crop_rows(thrown, 128, 168, 40, 16)))
    item_info = []
    for n, rows, info in item_shapes(gd):
        shapes.append((n, rows))
        item_info.append(info)
    deco = gd.cps("DECORATE.CPS")
    shapes.append(("deadchar", C.crop_rows(deco, 0, 88, 32, 32)))
    shapes.append(("disabledgrid", C.crop_rows(deco, 32, 88, 32, 32)))
    shapes.append(("weapongrid", C.crop_rows(deco, 64, 88, 32, 16)))
    shapes.append(("smallgrid", C.crop_rows(deco, 72, 88, 16, 8)))   # _blackBoxSmallGrid
    # the sparkles of the teleporters (EoBCoreEngine::_teleporterShapeDefs)
    for i, (x, y, w, h) in enumerate(((12, 88, 2, 14), (12, 103, 1, 7), (12, 111, 1, 7),
                                      (12, 119, 1, 5), (12, 125, 1, 5), (12, 131, 1, 3))):
        shapes.append(("tele%d" % i, C.crop_rows(deco, x * 8, y, w * 8, h)))

    ui = gd.cps("PLAYFLD.CPS")
    ui_rows = [list(ui[y * 320:(y + 1) * 320]) for y in range(200)]
    ui_rows[199] = [12] * 320          # the original never shows the last row
    compass = [C.crop_rows(deco, x * 24, dy, 24, dh) for dy, dh in zip((120, 137, 147), (17, 10, 10)) for x in range(4)]
    inv_rows = [list(inv[y * 320:(y + 1) * 320]) for y in range(200)]
    font_colours = [[GUI_COLOURS[k] for k in GUI_COLOURS]]
    fixed_rows = [ui_rows, inv_rows] + [s[1] for s in shapes] + compass + [font_colours * 64]
    fixed = C.quantize(C.pixel_colours(vgapal, fixed_rows), C.FIXED_N)
    cols = {}
    for rows in fixed_rows:
        for row in rows:
            for v in row:
                if v is not None:
                    k = C.rgb5(vgapal[v])
                    cols[k] = cols.get(k, 0) + 1
    # the interface colours are drawn by the program (texts, frames, the lit
    # buttons): each gets an entry of its own
    for v in GUI_COLOURS.values():
        k = C.rgb5(vgapal[v])
        cols[k] = cols.get(k, 0) + 5000
    fixed = C.refine_palette(fixed, cols, [(0, 0, 0)], iters=24)
    json.dump(fixed, open(BUILD / "fixed.json", "w"))
    pal = [(0, 0, 0), (0, 0, 0)] + fixed

    def lut_of(v):
        c = C.rgb5(vgapal[v])
        return C.C_BLACK if c == (0, 0, 0) else 1 + C.nearest_lab(pal[1:], c)
    lut = [lut_of(v) for v in range(256)]

    # --- UI frame ---
    C.write_ui(ui_rows, lut)

    # --- RAM shapes ---
    # Precoloured detection variants share the existing fixed blue palette.
    # Append them so original shape IDs stay stable. Runtime selects a shape;
    # no per-frame pixel recolouring or level-palette replacement is needed.
    for i in range(NUM_ICONS):
        rows = C.crop_rows(icons, (i % 20) * 16, (i // 20) * 16, 16, 16)
        def blue(v):
            if v is None:
                return None
            brightness = max(vgapal[v])
            return GUI_COLOURS['darkblue' if brightness < 20 else
                               'blue' if brightness < 42 else 'lightblue']
        shapes.append(("blueicon%d" % i, [[blue(v) for v in row] for row in rows]))
    normal_count = len(shapes) - NUM_ICONS
    ram = bytearray()
    table = bytearray(struct.pack("<H", len(shapes)))
    ids = {}
    for n, (name, rows) in enumerate(shapes):
        ids[name] = GLOBAL_ID + n
        if not rows:                       # nothing left after cropping
            table += struct.pack("<HHBBBB", 0xFFFF, 0xFFFF, 0, 0, 0, 0)
            continue
        px = C.rle_shape(C.to_pixels(rows, lut), len(rows[0]))
        if (len(ram) & 0x3FFF) + len(px) > 0x4000:
            ram += bytes(0x4000 - (len(ram) & 0x3FFF))
        table += struct.pack("<HHBBBB", 0x8000 + (len(ram) & 0x3FFF), 0xFFFE, len(rows[0]), len(rows), len(ram) >> 14, 0)
        ram += px
    nsegs = (len(ram) + 0x3FFF) >> 14
    # Keep the additional descriptors in the effects bank, not scarce
    # resident GLOBALDAT. Their synthetic IDs still key the normal cache.
    blue_entries = table[2 + normal_count * 8:]
    table = bytearray(struct.pack('<H', normal_count)) + table[2:2 + normal_count * 8]
    with open(BUILD / 'blueicons.inc', 'w') as f:
        f.write('FX_BLUE_SHAPES:\n')
        for j in range(0, len(blue_entries), 8):
            f.write(' db ' + ','.join(map(str, blue_entries[j:j + 8])) + '\n')
    open(BUILD / "GLOBAL.SHP", "wb").write(ram)
    open(BUILD / "GLOBAL.DAT", "wb").write(table)
    json.dump({"segments": nsegs, "ids": ids}, open(BUILD / "global.json", "w"))
    print("global: %d shapes, %d KB in %d segments" % (len(shapes), len(ram) // 1024, nsegs))

    # --- items and party (new game) ---
    items = load_items(gd)
    write_party(gd, items)
    write_items(gd, items)
    write_item_shapes(gd, ids, item_info)

    # --- includes ---
    with open(BUILD / "gui.inc", "w") as f:
        f.write("; gui.inc - generated by tools/conv_global.py\n")
        f.write("GLOBAL_ID:\tequ %d\nGLOBAL_SEGS:\tequ %d\nGLOBAL_N:\tequ %d\n" % (GLOBAL_ID, nsegs, normal_count))
        for name in ("face0", "icon0", "blueicon0", "box0", "box1", "deadchar", "disabledgrid", "weapongrid", "tele0", "smallgrid",
                     "redsplat", "greensplat", "item0_0"):
            f.write("SHP_%s:\tequ %d\n" % (name.upper(), ids[name]))
        for k, v in GUI_COLOURS.items():
            f.write("C_%s:\tequ %d\n" % (k.upper(), lut[v]))
        for k in ("P_FLAGS", "P_NAME", "P_HP", "P_HPMAX", "P_FACE", "P_CLASS",
                  "P_FOOD", "P_AC", "P_STR", "P_STREXT", "P_DEX", "P_LEVEL", "P_RACE",
                  "P_STATUS0", "P_STATUS1", "P_TIMER0", "P_TIMER1", "P_DISABLED", "P_DAMAGE", "P_DMGTIMER",
                  "P_INV", "P_EXP", "P_LEVELS", "P_CON", "P_EFFECT", "P_EFFREM", "P_MKNOWN", "P_WIS", "P_INT", "P_SIZE", "ITEM_MAX", "I_SIZE", "I_NAMEUNID", "I_NAMEID", "I_FLAGS", "I_ICON",
                  "I_TYPE", "I_POS", "I_BLOCK", "I_NEXT", "I_PREV", "I_LEVEL", "I_VALUE", "P_AID", "P_ALIGN", "P_CHA"):
            f.write("%s:\tequ %d\n" % (k, globals()[k]))
    with open(BUILD / "vgalut.inc", "w") as f:
        f.write("; vgalut.inc - VGA colour index -> palette entry (interface part), generated by tools/conv_global.py\nVGA_LUT:\n")
        for i in range(0, 256, 16):
            f.write("\tdb " + ",".join(str(v) for v in lut[i:i + 16]) + "\n")
    arrow = C.crop_rows(icons, 0, 0, 16, 16)
    with open(BUILD / "cursor.inc", "w") as f:
        f.write("PTR_ARROW_MASKS:\n")
        for shades in ((14, 15), (12, 13)):
            for row in arrow:
                bits = sum(1 << (15 - x) for x, pixel in enumerate(row) if pixel in shades)
                f.write(f"\tdb {bits >> 8},{bits & 255},0,0\n")
            f.write("\tds 64,0\n")
    write_font()
    write_strings(gd)
    write_ui_data(gd, lut, inv_rows)
    write_fade_tables(vgapal, pal, lut)
    write_magic_data(gd)
    write_effect_data(gd)
    write_npc_data(gd, items)
    write_title(gd)


def string_list(gd, name):
    d = gd.table(name)
    n = struct.unpack_from(">I", d)[0]
    return [x.decode("latin1") for x in d[4:].split(b"\0")[:n]]


def asm_string(label, text, keep_cr=False):
    """keep_cr: True keeps the inner CR (line breaks), "lead" the leading
    ones too (an empty first line, as the camp's text boxes show it)."""
    if keep_cr == "lead":
        text = text.rstrip("\r")
    elif keep_cr:
        text = text.strip("\r")
    else:
        text = text.replace("\r", "")
    out = []
    for ch in text:
        out.append(str(ord(ch) & 0x7F if ch != "\r" else 13))
    return "%s:\tdb %s\n" % (label, ",".join(out + ["0"]))


def write_lang():
    """lang.inc: the folder of the files that depend on the language (ES, EN)
    and the levels whose LEVELn.LVL is there (those with their own texts:
    LEVELn.INF in pc_en/, the Spanish LEVELn.DRO in pc/)."""
    mask = 0
    for p in list(E.LANGS["en"][1].glob("LEVEL*.INF")) + list(E.PC.glob("LEVEL*.DRO")):
        mask |= 1 << (int(p.stem[5:]) - 1)
    with open(BUILD / "lang.inc", "w") as f:
        f.write("; lang.inc - generated by tools/conv_global.py\n")
        f.write("LANG_C1:\tequ %d\t\t; the folder: %s\nLANG_C2:\tequ %d\n" % (
            ord(E.LANG[0].upper()), E.LANG.upper(), ord(E.LANG[1].upper())))
        f.write("LVL_LANG:\tequ %d\t\t; bit n-1: LEVELn.LVL in the folder\n" % mask)


def write_strings(gd):
    write_lang()
    with open(BUILD / "strings.inc", "w") as f:
        f.write("; strings.inc - texts of the %s version (generated by tools/conv_global.py)\n" % E.LANG)
        warn = string_list(gd, "kEoBBaseWarningStrings")
        f.write(asm_string("STR_CANTGO", warn[0]))
        hp = string_list(gd, "kEoBBaseCharGuiStringsHp")
        f.write(asm_string("STR_HP", hp[0]))
        wp = string_list(gd, "kEoBBaseCharGuiStringsWp1")
        wr = string_list(gd, "kEoBBaseCharGuiStringsWr")
        f.write(asm_string("STR_MISS", wp[0]))
        f.write(asm_string("STR_HACK", wp[1]))
        f.write(asm_string("STR_NOREACH1", wr[0]))
        f.write(asm_string("STR_NOREACH2", wr[1]))
        f.write(asm_string("STR_NOAMMO1", wr[2]))
        f.write(asm_string("STR_NOAMMO2", wr[3]))
        pry = string_list(gd, "kEoBBasePryDoorStrings")
        f.write(asm_string("STR_TOOBIG", pry[5]))
        f.write(asm_string("STR_PRY0", pry[0]))
        f.write(asm_string("STR_PRY1", pry[1]))
        f.write(asm_string("STR_PRY3", pry[3]))
        f.write(asm_string("STR_NOPRY", pry[6]))
        f.write(asm_string("STR_NODROP", string_list(gd, "kEoBBaseValidateNoDropString")[0]))
        f.write(asm_string("STR_TAKEN", string_list(gd, "kEoBBaseTakenStrings")[0]))
        misuse = string_list(gd, "kEoBBaseItemMisuseStrings")
        f.write(asm_string("STR_MISUSE1", misuse[1]))
        f.write(asm_string("STR_MISUSE2", misuse[2]))
        # a touch spell without a monster in front (a message of this port)
        f.write(asm_string("STR_NOMONSTER", {"es": "No hay ningun monstruo delante.",
                                             "en": "There is no monster in front."}[E.LANG]))
        f.write("; class -> class flags (1 fighter, 2 mage, 4 cleric, 8 thief)\nCLASS_FLAGS:\n\tdb " +
                ",".join(str(v) for v in gd.table("kEoBBaseClassModifierFlags")) + "\n")
    # item types: extraProperties & 7Fh, small dice (n, pips, inc), large dice (n, pips)
    d = gd.get("ITEMTYPE.DAT")
    n = struct.unpack_from("<H", d)[0]
    with open(BUILD / "itemtypes.inc", "w") as f:
        f.write("; itemtypes.inc - ITEMTYPE.DAT (generated by tools/conv_global.py)\n")
        f.write("; 16 bytes: extra properties & 7Fh, small dice n, pips, inc, large dice n, pips, inc,\n")
        f.write("; allowed classes, inventory slot flags (u16), hand flags (u16), armour class, hands,\n")
        f.write("; extra properties & 80h (metal: rust eats it), 0\n")
        f.write("IT_EP:\tequ 0\nIT_DICE_S:\tequ 1\nIT_DICE_L:\tequ 4\nIT_CLASSES:\tequ 7\nIT_INVF:\tequ 8\n"
                "IT_HANDF:\tequ 10\nIT_AC:\tequ 12\nIT_HANDS:\tequ 13\nIT_METAL:\tequ 14\nITEMTYPES:\n")
        for i in range(n):
            r = struct.unpack_from("<HHbbbbbbbbbBH", d, 2 + i * 16)
            f.write("\tdb %d,%d,%d,%d,%d,%d,%d,%d\n\tdw %d,%d\n\tdb %d,%d,%d,0\n" % (
                r[12] & 0x7F, r[5], r[6], r[7], r[8], r[9], r[10], r[3] & 0xFF, r[0], r[1], r[2], r[4],
                r[12] & 0x80))
        f.write("; inventory slot -> the item flags it accepts (_slotValidationFlags)\nSLOT_FLAGS:\n")
        f.write("\tdw " + ",".join(str(v & 0xFFFF) for v in gd.table16("kEoBBaseSlotValidationFlags")) + "\n")
        # monster properties (27 bytes each, EoBEngine::initStaticResource layout)
        props = gd.table("kEoB1MonsterProperties")
        f.write("; monster properties, 27 bytes each: ac, hitChance, level, attacks, 3 x (n, pips, inc),\n")
        f.write("; -, capsFlags, typeFlags (4), experience (2), u30, sound1, sound2, remote, tuResist, evade\n")
        f.write("MONPROPS:\n")
        for i in range(len(props) // 27):
            f.write("\tdb " + ",".join(str(v) for v in props[i * 27:(i + 1) * 27]) + "\n")
        for name, label in (("kEoBBaseMonsterStepTable2", "MON_STEPTAB2"), ("kEoBBaseMonsterStepTable3", "MON_STEPTAB3"),
                            ("kEoBBaseMonsterCloseAttPosTable1", "MON_CAPOS1"), ("kEoBBaseMonsterCloseAttPosTable21", "MON_CAPOS2"),
                            ("kEoBBaseMonsterCloseAttChkTable1", "MON_CACHK1"), ("kEoBBaseMonsterCloseAttChkTable2", "MON_CACHK2"),
                            ("kEoBBaseMonsterCloseAttDstTable1", "MON_CADST1"), ("kEoBBaseMonsterCloseAttDstTable2", "MON_CADST2"),
                            ("kEoBBaseMonsterProximityTable", "MON_PROXIMITY"), ("kEoBBaseMonsterDirChangeTable", "MON_DIRCHANGE")):
            f.write(label + ":\n\tdb " + ",".join(str(E.signed8(v)) for v in gd.table(name)[:48]) + "\n")


rle_row = C.rle_row


# EoBEngine::initSpells flag table: type flags, effect flags, damage flags
SPELL_FLAGS = [
    (0x0000, 0x000000, 0x00), (0x0033, 0x000001, 0x00), (0x0100, 0x000000, 0x21), (0x004C, 0x000002, 0x00),
    (0x0100, 0x000000, 0x01), (0x0000, 0x000000, 0x00), (0x008B, 0x000008, 0x00), (0x0488, 0x000000, 0x03),
    (0x0021, 0x000040, 0x00), (0x0000, 0x000000, 0x00), (0x0100, 0x000000, 0x11), (0x0000, 0x000000, 0x00),
    (0x00A0, 0x000000, 0x00), (0x0100, 0x000000, 0x21), (0x0100, 0x000000, 0x11), (0x0040, 0x000000, 0x00),
    (0x0100, 0x000000, 0x00), (0x0240, 0x000040, 0x00), (0x0100, 0x000000, 0x03), (0x0488, 0x000000, 0x01),
    (0x0100, 0x000000, 0x00), (0x0100, 0x000000, 0x41), (0x0033, 0x000001, 0x00), (0x0000, 0x000000, 0x00),
    (0x0100, 0x000000, 0x41), (0x0100, 0x000000, 0x00), (0x005C, 0x000400, 0x00), (0x0020, 0x000000, 0x00),
    (0x0100, 0x000000, 0x01), (0x004C, 0x000002, 0x00), (0x0029, 0x000800, 0x00), (0x0039, 0x000000, 0x00),
    (0x2408, 0x000000, 0x21), (0x0100, 0x000000, 0x00), (0x0028, 0x002000, 0x00), (0x0040, 0x000000, 0x00),
    (0x00A0, 0x000000, 0x00), (0x0099, 0x004000, 0x00), (0x004C, 0x008000, 0x00), (0x0040, 0x000000, 0x00),
    (0x0020, 0x000000, 0x00), (0x0100, 0x000000, 0x01), (0x0020, 0x000000, 0x00), (0x0248, 0x000800, 0x00),
    (0x0000, 0x000000, 0x00), (0x0020, 0x000000, 0x00), (0x0100, 0x000000, 0x01), (0x0100, 0x000000, 0x21),
    (0x0020, 0x000000, 0x00), (0x0020, 0x000000, 0x00), (0x0000, 0x000000, 0x00), (0x0000, 0x000000, 0x00),
    (0x0000, 0x000000, 0x00)]


def write_title(gd):
    """TITLE.V9 + TITLE.PAL: INTRO.CPS with EOBPAL.COL; the bottom (copyright)
    rows are cleared as the main menu does; colours of the menu boxes and
    of the cleared area go to magicdata.inc."""
    img = gd.cps("INTRO.CPS")
    vga = gd.palette("EOBPAL.COL")
    rows = [list(img[y * 320:(y + 1) * 320]) for y in range(200)]
    bg = rows[0][0]
    for y in range(159, 200):
        rows[y] = [bg] * 320
    pal, lut = C.build_palette(vga, [rows])
    with open(BUILD / "TITLE.PAL", "wb") as f:
        for c in pal:
            f.write(bytes(c))
    px = C.to_pixels(rows, lut)
    C.write_v9(BUILD / "TITLE.V9", [((C.SCREEN_Y + r) * C.IMG_W + C.SCREEN_X, px[r * 320:(r + 1) * 320])
                                     for r in range(200)])
    with open(BUILD / "magicdata.inc", "a") as f:
        f.write("TITLE_BG:\tequ %d\nTITLE_C12:\tequ %d\nTITLE_C13:\tequ %d\nTITLE_C14:\tequ %d\n" % (
            lut[bg], lut[12], lut[13], lut[14]))
        for i, t in enumerate(string_list(gd, "kEoB1MainMenuStrings")[:3]):
            f.write(asm_string("STR_TITLE%d" % i, t))


def write_npc_data(gd, items):
    """TEXT.DAT (7-bit text) and, appended to magicdata.inc, the NPC presets
    and the texts of the dialogues (EoBEngine::runNpcDialogue)."""
    d = bytearray(gd.get("TEXT.DAT"))
    first = struct.unpack_from("<H", d)[0]
    for i in range(first, len(d)):
        d[i] &= 0x7F
    open(BUILD / "TEXT.DAT", "wb").write(d)
    pre = bytes(gd.table("kEoBBaseNpcPresets"))
    names = string_list(gd, "kEoBBaseNpcPresetsNames")
    with open(BUILD / "magicdata.inc", "a") as f:
        f.write("; NPC presets (party records), EoB npcPreset\nNPC_PRESETS:\n")
        for i in range(struct.unpack_from(">H", pre)[0]):
            c = pre[2 + i * 100:2 + (i + 1) * 100]
            rec = bytearray(P_SIZE)
            rec[P_FLAGS] = c[1]
            name = names[i].encode("latin1")[:10]
            rec[P_NAME:P_NAME + len(name)] = name
            rec[P_HP] = struct.unpack_from(">h", c, 16)[0] & 0xFF
            rec[P_HPMAX] = struct.unpack_from(">h", c, 18)[0] & 0xFF
            rec[P_FACE] = NUM_FACES - 1 - struct.unpack("b", c[25:26])[0]
            rec[P_STR], rec[P_STREXT], rec[P_INT], rec[P_WIS] = c[2], c[4], c[6], c[8]
            rec[P_DEX], rec[P_CON] = c[10], c[12]
            rec[P_RACE], rec[P_CLASS] = c[22], c[23]
            rec[P_CHA], rec[P_ALIGN] = c[14], c[24]
            rec[P_LEVEL] = c[27]
            rec[P_LEVELS:P_LEVELS + 3] = c[27:30]
            struct.pack_into("<3I", rec, P_EXP, *struct.unpack_from(">3I", c, 30))
            struct.pack_into("<I", rec, P_MKNOWN, struct.unpack_from(">I", c, 42)[0])
            inv = struct.unpack_from(">27h", c, 46)
            struct.pack_into("<27H", rec, P_INV, *(v & 0xFFFF for v in inv))
            rec[P_FOOD] = 100
            rec[P_AC] = armor_class(gd, items, inv, c[23], c[10]) & 0xFF
            f.write("\tdb " + ",".join(str(v) for v in rec) + "\n")
        f.write(asm_string("STR_NPCMAX", string_list(gd, "kEoBBaseNpcMaxStrings")[0]))
        f.write(asm_string("STR_NPCJOIN", string_list(gd, "kEoBBaseNpcJoinStrings")[0].split("%s ")[1]))
        f.write(asm_string("STR_MORE", string_list(gd, "kRpgCommonMoreStrings")[0]))
    # the statistics page of the inventory (gui_drawCharacterStatsPage,
    # stats.asm in the script overlay)
    with open(BUILD / "statsdata.inc", "w") as f:
        f.write("; statsdata.inc - generated by tools/conv_global.py\n")
        f.write("ST_CTYPE:\n\tdb 0,-1,-1,5,-1,-1,4,-1,-1,1,-1,-1,2,-1,-1,3,-1,-1,0,2,-1,0,3,-1,0,1,-1,0,1,3,3,1,-1,2,3,-1,0,2,1,5,2,-1,2,1,-1\n")
        for lab, key in (("ST_GUI", "kEoBBaseCharGuiStringsIn"), ("ST_STAT", "kEoBBaseChargenStatStrings"),
                         ("ST_RACE", "kEoBBaseChargenRaceSexStrings"), ("ST_CLASS", "kEoBBaseChargenClassStrings"),
                         ("ST_ALIGN", "kEoBBaseChargenAlignmentStrings")):
            lst = [x for x in string_list(gd, key) if x]
            f.write("%s:\tdw %s\n" % (lab, ",".join("%s_%d" % (lab, i) for i in range(len(lst)))))
            for i, t in enumerate(lst):
                f.write(asm_string("%s_%d" % (lab, i), t))
        # the rust monster (rust.asm, also in the script overlay)
        rip = string_list(gd, "kEoBBaseRipItemStrings")     # "<name> has lost her / his <item>."
        f.write(asm_string("STR_RIP_F", rip[0].split("%s")[1]))
        f.write(asm_string("STR_RIP_M", rip[1].split("%s")[1]))
        f.write(asm_string("STR_RIP_END", rip[2]))
    with open(BUILD / "magicdata.inc", "a") as f:
        seq = list(gd.table("kEoBBasePortalSeqData"))
        f.write("; the portal: (strips, middle) pairs until FFh (_portalSeq)\nPORTAL_SEQ:\n\tdb " +
                ",".join(str(v) for v in seq[:seq.index(255) + 1]) + "\n")
        fb = string_list(gd, "kEoB1BonusStrings")
        for lab, t in (("FIN_B0", fb[0]), ("FIN_B1", fb[1]), ("FIN_B2", fb[2].split("%04x")[0]),
                       ("FIN_B3", fb[2].split("%04x")[1])):
            f.write("%s:\tdb %s\n" % (lab, ",".join([str(ord(ch) & 0x7F) for ch in t] + ["0"])))
        yn = string_list(gd, "kEoBBaseYesNoStrings")
        sets = [string_list(gd, n) for n in ("kEoB1Npc0Strings", "kEoB1Npc11Strings", "kEoB1Npc12Strings",
                                            "kEoB1Npc21Strings", "kEoB1Npc22Strings", "kEoB1Npc31Strings",
                                            "kEoB1Npc32Strings", "kEoB1Npc4Strings", "kEoB1Npc5Strings",
                                            "kEoB1Npc6Strings", "kEoB1Npc7Strings")]
        sets.append(yn[:2])
        f.write("; button sets of the dialogues (npcStrings 1..10, 11 = yes / no)\nDLG_SETS:\n")
        f.write("\tdw " + ",".join("DLG_SET%d" % i for i in range(len(sets))) + "\n")
        for i, st in enumerate(sets):
            st = [x for x in st if x]
            f.write("DLG_SET%d:\tdb %d\n" % (i, len(st)))
            for k, t in enumerate(st):
                f.write(asm_string("DLG_S%d_%d" % (i, k), t.replace("\r", " ").strip() if i else t, keep_cr=True))


def write_effect_data(gd):
    with open(BUILD / "effectdata.inc", "w") as f:
        # Each DOS AdLib program begins with its driver channel and priority.
        # These are independent of the register stream's aggregate voice mask.
        adlib = gd.get("ADLIB.DAT")
        f.write("FX_ADLIB_PROGRAMS:\n")
        for program in adlib[:120]:
            if program == 255:
                f.write("\tdb 255,0\n")
            else:
                offset = 120 + struct.unpack_from("<H", adlib, 120 + program * 2)[0]
                channel, priority = adlib[offset:offset + 2]
                f.write(f"\tdb {channel},{priority}\n")
        for label, texts in {
            "FX_NOEFFECT_TEXT": ("No tiene efecto aqui.", "No effect here."),
            "FX_CLOUD_TEXT": ("Una nube venenosa cubre la casilla.", "A poisonous cloud covers the square."),
            "FX_MAGIC_TEXT": (" [MAGICO]", " [MAGIC]"),
        }.items():
            f.write(asm_string(label, texts[0 if E.LANG == "es" else 1]))
        for label, key in (("FX_POT_NAMES", "kEoBBaseItemSuffixStringsPotions"),
                           ("FX_WAND_NAMES", "kEoBBaseItemSuffixStringsWands"),
                           ("FX_RING_NAMES", "kEoBBaseItemSuffixStringsRings")):
            names = string_list(gd, key)
            f.write(label + ":\n\tdw " + ",".join(label+str(i) for i in range(len(names))) + "\n")
            f.write(label + "_COUNT: equ " + str(len(names)) + "\n")
            for i, name in enumerate(names):
                f.write(asm_string(label+str(i), name))


def write_magic_data(gd):
    """magicdata.inc (MAGIC overlay): spell names, flags, flight objects,
    texts, and the spells the party of the save file carries."""
    with open(BUILD / "magicdata.inc", "w") as f:
        f.write("; magicdata.inc - generated by tools/conv_global.py\n")
        names = string_list(gd, "kEoBBaseSpellNames")
        # EoBCoreEngine::initSpells: spells 5 and 9 have no name of their own
        full = []
        n = 0
        for i in range(len(SPELL_FLAGS)):
            if i in (5, 9):
                full.append(names[0])
                n -= 1
            else:
                full.append(names[n] if n < len(names) else "")
            n += 1
        full[5] = string_list(gd, "kEoBBaseMageSpellsList")[5]
        full[9] = string_list(gd, "kEoBBaseMageSpellsList")[9]
        f.write("SPELL_NAMES:\n\tdw " + ",".join("SPN_%d" % i for i in range(len(full))) + "\n")
        for i, nm in enumerate(full):
            f.write(asm_string("SPN_%d" % i, nm))
        for label, key in (("BOOK_MAGE", "kEoBBaseMageSpellsList"), ("BOOK_CLERIC", "kEoBBaseClericSpellsList")):
            lst = string_list(gd, key)
            f.write(label + ":\n\tdw " + ",".join("%s_%d" % (label, i) for i in range(len(lst))) + "\n")
            for i, nm in enumerate(lst):
                f.write(asm_string("%s_%d" % (label, i), nm))
        f.write("; per spell: type flags (u16), effect flags (u16; haste handled by FX event 53), damage flags\n")
        f.write("SPELL_TAB:\n")
        for spell_id, (t, e, d) in enumerate(SPELL_FLAGS):
            if spell_id in (11, 23):
                t |= 0x100  # offensive cloud casting breaks invisibility
            f.write("\tdw %d, %d\n\tdb %d\n" % (t, e & 0xFFFF if e < 0x10000 else 0x8000, d))
        fp = gd.table("kEoBBaseMagicFlightProps")[:48]
        f.write("; magic flights: spell of the hit, distance, flags, shape\nFLIGHT_PROPS:\n\tdb " +
                ",".join(str(v) for v in fp) + "\n")
        m1 = string_list(gd, "kEoBBaseMagicStrings1")
        f.write(asm_string("STR_ABORT", m1[0]))
        f.write(asm_string("STR_FREEHAND", m1[2]))
        f.write(asm_string("STR_TWOEFF", m1[3]))
        f.write(asm_string("STR_CASTS", m1[4].split("%s")[1]))
        m2 = string_list(gd, "kEoBBaseMagicStrings2")
        f.write(asm_string("STR_DISINT", m2[1].split("%s ")[1]))
        f.write(asm_string("STR_DEATHSPELL", m2[2]))
        da = string_list(gd, "kEoBBaseMonsterDistAttStrings")
        f.write(asm_string("STR_EYERAY", da[0].split("%s ")[1]))
        f.write(asm_string("STR_MINDBLAST", da[1]))
        f.write(asm_string("STR_NOEFFECT", string_list(gd, "kEoBBaseMagicStrings4")[0]))
        m3 = string_list(gd, "kEoBBaseMagicStrings3")
        f.write(asm_string("STR_CHOOSE", m3[0]))
        f.write(asm_string("STR_ABORTED", m3[2]))
        for lab, t in zip(("STR_EXPIRES0", "STR_EXPIRES", "STR_EXPIRES2"), m3[3].split("%s")):
            f.write(asm_string(lab, t))        # "<0><name><1><spell><2>"
        f.write(asm_string("STR_NOTFRONT", m3[5].split("%s", 1)[1]))
        st = string_list(gd, "kEoBBaseCharStatusStrings131")[0].split("%s")
        f.write(asm_string("STR_ES", st[1]))   # "<name> is <state>!"
        f.write(asm_string("STR_EXCL", st[2]))
        f.write(asm_string("STR_PARALYZED", da[-3]))
        f.write(asm_string("STR_POISONED", da[-2]))
        f.write(asm_string("STR_POISONHIT", string_list(gd, "kEoBBaseCharStatusStrings81")[0].split("%s ", 1)[1]))
        f.write(asm_string("STR_SWAPPING", string_list(gd, "kEoBBaseCharGuiStringsSt1")[0]))
        f.write(asm_string("STR_UNPARA", string_list(gd, "kEoBBaseCharStatusStrings9")[0].split("%s ", 1)[1]))
        # the rest of the camp menu (GUI_EoB::restParty, rest.asm)
        rest = string_list(gd, "kEoBBaseMenuStringsRest")
        rest2 = string_list(gd, "kEoBBaseMenuStringsRest2")
        f.write(asm_string("RS_S_HEAL", rest[0], "lead"))
        f.write(asm_string("RS_S_CONT", rest[1], True))
        f.write(asm_string("RS_S_TITLE", rest[2]))
        f.write(asm_string("RS_S_RESTED", rest[3], "lead"))
        f.write(asm_string("RS_S_POISON", string_list(gd, "kEoBBaseMenuStringsPoison")[0], True))
        f.write(asm_string("RS_S_STARVE", string_list(gd, "kEoBBaseMenuStringsStarve")[0], True))
        f.write(asm_string("RS_S_HOURS", rest2[3].split("%")[0]))
        # restParty_displayWarning: "\r%s\r" of a text that starts with \r
        near = "\r" + string_list(gd, "kEoBBaseMenuStringsRest4")[0] + "\r"
        f.write("RS_S_NEAR:\tdb %s\n" % ",".join([str(13 if ch == "\r" else ord(ch) & 0x7F) for ch in near] + ["0"]))
        # "%s obtiene %s.", "%s memoriza %s.", "%s cura a %s." in three parts
        for k in range(3):
            parts = rest2[k].rstrip("\r").split("%s")
            assert len(parts) == 3, rest2[k]
            for j, t in enumerate(parts):
                f.write(asm_string("RS_F%d_%d" % (k, j), t))
        props = gd.table("kEoBBaseSpellProperties")
        f.write("; the sound of each spell (spell properties, byte 17 of 19)\nSPELL_SND:\n\tdb " +
                ",".join(str(props[i * 19 + 17]) for i in range(len(props) // 19)) + "\n")
        ws = string_list(gd, "kEoBBaseWandStrings")
        f.write(asm_string("STR_WAND0", ws[0]))
        f.write(asm_string("STR_WAND1", ws[1]))
        f.write("WAND_TYPES:\n\tdb " + ",".join(str(v) for v in gd.table("kEoBBaseWandTypes")) + "\n")
        f.write("TU_EFFECT:\n\tdb " + ",".join(str(v) for v in gd.table("kEoBBaseTurnUndeadEffect")) + "\n")
        tu = string_list(gd, "kEoB1TurnUndeadString")[0]
        f.write(asm_string("STR_TURN", "".join(ch for ch in tu.split("%s")[1] if ord(ch) >= 32).strip()))
        f.write(asm_string("STR_DEFEAT", string_list(gd, "kEoBBaseMenuStringsDefeat")[0]))
        m8 = string_list(gd, "kEoBBaseMagicStrings8")
        f.write(asm_string("STR_BLESSED", m8[1]))
        f.write(asm_string("STR_DISPELLED", m8[0].split("%s ")[0]))
        f.write(asm_string("STR_DISPELLED2", m8[0].split("%s")[1]))
        f.write(asm_string("STR_AIDFAIL", m8[2]))
        f.write("CONE_DEST:\n")
        for k in range(1, 5):
            f.write("\tdb " + ",".join(str(E.signed8(v)) for v in gd.table("kEoBBaseConeOfColdDest%d" % k)) + "\n")
        tabs = string_list(gd, "kEoBBaseMagicStrings7")
        f.write("BOOK_TABS:\n\tdw " + ",".join("BTAB_%d" % i for i in range(5)) + "\n")
        for i, t in enumerate(tabs):
            f.write(asm_string("BTAB_%d" % i, t))
        f.write("MAGE_LEVELS:\n\tdb " + ",".join(str(v) for v in gd.table("kEoBBaseSpellLevelsMage")) + "\n")
        f.write("CLERIC_LEVELS:\n\tdb " + ",".join(str(v) for v in gd.table("kEoBBaseSpellLevelsCleric")) + "\n")
        for label, key in (("NUM_MAGE", "kEoBBaseNumSpellsMage"), ("NUM_CLERIC", "kEoBBaseNumSpellsCleric"),
                           ("NUM_WISADJ", "kEoBBaseNumSpellsWisAdj"), ("NUM_PAL", "kEoBBaseNumSpellsPal")):
            f.write(label + ":\n\tdb " + ",".join(str(v) for v in gd.table(key)) + "\n")
        # the spells of the party (stride 10 per level as the original keeps them)
        d = gd.get("EOBDATA.SAV")
        f.write("; per character: mage spells 5 x 10, cleric spells 5 x 10 (signed: < 0 used)\nCH_SPELLS:\n")
        for i in range(6):
            c = d[i * 243:(i + 1) * 243]
            out = []
            for base in (55, 85):
                for lv in range(5):
                    row = list(c[base + lv * 6:base + lv * 6 + 6]) + [0] * 4
                    out += row
            f.write("\tdb " + ",".join(str(E.signed8(v)) for v in out) + "\n")
        f.write("CH_MAGEKNOWN:\n")
        for i in range(6):
            c = d[i * 243:(i + 1) * 243]
            f.write("\tdd %d\n" % struct.unpack_from("<I", c, 115)[0])


def write_fade_tables(vgapal, pal, lut):
    """facetint.inc (magic overlay): FT_TABLES, the faces of the poisoned (green), the stoned
    (blue) and the invisible (dark): Screen_EoB::createFadeTable with the
    root colours and weights of the original, over the fixed palette
    entries (the faces use only those); 64 bytes per table."""
    out = []
    for root, weight in ((4, 75), (10, 85), (12, 200)):
        r, g, b = vgapal[root]
        w = weight >> 1
        rl = lut[root]
        t = list(range(64))
        for e in range(1, C.FIXED_N + 2):
            c = [v * 2 for v in pal[e]]
            tc = []
            for v, rv in zip(c, (r, g, b)):
                tmp = (((v - rv) * w) & 0xFFFF) << 1 & 0xFFFF
                tc.append((v - ((tmp >> 8) & 0xFF)) & 0xFF)
            best, col = 1 << 30, rl
            for ii in range(1, C.FIXED_N + 2):
                d = sum((pal[ii][k] * 2 - tc[k]) ** 2 for k in range(3))
                if d <= best and (ii == rl or ii != e):
                    best, col = d, ii
            t[e] = col
        out += t
    with open(BUILD / "facetint.inc", "w") as f:
        f.write("; facetint.inc - generated by tools/conv_global.py\n; faces: poisoned (green), stone (blue), invisible (dark), 64 entries each\nFT_TABLES:\n")
        for i in range(0, len(out), 32):
            f.write("\tdb " + ",".join(str(v) for v in out[i:i + 32]) + "\n")


def write_ui_data(gd, lut, inv_rows):
    """uidata.inc (UI overlay): the inventory page of INVENT.CPS (RLE rows),
    the inventory slot positions and the texts of the inventory."""
    with open(BUILD / "uidata.inc", "w") as f:
        f.write("; uidata.inc - generated by tools/conv_global.py\n")
        f.write("; inventory page: INVENT.CPS (176, 0) 144 x 168, rows in RLE (n: n bytes; 80h+n: n times one byte)\n")
        f.write("INVBG_X:\tequ 176\nINVBG_W:\tequ 144\nINVBG_H:\tequ 168\nINVBG:\n")
        total = 0
        for y in range(168):
            px = [lut[v] for v in inv_rows[y][176:320]]
            r = rle_row(px)
            total += len(r)
            f.write("\tdb " + ",".join(str(b) for b in r) + "\n")
        xs = gd.table16("kEoBBaseInvSlotX")
        ys = list(gd.table("kEoBBaseInvSlotY"))
        f.write("INV_SLOT_X:\n\tdw " + ",".join(str(v) for v in xs[:27]) + "\n")
        f.write("INV_SLOT_Y:\n\tdb " + ",".join(str(v) for v in ys[:27]) + "\n")
        st = string_list(gd, "kEoBBaseCharGuiStringsSt1")
        f.write(asm_string("STR_ST_DEAD", st[1]))
        f.write(asm_string("STR_ST_UNCON", st[2]))
        f.write(asm_string("STR_ST_POISON", st[4]))
        f.write(asm_string("STR_ST_PARA", st[5]))
        f.write(asm_string("STR_VAL_ARMOR", string_list(gd, "kEoBBaseValidateArmorString")[0].replace("%s ", "")))
        warn = string_list(gd, "kEoBBaseWarningStrings")
        f.write(asm_string("STR_NOEAT", warn[1].replace("%s ", "")))
        f.write(asm_string("STR_EATFOOD", warn[2]))
        gain = string_list(gd, "kEoBBaseLevelGainStrings")[0]
        gain = gain.split("%s", 1)[1].split("\x06")[0]
        # camp menu
        main = string_list(gd, "kEoBBaseMenuStringsMain")
        sl = string_list(gd, "kEoBBaseMenuStringsSaveLoad")
        rest = string_list(gd, "kEoBBaseMenuStringsRest")
        rest2 = string_list(gd, "kEoBBaseMenuStringsRest2")
        for i, s in enumerate(main):
            if i:                       # (0: the title runCampMenu never shows)
                f.write(asm_string("STR_CM%d" % i, s))
        for i, s in enumerate(sl[:5]):
            f.write(asm_string("STR_CO%d" % i, s))
        f.write(asm_string("STR_SAVED", sl[5], "lead"))
        f.write(asm_string("STR_SAVEERR", sl[6], "lead"))
        f.write(asm_string("STR_LOADERR", sl[7], "lead"))
        # (the rest has its texts in the magic overlay: RS_S_*)
        f.write(asm_string("STR_NEEDREST", rest[4], True))
        head = string_list(gd, "kEoBBaseMenuStringsHead")      # runCampMenu titles 56..58
        f.write(asm_string("STR_HEAD0", head[0]))
        f.write(asm_string("STR_HEAD1", head[1]))
        f.write(asm_string("STR_QUITQ", string_list(gd, "kEoBBaseMenuStringsExit")[0], True))
        sound = string_list(gd, "kEoBBaseMenuStringsPrefs")[1].split("%")[0]
        assert len(sound) + 3 < 24, "PF_L_LEN (src/ui.asm) too short"
        f.write(asm_string("STR_PF_SOUND", sound))
        oo = string_list(gd, "kEoBBaseMenuStringsOnOff")
        f.write(asm_string("STR_ON", oo[0]))
        f.write(asm_string("STR_OFF", oo[1]))
        for i, t in enumerate(string_list(gd, "kEoBBaseMenuStringsScribe")[:5]):
            f.write(asm_string("STR_SC%d" % i, t, True))
        f.write(asm_string("STR_DROP0", string_list(gd, "kEoBBaseMenuStringsDrop")[0], True))
        f.write(asm_string("STR_DROP1", string_list(gd, "kEoBBaseMenuStringsDrop2")[0], True))
        yn = string_list(gd, "kEoBBaseMenuYesNoStrings")
        f.write(asm_string("STR_YES", yn[0]))
        f.write(asm_string("STR_NO", yn[1]))
        # memorize / pray menu
        sp = string_list(gd, "kEoBBaseMenuStringsSpells")
        for i in range(8):
            f.write(asm_string("STR_SP%d" % i, sp[i], True))
        f.write(asm_string("STR_SPCLEAR", sp[13]))
        f.write(asm_string("STR_SPTITLE", sp[14]))
        f.write(asm_string("STR_LEFT", string_list(gd, "kEoBBaseMenuStringsMgc")[1].split("%d")[1].split("%d")[0]))
        f.write(asm_string("STR_LEFT2", string_list(gd, "kEoBBaseMenuStringsMgc")[1].split("%d")[2].rstrip()))
        f.write("UI_MAGE_LEVELS:\n\tdb " + ",".join(str(v) for v in gd.table("kEoBBaseSpellLevelsMage")) + "\n")
        f.write("UI_CLERIC_LEVELS:\n\tdb " + ",".join(str(v) for v in gd.table("kEoBBaseSpellLevelsCleric")) + "\n")
        for label, key in (("UI_NUM_MAGE", "kEoBBaseNumSpellsMage"), ("UI_NUM_CLERIC", "kEoBBaseNumSpellsCleric"),
                           ("UI_NUM_WISADJ", "kEoBBaseNumSpellsWisAdj"), ("UI_NUM_PAL", "kEoBBaseNumSpellsPal")):
            f.write(label + ":\n\tdb " + ",".join(str(v) for v in gd.table(key)) + "\n")
        for label, key in (("UI_BOOKM", "kEoBBaseMageSpellsList"), ("UI_BOOKC", "kEoBBaseClericSpellsList")):
            lst = string_list(gd, key)
            f.write(label + ":\n\tdw " + ",".join("%s_%d" % (label, i) for i in range(len(lst))) + "\n")
            for i, nm in enumerate(lst):
                f.write(asm_string("%s_%d" % (label, i), nm))
        # the frame that marks a character to choose (_highlightColorTableVGA)
        f.write("PK_COLS:\n\tdb " + ",".join(str(lut[v]) for v in (
            0x0F, 0xB0, 0xB2, 0xB4, 0xB6, 0xB8, 0xBA, 0xBC, 0x0C, 0xBC, 0xBA, 0xB8, 0xB6, 0xB4, 0xB2, 0xB0)) + "\n")
        # _characterClassType (CLASS_LEVEL)
        f.write("CLASS_TYPE:\n\tdb " + CLASS_TYPE_DB + "\n")
    # experience and levels (exp.asm, script overlay)
    with open(BUILD / "expdata.inc", "w") as f:
        f.write("; expdata.inc - generated by tools/conv_global.py\n")
        # experience needed for level n + 1 (u32), per class type (5 = 4)
        f.write("EXP_TABLES:\n")
        for i in (0, 1, 2, 3, 4, 4):
            d = gd.table("kEoBBaseExperienceTable%d" % i)
            v = [struct.unpack_from(">I", d, j)[0] for j in range(0, len(d), 4)]
            v = (v + [0xFFFFFFFF] * 12)[:12]
            f.write("\tdd " + ",".join(str(x) for x in v) + "\n")
        # _characterClassType, _hpIncrPerLevel, _hpConstModifiers
        f.write("EXP_CTYPE:\n\tdb " + CLASS_TYPE_DB + "\n")
        f.write("HP_INCR:\n\tdb 10,4,8,6,10,10,9,10,9,10,9,9,3,1,2,2,3,3\n")
        f.write("HP_CON_MOD:\n\tdb -1,-3,-2,-2,-1,-1,-1,0,0,0,0,0,0,0,0,1,2,3,4,5,6,6,6,7,7\n")
        f.write(asm_string("STR_LEVELGAIN", gain))
    print("ui data: inventory page %d bytes" % total)


def opaque(rows):
    return [[(v if v is not None else 0) for v in r] for r in rows]


def load_items(gd):
    """ITEM.DAT as loadItemDefs leaves it: ITEM_MAX records, unused ones with block -1."""
    d = gd.get("ITEM.DAT")
    n = struct.unpack_from("<H", d)[0]
    items = [list(struct.unpack_from(ITEM_FMT, d, 2 + i * I_SIZE)) for i in range(n)]
    items += [[0, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0] for _ in range(ITEM_MAX - n)]
    return items


def duplicate_item(items, idx):
    """EoBCoreEngine::duplicateItem: copy into the first free record."""
    if items[idx][6] == -1:
        return 0
    for i in range(1, ITEM_MAX):
        if items[i][6] == -1:
            items[i] = list(items[idx])
            return i
    return 0


def item_type(gd, t):
    d = gd.get("ITEMTYPE.DAT")
    r = struct.unpack_from("<HHbbbbbbbbbBH", d, 2 + t * 16)
    return dict(inv=r[0], hand=r[1], ac=r[2], classes=r[3] & 0xFF, hands=r[4], extra=r[12])


def starting_items(gd, items, c, cls, race, first):
    """CharacterGenerator::finish, EOB1: the letter of Waterdeep for the first
    character, rations, and the items of the class (as src/chargen.asm)."""
    from conv_chargen import ITEM_LIST, ITEM_LIST_INDEX
    inv = [0] * 27
    if first:
        inv[2] = duplicate_item(items, 35)
    inv[3] = duplicate_item(items, 10)
    for ii in range(4):
        l = ITEM_LIST_INDEX[cls * 4 + ii]
        if l < 0 or ITEM_LIST[l * 2] == -1:
            continue
        d, slot = ITEM_LIST[l * 2], ITEM_LIST[l * 2 + 1]
        if slot < 0:
            slot = 0
            if inv[slot]:
                slot += 1
            if inv[slot]:
                slot += 1
        if slot != 2 and inv[slot]:
            continue
        if d == 5 and race == 3:
            d = 36
        if slot == 2:
            while inv[slot]:
                slot += 1
        inv[slot] = duplicate_item(items, d)
    return inv


def armor_class(gd, items, inv, cls, dex):
    """EoBCoreEngine::recalcArmorClass."""
    mod = (5, 5, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, -1, -2, -3, -4, -4, -5, -5, -5, -6, -6)
    ac = 10 + mod[dex]
    m = gd.table("kEoBBaseClassModifierFlags")[cls]
    for k, slot in enumerate((17, 0, 1, 18)):
        itm = inv[slot]
        if not itm:
            continue
        tp = items[itm][4]
        t = item_type(gd, tp)
        if k == 2 and inv[0] and item_type(gd, items[inv[0]][4])["hands"] > 1:
            continue
        if not (t["classes"] & m) or (t["extra"] & 0x7F) or (1 <= k <= 2 and tp != 27):
            continue
        ac += t["ac"] - items[itm][10]
    return ac


def write_party(gd, items):
    d = gd.get("EOBDATA.SAV")
    R = 243
    out = bytearray()
    first = True
    for i in range(6):
        c = d[i * R:(i + 1) * R]
        rec = bytearray(P_SIZE)
        rec[P_FLAGS] = c[1]
        name = c[2:13].split(b"\0")[0][:10]
        rec[P_NAME:P_NAME + len(name)] = name
        rec[P_HP] = c[27]
        rec[P_HPMAX] = c[28]
        rec[P_FACE] = c[34]
        rec[P_STR] = c[13]
        rec[P_STREXT] = c[15]
        rec[P_DEX] = c[21]
        rec[P_LEVEL] = c[36]
        rec[P_LEVELS:P_LEVELS + 3] = c[36:39]
        rec[P_CON] = c[23]
        rec[P_MKNOWN:P_MKNOWN + 4] = c[115:119]
        rec[P_WIS] = c[19]
        rec[P_INT] = c[17]
        rec[P_CHA] = c[25]
        rec[P_ALIGN] = c[33]
        rec[P_EXP:P_EXP + 12] = c[39:51]
        rec[P_RACE] = c[31]
        rec[P_CLASS] = c[32]
        rec[P_FOOD] = 100
        rec[P_AC] = c[29]
        if c[1] & 1:
            inv = starting_items(gd, items, c, c[32], c[31] >> 1, first)
            first = False
            struct.pack_into("<27H", rec, P_INV, *inv)
            rec[P_AC] = armor_class(gd, items, inv, c[32], c[21]) & 0xFF
        out += rec
    open(BUILD / "PARTY.DAT", "wb").write(out)


def write_items(gd, items):
    out = bytearray()
    for it in items:
        out += struct.pack(ITEM_FMT, *it)
    open(BUILD / "ITEMS.DAT", "wb").write(out)
    d = gd.get("ITEM.DAT")
    n = struct.unpack_from("<H", d)[0]
    o = 2 + n * I_SIZE
    nn = struct.unpack_from("<H", d, o)[0]
    names = bytearray()
    for i in range(nn):
        nm = d[o + 2 + i * 35:o + 2 + (i + 1) * 35].split(b"\0")[0]
        names += bytes(b & 0x7F for b in nm) + b"\0"
    open(BUILD / "ITEMNAME.DAT", "wb").write(names)


def crop(rows):
    """Bounding box of the non transparent pixels -> (rows, dx, dy)."""
    ys = [y for y, r in enumerate(rows) if any(v is not None for v in r)]
    if not ys:
        return [], 0, 0
    xs = [x for r in rows for x, v in enumerate(r) if v is not None]
    x0, x1, y0, y1 = min(xs) & ~1, max(xs), ys[0], ys[-1]   # even x: the engine draws at even x
    return [r[x0:x1 + 1] for r in rows[y0:y1 + 1]], x0, y0


def item_shapes(gd):
    """Floor item shapes (loadItemsAndDecorationsShapes, EOB1): 14 large and
    23 small, each in its full size and the 3 smaller ones of the sheet."""
    out = []
    first = {"l": 0, "s": LARGE_N, "t": LARGE_N + SMALL_N}
    for sheet, n, w8, kind in (("ITEML1.CPS", LARGE_N, 8, "l"), ("ITEMS1.CPS", SMALL_N, 4, "s"),
                               ("THROWN.CPS", THROWN_N, 4, "t")):
        img = gd.cps(sheet)
        for i in range(n):
            bx, by = (i // 3) * w8 * 8, (i % 3) * 64
            sizes = [(w8 * 8, 24, 0)]
            for k in range(3):
                w = (6 - 2 * k) * 8 if w8 == 8 else (3 - k) * 8
                sizes.append((w, 16 - ((k >> 1) << 3), 24 + k * 16))
            for s, (w, h, yo) in enumerate(sizes):
                rows, dx, dy = crop(C.crop_rows(img, bx, by + yo, w, h))
                out.append(("item%d_%d" % (first[kind] + i, s), rows, (dx, dy, w, h)))
    return out


def write_item_shapes(gd, ids, info):
    """itemshp.inc: per floor item shape (large ones, then small ones) and
    size: crop dx, dy, original width / 2, original height."""
    with open(BUILD / "itemshp.inc", "w") as f:
        f.write("; itemshp.inc - generated by tools/conv_global.py\n")
        f.write("ITEM_LARGE_N:\tequ %d\nITEM_SMALL_N:\tequ %d\nITEM_THROWN0:\tequ %d\n" % (LARGE_N, SMALL_N, LARGE_N + SMALL_N))
        f.write("; shape id = SHP_ITEM0_0 + n * 4 + size; dx, dy, w / 2, h\nITEMSHP:\n")
        for n, (dx, dy, w, h) in enumerate(info):
            f.write("\tdb %d,%d,%d,%d\n" % (dx, dy, w // 2, h))
        f.write("; icon -> floor shape: < 14 large, >= 15 small + 15, else none\nITEM_SHPMAP:\n")
        m = list(gd.table("kEoBBaseDscItemShapeMap"))
        f.write("\tdb " + ",".join(str(v) for v in m) + "\n")
        f.write("; flying items: shape map -> first thrown shape (-1 none), flip by (dir << 2) + pos,\n")
        f.write("; size by (block << 2) + position (-1 not drawn)\n")
        for label, name in (("FLIGHT_SHPMAP", "kEoBBaseFlightObjShpMap"), ("FLIGHT_FLIP", "kEoBBaseFlightObjFlipIndex"),
                            ("FLIGHT_SCL", "kEoBBaseFlightObjSclIndex")):
            f.write(label + ":\n\tdb " + ",".join(str(E.signed8(v)) for v in gd.table(name)) + "\n")


def write_font():
    with open(BUILD / "font.inc", "w") as f:
        f.write("; font.inc - FONT6.FNT and FONT8.FNT glyphs (generated by tools/conv_global.py)\n")
        for name, label, wl, hl in (("FONT6.FNT", "FONT6", "FONT_W", "FONT_H"), ("FONT8.FNT", "FONT8", "FONT8_W", "FONT8_H")):
            d = open(E.PC / name, "rb").read()
            n = struct.unpack_from("<H", d, 2)[0] // 2 - 2
            h, w = d[258], d[259]
            offs = struct.unpack_from("<%dH" % n, d, 2)
            f.write("%s:\tequ %d\n%s:\tequ %d\n%s:\n" % (wl, w, hl, h, label))
            for c in range(32, 128):           # from the space on
                g = d[offs[c]:offs[c] + h] if c < n else bytes(h)
                f.write("\tdb " + ",".join("%d" % b for b in g) + "\n")


if __name__ == "__main__":
    main()
