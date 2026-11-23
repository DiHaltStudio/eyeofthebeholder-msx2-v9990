#!/usr/bin/env python3
"""conv_level.py - Converts one dungeon level to the V9990 B2/BP6 files.

Video: B2 384x240, 8 bpp, 64-colour palette (BP6), image 512 pixels wide
(XIMM = 01), so VRAM address = y * 512 + x and the 512 KB hold 1024 rows.

VRAM map (see also src/vram.inc, generated here):
  rows   0..239, x 0..383   screen; the 320x200 game image sits at (32, 20)
  rows 240..359, x 0..175   VIEW_BUF: the 3D view is composed here and then
                            copied to the screen in one LMMM
  everything else           level store: floor/ceiling backgrounds, wall
                            pieces, decorations, doors, monsters (packed)

Palette (64 entries of R,G,B in 0..31):
  0             transparent (never drawn by the transparent copies)
  1             black (opaque)
  2..FIXED_N+1  fixed part: user interface, items, portraits, fonts
  the rest      level part: walls, decorations, monsters of the level

Files written to build/:
  LEVELn.V9   VRAM chunks in RLE (see write_v9; the loader is LOAD_V9)
  LEVELn.PAL  64 x 3 bytes
  LEVELn.DAT  maze, wall tables, shapes and coordinates (layout: D_* below)
  LEVELn.LVL  what the game reads: .DAT, .PAL, .INF (SCRIPT_MAX), .SHP
  UI.V9       the playfield frame written straight to the screen rows
  drawlist.inc / tables.inc / vram.inc  tables shared with the assembler
"""
import json
import struct
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eoblib as E

ROOT = E.ROOT
BUILD = E.BUILD

IMG_W, IMG_H = 512, 1024
SCREEN_X, SCREEN_Y, SCREEN_W, SCREEN_H = 32, 20, 384, 240
VIEW_W, VIEW_H = 176, 120
VIEWBUF_X, VIEWBUF_Y = 0, 240
PANEL_W, PANEL_H = 144, 168          # the party panel (176, 0) while the inventory covers it
PANELBUF_X, PANELBUF_Y = 0, VIEWBUF_Y + VIEW_H
BOOK_STAGE_W, BOOK_STAGE_H = 120, 56  # includes the trailing glyph's padding
FIXED_N = 27           # fixed palette entries after black (indexes 2..28)
LEVEL_FIRST = FIXED_N + 2
LEVEL_N = 64 - LEVEL_FIRST
C_TRANSPARENT, C_BLACK = 0, 1
CHUNK_MAX = 16384      # the loader buffer is 16 KB

# Draw list of generateBlockDrawingBuffer (ScummVM scene_rpg.cpp): visible
# block, wall side (D/R/L = facing us / right face / left face), piece,
# flipped, block x, block y, condition, second visible block for conditions 3-4
#   cond 0: wall type != 0          cond 1: hasWall: type != 0 and not a door
#   cond 2: not a door (type 0 draws nothing)
#   cond 3: hasWall(t) and t2 is not a door       -> draws t
#   cond 4: t != 0 and t2 is a door               -> draws t2
DRAWLIST = [
    (0, "R", 0, 0, -2, 3, 0, 0), (6, "L", 0, 1, 21, 3, 0, 0),
    (1, "R", 0, 0, 2, 3, 3, 2), (1, "R", 0, 0, 2, 3, 4, 2),
    (5, "L", 0, 1, 17, 3, 3, 4), (5, "L", 0, 1, 17, 3, 4, 4),
    (2, "R", 1, 0, 8, 3, 0, 0), (4, "L", 1, 1, 13, 3, 0, 0),
    (1, "D", 2, 0, -4, 3, 1, 0), (5, "D", 2, 0, 20, 3, 1, 0),
    (2, "D", 2, 0, 2, 3, 1, 0), (4, "D", 2, 0, 14, 3, 1, 0),
    (3, "D", 2, 0, 8, 3, 0, 0),
    (7, "R", 3, 0, 0, 3, 0, 0), (11, "L", 3, 1, 20, 3, 0, 0),
    (8, "R", 4, 0, 6, 2, 0, 0), (10, "L", 4, 1, 14, 2, 0, 0),
    (8, "D", 5, 0, -4, 2, 1, 0), (10, "D", 5, 0, 16, 2, 1, 0),
    (9, "D", 5, 0, 6, 2, 0, 0),
    (12, "R", 6, 0, 3, 1, 0, 0), (14, "L", 6, 1, 16, 1, 0, 0),
    (12, "D", 7, 0, -13, 1, 2, 0), (14, "D", 7, 0, 19, 1, 2, 0),
    (13, "D", 7, 0, 3, 1, 0, 0),
    (15, "R", 8, 0, 0, 0, 0, 0), (17, "L", 8, 1, 19, 0, 0, 0),
]
SIDE = {"D": 0, "R": 1, "L": 2}
FLIPPED_PIECES = {0, 1, 3, 4, 6, 8}

# _dscWallMapping (eobcommon.cpp): per visible block, the wall whose
# decoration is drawn for the "side" pass (i = 1) and the "facing" pass (i = 0)
# 0 = none, 1 = facing us, 2 = right face, 3 = left face
DSC_WALLMAPPING = [0, 0, 1, 2, 1, 2, 1, 0, 1, 3, 1, 3,
                   0, 0, 1, 2, 1, 2, 1, 0, 1, 3, 1, 3,
                   1, 2, 1, 0, 1, 3, 0, 2, 1, 0, 0, 3]
DIST_MAP = [2, 1, 0, 4]          # drawMonsters: dim map -> scale steps
MONSTER_Y_ADD = [20, 12, 4, 4, 2, 0, 0]
COMPASS_X = [0x70, 0x4D, 0x95]
COMPASS_Y = [0x7F, 0x9A, 0x9A]

# LEVELn.DAT layout
D_MAZE = 0
D_WVMP = 4096
D_WFLAGS = 4352
D_WSHAPE = 4608
D_PIECES = 4864            # 6 sets * 9 pieces * 2 flips * (vx, vy)
D_BG = 5296                # 2 * (vx, vy)
D_START = 5304             # block u16, dir u8
D_NSEGS = 5307            # mapper segments of LEVELn.SHP
D_NSHAPES = 5308
D_CACHEY = 5310            # first VRAM row of the shape cache
D_SHAPES = 5312            # SHP_MAX * 8: vx, vy, w, h, flipped twin id
SHP_MAX = 190                          # the levels use up to 185
D_DECOS = D_SHAPES + SHP_MAX * 8      # DEC_MAX * 64: flags, next, pad, 10 * (shape, x, y)
DEC_MAX = 36                           # the levels use up to 35
D_DOORS = D_DECOS + DEC_MAX * 64      # 6 * (shape, switch shape, switch x, switch y)
MON_SIZE = 24
D_MONSTERS = D_DOORS + 40             # 30 * MON_SIZE (layout in src/monsters.asm)
D_MONTIMERS = D_MONSTERS + 30 * MON_SIZE  # 4 monster unit timer intervals (ticks)
D_MONSHAPE = D_MONTIMERS + 4          # 2 types * 6 frames * 3 scales * shape id
D_BOOK_STAGE = D_MONSHAPE + 72        # x, y in the alignment padding
D_WSPECIAL = (D_MONSHAPE + 72 + 255) & ~255   # special wall types (1 = door switch)
assert D_BOOK_STAGE + 4 <= D_WSPECIAL
TRIG_MAX = 110
SCRIPT_MAX = 0x2000                    # LEVELn.INF in the script segment (8000h-9FFFh)
D_TRIGGERS = D_WSPECIAL + 256         # u8 count, then TRIG_MAX * (block u16, flags u8, script offset u16)
D_SCRTIMER = D_TRIGGERS + 1 + TRIG_MAX * 5   # script timer: mode u8, ticks u16; steps between step calls u16
D_STATIC = D_SCRTIMER + 5             # the engine tables of tables.inc and drawlist.inc
STATIC_MAX = 2240                      # used: 2228
D_SIZE = D_STATIC + STATIC_MAX
SHAPE_NONE = 0xFFFF

