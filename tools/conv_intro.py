#!/usr/bin/env python3
"""conv_intro.py - The animated intro of EOB1 (EoBIntroPlayer, DOS) compiled
for src/intro.asm: the scenes of the original run here against a model of
its pages, and every drawing operation becomes a V9990 command in a list
(build/INTRO.SEQ); the images (one per page load, in the 64-colour palette
of their scene) and the blurred shapes become V9 files (build/INnn.V9);
the palettes INPALn.PAL; the music and sounds of SOUND.DAT two sound sets
(INSND1.DAT: the credits, INSND2.DAT: the rest).

The pages of the original are VRAM areas: page 0 the screen (32, 20),
page 2 (= 3) at (0, 240), page 4 (= 5) at (0, 440). Shapes (encodeShape)
are copied to a shape area and drawn back with the transparent copy.

INTRO.SEQ commands:
  00                   end
  01 n                 wait n frames (60 Hz); a key or a click ends the intro
  02 sx sy dx dy w h   copy (u16 each, VRAM coordinates)
  03 sx sy dx dy w h   transparent copy (colour 0)
  04 x y w h c         fill (u16 x4, u8 colour)
  05 name 0            load a V9 file
  06 192 bytes         the palette
  07 n                 sound effect / song n of the current sound set
  08 name 0            sound set (stops what plays)
  09 x y c text 0      text with the 8x8 font (u16 x, u8 y, u8 colour)
  0A c                 whirl transition with colour c"""
import random
import struct
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import eoblib as E
import conv_level as C
import conv_sfx as S

BUILD = E.BUILD
SX, SY = C.SCREEN_X, C.SCREEN_Y
PAGES = {0: (SX, SY), 2: (0, 240), 3: (0, 240), 4: (0, 440), 5: (0, 440)}
SHAPE_AREAS = [(320, 240, 192, 760), (0, 640, 320, 360)]
TICK_FRAMES = 55 / 16.683       # the engine tick of the original, in frames
CHUNK_MAX = 0xC000 - 0x8C00     # the buffer of src/intro.asm

# the palette of the scene in which each image is shown
TAGS = {
    "WESTWOOD.COL": ["AND.CMP", "SSI.CMP", "PRESENT.CMP", "DAND.CMP", "WESTWOOD.CMP", "TITLE-V.CMP"],
    "TOWRMAGE.COL": ["TOWRMAGE.CMP", "ORB.CMP"],
    "WTRDP2.COL": ["WTRDP1.CMP", "WTRDP2.CMP", "WTRDP3.CMP", "KING.CMP", "ADVENTUR.CMP", "HANDS.CMP"],
    "ORB.COL": ["ORB.CMP", "TUNNEL.CMP"],
    "ZOOMTUNL.COL": ["TUNNEL.CMP", "AVALANCH.CMP", "ZOOMTUNL.CMP"],
}
FILL1, FILL2 = 12, 157


