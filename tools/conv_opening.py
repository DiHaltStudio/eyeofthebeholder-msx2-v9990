#!/usr/bin/env python3
"""conv_opening.py - The pictures of the launcher (src/launch.asm).

  build/LOGO.BIN   the DiHalt Studio logo (assets/dihalt_logo-b1.png) for B1
                   mode: the 16 colours (R, G, B in 5 bits), then 256x212
                   pixels at 4 bpp (left pixel in the high nibble).
  build/COVER.BIN  the cover for B3 mode with BD8 colours (GGGRRRBB, the
                   V9990's fixed 256 colours), 512 pixels per line: 424 lines
                   of screen (docs/img/opening.png,
                   over a black band at the bottom), then the two language
                   choices and the mouse prompt. The launcher copies the
                   selected band into view. In RLE blocks of BLOCK bytes, read one
                   by one (see rle_blocks).
  build/cover.png  a preview of the screen with the Spanish choice.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
LOGO = ROOT / "assets" / "dihalt_logo-b1.png"
COVER = ROOT / "docs" / "img" / "opening.png"
FONT = "DejaVuSerif-Bold.ttf"    # Pillow finds the installed font on Debian or Arch

BLOCK = 1024                    # src/launch.asm: BLOCK
W, H = 512, 424                 # B3, interlaced
BAND_Y, BAND_H = 380, 44        # the language band (src/launch.asm: BAND_Y, BAND_H)
WORDS = (("ESPAÑOL", 168), ("ENGLISH", 344))    # text, centre x
ON, OFF = (255, 218, 85), (109, 109, 85)


def rgb332_palette():
    pal = []
    for code in range(256):
        pal += [((code >> 2) & 7) * 255 // 7, ((code >> 5) & 7) * 255 // 7, (code & 3) * 255 // 3]
    return pal


def to_bd8(img):
    """RGB image -> BD8 bytes (Floyd-Steinberg against the fixed colours)."""
    ref = Image.new("P", (1, 1))
    ref.putpalette(rgb332_palette())
    return img.convert("RGB").quantize(palette=ref, dither=Image.Dither.FLOYDSTEINBERG)


def band(choice):
    img = Image.new("RGB", (W, BAND_H))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, 24)
    for i, (text, cx) in enumerate(WORDS):
        col = ON if i == choice else OFF
        x0, y0, x1, y1 = d.textbbox((0, 0), text, font=font)
        x = cx - (x1 - x0) // 2 - x0
        y = (BAND_H - (y1 - y0)) // 2 - y0
        d.text((x, y), text, font=font, fill=col)
        if i == choice:     # a frame around the chosen one
            d.rectangle((x + x0 - 10, y + y0 - 7, x + x1 + 9, y + y1 + 6), outline=col, width=2)
    return img


def mouse_prompt():
    img = Image.new("RGB", (W, BAND_H))
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, 15)
    draw.text((W // 2, 11), "Conecta un ratón MSX al puerto 1", font=font, fill=ON, anchor="mm")
    draw.text((W // 2, 32), "Connect an MSX mouse to port 1", font=font, fill=ON, anchor="mm")
    return img


def logo():
    img = Image.open(LOGO).convert("RGB")
    assert img.size == (256, 212), img.size
    corner = img.getpixel((0, 0))       # colour 0: the background and the border
    cols = [corner] + sorted(set(img.getdata()) - {corner})
    assert len(cols) <= 16, len(cols)
    idx = {c: i for i, c in enumerate(cols)}
    px = [idx[c] for c in img.getdata()]
    data = bytearray((px[i] << 4) | px[i + 1] for i in range(0, len(px), 2))
    pal = bytearray(48)
    for i, (r, g, b) in enumerate(cols):
        pal[i * 3:i * 3 + 3] = bytes((r >> 3, g >> 3, b >> 3))
    (BUILD / "LOGO.BIN").write_bytes(pal + data)


def cover():
    art = Image.open(COVER).convert("RGB")
    h = BAND_Y - 4
    w = round(art.width * h / art.height)           # B3 pixels are square
    art = art.resize((w, h), Image.LANCZOS)
    screen = Image.new("RGB", (W, H))
    screen.paste(art, ((W - w) // 2, 0))
    out = bytearray(to_bd8(screen).tobytes())
    for image in (band(0), band(1), mouse_prompt()):
        out.extend(to_bd8_flat(image))  # bands use pure colours without dithering
    (BUILD / "COVER.BIN").write_bytes(rle_blocks(bytes(out)))
    preview = Image.frombytes("P", (W, H), bytes(out[:W * H]))
    preview.putpalette(rgb332_palette())
    preview = preview.convert("RGB")
    preview.paste(band(0), (0, BAND_Y))
    preview.save(BUILD / "cover.png")


def rle_tokens(data):
    """01h-7Fh: so many bytes follow; 81h-FFh: the next byte so many (- 80h) times."""
    i = 0
    lit = bytearray()
    while i < len(data):
        n = 1
        while i + n < len(data) and n < 127 and data[i + n] == data[i]:
            n += 1
        if n >= 3:
            if lit:
                yield bytes((len(lit),)) + bytes(lit)
                lit = bytearray()
            yield bytes((0x80 + n, data[i]))
            i += n
        else:
            lit.append(data[i])
            i += 1
            if len(lit) == 127:
                yield bytes((127,)) + bytes(lit)
                lit = bytearray()
    if lit:
        yield bytes((len(lit),)) + bytes(lit)


def rle_blocks(data):
    """The tokens in blocks of BLOCK bytes, each ended by 80h (no token crosses
    a block); the last block is not padded."""
    out = bytearray()
    blk = bytearray()
    for t in rle_tokens(data):
        if len(blk) + len(t) + 1 > BLOCK:
            out += blk + b"\x80" + bytes(BLOCK - len(blk) - 1)
            blk = bytearray()
        blk += t
    return bytes(out + blk + b"\x80")


def to_bd8_flat(img):
    out = bytearray()
    for r, g, b in img.getdata():
        out.append((((g * 7 + 127) // 255) << 5) | (((r * 7 + 127) // 255) << 2) | ((b * 3 + 127) // 255))
    return out


if __name__ == "__main__":
    BUILD.mkdir(exist_ok=True)
    logo()
    cover()
    print("opening: LOGO.BIN, COVER.BIN")
    sys.exit(0)