# NPC sequences: figures of OUTTAKE.CPS drawn over the view (EoBEngine::drawNpcScene)
# scene -> (level, [(shape, x, y)]); 8 = Armun with the cleric, 9..14 = the cleric
# with a raised NPC (npcSequenceSub 0..5)
NPC_SCENES = {0: (4, [(2, 88, 104)]), 1: (5, [(0, 88, 104)]), 2: (5, [(3, 88, 104)]),
              3: (7, [(7, 88, 104)]), 4: (10, [(6, 88, 104)]), 5: (12, [(18, 88, 88)]),
              6: (6, [(17, 88, 104)]), 7: (10, [(4, 88, 104)]),
              8: (5, [(0, 60, 104), (5, 116, 104)])}
for _s, (_b, _h, _y) in enumerate(zip([9, 8, 8, 9, 9, 10], [13, 11, 12, 14, 15, 16], [52, 49, 49, 52, 52, 69])):
    NPC_SCENES[9 + _s] = (5, [(3, 60, 104), (_b, 116, 104), (_h, 116, _y)])
NPC_TAB = 0x1F00                       # the scene table, at this offset of LEVELn.INF
XD_TAB = 0x1FF2                        # level 12: the first VRAM row of XDEATH.V9 (u16)
XD_LEVEL = 12
PT_TAB = 0x1FF0                        # levels with portals: the first VRAM row of PORTALn.V9 (u16)
PORTAL_LEVELS = (2, 4, 5, 6, 7, 8, 9, 10, 11, 12)   # the scripts use "sequence 8"
CACHE_END = 1000                       # the pointer background is saved from here


class Packer:
    """Skyline packer over the whole VRAM minus the screen and VIEW_BUF."""

    def __init__(self):
        # segments (x0, x1, y): the skyline top of each column range
        self.sky = [(0, VIEW_W, VIEWBUF_Y + VIEW_H), (VIEW_W, SCREEN_W, SCREEN_H), (SCREEN_W, IMG_W, 0)]
        self._raise(PANELBUF_X, PANELBUF_X + PANEL_W, PANELBUF_Y + PANEL_H)
        self.used = 0

    @classmethod
    def with_book_stage(cls, sizes):
        """Try the book between shapes so it does not block a whole column."""
        best = None
        book = ("book_stage", BOOK_STAGE_W, BOOK_STAGE_H)
        for i in range(len(sizes) + 1):
            packer = cls()
            coords = {}
            top = SCREEN_H
            for name, w, h in sizes[:i] + [book] + sizes[i:]:
                position = packer.add(name, w, h)
                if position is None:
                    break
                coords[name] = position
                top = max(top, position[1] + h)
            else:
                if best is None or top < best[0]:
                    best = top, packer, coords
        if best is None:
            raise SystemExit("no room for the level store and spellbook")
        return best

    def add(self, name, w, h):
        best = None
        for i, (x0, x1, y) in enumerate(self.sky):
            x = x0
            while x + w <= IMG_W:
                # the skyline height under [x, x+w)
                top = 0
                j = i
                xx = x
                while xx < x + w:
                    sx0, sx1, sy = self.sky[j]
                    top = max(top, sy)
                    xx = sx1
                    j += 1
                if top + h <= IMG_H and (best is None or top < best[0] or (top == best[0] and x < best[1])):
                    best = (top, x)
                break
        if best is None:
            return None
        y, x = best
        self._raise(x, x + w, y + h)
        self.used += w * h
        return x, y

    def _raise(self, x0, x1, y):
        new = []
        for sx0, sx1, sy in self.sky:
            if sx1 <= x0 or sx0 >= x1:
                new.append((sx0, sx1, sy))
                continue
            if sx0 < x0:
                new.append((sx0, x0, sy))
            if sx1 > x1:
                new.append((x1, sx1, sy))
        new.append((x0, x1, y))
        new.sort()
        # merge equal neighbours
        merged = [new[0]]
        for seg in new[1:]:
            if seg[2] == merged[-1][2] and seg[0] == merged[-1][1]:
                merged[-1] = (merged[-1][0], seg[1], seg[2])
            else:
                merged.append(seg)
        self.sky = merged


def rgb5(c):
    return tuple(v >> 1 for v in c)   # VGA 0..63 -> 0..31


