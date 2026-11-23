"""eoblib.py - Readers for the Eye of the Beholder (DOS) data files.

PAK archives, Westwood LCW ("format80") decompression, CPS images, VCN/VMP
wall block sets, MAZ files and the EOB1 level header (INF).
"""
import glob
import json
import os
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PC = Path(os.environ.get("EOB_PC_DIR", ROOT / "third_party" / "dos-es"))
TABLES = ROOT / "build" / "eob_tables.json"
# EOB_LANG=es (the default) converts the Spanish DOS game into build/;
# EOB_LANG=en takes the English texts (build/pc_en/: LEVEL1.INF, LEVEL2.INF,
# TEXT.DAT, ITEM.DAT; the rest is the same in both) and the English tables of
# the executable, into build/en/.
LANG = os.environ.get("EOB_LANG", "es")
LANGS = {"es": ("0x3044", None, ROOT / "build"),
         "en": ("0x3001", ROOT / "build" / "pc_en", ROOT / "build" / "en")}
TABLE_KEY, PC_LANG, BUILD = LANGS[LANG]


def lcw(src, size):
    """Westwood LCW decompression (format80)."""
    dst = bytearray()
    i = 0
    while len(dst) < size:
        c = src[i]
        i += 1
        if c == 0x80:
            break
        if not c & 0x80:
            cnt = ((c & 0x70) >> 4) + 3
            pos = ((c & 0x0F) << 8) | src[i]
            i += 1
            for _ in range(cnt):
                dst.append(dst[len(dst) - pos])
        elif c == 0xFE:
            cnt, v = struct.unpack_from("<HB", src, i)
            i += 3
            dst += bytes([v]) * cnt
        elif c == 0xFF:
            cnt, pos = struct.unpack_from("<HH", src, i)
            i += 4
            for k in range(cnt):
                dst.append(dst[pos + k])
        elif c & 0x40:
            cnt = (c & 0x3F) + 3
            pos = struct.unpack_from("<H", src, i)[0]
            i += 2
            for k in range(cnt):
                dst.append(dst[pos + k])
        else:
            cnt = c & 0x3F
            dst += src[i:i + cnt]
            i += cnt
    return bytes(dst)


def read_pak(path):
    d = open(path, "rb").read()
    i = 0
    ents = []
    while True:
        off = struct.unpack_from("<I", d, i)[0]
        if off == 0 or off > len(d):
            break
        j = d.index(b"\0", i + 4)
        ents.append((d[i + 4:j].decode("latin1").upper(), off))
        i = j + 1
    files = {}
    for k, (n, o) in enumerate(ents):
        e = ents[k + 1][1] if k + 1 < len(ents) else len(d)
        if e > o and n:
            files[n] = d[o:e]
    return files


