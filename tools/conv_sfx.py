#!/usr/bin/env python3
"""conv_sfx.py - The sound effects of EOB1 (ADLIB.DAT) for the FM part of
the OPL4: build/adlib_render (the AdLib driver of the original, v1, built
from tools/adlib_render) writes the OPL register writes of every driver
tick (72 Hz) of each track; here they become streams for src/sound.asm.

build/SFX.DAT (one 16 KB mapper segment, loaded at 8000h):
  120 x u16  offset of the stream of each track (0: none)
  120 x u16  OPL channels in bits 0..9, DOS distance coefficient in bits 10..15
  streams:   n = 1..7Fh: n writes (register, value) in this tick
             80h + k:    k + 1 ticks without writes
             00h:        the end
  C9h..DEh in an effect's register writes mark distance-sensitive 40h..55h
  operator levels. Intro and character generation streams are unmarked.
Writes that repeat the value a register already has in the same stream are
dropped. Very long tracks are cut (MAX_TICKS)."""
import struct
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import eoblib as E

BUILD = E.BUILD
MAX_TICKS = 72 * 5
SEG = 0x4000


def channel_of(reg):
    """The OPL2 channel of a register, or 9 for the global ones."""
    if 0xA0 <= reg <= 0xA8 or 0xB0 <= reg <= 0xB8 or 0xC0 <= reg <= 0xC8:
        return reg & 0x0F
    if 0x20 <= reg <= 0x95 or 0xE0 <= reg <= 0xF5:
        op = reg & 0x1F
        slot = [0, 1, 2, 0, 1, 2, None, None, 3, 4, 5, 3, 4, 5, None, None, 6, 7, 8, 6, 7, 8]
        if op < len(slot) and slot[op] is not None:
            return slot[op]
    return 9


def load_raw(path):
    d = open(path, "rb").read()
    p = 0
    tracks = []
    for _ in range(120):
        nt = struct.unpack_from("<H", d, p)[0]
        p += 2
        ticks = []
        for _ in range(nt):
            c = d[p]
            p += 1
            ticks.append([(d[p + 2 * i], d[p + 2 * i + 1]) for i in range(c)])
            p += 2 * c
        tracks.append(ticks)
    return tracks


def encode(ticks, max_ticks=MAX_TICKS):
    regs = {}
    out = bytearray()
    mask = 0
    wait = 0
    # the trailing silent ticks go
    while ticks and not ticks[-1]:
        ticks = ticks[:-1]
    for t in ticks[:max_ticks]:
        w = []
        for r, v in t:
            register = r - 0x89 if 0xC9 <= r <= 0xDE else r
            if regs.get(register) == (r, v):
                continue
            regs[register] = (r, v)
            w.append((r, v))
            mask |= 1 << channel_of(register)
        if not w:
            wait += 1
            continue
        while wait:
            k = min(wait, 128)
            out.append(0x80 + k - 1)
            wait -= k
        while w:
            part, w = w[:127], w[127:]
            out.append(len(part))
            for r, v in part:
                out += bytes((r, v))
            if w:                       # (a long tick: the rest at once)
                pass
    if len(ticks) > max_ticks:
        # cut: every note off
        out.append(9)
        for c in range(9):
            out += bytes((0xB0 + c, regs.get(0xB0 + c, (0, 0))[1] & 0xDF))
    out.append(0)
    return out, mask


def encode_init(writes):
    """Track 0: the writes of initDriver, all of them, in ticks of 127."""
    out = bytearray()
    while writes:
        part, writes = writes[:127], writes[127:]
        out.append(len(part))
        for r, v in part:
            out += bytes((r, v))
    out.append(0)
    return out, 0


def mark_levels(near, far, delta):
    """Find the writes affected by changing only the DOS program's level."""
    if len(near) != len(far):
        raise ValueError("changed tick count")
    result = []
    for base, distant in zip(near, far):
        if len(base) != len(distant):
            raise ValueError("changed write count")
        tick = []
        for (reg, value), (other, after) in zip(base, distant):
            if (reg, value) != (other, after):
                expected = (value & 0xC0) | min(63, (value & 0x3F) + delta)
                if reg != other or not 0x40 <= reg <= 0x55 or after != expected:
                    raise ValueError("changed non-level write")
                reg += 0x89
            tick.append((reg, value))
        result.append(tick)
    return result