def lab(c):
    """CIE L*a*b* of a 5-bit colour (D65)."""
    def lin(v):
        v = v / 31
        return ((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92
    r, g, b = (lin(v) for v in c)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def nearest_lab(pal, c):
    """Index of the entry of pal nearest to c in L*a*b* (the level colours:
    a shift of hue shows more than one of brightness)."""
    lc = lab(c)
    best, bi = 1e30, 0
    for i, p in enumerate(pal):
        lp = lab(p)
        d = (lp[0] - lc[0]) ** 2 + (lp[1] - lc[1]) ** 2 + (lp[2] - lc[2]) ** 2
        if d < best:
            best, bi = d, i
    return bi


def nearest(pal, c):
    best, bi = 1 << 30, 0
    for i, p in enumerate(pal):
        d = (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2
        if d < best:
            best, bi = d, i
    return bi


def quantize(colours, n):
    """colours: list of (r,g,b) in 0..31 with repetitions -> n palette entries."""
    img = Image.new("RGB", (len(colours), 1))
    img.putdata([(r * 8, g * 8, b * 8) for r, g, b in colours])
    q = img.quantize(n, method=Image.Quantize.LIBIMAGEQUANT, dither=Image.Dither.NONE)
    p = q.getpalette()[:n * 3]
    pal = [(p[i] >> 3, p[i + 1] >> 3, p[i + 2] >> 3) for i in range(0, len(p), 3)]
    pal = list(dict.fromkeys(pal))
    return pal + [(0, 0, 0)] * (n - len(pal))


def pixel_colours(vgapal, rows_list):
    cnt = {}
    for rows in rows_list:
        for row in rows:
            for v in row:
                if v is not None:
                    cnt[v] = cnt.get(v, 0) + 1
    out = []
    for v, c in cnt.items():
        out += [rgb5(vgapal[v])] * max(1, c // 16)
    return out


def refine_palette(level, cols, base, iters=12, minpix=24):
    """The quantizer leaves out colours of few pixels (the red of the pits of
    levels 7-9...): while some colour of at least minpix pixels is far from
    every entry, it replaces the level entry whose loss costs least, if the
    total error does not grow more than 15 %. cols: colour -> pixels."""
    labs = {k: lab(k) for k in cols}

    def err(pal):
        lp = [lab(p) for p in pal]
        tot, worst = 0, (0, None)
        for k, c in cols.items():
            a = labs[k]
            e = min((a[0] - q[0]) ** 2 + (a[1] - q[1]) ** 2 + (a[2] - q[2]) ** 2 for q in lp)
            tot += e * c
            if c >= minpix and e > worst[0]:
                worst = (e, k)
        return tot, worst
    for _ in range(iters):
        tot, (we, wk) = err(base + level)
        if we <= 25:            # (delta E 5)
            break
        best = None
        for i in range(len(level)):
            cand = level[:i] + level[i + 1:] + [wk]
            t = err(base + cand)[0]
            if best is None or t < best[0]:
                best = (t, cand)
        if best[0] > tot * 1.15:
            break
        level = best[1]
    return level


def build_palette(vgapal, level_rows):
    """The fixed part comes from tools/conv_global.py (build/fixed.json)."""
    fixed = [tuple(c) for c in json.load(open(BUILD / "fixed.json"))]
    level = quantize(pixel_colours(vgapal, level_rows), LEVEL_N)
    cols = {}
    for rows in level_rows:
        for row in rows:
            for v in row:
                if v is not None:
                    k = rgb5(vgapal[v])
                    cols[k] = cols.get(k, 0) + 1
    level = refine_palette(level, cols, [(0, 0, 0)] + fixed)
    pal = [(0, 0, 0), (0, 0, 0)] + fixed + level
    assert len(pal) == 64
    lut = []
    for v in range(256):
        c = rgb5(vgapal[v])
        lut.append(C_BLACK if c == (0, 0, 0) else 1 + nearest_lab(pal[1:], c))
    return pal, lut


def rle_row(px):
    """One row: n < 80h: n literal bytes follow; 80h + n: n times the next byte."""
    out = bytearray()
    i = 0
    while i < len(px):
        j = i
        while j < len(px) and px[j] == px[i] and j - i < 127:
            j += 1
        if j - i >= 3:
            out += bytes([0x80 | (j - i), px[i]])
            i = j
            continue
        k = i
        while k < len(px) and k - i < 127 and not (k + 2 < len(px) and px[k] == px[k + 1] == px[k + 2]):
            k += 1
        out += bytes([k - i]) + bytes(px[i:k])
        i = k
    return out


def rle_shape(px, w):
    """A RAM shape as stored: its rows one after the other, each in RLE."""
    out = bytearray()
    for r in range(0, len(px), w):
        out += rle_row(px[r:r + w])
    return bytes(out)


def to_pixels(rows, lut):
    return bytes(C_TRANSPARENT if v is None else lut[v] for row in rows for v in row)


V9_BLOCK = 16384         # LOAD_V9 reads the file in blocks of this size
V9_GAP = 16              # zero runs this long split a chunk (cleared files)
V9_MINRUN = 10            # shorter runs go as literal bytes (otir is faster)


def v9_tokens(data):
    """RLE tokens: n = 1..7Fh literal bytes; 80h + n (n >= 3): n times a byte."""
    out = []
    i = 0
    L = len(data)
    while i < L:
        j = i
        while j < L and data[j] == data[i] and j - i < 127:
            j += 1
        if j - i >= V9_MINRUN:
            out.append(bytes((0x80 | (j - i), data[i])))
            i = j
            continue
        k = i
        while k < L and k - i < 127 and data[k:k + V9_MINRUN] != bytes((data[k],)) * V9_MINRUN:
            k += 1
        out.append(bytes((k - i,)) + bytes(data[i:k]))
        i = k
    return out


def v9_spans(addr, data):
    """The non-zero parts of a chunk, split where V9_GAP zeros or more come."""
    i = 0
    L = len(data)
    while i < L:
        while i < L and data[i] == 0:
            i += 1
        if i >= L:
            return
        j = k = i
        z = 0
        while k < L:
            if data[k]:
                z = 0
                j = k + 1
            else:
                z += 1
                if z >= V9_GAP:
                    break
            k += 1
        yield addr + i, data[i:j]
        i = j


def write_v9(path, chunks, clear=()):
    """A .V9 file: VRAM chunks in RLE, read by LOAD_V9 in V9_BLOCK blocks.
      header: u24 VRAM address, then tokens up to the token 80h;
              address FExxxxh: clear (u16 dx, dy, nx, ny) to colour 0, then
              another header; address FFxxxxh: the end
      tokens: 00h: the rest of this block is padding (the next block)
              01h-7Fh n: n bytes follow; 81h-FFh 80h + n: n times the next
              byte; 80h: the end of the chunk, a header follows
    Nothing crosses a block: no item is split, so the loader never checks.
    With clear rectangles the zeros between chunk parts are not stored."""
    if clear:
        chunks = [s for a, d in chunks for s in v9_spans(a, d)]
    out = bytearray()

    def put(item):
        # one byte stays free in the block for the token 00h
        if len(out) % V9_BLOCK + len(item) > V9_BLOCK - 1:
            out.append(0)
            out.extend(bytes(-len(out) % V9_BLOCK))
        out.extend(item)

    head = bytearray()
    for r in clear:
        head += bytes((0, 0, 0xFE)) + struct.pack("<HHHH", *r)
    for addr, data in chunks:
        head += struct.pack("<HB", addr & 0xFFFF, addr >> 16)
        put(head)
        for t in v9_tokens(data):
            put(t)
        head = bytearray((0x80,))
    head += bytes((0, 0, 0xFF))
    put(head)
    with open(path, "wb") as f:
        f.write(out)


# ---------------------------------------------------------------------------
# shapes
# ---------------------------------------------------------------------------
def crop_rows(img, x, y, w, h):
    """Rows of a rectangle of a 320-wide VGA image, 0 = transparent."""
    return [[(v if v else None) for v in img[(y + r) * 320 + x:(y + r) * 320 + x + w]] for r in range(h)]


def flip_rows(rows):
    return [list(reversed(r)) for r in rows]


def scale_step(rows):
    """One 2/3 scaling step, as Screen_EoB::scaleShapeStep does for 4-bit shapes."""
    h = len(rows)
    w = len(rows[0])
    wb = w // 2                      # source bytes per line (2 pixels each)
    div, rem = wb // 3, wb % 3
    out = []
    i = 0
    hh = h + 1
    while True:
        hh -= 1
        if not hh:
            break
        out.append(scale_line(rows[i], div, rem))
        i += 1
        hh -= 1
        if not hh:
            break
        out.append(scale_line(rows[i], div, rem))
        i += 1
        hh -= 1
        if not hh:
            break
        i += 1                       # the third line is dropped
    return out


def scale_line(row, div, rem):
    out = []
    p = 0
    for _ in range(div):
        out += [row[p], row[p + 1], row[p + 3], row[p + 4]]
        p += 6
    if rem == 1:
        out += [row[p], row[p + 1], None, None]
    elif rem == 2:
        out += [row[p], row[p + 2], None, None, None, None, None, None]
    return out


def fade_table(vgapal, root=12, weight=85):
    """Screen_EoB::createColorFadeTable: VGA index -> darker VGA index."""
    r, g, b = vgapal[root]
    weight >>= 1
    tab = [0]
    for i in range(1, 256):
        c = vgapal[i]
        t = []
        for k, base in enumerate((r, g, b)):
            tmp = (((c[k] - base) * weight) & 0xFFFF) << 1
            t.append((c[k] - ((tmp >> 8) & 0xFF)) & 0xFF)
        v = 0xFFFF
        col = root
        for ii in range(1, 256):
            d = vgapal[ii]
            e = (d[0] - t[0]) ** 2 + (d[1] - t[1]) ** 2 + (d[2] - t[2]) ** 2
            if e <= v and (ii == root or ii != i):
                v = e
                col = ii
        tab.append(col)
    return tab


def fade_rows(rows, tab, steps):
    out = []
    for row in rows:
        nr = []
        for v in row:
            if v is not None:
                for _ in range(steps):
                    v = tab[v]
            nr.append(v)
        out.append(nr)
    return out


def is_ram_shape(name):
    """Decorations and monsters live in RAM and are uploaded to the VRAM
    cache when a scene needs them (mirrored on the fly)."""
    return name.startswith("dec_") or name.startswith("mon")


class ShapeSet:
    def __init__(self):
        self.shapes = []     # (name, rows, flip_of or None)
        self.index = {}

    def add(self, name, rows, flipped=False):
        if name in self.index:
            return self.index[name]
        sid = len(self.shapes)
        self.index[name] = sid
        self.shapes.append([name, rows, SHAPE_NONE])
        if flipped:
            fid = sid + 1
            self.index[name + "_f"] = fid
            self.shapes.append([name + "_f", flip_rows(rows), sid])
            self.shapes[sid][2] = fid
        return sid


# ---------------------------------------------------------------------------
# level conversion
# ---------------------------------------------------------------------------
class Level:
    def __init__(self, gd, level):
        self.gd = gd
        self.n = level
        self.li = li = E.LevelInfo(gd, level)
        self.maze = E.Maze(gd.get(li.maz_name))
        self.vcn = E.VCN(gd.cps(li.gfx_name + ".VCN"))
        self.vmp = E.VMP(gd.get(li.gfx_name + ".VMP"))
        self.vgapal = gd.palette(li.gfx_name + ".PAL")
        self.wvmp, self.wflags, self.wspecial = E.default_wall_tables(gd)
        self.wshape = [0] * 256          # 0xFF = preset -1: the door switch is drawn
        for w in list(range(3, 8)) + list(range(13, 18)):
            self.wshape[w] = 0xFF
        for w, (v, dec, special, flags, dset) in li.wall_map.items():
            self.wshape[w] = 0
            self.wvmp[w] = v
            self.wflags[w] = flags
            self.wspecial[w] = special
        self.used_sets = sorted({self.wvmp[t] for t in set(self.maze.walls)} - {0})
        self.images = {}          # name -> rows (walls and backgrounds)
        self.shapes = ShapeSet()
        self.decos = []           # mapped decoration entries
        self.doors = [None] * 6
        self.monshapes = {}       # (type slot, frame, scale) -> shape id
        self.render_walls()
        self.load_compass()
        self.load_decorations()
        self.load_doors()
        self.load_monsters()

    # --- walls -------------------------------------------------------------
    def render_walls(self):
        vmp, vcn = self.vmp, self.vcn
        for f in (0, 1):
            self.images["bg%d" % f] = vmp.background(vcn, bool(f))
        for s in self.used_sets:
            for p in range(9):
                if vmp.piece_empty(s - 1, p):
                    continue
                for f in (0, 1):
                    if f and p not in FLIPPED_PIECES:
                        continue
                    self.images["p%d_%d_%d" % (s, p, f)] = vmp.piece(vcn, s - 1, p, bool(f))

    # --- compass needles (DECORATE.CPS), shape ids 0..11 -------------------
    def load_compass(self):
        img = self.gd.cps("DECORATE.CPS")
        for y, (dy, dh) in enumerate(zip((120, 137, 147), (17, 10, 10))):
            for x in range(4):
                sid = self.shapes.add("compass%d" % (y * 4 + x), crop_rows(img, x * 24, dy, 24, dh))
                assert sid == y * 4 + x

    # --- decorations (assignWallsAndDecorations / loadDecorations) -----------
    def load_decorations(self):
        sets = []
        for cps, dat in self.li.decoration_sets:
            img = self.gd.cps(cps + ".CPS")
            d = self.gd.get(dat.upper())
            n = struct.unpack_from("<H", d)[0]
            props = []
            pos = 2
            for i in range(n):
                shp = [v if v != 0xFF else None for v in d[pos:pos + 10]]
                nxt, flg = d[pos + 10], d[pos + 11]
                xs = struct.unpack_from("<10h", d, pos + 12)
                ys = struct.unpack_from("<10h", d, pos + 32)
                props.append((shp, nxt, flg, xs, ys))
                pos += 52
            m = struct.unpack_from("<H", d, pos)[0]
            pos += 2
            rects = [struct.unpack_from("<4H", d, pos + i * 8) for i in range(m)]
            sets.append((cps, img, props, rects))
        # mapped list, in INF order (the INF lists the wall mappings after
        # the decoration set they refer to)
        for w, (v, dec, special, flags, dset) in self.li.wall_map.items():
            if dec == -1:
                continue
            self.wshape[w] = len(self.decos) + 1
            while True:
                cps, img, props, rects = sets[dset]
                shp, nxt, flg, xs, ys = props[dec]
                slots = []
                for k in range(10):
                    if shp[k] is None:
                        slots.append((SHAPE_NONE, 0, 0))
                        continue
                    rx, ry, rw, rh = rects[shp[k]]
                    name = "dec_%s_%d" % (cps, shp[k])
                    sid = self.shapes.add(name, crop_rows(img, rx * 8, ry, rw * 8, rh))
                    slots.append((sid, xs[k], ys[k]))
                self.decos.append([flg, 0, slots])
                if nxt:
                    self.decos[-1][1] = len(self.decos) + 1
                    dec = nxt
                else:
                    break
        assert len(self.decos) <= DEC_MAX, len(self.decos)

    # --- doors (EoBEngine::loadDoorShapes) ---------------------------------
    def load_doors(self):
        gd = self.gd
        img = gd.cps("DOOR.CPS")
        defs = gd.table("kEoB1DoorShapeDefs")
        sdefs = gd.table("kEoB1DoorSwitchShapeDefs")
        coords = gd.table("kEoB1DoorSwitchCoords")
        t1, s1, t2, s2 = self.li.door_defs
        for dtype, sid0 in ((t1, s1), (t2, s2)):
            if dtype == 0xFF:
                continue
            for i in range(3):
                e = defs[(dtype * 3 + i) * 4:(dtype * 3 + i) * 4 + 4]
                # levels 4-6: two halves, the right one mirrored (drawDoorIntern)
                shape = self.shapes.add("door%d_%d" % (dtype, i), crop_rows(img, e[0] * 8, e[1], e[2] * 8, e[3]),
                                        flipped=4 <= self.n <= 6)
                e = sdefs[(dtype * 3 + i) * 4:(dtype * 3 + i) * 4 + 4]
                sw = self.shapes.add("doorsw%d_%d" % (dtype, i), crop_rows(img, e[0] * 8, e[1], e[2] * 8, e[3]))
                self.doors[sid0 + i] = (shape, sw, coords[dtype * 6 + i * 2], coords[dtype * 6 + i * 2 + 1])

    # --- monsters: 6 frames x 3 scales (+ flipped twins) ----------------------
    def load_monsters(self):
        gd = self.gd
        enc = gd.table16("kEoBBaseEncodeMonsterDefs")
        fade = fade_table(self.vgapal)
        for slot, mg in enumerate(self.li.monster_gfx):
            if not mg:
                continue
            method, name = mg
            img = gd.cps(name + ("1.CPS" if method == 2 else ".CPS"))
            for frame in range(6):
                e = enc[(method * 18 + frame) * 4:(method * 18 + frame) * 4 + 4]
                rows = crop_rows(img, e[0] * 8, e[1], e[2] * 8, e[3])
                for scale in range(3):
                    if scale:
                        rows = scale_step(rows)
                    shown = fade_rows(rows, fade, scale) if scale else rows
                    sid = self.shapes.add("mon%d_%d_%d" % (slot, frame, scale), shown)
                    self.monshapes[(slot, frame, scale)] = sid

    # --- output ----------------------------------------------------------
    def write(self, ui_rows):
        level = self.n
        npc = self.npc_shapes()
        xd = self.xdeath_images() if self.n == XD_LEVEL else []
        pt = self.portal_images() if self.n in PORTAL_LEVELS else []
        all_rows = list(self.images.values()) + [s[1] for s in self.shapes.shapes[12:]] + list(npc.values()) + \
            [r for x, y, r in xd] + [r for x, y, r in pt]
        pal, lut = build_palette(self.vgapal, all_rows)
        # The compass stays visible while the next floor's palette is loaded.
        self.compass_lut = [1 + nearest_lab(pal[1:LEVEL_FIRST], rgb5(c)) for c in self.vgapal]
        self.pal, self.lut = pal, lut

        # --- fixed VRAM store: wall pieces, backgrounds, doors, compass ---
        items = [(n, r) for n, r in self.images.items()] + \
                [(s[0], s[1]) for s in self.shapes.shapes if not is_ram_shape(s[0])]
        sizes = [(name, len(rows[0]), len(rows)) for name, rows in items]
        sizes.sort(key=lambda item: (-item[2], -item[1]))
        top, packer, coords = Packer.with_book_stage(sizes)
        vram = bytearray(IMG_W * IMG_H)
        for name, rows in items:
            x, y = coords[name]
            w = len(rows[0])
            px = to_pixels(rows, self.compass_lut if name.startswith("compass") else lut)
            for r in range(len(rows)):
                o = (y + r) * IMG_W + x
                vram[o:o + w] = px[r * w:(r + 1) * w]
        chunks = []
        for y in range(0, SCREEN_H):
            seg = bytes(vram[y * IMG_W + SCREEN_W:(y + 1) * IMG_W])
            if any(seg):
                chunks.append((y * IMG_W + SCREEN_W, seg))
        y = SCREEN_H
        while y < top:
            n = min(CHUNK_MAX // IMG_W, top - y)
            chunks.append((y * IMG_W, bytes(vram[y * IMG_W:(y + n) * IMG_W])))
            y += n
        # the store is cleared first (what the last level left): only the
        # non-zero parts are stored
        store_clear = ((SCREEN_W, 0, IMG_W - SCREEN_W, SCREEN_H), (0, SCREEN_H, IMG_W, top - SCREEN_H))
        self.cache_y = top
        if IMG_H - 1 - top < 96:
            raise SystemExit("no room left for the shape cache (top row %d)" % top)

        # --- RAM shapes (decorations, monsters): 16 KB mapper segments ---
        gsegs = json.load(open(BUILD / "global.json"))["segments"]
        ram = bytearray()
        self.ramref = {}
        for name, rows, twin in self.shapes.shapes:
            if not is_ram_shape(name):
                continue
            px = rle_shape(to_pixels(rows, lut), len(rows[0]))
            if (len(ram) & 0x3FFF) + len(px) > 0x4000:
                ram += bytes(0x4000 - (len(ram) & 0x3FFF))
            self.ramref[name] = (gsegs + (len(ram) >> 14), len(ram) & 0x3FFF)
            ram += px
        nsegs = (len(ram) + 0x3FFF) >> 14
        open(BUILD / ("LEVEL%d.SHP" % level), "wb").write(ram)
        self.nsegs = nsegs
        print("level %d: %s, sets %s, %d images, %d shapes, %d decorations, VRAM store %d KB, cache rows %d..1022 (%d KB), RAM shapes %d KB (%d segments)"
              % (level, self.li.gfx_name, self.used_sets, len(self.images), len(self.shapes.shapes),
                 len(self.decos), packer.used // 1024, top, (1023 - top) // 2, len(ram) // 1024, nsegs))
        write_v9(BUILD / ("LEVEL%d.V9" % level), chunks, store_clear)

        with open(BUILD / ("LEVEL%d.PAL" % level), "wb") as f:
            for c in pal:
                f.write(bytes(c))

        dat = bytearray(D_SIZE)
        struct.pack_into("<HH", dat, D_BOOK_STAGE, *coords["book_stage"])
        dat[D_MAZE:D_MAZE + 4096] = self.maze.walls
        dat[D_WVMP:D_WVMP + 256] = bytes(self.wvmp)
        dat[D_WFLAGS:D_WFLAGS + 256] = bytes(self.wflags)
        dat[D_WSHAPE:D_WSHAPE + 256] = bytes(self.wshape)
        dat[D_WSPECIAL:D_WSPECIAL + 256] = bytes(self.wspecial)
        for s in range(6):
            for p in range(9):
                for f in (0, 1):
                    o = D_PIECES + ((s * 9 + p) * 2 + f) * 4
                    c = coords.get("p%d_%d_%d" % (s + 1, p, f), (0xFFFF, 0xFFFF))
                    struct.pack_into("<HH", dat, o, *c)
        for f in (0, 1):
            struct.pack_into("<HH", dat, D_BG + f * 4, *coords["bg%d" % f])
        start_block, start_dir = (490, 0) if level == 1 else (0, 0)
        struct.pack_into("<HB", dat, D_START, start_block, start_dir)
        assert len(self.shapes.shapes) <= SHP_MAX, len(self.shapes.shapes)
        struct.pack_into("<H", dat, D_NSHAPES, len(self.shapes.shapes))
        struct.pack_into("<H", dat, D_CACHEY, self.cache_y)
        dat[D_NSEGS] = self.nsegs
        for sid, (name, rows, twin) in enumerate(self.shapes.shapes):
            if is_ram_shape(name):
                seg, off = self.ramref[name]
                struct.pack_into("<HHBBBB", dat, D_SHAPES + sid * 8, 0x8000 + off, 0xFFFE, len(rows[0]), len(rows), seg, 0)
                continue
            x, y = coords[name]
            struct.pack_into("<HHBBH", dat, D_SHAPES + sid * 8, x, y, len(rows[0]), len(rows), twin)
        for i, (flg, nxt, slots) in enumerate(self.decos):
            o = D_DECOS + i * 64
            dat[o] = flg
            dat[o + 1] = nxt
            for k, (sid, x, y) in enumerate(slots):
                struct.pack_into("<Hhh", dat, o + 4 + k * 6, sid, x, y)
        for i, d in enumerate(self.doors):
            o = D_DOORS + i * 6
            if d:
                struct.pack_into("<HHBB", dat, o, *d)
            else:
                struct.pack_into("<HHBB", dat, o, SHAPE_NONE, SHAPE_NONE, 0, 0)
        for m in self.li.monsters:
            i = m["index"]
            o = D_MONSTERS + i * MON_SIZE
            unit = (m["unit"] << 1) + (i & 1)
            # block, pos, dir, type, shape, unit, mode, hp (rolled at start), dest
            struct.pack_into("<HBBBBBBhH", dat, o, m["block"], m["pos"], m["dir"] & 3, m["type"], m["shape"],
                             unit, m["mode"] & 0xFF, 0, 0)
            dat[o + 16] = m["flags"]            # spell status left
            # the items it leaves: random (half the times), fixed
            struct.pack_into("<HH", dat, o + 18, m["phase"], m["pal"])
        timers = [20, 20, 20, 20]
        for p, v in self.li.monster_timers:
            timers[p * 2] = timers[p * 2 + 1] = v
        dat[D_MONTIMERS:D_MONTIMERS + 4] = bytes(timers)
        for slot in range(2):
            for frame in range(6):
                for scale in range(3):
                    o = D_MONSHAPE + ((slot * 6 + frame) * 3 + scale) * 2
                    struct.pack_into("<H", dat, o, self.monshapes.get((slot, frame, scale), SHAPE_NONE))
        # level script: block triggers, timers; the INF itself goes to LEVELn.INF
        raw = self.li.raw
        to = struct.unpack_from("<H", raw)[0]
        n = struct.unpack_from("<H", raw, to)[0]
        assert n <= TRIG_MAX, n
        dat[D_TRIGGERS] = n
        for i in range(n):
            blk, flg, off = struct.unpack_from("<HBH", raw, to + 2 + i * 5)
            struct.pack_into("<HBH", dat, D_TRIGGERS + 1 + i * 5, blk, flg, off)
        struct.pack_into("<BHH", dat, D_SCRTIMER, self.li.timer_mode, self.li.timer_ticks, self.li.steps_until_script)
        assert to <= SCRIPT_MAX, to
        inf = bytearray(raw[:to])
        if npc:
            assert len(inf) <= NPC_TAB, len(inf)
            inf += bytes(NPC_TAB - len(inf)) + self.write_npc(npc, lut)
        for name, imgs, tab in (("PORTAL%d.V9" % level, pt, PT_TAB), ("XDEATH.V9", xd, XD_TAB)):
            if not imgs:
                continue
            chunks = []
            for x, y, rows in imgs:
                px = to_pixels(rows, lut)
                w = len(rows[0])
                for r in range(len(rows)):
                    chunks.append(((self.cache_y + y + r) * IMG_W + x, px[r * w:(r + 1) * w]))
            assert self.cache_y + max(y + len(r) for x, y, r in imgs) <= CACHE_END, name
            write_v9(BUILD / name, chunks)
            inf += bytes(tab - len(inf)) + struct.pack("<H", self.cache_y)
        open(BUILD / ("LEVEL%d.INF" % level), "wb").write(inf)
        dat[D_STATIC:D_STATIC + len(STATIC)] = STATIC
        open(BUILD / ("LEVEL%d.DAT" % level), "wb").write(dat)
        # what LOAD_LEVEL reads in one go: maze and tables, palette, script
        # (padded to SCRIPT_MAX), RAM shapes
        assert len(inf) <= SCRIPT_MAX
        with open(BUILD / ("LEVEL%d.LVL" % level), "wb") as f:
            f.write(dat)
            f.write((BUILD / ("LEVEL%d.PAL" % level)).read_bytes())
            f.write(inf + bytes(SCRIPT_MAX - len(inf)))
            f.write((BUILD / ("LEVEL%d.SHP" % level)).read_bytes())
        self.coords = coords
        return lut


    def npc_shapes(self):
        """The OUTTAKE.CPS figures of the NPC scenes of this level."""
        used = sorted({sh for lv, figs in NPC_SCENES.values() if lv == self.n for sh, x, y in figs})
        if not used:
            return {}
        img = self.gd.cps("OUTTAKE.CPS")
        defs = self.gd.table("kEoB1NpcShpData")
        return {sh: crop_rows(img, defs[sh * 4] * 8, defs[sh * 4 + 1], defs[sh * 4 + 2] * 8, defs[sh * 4 + 3])
                for sh in used}

    def portal_images(self):
        """The portal (EoBCoreEngine::seq_portal) in the cache area, 172 rows:
        frames 0..7 of PORTALB (64 x 77) in a row; under them frames 8, 9, the
        stone shape (64 x 77), the side strips 1..5 and 6..10 (24 x 75) and the
        two halves of the top strip 15 (60 x 18); then top strips 11..14."""
        a = self.gd.cps("PORTALA.CPS")
        b = self.gd.cps("PORTALB.CPS")
        out = []
        for f in range(10):
            fx, fy = (f % 5) * 64, (f // 5) * 77
            rows = [[v if v else 0 for v in r] for r in crop_rows(b, fx, fy, 64, 77)]
            out.append(((f % 8) * 64, (f // 8) * 77, rows))
        out.append((128, 77, crop_rows(a, 240, 0, 64, 77)))
        for i in range(5):
            out.append((192 + i * 24, 77, crop_rows(a, i * 24, 0, 24, 75)))
            out.append((312 + i * 24, 77, crop_rows(a, i * 24, 80, 24, 75)))
        for i in range(4):
            out.append((i * 120, 154, crop_rows(a, 120, i * 18, 120, 18)))
        out.append((432, 77, crop_rows(a, 120, 72, 60, 18)))
        out.append((432, 95, crop_rows(a, 180, 72, 60, 18)))
        return out

    def xdeath_images(self):
        """The death of Xanathar (EoBEngine::seq_xdeath): (x, y, rows) in the
        cache area: the 6 frames of XDEATH1 (3 x 2 of 104 x 88), the 4 shapes
        of XDEATH2 (112 x 88) and the falling one of XDEATH3 (128 x 95)."""
        x1 = self.gd.cps("XDEATH1.CPS")
        x2 = self.gd.cps("XDEATH2.CPS")
        x3 = self.gd.cps("XDEATH3.CPS")
        frames = [[v if v else 0 for v in r] for r in crop_rows(x1, 0, 0, 312, 176)]
        return [
            (0, 0, frames),
            (312, 0, crop_rows(x2, 0, 0, 112, 88)),
            (312, 88, crop_rows(x2, 112, 0, 112, 88)),
            (128, 176, crop_rows(x2, 0, 88, 112, 88)),
            (240, 176, crop_rows(x2, 112, 88, 112, 88)),
            (0, 176, crop_rows(x3, 176, 0, 128, 95)),
        ]

    def write_npc(self, npc, lut):
        """NPCn.V9: the figures in the shape cache area; -> the scene table."""
        pos = {}
        x = 0
        y = self.cache_y
        shelf = 0
        for sh in sorted(npc, key=lambda k: -len(npc[k])):
            w, h = len(npc[sh][0]), len(npc[sh])
            if x + w > IMG_W:
                x, y, shelf = 0, y + shelf, 0
            assert y + h <= CACHE_END, "no room for the NPC figures of level %d" % self.n
            pos[sh] = (x, y)
            x += w
            shelf = max(shelf, h)
        chunks = []
        for sh, rows in npc.items():
            px = to_pixels(rows, lut)
            w = len(rows[0])
            for r in range(len(rows)):
                chunks.append(((pos[sh][1] + r) * IMG_W + pos[sh][0], px[r * w:(r + 1) * w]))
        write_v9(BUILD / ("NPC%d.V9" % self.n), chunks)
        offs = bytearray(16)
        ents = bytearray()
        for sc, (lv, figs) in sorted(NPC_SCENES.items()):
            if lv != self.n:
                continue
            offs[sc] = 16 + len(ents)
            ents.append(len(figs))
            for sh, dx, dy in figs:
                w, h = len(npc[sh][0]), len(npc[sh])
                ents += struct.pack("<HHBBBB", pos[sh][0], pos[sh][1], w, h, dx - w // 2, dy - h)
        assert len(offs) + len(ents) <= 0xF0
        assert max(p[1] + len(npc[s]) for s, p in pos.items()) - self.cache_y <= 176, "NPC figures above 176 rows"
        return bytes(offs + ents)


def write_ui(ui_rows, lut):
    chunks = []
    px = to_pixels(ui_rows, lut)
    for r in range(200):
        chunks.append(((SCREEN_Y + r) * IMG_W + SCREEN_X, px[r * 320:(r + 1) * 320]))
    write_v9(BUILD / "UI.V9", chunks)


# ---------------------------------------------------------------------------
# Python model of the Z80 scene renderer, for checking against ScummVM
# ---------------------------------------------------------------------------
class Scene:
    def __init__(self, lv, block, d):
        self.lv = lv
        gd = lv.gd
        self.bidx = [E.signed8(v) for v in gd.table("kRpgCommonDscBlockIndex")]
        bmap = gd.table("kRpgCommonDscBlockMap")
        self.block, self.d = block, d
        self.sides = {"D": bmap[d], "R": bmap[d + 4], "L": bmap[d + 8]}
        self.vis = [(block + self.bidx[d * 18 + i]) & 0x3FF for i in range(18)]
        self.procflag = ((block >> 5) + (block & 31) + d) & 1
        self.dim1 = [E.signed8(v) for v in gd.table("kRpgCommonDscDimData1")]
        self.dim2 = gd.table("kRpgCommonDscDimData2")
        self.dimmap = gd.table("kRpgCommonDscDimMap")
        self.tileidx = gd.table("kRpgCommonDscTileIndex")
        self.shapeidx = [E.signed8(v) for v in gd.table("kRpgCommonDscShapeIndex")]
        self.dscx = gd.table16("kRpgCommonDscX")
        self.coords = gd.table16("kEoBBaseDscShapeCoords")
        self.doorshp = gd.table("kRpgCommonDscDoorShapeIndex")
        self.doorscl = gd.table("kRpgCommonDscDoorScaleOffs")
        self.doory1 = gd.table("kEoBBaseDscDoorY1")
        self.doormult1 = gd.table("kEoBBaseDscDoorScaleMult1")
        self.doormult2 = gd.table("kEoBBaseDscDoorScaleMult2")
        self.framey1 = gd.table("kRpgCommonDscDoorFrameY1")
        self.framey2 = gd.table("kRpgCommonDscDoorFrameY2")
        self.frameidx1 = gd.table("kRpgCommonDscDoorFrameIndex1")
        self.frameidx2 = gd.table("kRpgCommonDscDoorFrameIndex2")
        self.itempos = gd.table("kEoBBaseDscItemPosIndex")
        self.frm2 = [E.signed8(v) for v in gd.table("kEoBBaseDscMonsterFrmOffsTbl2")]
        self.frm1 = [E.signed8(v) for v in gd.table("kEoBBaseDscMonsterFrmOffsTbl1")]
        self.objpos = gd.table("kEoBBaseDrawObjPosIndex")
        props = gd.table("kEoB1MonsterProperties")
        self.mprops = [(props[i * 27 + 14], props[i * 27 + 23]) for i in range(len(props) // 27)]  # capsFlags, u30
        self.rows = None

    def wall(self, vb, side):
        return self.lv.maze.wall(self.vis[vb], self.sides[side])

    def door(self, w):
        return bool(self.lv.wflags[w] & 8)

    def render(self):
        lv = self.lv
        self.rows = [list(r) for r in lv.images["bg%d" % self.procflag]]
        for vb, side, piece, flip, bx, by, cond, vb2 in DRAWLIST:
            t = self.wall(vb, side)
            t2 = self.wall(vb2, "D") if cond in (3, 4) else 0
            if cond == 0 and not t:
                continue
            if cond == 1 and (not t or self.door(t)):
                continue
            if cond == 2 and self.door(t):
                continue
            if cond == 3 and (not t or self.door(t) or self.door(t2)):
                continue
            if cond == 4:
                if not t or not self.door(t2):
                    continue
                t = t2
            s = lv.wvmp[t]
            if not s:
                continue
            im = lv.images.get("p%d_%d_%d" % (s, piece, flip))
            if im:
                self.blit(im, bx * 8, by * 8, 0, VIEW_W, 0, VIEW_H)
        for i in range(18):
            t = self.tileidx[i]
            x1, x2 = self.shape_dim(t)
            if x2 <= x1:
                continue
            self.clip = (x1 * 8, x2 * 8, 0, VIEW_H)
            self.draw_decorations(t)
            if t < 15:
                w = self.wall(t, "D")
                if self.door(w):
                    self.draw_door(t, w)
                self.draw_monsters(t)
        return self.rows

    def blit(self, rows, x, y, cx1, cx2, cy1, cy2):
        for ry, row in enumerate(rows):
            yy = y + ry
            if yy < cy1 or yy >= cy2:
                continue
            for rx, v in enumerate(row):
                xx = x + rx
                if v is None or xx < cx1 or xx >= cx2:
                    continue
                self.rows[yy][xx] = v

    def draw_shape(self, sid, x, y, flipped=False):
        name, rows, twin = self.lv.shapes.shapes[sid]
        if rows is None:
            return
        if flipped:
            rows = flip_rows(rows)
        self.blit(rows, x & ~1, y, *self.clip)

    def shape_dim(self, index):
        x1, x2 = 0, 22
        m = index * 18
        for i in range(18):
            d = self.wall(i, "D")
            a = self.lv.wflags[d]
            if a & 8:
                t = self.dim2[(m + i) * 2]
                if t > x1:
                    x1 = t
                t = self.dim2[(m + i) * 2 + 1]
                if t < x2:
                    x2 = t
            else:
                t = self.dim1[m + i]
                if not self.lv.wvmp[d] or t == -40:
                    continue
                if t == -41:
                    return 22, 0
                if t > 0 and x2 > t:
                    x2 = t
                if t < 0 and x1 < -t:
                    x1 = -t
            if x2 < x1:
                break
        return x1, x2

    def draw_decorations(self, index):
        for i in (1, 0):
            s = index * 2 + i
            sel = DSC_WALLMAPPING[s]
            if not sel:
                continue
            l = self.lv.wshape[self.wall(index, "DRL"[sel - 1])]
            if l == 0xFF:
                l = 0
            while l > 0:
                l -= 1
                flg, nxt, slots = self.lv.decos[l]
                ix = self.shapeidx[s]
                shpix = abs(ix) - 1
                if i == 0 and (flg & 1 or ((flg & 2) and self.procflag)):
                    ix = -ix
                sid, sx, sy = slots[shpix]
                if sid == SHAPE_NONE:
                    l = nxt
                    continue
                w = len(self.lv.shapes.shapes[sid][1][0])
                x = 0
                if i == 0:
                    x += self.coords[(index * 5 + 4) * 2] if flg & 4 else self.dscx[index]
                if ix < 0:
                    x += 176 - sx - w
                    self.draw_shape(sid, x, sy, True)
                else:
                    x += sx
                    self.draw_shape(sid, x, sy)
                l = nxt

    def draw_door(self, index, s):
        if s == 0x85 or s >= 32:
            return
        dtype = self.doorshp[s]
        d = self.dimmap[index]
        w = self.coords[(index * 5 + 4) * 2]
        x = 88 + w
        door = self.lv.doors[dtype + 2 - d]
        if not door:
            return
        sid, swid, swx, swy = door
        a = d + self.frameidx1[self.lv.n - 1]
        b = d + self.frameidx2[self.lv.n - 1]
        self.clip = (self.clip[0], self.clip[1], self.framey1[a], self.framey2[b])
        rows = self.lv.shapes.shapes[sid][1]
        y = self.doory1[d] - len(rows)
        x -= len(rows[0]) // 2
        y -= self.doormult2[d] if s >= 30 else (s - self.doorscl[s]) * self.doormult1[d]
        self.draw_shape(sid, x, y)
        if self.lv.wshape[s] == 0xFF:
            self.draw_shape(swid, swx + w, swy)
        self.clip = (self.clip[0], self.clip[1], 0, VIEW_H)

    def draw_monsters(self, index):
        bl = self.vis[index]
        if not bl:
            return
        dist = DIST_MAP[self.dimmap[index]]
        if dist > 2:
            return
        objs = [None] * 5
        for m in self.lv.li.monsters:
            if m["block"] == bl:
                objs[self.objpos[self.d * 5 + m["pos"]]] = m
        for m in objs:
            if not m:
                continue
            caps, u30 = self.mprops[m["type"]]
            f = (self.d << 2) + (m["dir"] & 3)
            f = self.frm1[f] if caps & 2 else self.frm2[f]
            sub = abs(f)
            slot = 1 if m["shape"] else 0
            sid = self.lv.monshapes.get((slot, sub - 1, dist))
            if sid is None:
                continue
            v30 = 1 if (sub == 1 or sub > 3) else 0
            posoffs = 4 if m["pos"] == 4 else self.itempos[(self.d << 2) + m["pos"]]
            pi = (index * 5 + posoffs) * 2
            x = self.coords[pi] + 88
            y = self.coords[pi + 1] + 127
            if u30 == 1 and v30:
                y += MONSTER_Y_ADD[dist]
            rows = self.lv.shapes.shapes[sid][1]
            x -= len(rows[0]) // 2
            y -= len(rows)
            self.draw_shape(sid, x, y, f < 0)


def preview(lv, block, d, ui_rows):
    scene = Scene(lv, block, d).render()
    img = Image.new("P", (320, 200))
    img.putpalette(sum(([r * 8, g * 8, b * 8] for r, g, b in lv.pal), []))
    img.putdata(to_pixels(ui_rows, lv.lut))
    view = Image.new("P", (VIEW_W, VIEW_H))
    view.putpalette(img.getpalette())
    view.putdata(to_pixels(scene, lv.lut))
    img.paste(view, (0, 0))
    for i in range(3):
        name, rows, _ = lv.shapes.shapes[(i << 2) + d]
        shp = Image.new("P", (len(rows[0]), len(rows)))
        shp.putpalette(img.getpalette())
        shp.putdata(to_pixels(rows, lv.compass_lut))
        img.paste(shp, (COMPASS_X[i], COMPASS_Y[i]), shp.point(lambda v: 255 if v else 0, "L"))
    out = BUILD / ("preview_l%d_b%d_d%d.png" % (lv.n, block, d))
    img.convert("RGB").save(out)
    print("preview:", out)


STATIC = bytearray()     # filled by write_includes


def write_includes(gd):
    STATIC.clear()
    with open(BUILD / "vram.inc", "w") as f:
        f.write("; vram.inc - generated by tools/conv_level.py\n")
        for k in ("SCREEN_X", "SCREEN_Y", "VIEW_W", "VIEW_H", "VIEWBUF_X", "VIEWBUF_Y", "PANEL_W", "PANEL_H",
                  "PANELBUF_X", "PANELBUF_Y", "D_BOOK_STAGE",
                  "D_MAZE", "D_WVMP", "D_WFLAGS", "D_WSHAPE", "D_PIECES", "D_BG", "D_START", "D_NSHAPES",
                  "D_NSEGS", "D_CACHEY", "D_WSPECIAL", "D_MONTIMERS", "MON_SIZE",
                  "D_SHAPES", "D_DECOS", "D_DOORS", "D_MONSTERS", "D_MONSHAPE", "D_TRIGGERS", "D_SCRTIMER",
                  "TRIG_MAX", "SCRIPT_MAX", "D_STATIC", "D_SIZE"):
            f.write("%s:\tequ %d\n" % (k, globals()[k]))
    with open(BUILD / "tables.inc", "w") as f:
        f.write("; tables.inc - generated by tools/conv_level.py from the original engine tables;\n")
        f.write("; the data is in every LEVELn.DAT (D_STATIC, world segment)\n")
        blk = STATIC

        def dump(label, vals, per=18, fmt="%d"):
            f.write("%s:\tequ LEVELDAT+D_STATIC+%d\n" % (label, len(blk)))
            blk.extend(v & 0xFF for v in vals)

        def dumpw(label, vals, per=10):
            f.write("%s:\tequ LEVELDAT+D_STATIC+%d\n" % (label, len(blk)))
            for v in vals:
                blk.extend(struct.pack("<h", v))

        f.write("; offsets of the 18 visible blocks for each facing (signed)\n")
        dump("DSC_BLOCKINDEX", [E.signed8(v) for v in gd.table("kRpgCommonDscBlockIndex")])
        f.write("; wall side facing the party / its right face / its left face, per facing\n")
        dump("DSC_BLOCKMAP", list(gd.table("kRpgCommonDscBlockMap")), 12)
        f.write("; order in which the visible blocks get their shapes drawn\n")
        dump("DSC_TILEINDEX", list(gd.table("kRpgCommonDscTileIndex")))
        f.write("; distance class of each visible block (0 far .. 3 the party row)\n")
        dump("DSC_DIMMAP", list(gd.table("kRpgCommonDscDimMap")))
        f.write("; horizontal clip of the shapes of block m caused by the blocks i in front:\n")
        f.write("; 18 pointers, then per m (i, t signed, door x1, door x2)... FFh; only the\n")
        f.write("; pairs of kRpgCommonDscDimData1/2 that change the window\n")
        d1 = [E.signed8(v) for v in gd.table("kRpgCommonDscDimData1")]
        d2 = list(gd.table("kRpgCommonDscDimData2"))
        lists = []
        for m in range(18):
            e = bytearray()
            for i in range(18):
                k = m * 18 + i
                if d1[k] != -40 or (d2[2 * k], d2[2 * k + 1]) != (0, 22):
                    e += bytes((i, d1[k] & 0xFF, d2[2 * k], d2[2 * k + 1]))
            lists.append(e + b"\xff")
        f.write("DSC_DIMLIST:\tequ LEVELDAT+D_STATIC+%d\n" % len(blk))
        p = 0x8000 + D_STATIC + len(blk) + 36
        for e in lists:
            blk.extend(struct.pack("<H", p))
            p += len(e)
        for e in lists:
            blk.extend(e)
        f.write("; decoration slot (1-based, negative = mirrored) for block*2 + pass\n")
        dump("DSC_SHAPEINDEX", [E.signed8(v) for v in gd.table("kRpgCommonDscShapeIndex")])
        f.write("; wall used by the decoration passes: 0 none, 1 facing, 2 right, 3 left\n")
        dump("DSC_WALLMAPPING", DSC_WALLMAPPING)
        f.write("; x offset of the facing-wall decoration per visible block\n")
        dumpw("DSC_X", gd.table16("kRpgCommonDscX"))
        f.write("; (x, y) of the 5 object positions of each visible block\n")
        dumpw("DSC_SHAPECOORDS", gd.table16("kEoBBaseDscShapeCoords"))
        dump("DSC_ITEMPOSINDEX", list(gd.table("kEoBBaseDscItemPosIndex")), 16)
        f.write("; floor items: x of the niche items, size per (distance << 2) + position, other clip block\n")
        dumpw("DSC_ITEMSHPX", gd.table16("kEoBBaseDscItemShpX"), 18)
        dump("DSC_ITEMSCALE", [E.signed8(v) for v in gd.table("kEoBBaseDscItemScaleIndex")])
        dump("DSC_ITEMTILE", list(gd.table("kEoBBaseDscItemTileIndex")))
        dump("DSC_MONFRM1", [E.signed8(v) for v in gd.table("kEoBBaseDscMonsterFrmOffsTbl1")], 16)
        dump("DSC_MONFRM2", [E.signed8(v) for v in gd.table("kEoBBaseDscMonsterFrmOffsTbl2")], 16)
        dump("DSC_OBJPOSINDEX", list(gd.table("kEoBBaseDrawObjPosIndex")), 20)
        dump("DIST_MAP", DIST_MAP, 4)
        dump("MONSTER_YADD", MONSTER_Y_ADD, 7)
        props = gd.table("kEoB1MonsterProperties")
        f.write("; monster type -> capsFlags, u30\n")
        dump("MONSTER_PROPS", sum(([props[i * 27 + 14], props[i * 27 + 23]] for i in range(len(props) // 27)), []), 22)
        dump("COMPASS_X", COMPASS_X, 3)
        dump("COMPASS_Y", COMPASS_Y, 3)
    with open(BUILD / "doortab.inc", "w") as f:
        # the door tables live in page 3 with DRAW_DOOR (doors.asm)
        f.write("; doortab.inc - generated by tools/conv_level.py: the door tables (page 3)\n")

        def tab(label, vals):
            f.write("%s:\tdb %s\n" % (label, ",".join(str(v & 0xFF) for v in vals)))
        tab("DSC_DOORSHPINDEX", gd.table("kRpgCommonDscDoorShapeIndex"))
        tab("DSC_DOORSCALEOFFS", gd.table("kRpgCommonDscDoorScaleOffs"))
        for n in (1, 3, 4, 5, 6, 7):
            tab("DSC_DOORY%d" % n, gd.table("kEoBBaseDscDoorY%d" % n))
        for n in range(1, 7):
            tab("DSC_DOORMULT%d" % n, gd.table("kEoBBaseDscDoorScaleMult%d" % n))
        tab("DSC_DOORFRAMEY1", gd.table("kRpgCommonDscDoorFrameY1"))
        tab("DSC_DOORFRAMEY2", gd.table("kRpgCommonDscDoorFrameY2"))
        tab("DSC_DOORFRAMEIDX1", gd.table("kRpgCommonDscDoorFrameIndex1"))
        tab("DSC_DOORFRAMEIDX2", gd.table("kRpgCommonDscDoorFrameIndex2"))
        # levels 4-6: the window of the two halves, per visible block (x1, x2
        # in pixels, rounded down to 8 as the original's >> 3)
        ext = gd.table16("kEoBBaseDscDoorCoordsExt")
        f.write("DSC_DOOREXT:\tdw %s\n" % ",".join(str((v >> 3) << 3) for v in ext))
    with open(BUILD / "teletab.inc", "w") as f:
        f.write("; teletab.inc - generated by tools/conv_level.py: the sparkles of the\n")
        f.write("; teleporters, 6 x 13 (x, y) (kEoBBaseDscTelptrShpCoords, page 3)\n")
        f.write("TELE_COORDS:\tdb %s\n" % ",".join(str(E.signed8(v)) for v in gd.table("kEoBBaseDscTelptrShpCoords")))
    with open(BUILD / "drawlist.inc", "w") as f:
        f.write("; drawlist.inc - generated by tools/conv_level.py (data in LEVELn.DAT)\n")
        f.write("; vb, side, vb2, cond, piece*2+flip, src x offset (px), dst x (px), dst y (px), w (px), h (px)\n")
        f.write("DRAWLIST:\tequ LEVELDAT+D_STATIC+%d\n" % len(STATIC))
        for vb, side, piece, flip, bx, by, cond, vb2 in DRAWLIST:
            _, w, h = E.VMP.PIECES[piece]
            x0 = max(bx, 0)
            x1 = min(bx + w, 22)
            STATIC.extend([vb, SIDE[side], vb2, cond, piece * 2 + flip, (x0 - bx) * 8, x0 * 8, by * 8,
                           (x1 - x0) * 8, h * 8])
        STATIC.append(255)
    assert len(STATIC) <= STATIC_MAX, len(STATIC)


def main():
    level = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    prev = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else None
    gd = E.GameData()
    BUILD.mkdir(exist_ok=True)
    ui = gd.cps("PLAYFLD.CPS")
    ui_rows = [list(ui[y * 320:(y + 1) * 320]) for y in range(200)]
    write_includes(gd)
    lv = Level(gd, level)
    lv.write(ui_rows)
    if prev:
        preview(lv, prev[0], prev[1], ui_rows)


if __name__ == "__main__":
    main()