class GameData:
    """All files of the PAK archives plus the loose files of the game dir."""

    def __init__(self, pcdir=PC, language_dir=PC_LANG):
        self.files = {}
        for p in sorted(glob.glob(str(pcdir / "EOBDATA*.PAK"))):
            self.files.update(read_pak(p))
        for p in pcdir.iterdir():
            if p.is_file() and p.suffix.upper() != ".PAK":
                self.files.setdefault(p.name.upper(), open(p, "rb").read())
        if language_dir is None:
            # the Spanish release keeps its translated level scripts in
            # LEVELn.DRO (uncompressed CPS); the original looks for them
            # before LEVELn.INF (readLevelFileData). Their door shapes stay
            # those of the INF: LEVEL3.DRO has none for the second kind of
            # door, which the level uses (invisible closed doors there).
            for n in list(self.files):
                if n.startswith("LEVEL") and n.endswith(".DRO"):
                    inf = n[:-4] + ".INF"
                    dro = bytearray(self.files[n])
                    pos = 10 + struct.unpack_from("<H", dro, 8)[0] + 38
                    dro[pos:pos + 4] = self.cps(inf)[38:42]
                    self.files[inf] = bytes(dro)
        else:
            for p in language_dir.iterdir():
                if p.is_file():
                    self.files[p.name.upper()] = open(p, "rb").read()
        self.tables = None

    def get(self, name):
        return self.files[name.upper()]

    def cps(self, name):
        """Decoded CPS: 64000 bytes of VGA palette indexes (320x200)."""
        b = self.get(name)
        comp, usz, pal = struct.unpack_from("<HIH", b, 2)
        if comp == 4:
            return lcw(b[10 + pal:], usz)
        if comp == 0:
            return b[10 + pal:10 + pal + usz]
        raise ValueError("%s: compression %d" % (name, comp))

    def palette(self, name):
        """VGA palette file (.PAL / .COL): 256 x (r, g, b) in 0..63."""
        p = self.get(name)
        return [(p[i * 3] & 0x3F, p[i * 3 + 1] & 0x3F, p[i * 3 + 2] & 0x3F) for i in range(256)]

    def table(self, name):
        if self.tables is None:
            self.tables = json.load(open(TABLES))[TABLE_KEY]   # DOS, Spanish or English
        return bytes(self.tables[name]["data"])

    def table16(self, name):
        d = self.table(name)
        return [struct.unpack_from(">h", d, i)[0] for i in range(0, len(d), 2)]


def signed8(v):
    return v - 256 if v > 127 else v


class VCN:
    """8x8 blocks of 4 bits plus the two 16-entry colour tables."""

    def __init__(self, data):
        self.count = struct.unpack_from("<H", data)[0]
        self.coltab = data[2:34]
        self.blocks = data[34:34 + self.count * 32]

    def block(self, idx, table, flip=False, overlay=False):
        """64 VGA indexes; None = transparent (overlay blocks, nibble 0)."""
        off = idx * 32
        out = []
        for y in range(8):
            row = []
            for x in range(4):
                c = self.blocks[off + y * 4 + x]
                for nib in ((c >> 4), (c & 15)):
                    if overlay and nib == 0:
                        row.append(None)
                    else:
                        row.append(self.coltab[table * 16 + nib])
            if flip:
                row.reverse()
            out += row
        return out


class VMP:
    # (offset inside a wall set, width, height) of the nine wall pieces,
    # in the order used by the draw list (vmpVisOffs)
    PIECES = [(102, 3, 5), (97, 1, 5), (129, 6, 5), (117, 2, 6), (81, 2, 8),
              (159, 10, 8), (45, 3, 12), (239, 16, 12), (0, 3, 15)]

    def __init__(self, data):
        n = struct.unpack_from("<H", data)[0]
        self.codes = struct.unpack_from("<%dH" % n, data, 2)
        self.sets = (n - 330) // 431

    def render(self, vcn, base, w, h, table, flipped=False):
        """Pixels of a rectangle of blocks: list of rows of VGA indexes/None.
        flipped: the piece as generateVmpTileDataFlipped would place it
        (mirrored block order and each block mirrored)."""
        rows = [[None] * (w * 8) for _ in range(h * 8)]
        for by in range(h):
            for bx in range(w):
                code = self.codes[base + by * w + bx]
                if code == 0:
                    continue
                overlay = bool(code & 0x8000)
                flip = bool(code & 0x4000)
                idx = code & 0x3FFF
                if overlay:
                    idx = code & 0x3FFF
                    flip = bool(code & 0x4000)
                px = vcn.block(idx, table, flip ^ flipped, overlay)
                dx = (w - 1 - bx) if flipped else bx
                for y in range(8):
                    rows[by * 8 + y][dx * 8:dx * 8 + 8] = px[y * 8:y * 8 + 8]
        return rows

    def background(self, vcn, flipped=False):
        return self.render(vcn, 0, 22, 15, 0, flipped)

    def piece(self, vcn, wset, piece, flipped=False):
        off, w, h = self.PIECES[piece]
        return self.render(vcn, 330 + wset * 431 + off, w, h, 1, flipped)

    def piece_empty(self, wset, piece):
        off, w, h = self.PIECES[piece]
        base = 330 + wset * 431 + off
        return not any(self.codes[base:base + w * h])