class Intro:
    def __init__(self, gd):
        self.gd = gd
        self.seq = bytearray()
        self.nfiles = 0
        self.pals = {}
        self.luts = {}
        self.palno = {}
        for n, (tag, files) in enumerate(TAGS.items()):
            vga = gd.palette(tag)
            rows = []
            for f in files:
                img = gd.cps(f)
                rows.append([list(img[y * 320:(y + 1) * 320]) for y in range(200)])
            # 0 (transparent in the shapes) and 1 are black in every palette:
            # what stays on the screen keeps its colour when it changes
            cols = [c for c in C.pixel_colours(vga, rows) if c != (0, 0, 0)]
            pal = [(0, 0, 0), (0, 0, 0)] + C.quantize(cols, 62)
            lut = [0 if v == 0 else (1 if C.rgb5(vga[v]) == (0, 0, 0) else 2 + C.nearest(pal[2:], C.rgb5(vga[v])))
                   for v in range(256)]
            self.pals[tag] = pal
            self.luts[tag] = lut
            self.palno[tag] = n
            with open(BUILD / ("INPAL%d.PAL" % n), "wb") as fp:
                for c in pal:
                    fp.write(bytes(c))
        self.tag = "WESTWOOD.COL"
        self.images = {}
        self.page_img = {}
        self.release()
        random.seed(1990)

    # --- the command list ---------------------------------------------
    def op(self, code, *words, b=b""):
        self.seq.append(code)
        for w in words:
            self.seq += struct.pack("<H", w & 0xFFFF)
        self.seq += b

    def wait(self, ticks):
        f = int(round(ticks * TICK_FRAMES))
        while f > 0:
            self.seq += bytes((1, min(f, 255)))
            f -= 255

    def wait_frames(self, f):
        while f > 0:
            self.seq += bytes((1, min(f, 255)))
            f -= 255

    def sfx(self, n):
        self.seq += bytes((7, n))

    def sndset(self, name):
        self.seq += bytes((8,)) + name.encode() + b"\0"

    def setpal(self, tag):
        self.tag = tag
        self.seq += bytes((6,)) + b"".join(bytes(c) for c in self.pals[tag])

    def col(self, vga):
        return self.luts[self.tag][vga]

    # --- the pages -----------------------------------------------------
    def load(self, name, page, tag=None):
        """loadBitmap: the image (in the palette of its scene) into a page."""
        tag = tag or self.tag
        key = (name, tag)
        img = self.gd.cps(name)
        self.page_img[page & ~1] = img
        if key not in self.images:
            lut = self.luts[tag]
            px = bytes(lut[v] for v in img)
            n = self.nfiles
            self.nfiles += 1
            self.images[key] = n
            self.images[(key, "px")] = px
        n = self.images[key]
        px = self.images[(key, "px")]
        fn = "IN%02d_%d.V9" % (n, page & ~1)
        if not (BUILD / fn).exists() or True:
            ox, oy = PAGES[page]
            C.write_v9(BUILD / fn, [((oy + r) * C.IMG_W + ox, px[r * 320:(r + 1) * 320]) for r in range(200)])
        self.seq += bytes((5,)) + fn.encode() + b"\0"

    def copy(self, sx, sy, dx, dy, w, h, sp, dp, trans=False):
        """copyRegion within the 320 x 200 pages."""
        if sx < 0:
            dx -= sx; w += sx; sx = 0
        if sy < 0:
            dy -= sy; h += sy; sy = 0
        if dx < 0:
            sx -= dx; w += dx; dx = 0
        if dy < 0:
            sy -= dy; h += dy; dy = 0
        w = min(w, 320 - sx, 320 - dx)
        h = min(h, 200 - sy, 200 - dy)
        if w <= 0 or h <= 0:
            return
        spx, spy = PAGES[sp]
        dpx, dpy = PAGES[dp]
        self.op(3 if trans else 2, spx + sx, spy + sy, dpx + dx, dpy + dy, w, h)

    def fill(self, x1, y1, x2, y2, vga, page=0):
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(319, x2), min(199, y2)
        if x2 < x1 or y2 < y1:
            return
        px, py = PAGES[page]
        self.op(4, px + x1, py + y1, x2 - x1 + 1, y2 - y1 + 1, b=bytes((self.col(vga),)))

    def clear(self, page):
        self.fill(0, 0, 319, 199, 0, page)

    # --- shapes --------------------------------------------------------
    def release(self):
        self.shapes = {}
        self.free = [list(a) for a in SHAPE_AREAS]     # (x, y, w, h) shelves

    def alloc(self, w, h):
        for a in self.free:
            x, y, aw, ah = a
            # one shelf per allocation column: simple top-down, left-right packing
            if not hasattr(self, "shelf"):
                self.shelf = {}
            sh = self.shelf.setdefault(id(a), [x, y, 0])
            if sh[0] + w > x + aw:
                sh[0], sh[1], sh[2] = x, sh[1] + sh[2], 0
            if sh[1] + h <= y + ah and sh[0] + w <= x + aw:
                pos = (sh[0], sh[1])
                sh[0] += w
                sh[2] = max(sh[2], h)
                return pos
        raise SystemExit("intro: no room for a shape %dx%d" % (w, h))

    def encode(self, idx, page, x8, y, w8, h):
        w = w8 * 8
        pos = self.alloc(w, h)
        px, py = PAGES[page]
        self.op(2, px + x8 * 8, py + y, pos[0], pos[1], w, h)
        self.shapes[idx] = (pos[0], pos[1], w, h)

    def shape_pixels(self, idx, rows):
        """A shape made here (blur): its own V9 file."""
        h, w = len(rows), len(rows[0])
        pos = self.alloc(w, h)
        lut = self.luts[self.tag]
        n = self.nfiles
        self.nfiles += 1
        fn = "IN%02d_S.V9" % n
        C.write_v9(BUILD / fn, [((pos[1] + r) * C.IMG_W + pos[0], bytes(lut[v] for v in rows[r])) for r in range(h)])
        self.seq += bytes((5,)) + fn.encode() + b"\0"
        self.shapes[idx] = (pos[0], pos[1], w, h)

    def draw(self, page, idx, x, y):
        sx, sy, w, h = self.shapes[idx]
        # clip to the page
        if x < 0:
            sx -= x; w += x; x = 0
        if y < 0:
            sy -= y; h += y; y = 0
        w = min(w, 320 - x)
        h = min(h, 200 - y)
        if w <= 0 or h <= 0:
            return
        px, py = PAGES[page]
        self.op(3, sx, sy, px + x, py + y, w, h)

    # --- text ------------------------------------------------------------
    def subtitle(self, s, y, col):
        """printSubtitle, Spanish: centred lines of the 8x8 font. The English
        version of the original has no subtitles in its introduction."""
        if E.LANG != "es":
            return
        y -= 1
        for line in s.split("\r"):
            tx = (20 - (len(line) >> 1)) << 1
            self.seq += bytes((9,)) + struct.pack("<HBB", tx << 2, y << 3, self.col(col)) + \
                bytes(ord(ch) & 0x7F for ch in line) + b"\0"
            y += 1

    # --- transitions -------------------------------------------------------
    def crossfade(self, sx, sy, dx, dy, w, h, sp):
        self.copy(sx, sy, dx, dy, w, h, sp, 0)

    def whirl(self):
        self.seq += bytes((10, self.col(FILL1)))

    def box_morph(self, tdx, tdy, tfx, tfy, tsx, tsy, tfw, tfh, ox1, oy1, ow, oh, fill=-1):
        ox2 = ox1 + ow
        oy2 = oy1 + oh
        if oy2 > 21:
            oy2 = 21
        if fill != -1:
            self.fill(0, 170, 319, 186, fill, 0)
            self.fill(0, 170, 319, 186, fill, 2)
        w = h = 1
        while True:
            self.copy(tsx << 3, tsy << 3, tdx << 3, tdy << 3, w << 3, h << 3, 2, 0)
            if ox1 < tdx:
                self.copy(312, 0, ox1 << 3, 0, 8, 176, 0, 0)
            if oy1 < tdy:
                self.copy(0, 192, 0, oy1 << 3, 320, 8, 0, 0)
            if tfx + tfw <= ox2:
                self.copy(312, 0, ox2 << 3, 0, 8, 176, 0, 0)
            if tfy + tfh <= oy2:
                self.copy(0, 192, 0, oy2 << 3, 320, 8, 0, 0)
            done = not (tdx != tfx or tdy != tfy or w != tfw or h != tfh or ox1 < tfx or oy1 < tfy
                        or tfx + tfw < ox2 or tfy + tfh < oy2)
            v = tfx - tdx
            tdx += (v > 0) - (v < 0)
            v = tfy - tdy
            tdy += (v > 0) - (v < 0)
            if w != tfw:
                w += 2
            w = min(w, tfw)
            if h != tfh:
                h += 2
            h = min(h, tfh)
            ox1 = min(ox1 + 1, tfx)
            oy1 = min(oy1 + 1, tfy)
            if tfx + tfw < ox2:
                ox2 -= 1
            if tfy + tfh < oy2:
                oy2 -= 1
            self.wait(1)
            if done:
                break

    def blur(self, img, x1, y1, w, h, step):
        """copyBlurRegion: the rows of the result (to (0, 0) of page 3)."""
        out = [[0] * w for _ in range(h)]

        def px(x, y):
            return img[(y1 + y) * 320 + x1 + x]
        if step in (1, 2):
            y = 0
            while y < h:
                for i in range(0, w, 2):
                    out[y][i] = px(i, y)
                if y + 1 < h:
                    if step == 1:
                        for i in range(0, w, 2):
                            if i + 1 < w:
                                out[y + 1][i + 1] = px(i + 1, y + 1)
                y += 2
        else:
            for y in range(h):
                if y % 3 == 0:
                    ii = 0
                    while ii < w - 3:
                        out[y][ii] = px(ii, y)
                        ii += 3
        return out

    # =======================================================================
    # the scenes (EoBIntroPlayer, the DOS branches)
    # =======================================================================
    def opening_credits(self):
        files = ["AND.CMP", "SSI.CMP", "PRESENT.CMP", "DAND.CMP", "WESTWOOD.CMP"]
        delays = [140, 50, 100, 50, 140]
        self.sndset("INSND1.DAT")
        self.sfx(1)
        self.setpal("WESTWOOD.COL")
        self.load("WESTWOOD.CMP", 2)
        self.copy(0, 0, 0, 0, 320, 200, 2, 0)
        self.wait(delays[0])
        for i in range(4):
            self.load(files[i], 2)
            self.copy(0, 0, 0, 0, 320, 200, 2, 4)
            self.crossfade(0, 50, 0, 50, 320, 102, 4)
            self.wait(delays[i + 1])

    def title(self):
        self.sndset("INSND2.DAT")
        self.sfx(2)
        self.load("TITLE-V.CMP", 4)
        self.copy(0, 0, 0, 0, 320, 200, 4, 2)
        self.crossfade(0, 0, 0, 0, 320, 200, 2)
        self.wait(120)

    def tower(self):
        g = self.gd
        strings = ["NOSOTROS, LOS LORDS DE WATERDEEP,\rHEMOS DECIDIDO SALVAR NUESTRA CIUDAD\rDE LOS ANTIGUOS DEMONIOS",
                   "", "LLAMEMOS A LOS HEROES DE LA REGION\rY ELIJAMOS A NUESTROS GUERREROS."]
        self.tag = "TOWRMAGE.COL"
        self.load("TOWRMAGE.CMP", 2)
        self.encode(10, 2, 0, 0, 16, 56)
        self.copy(0, 0, 0, 0, 320, 200, 2, 4)
        self.clear(2)
        for i in range(0, 200, 64):
            self.copy(128, 104, 96, i, 128, 64, 4, 2)
        self.fill(0, 184, 319, 199, FILL1, 2)
        self.whirl()
        self.setpal("TOWRMAGE.COL")
        self.clear(2)
        for i in range(0, 200, 64):
            self.copy(128, 104, 0, i, 128, 64, 4, 2)
        self.subtitle(strings[0], 22, 0x0F)
        for i in range(64):
            self.copy(0, 142 - i, 96, 0, 128, i + 1, 4, 0)
            self.copy(0, 0, 96, i + 1, 128, 167 - i, 2, 0)
            self.wait(1)
        for i in range(23):
            self.copy(0, 78 - i, 96, 0, 24, 65 + i, 4, 0)
            self.copy(104, 78 - i, 200, 0, 24, 65 + i, 4, 0)
            self.copy(24, 109, 120, i + 31, 80, 34, 4, 0)
            self.copy(152, 0, 120, 32, 80, i + 1, 4, 0)
            self.copy(0, 0, 96, 65 + i, 128, 103 - i, 2, 0)
            self.wait(1)
        for i in range(56):
            self.copy(0, 55, 96, i, 24, 54, 4, 0)
            self.copy(104, 55, 200, i, 24, 54, 4, 0)
            self.copy(0, 109, 96, 54 + i, 128, 34, 4, 0)
            if i < 32:
                self.fill(128, 0, 255, i + 1, FILL1, 2)
                self.copy(152, 0, 120, 32, 80, i + 25, 4, 0)
            else:
                self.fill(128, 0, 255, i + 1, FILL1, 2)
                self.copy(152, i + 1, 120, 32 + i + 1, 80, 23, 4, 0)
                self.copy(152, 0, 152, 32, 80, i + 1, 4, 2)
            self.draw(2, 10, 128, i - 55)
            self.copy(128, 0, 96, 0, 128, i + 1, 2, 0)
            self.copy(0, 0, 96, i + 88, 128, 80 - i, 2, 0)
            self.wait(1)
        self.fill(0, 168, 319, 199, FILL1, 0)
        self.subtitle(strings[2], 23, 0x0F)
        self.wait(65)
        self.release()

    def orb(self):
        orb = self.gd.cps("ORB.CMP")
        towr = self.gd.cps("TOWRMAGE.CMP")
        self.load("ORB.CMP", 2)
        self.encode(4, 2, 0, 0, 20, 136)
        self.load("TOWRMAGE.CMP", 2)
        self.encode(3, 2, 16, 0, 16, 104)
        self.fill(0, 0, 127, 103, FILL1, 2)
        for i in range(1, 4):
            self.shape_pixels(3 - i, self.blur(towr, 128, 0, 128, 104, i))
        self.fill(0, 0, 159, 135, FILL1, 2)
        self.copy(0, 0, 0, 0, 320, 200, 2, 4)
        self.clear(0)
        self.sfx(6)
        for i in range(-1, 4):
            if i >= 0:
                self.draw(2, i, 16, 16)
            self.draw(2, 4, 0, 0)
            self.copy(0, 0, 80, 24, 160, 136, 2, 0)
            self.wait(3)
        self.subtitle("GRAN MAESTRO....", 23, 0x08)
        self.wait(40)
        self.sfx(6)
        for i in range(3, -2, -1):
            self.fill(16, 16, 143, 119, FILL1, 2)
            if i >= 0:
                self.draw(2, i, 16, 16)
            self.draw(2, 4, 0, 0)
            self.copy(0, 0, 80, 24, 160, 136, 2, 0)
            self.wait(3)
        self.wait(40)
        self.release()

    def waterdeep_entry(self):
        self.setpal("WTRDP2.COL")
        wd1 = self.gd.cps("WTRDP1.CMP")
        self.load("WTRDP1.CMP", 2)
        self.encode(43, 2, 0, 0, 20, 136)
        for i in range(1, 4):
            self.shape_pixels(43 - i, self.blur(wd1, 0, 0, 160, 136, i))
        self.copy(0, 0, 0, 0, 320, 200, 2, 4)
        self.fill(0, 168, 319, 199, FILL1, 0)
        self.sfx(6)
        for i in range(0, 4):
            self.draw(0, 40 + i, 80, 24)
            self.wait(3)
        self.subtitle("PARECE QUE TENEMOS UNA POSIBLE SOLUCION.", 23, 0x08)
        self.wait(50)
        self.encode(45, 2, 20, 0, 20, 136)
        self.load("WTRDP2.CMP", 2)
        self.encode(46, 2, 0, 0, 20, 136)
        self.encode(47, 2, 20, 0, 20, 136)
        self.load("WTRDP3.CMP", 2)
        ex = list(self.gd.table("kEoB1IntroWdEncodeX"))
        ey = list(self.gd.table("kEoB1IntroWdEncodeY"))
        ewh = list(self.gd.table("kEoB1IntroWdEncodeWH"))
        for i in range(31):
            self.encode(i, 2, ex[i], 136 + (ey[i] << 3), ewh[i], ewh[i] << 3)
        for i in range(3):
            self.encode(50 + i, 2, 5 * i, 152, 5, 32)
        self.copy(0, 0, 0, 0, 320, 200, 2, 4)
        for i in range(3):
            self.fill(0, 0, 159, 135, FILL1, 2)
            self.draw(2, 45 + i, 0, 0)
            self.copy(0, 0, 80, 24, 160, 136, 2, 0)
            self.wait(3)
        self.copy(0, 0, 80, 24, 160, 136, 4, 0)
        self.wait(4)
        self.copy(160, 0, 80, 24, 160, 136, 4, 0)
        self.fill(0, 168, 319, 199, FILL1, 0)
        self.wait(4)
        self.copy(0, 184, 40, 184, 232, 16, 4, 0)
        self.sparkles(264, 11, -1, 1, False)
        self.release()

    def sparkles(self, cx, cy, ddx, ddy, exitpart):
        dsx = self.gd.table16("kEoB1IntroWdDsX")
        dsy = list(self.gd.table("kEoB1IntroWdDsY"))
        for i in range(70):
            if exitpart:
                fx = max(cx - 2, 160)
                fy = min(cy - 2, 98)
                self.copy(fx, fy, 0, 0, 48, 36, 4, 4)
                self.draw(4, 41 if (i & 3) == 3 else 40 + (i & 3), cx, cy)
                self.draw(4, 50, 160, 104)
                self.copy(fx, fy, fx - 80, fy + 24, 48, 36, 4, 0)
                self.copy(0, 0, fx, fy, 48, 36, 4, 4)
            else:
                self.copy(cx - 2, cy - 2, 0, 0, 48, 36, 4, 4)
                self.draw(4, 51 if (i & 3) == 3 else 50 + (i & 3), cx, cy)
                self.copy(cx - 2, cy - 2, cx - 82, cy + 22, 48, 36, 4, 0)
                self.copy(0, 0, cx - 2, cy - 2, 48, 36, 4, 4)
            cx += ddx
            cy += ddy
            for _ in range(5):
                s = random.randrange(256) % 31
                self.draw(0, s, dsx[s] - 80, dsy[s] + 24)
            if not (random.randrange(256) & 7):
                self.sfx(5 if random.randrange(2) else 14)
            self.wait(3)

    def king(self):
        self.load("KING.CMP", 2)
        self.copy(0, 0, 0, 0, 320, 200, 2, 4)
        x, y, w, h = 15, 14, 1, 1
        for i in range(10):
            self.copy(x << 3, y << 3, x << 3, y << 3, w << 3, h << 3, 4, 0)
            if x > 6:
                x -= 1
            if y > 0:
                y -= 2
            w += 3
            if x + w > 34:
                w = 34 - x
            h += 3
            if y + h > 23:
                h = 23 - y
            self.wait(1)
        self.wait(25)
        enc_x = [0, 6, 12, 19]
        enc_w = [6, 6, 7, 6]
        mod_y = [-4, -8, -2, -2, 1, 0, 0, 0]
        self.load("ADVENTUR.CMP", 2)
        dy = []
        step = []
        for i in range(4):
            self.encode(i, 2, enc_x[i], 0, enc_w[i], 98)
            dy.append(180 + ((random.randrange(256) & 3) << 3))
            step.append((i * 5) & 3)
        self.copy(0, 0, 0, 0, 320, 200, 0, 4)
        run = True
        while run:
            run = False
            for i in range(4):
                if dy[i] <= 82:
                    continue
                step[i] = (step[i] + 1) & 7
                dy[i] += mod_y[step[i]]
                if dy[i] < 82:
                    dy[i] = 82
                if dy[i] < 180:
                    self.copy((enc_x[i] + 8) << 3, dy[i] - 2, 0, dy[i] - 2, enc_w[i] << 3, 182 - dy[i], 4, 4)
                    self.draw(4, i, 0, dy[i])
                    self.copy(0, dy[i] - 2, (enc_x[i] + 8) << 3, dy[i] - 2, enc_w[i] << 3, 182 - dy[i], 4, 0)
                run = True
            if not (random.randrange(256) & 3):
                self.sfx(7)
            self.wait(2)
        self.subtitle("TE ENCOMENDAMOS LA MISION DE DESTRUIR\rA LOS DEMONIOS....SI ERES CAPAZ.", 24, 0x03)
        self.wait(70)
        self.release()

    def hands(self):
        self.clear(0)
        self.encode(0, 2, 0, 140, 21, 60)
        self.encode(1, 2, 21, 140, 12, 60)
        self.load("HANDS.CMP", 4)
        self.wait(60)
        self.fill(0, 160, 319, 199, FILL1, 0)
        self.fill(0, 0, 191, 63, FILL2, 2)
        self.draw(2, 0, 0, 4)
        self.draw(2, 1, 151, 4)
        self.box_morph(25, 8, 18, 4, 3, 0, 21, 8, 6, 0, 28, 23)
        self.subtitle("PREPARAOS PARA UNA LARGA JORNADA.", 23, 0x0F)
        self.wait(15)
        self.sfx(11)
        for i in range(-22, 21, 4):
            self.fill(0, 0, 167, 63, FILL2, 2)
            self.draw(2, 0, i, 4)
            self.draw(2, 1, 105 - i, 4)
            self.copy(0, 0, 144, 32, 168, 64, 2, 0)
            self.wait(1)
        self.sfx(10)
        self.wait(15)
        self.encode(5, 4, 17, 0, 11, 120)
        self.encode(6, 4, 28, 112, 1, 31)
        self.encode(7, 4, 9, 138, 14, 54)
        self.fill(0, 0, 135, 63, FILL2, 2)
        self.draw(2, 5, 32, -80)
        self.draw(2, 6, 40, -16)
        self.box_morph(18, 16, 10, 12, 0, 0, 17, 8, 17, 3, 25, 10)
        self.wait(15)
        for i in range(-80, 1, 4):
            self.fill(0, 0, 135, 63, FILL2, 2)
            self.draw(2, 5, 32, i)
            self.draw(2, 6, 40, i + 64)
            self.copy(0, 0, 80, 96, 136, 64, 2, 0)
            self.wait(1)
        self.sfx(12)
        self.wait(5)
        for i in range(0, -54, -4):
            self.fill(0, 0, 135, 63, FILL2, 2)
            self.draw(2, 7, 12, 64 + i)
            self.draw(2, 5, 32, i)
            self.copy(0, 0, 80, 96, 136, 64, 2, 0)
            self.wait(1)
        self.wait(15)
        self.encode(10, 4, 0, 0, 17, 136)
        self.encode(11, 4, 0, 136, 9, 48)
        self.fill(0, 0, 143, 95, FILL2, 2)
        self.draw(2, 10, -56, -56)
        self.draw(2, 11, 52, 49)
        self.box_morph(9, 6, 0, 0, 0, 0, 18, 12, 8, 11, 21, 10)
        self.wait(15)
        self.sfx(11)
        for i in range(-56, -7, 4):
            self.fill(0, 0, 143, 95, FILL2, 2)
            self.draw(2, 10, i, i)
            self.draw(2, 11, 55 if i == -8 else 52, 52 if i == -8 else 49)
            self.copy(0, 0, 0, 0, 144, 96, 2, 0)
            self.wait(1)
        self.sfx(10)
        self.wait(30)
        self.encode(15, 4, 28, 0, 11, 40)
        self.encode(16, 4, 28, 40, 10, 72)
        self.fill(0, 0, 87, 112, FILL2, 2)
        self.draw(2, 16, 0, 90)
        self.box_morph(20, 13, 15, 6, 0, 0, 11, 14, 0, 0, 24, 16)
        self.wait(15)
        dy = 90
        for i in range(-40, 1, 4):
            self.fill(0, 0, 87, 112, FILL2, 2)
            self.draw(2, 16, 0, dy)
            self.copy(0, 0, 120, 48, 88, 112, 2, 0)
            self.wait(1)
            dy -= 5
        self.sfx(13)
        for i in range(-40, 1, 4):
            self.fill(0, 0, 87, 39, FILL2, 2)
            self.draw(2, 15, 0, i)
            self.copy(0, 0, 120, 48, 88, 112, 2, 0)
            self.wait(1)
        self.release()
        self.wait(48)

    def waterdeep_exit(self):
        self.load("WTRDP3.CMP", 2)
        ex = list(self.gd.table("kEoB1IntroWdEncodeX"))
        ey = list(self.gd.table("kEoB1IntroWdEncodeY"))
        ewh = list(self.gd.table("kEoB1IntroWdEncodeWH"))
        for i in range(31):
            self.encode(i, 2, ex[i], 136 + (ey[i] << 3), ewh[i], ewh[i] << 3)
        for i in range(3):
            self.encode(40 + i, 2, 5 * i + 15, 152, 5, 32)
        self.encode(50, 2, 31, 136, 5, 32)
        self.copy(0, 0, 0, 0, 320, 200, 2, 4)
        self.copy(0, 0, 0, 136, 48, 36, 4, 4)
        self.fill(0, 168, 319, 199, FILL1, 0)
        self.copy(160, 0, 80, 24, 160, 136, 4, 0)
        self.sparkles(140, 128, 1, -1, True)
        self.release()
        self.fill(0, 168, 319, 199, FILL1, 0)
        self.copy(0, 136, 0, 0, 48, 36, 0, 4)
        self.load("ORB.CMP", 2, "ORB.COL")
        self.whirl()
        self.setpal("ORB.COL")
        self.wait(6)
        self.subtitle("COMENZAD LA BUSQUEDA BAJO LA CIUDAD.", 23, 0x0F)
        cx, cy, dy = 0, 136, 0
        for i in range(19):
            self.copy(cx, cy, 80, dy + 16, 160, 8, 2, 0)
            cy += 8
            dy += 8
            if i == 6:
                cx, cy = 160, 0
            self.wait(1)
        self.sfx(3)
        self.wait(60)
        for i in range(56):
            self.copy(0, 136 + i, 80, 16, 160, 56 - i, 2, 0)
            self.copy(160, 0, 80, 72 - i, 160, 96 + i, 2, 0)
            self.wait(1)
        for i in range(1, 48):
            self.copy(160, i, 80, 16, 160, 152, 2, 0)
            self.wait(1)
        self.load("TUNNEL.CMP", 2, "ZOOMTUNL.COL")
        self.wait(30)
        self.fill(0, 16, 319, 31, FILL1, 0)
        self.fill(0, 136, 319, 199, FILL1, 0)
        self.copy(0, 0, 80, 32, 160, 120, 2, 0)
        self.setpal("ZOOMTUNL.COL")
        self.wait(50)

    def tunnel(self):
        # drawBlockObject of the two halves of TUNNEL (page 2) into page 4
        self.encode(2, 2, 20, 0, 20, 120)
        self.encode(1, 2, 0, 0, 20, 120)
        self.clear(4)
        self.draw(4, 2, 160, 0)
        self.draw(4, 1, 0, 0)
        for i in range(3):
            self.copy(0, 0, 80, 32, 160, 120, 4, 0)
            self.sfx(7)
            self.wait(8)
            self.copy(0, 0, 80, 32, 160, 120, 2, 0)
            self.sfx(7)
            self.wait(8)
        self.subtitle("COMIENZA LA AVENTURA.", 23, 0x0F)
        self.wait(18)
        self.copy(160, 0, 80, 32, 160, 120, 2, 0)
        self.wait(5)
        self.copy(0, 122, 80, 32, 160, 60, 2, 0)
        self.copy(160, 122, 80, 92, 160, 60, 2, 0)
        self.wait(5)
        self.copy(160, 0, 80, 32, 160, 120, 4, 0)
        for i in range(6):
            self.copy(i * 48, 185, 56, (i << 3) + 24, 48, 8, 2, 2)
        self.wait(5)
        self.copy(0, 0, 80, 32, 160, 120, 2, 0)
        self.load("AVALANCH.CMP", 4)
        self.wait(40)
        self.copy(264, 0, 136, 56, 48, 48, 4, 0)
        self.sfx(8)
        self.copy(0, 0, 0, 0, 320, 184, 0, 2)
        self.wait(16)
        self.sfx(4)
        for i in range(30):
            if i == 0:
                self.fill(0, 168, 319, 199, FILL1, 0)
            self.copy(80, 25 + (random.randrange(256) & 7), 80, 24, 160, 144, 2, 0)
            self.wait(1)
        self.sfx(9)
        tx1 = list(self.gd.table("kEoB1IntroTvlX1"))
        ty1 = list(self.gd.table("kEoB1IntroTvlY1"))
        tx2 = list(self.gd.table("kEoB1IntroTvlX2"))
        ty2 = list(self.gd.table("kEoB1IntroTvlY2"))
        tw = list(self.gd.table("kEoB1IntroTvlW"))
        th = list(self.gd.table("kEoB1IntroTvlH"))
        for i in range(6):
            self.copy(tx1[i] << 3, ty1[i], tx2[i] << 3, ty2[i], tw[i] << 3, th[i], 4, 2)
            for _ in range(4):
                self.wait(1)
                self.copy(80, 25 + (random.randrange(256) & 7), 80, 24, 160, 144, 2, 0)
        self.copy(0, 0, 0, 0, 320, 168, 2, 0)
        self.wait(40)
        self.load("ZOOMTUNL.CMP", 4)
        self.sfx(6)
        self.copy(0, 0, 80, 32, 160, 120, 4, 0)
        self.wait(2)
        self.copy(160, 0, 80, 32, 160, 120, 4, 0)
        self.wait(2)
        self.copy(0, 120, 80, 30, 160, 64, 4, 0)
        self.copy(160, 120, 80, 94, 160, 64, 4, 0)
        self.subtitle("LA SALIDA ESTA OBSTRUIDA!!.", 23, 0x08)
        self.wait(50)
        self.release()

    def build(self):
        self.opening_credits()
        self.title()
        self.tower()
        self.orb()
        self.waterdeep_entry()
        self.king()
        self.hands()
        self.waterdeep_exit()
        self.tunnel()
        self.whirl()
        self.seq.append(0)
        return self.chunks()

    def chunks(self):
        """INSEQnn.BIN of CHUNK_MAX bytes at most, cut between commands;
        each but the last ends with 0Bh (the next one)."""
        s = self.seq
        p = 0
        starts = []
        while p < len(s):
            starts.append(p)
            c = s[p]
            if c == 0:
                p += 1
            elif c in (1, 7, 10):
                p += 2
            elif c in (2, 3):
                p += 13
            elif c == 4:
                p += 10
            elif c == 6:
                p += 1 + 192
            elif c in (5, 8):
                p = s.index(0, p + 1) + 1
            elif c == 9:
                p = s.index(0, p + 5) + 1
            else:
                raise SystemExit("intro: bad command %d" % c)
        starts.append(len(s))
        n = 0
        a = 0
        i = 0
        while a < len(s):
            b = a
            while i + 1 < len(starts) and starts[i + 1] - a <= CHUNK_MAX - 1:
                i += 1
                b = starts[i]
            part = bytes(s[a:b])
            if b < len(s):
                part += b"\x0b"
            (BUILD / ("INSEQ%02d.BIN" % n)).write_bytes(part)
            n += 1
            a = b
        return len(s), n