def environmental_tracks(adlib, tracks, render):
    # EOB.EXE, file offset 1A14Fh: extra level += (63 - level) * (d - 1) / 16.
    # Program data follows the 120 track IDs. ABh sets the extra level.
    programs = {}
    for track, program in enumerate(adlib[1:120], 1):
        if program == 255:
            continue
        offset = 120 + struct.unpack_from("<H", adlib, 120 + 2 * program)[0]
        if 420 <= offset < len(adlib) - 3 and adlib[offset] < 9 and adlib[offset + 2] == 0xAB:
            level = adlib[offset + 3]
            assert level <= 63, (track, level)
            programs[track] = (offset + 3, 63 - level)

    def distant_tracks(selected):
        distant = bytearray(adlib)
        for offset, coefficient in selected:
            distant[offset] = adlib[offset] + coefficient * 14 // 16
        return render(distant)

    # Programs occasionally trigger another program. Retry those tracks with
    # only their own starting level changed, as the DOS engine does.
    distant = distant_tracks(programs.values())
    coefficients = [0] * 120
    for track, (offset, coefficient) in programs.items():
        delta = coefficient * 14 // 16
        try:
            marked = mark_levels(tracks[track], distant[track], delta)
        except ValueError:
            far = distant_tracks([(offset, coefficient)])[track]
            marked = mark_levels(tracks[track], far, delta)
        tracks[track] = marked
        coefficients[track] = coefficient
    return coefficients


def main():
    gd = E.GameData()
    BUILD.mkdir(exist_ok=True)
    adl = BUILD / "ADLIB.DAT"
    adlib = gd.get("ADLIB.DAT")
    adl.write_bytes(adlib)
    raw = BUILD / "sfx_raw.bin"
    subprocess.run([str(E.ROOT / "build" / "adlib_render"), str(adl), str(raw)], check=True)
    tracks = load_raw(raw)
    assert all(not 0xC9 <= reg <= 0xDE for track in tracks[1:]
               for tick in track for reg, _ in tick)
    # Preserve unmarked data for the character generator.
    write_set(tracks, "CGSND.DAT", {20: len(tracks[20]), 76: MAX_TICKS})

    def render_distant(blob):
        source = BUILD / "adlib-distant.dat"
        output = BUILD / "sfx-distant.bin"
        source.write_bytes(blob)
        subprocess.run([str(E.ROOT / "build" / "adlib_render"), str(source), str(output)], check=True)
        return load_raw(output)

    coefficients = environmental_tracks(adlib, tracks, render_distant)
    offs = [0] * 120
    masks = [0] * 120
    data = bytearray()
    seen = {}
    for i, ticks in enumerate(tracks):
        if not ticks:
            continue
        s, m = encode(ticks) if i else encode_init(ticks[0])
        if bytes(s) not in seen:          # identical tracks share their stream
            seen[bytes(s)] = 0x8000 + 480 + len(data)
            data += s
        offs[i] = seen[bytes(s)]
        masks[i] = m | (coefficients[i] << 10)
    out = struct.pack("<120H", *offs) + struct.pack("<120H", *masks) + data
    assert len(out) <= SEG, "SFX.DAT: %d bytes" % len(out)
    (BUILD / "SFX.DAT").write_bytes(out)
    print("sfx: %d tracks, %d bytes" % (sum(1 for o in offs if o), len(out)))


def write_set(tracks, name, wanted):
    """A set of a few tracks, whole (CGSND.DAT: the music of the character
    generation, 20, and the click of its buttons, 76), as SFX.DAT."""
    offs = [0] * 120
    masks = [0] * 120
    data = bytearray()
    s, m = encode_init(tracks[0][0])
    offs[0] = 0x8000 + 480
    data += s
    for i, n in wanted.items():
        s, m = encode(tracks[i], n)
        offs[i] = 0x8000 + 480 + len(data)
        masks[i] = m
        data += s
    out = struct.pack("<120H", *offs) + struct.pack("<120H", *masks) + data
    assert len(out) <= SEG, "%s: %d bytes" % (name, len(out))
    (BUILD / name).write_bytes(out)


if __name__ == "__main__":
    main()