class Maze:
    def __init__(self, data):
        self.walls = data[6:6 + 4096]  # block*4 + side (N, E, S, W)

    def wall(self, block, side):
        return self.walls[(block & 0x3FF) * 4 + side]


class LevelInfo:
    """EOB1 LEVELn.INF header (see ScummVM initLevelData, EOB1 branch)."""

    def __init__(self, gd, level):
        data = gd.cps("LEVEL%d.INF" % level)   # the INF is LCW compressed
        self.raw = data
        pos = 2
        self.maz_name = data[pos:pos + 12].split(b"\0")[0].decode()
        pos += 12
        self.gfx_name = data[pos:pos + 12].split(b"\0")[0].decode()
        pos += 12
        pos += 12                      # 0xFF byte + 11 unused
        self.door_defs = tuple(data[pos:pos + 4])
        pos += 4
        self.timer_mode = data[pos]
        pos += 1
        self.timer_ticks = struct.unpack_from("<H", data, pos)[0]
        pos += 2
        self.steps_until_script = struct.unpack_from("<H", data, pos)[0]
        pos += 2
        self.monster_gfx = []          # (method, name)
        for i in range(2):
            if data[pos] != 0xFF:
                self.monster_gfx.append((data[pos], data[pos + 1:pos + 13].split(b"\0")[0].decode()))
            else:
                self.monster_gfx.append(None)
            pos += 13
        # monster timer intervals: pairs until 0xFF
        self.monster_timers = []
        while data[pos] != 0xFF:
            self.monster_timers.append((data[pos], data[pos + 1]))
            pos += 2
        pos += 1
        self.monsters = []
        for i in range(30):
            m = data[pos:pos + 14]
            pos += 14
            if m[0] == 0xFF:
                continue
            self.monsters.append(dict(index=m[0], unit=m[1],
                                      block=struct.unpack_from("<H", m, 2)[0],
                                      pos=m[4], dir=signed8(m[5]), type=m[6],
                                      shape=m[7], mode=m[8], flags=m[9],
                                      phase=struct.unpack_from("<H", m, 10)[0],   # random item
                                      pal=struct.unpack_from("<H", m, 12)[0]))    # fixed item
        num = struct.unpack_from("<H", data, pos)[0]
        pos += 2
        self.decoration_sets = []      # (cps, dat)
        self.wall_map = {}             # wall type -> (vmp set, dec index, special, flags)
        for i in range(num):
            kind = data[pos]
            pos += 1
            if kind == 0xEC:
                cps = data[pos:pos + 12].split(b"\0")[0].decode()
                dat = data[pos + 12:pos + 24].split(b"\0")[0].decode()
                self.decoration_sets.append((cps, dat))
                pos += 24
            else:
                w, vmp, dec, special, flags = data[pos:pos + 5]
                self.wall_map[w] = (vmp, signed8(dec), special, flags ^ 4, len(self.decoration_sets) - 1)
                pos += 5
        self.script_offset = pos


# resetWallData() presets (ScummVM scene_eob.cpp)
def default_wall_tables(gd):
    vmp = [0] * 256
    vmp[1] = 1
    vmp[2] = 2
    for i in range(3, 23):
        vmp[i] = 3
    vmp[23] = 4
    vmp[24] = 5
    flags = [0] * 256
    preset = gd.table("kEoBBaseWllFlagPreset")
    flags[:len(preset)] = preset
    special = [0] * 256
    for i in list(range(3, 8)) + list(range(13, 18)):
        special[i] = 1
    special[8] = special[18] = 6
    return vmp, flags, special