def sound_sets(gd):
    """INSND1.DAT: the music of the credits; INSND2.DAT: the rest."""
    snd = BUILD / "SOUND.DAT"
    snd.write_bytes(gd.get("SOUND.DAT"))
    raw = BUILD / "insnd_raw.bin"
    subprocess.run([str(E.ROOT / "build" / "adlib_render"), str(snd), str(raw)], check=True,
                   env={"SECS": "240"})
    tracks = S.load_raw(raw)
    for name, keep in (("INSND1.DAT", {1}), ("INSND2.DAT", set(range(2, 15)))):
        offs = [0] * 120
        masks = [0] * 120
        data = bytearray()
        for i, ticks in enumerate(tracks):
            if not ticks or (i and i not in keep):
                continue
            # encode's default argument is bound when conv_sfx is imported.
            # Changing S.MAX_TICKS later still truncated these songs at 5s.
            s, m = S.encode(ticks, max_ticks=len(ticks)) if i else S.encode_init(ticks[0])
            offs[i] = 0x8000 + 480 + len(data)
            masks[i] = m
            data += s
        out = struct.pack("<120H", *offs) + struct.pack("<120H", *masks) + data
        assert len(out) <= S.SEG, "%s: %d bytes" % (name, len(out))
        (BUILD / name).write_bytes(out)


def main():
    gd = E.GameData()
    sound_sets(gd)
    intro = Intro(gd)
    n, parts = intro.build()
    print("intro: %d bytes of commands in %d parts, %d images" % (n, parts, intro.nfiles))


if __name__ == "__main__":
    main()
