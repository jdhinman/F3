"""Read and write Fable III TEX textures.

The community position was "likely DXTn, compression unknown, swizzling possible", and the
only artifact anyone produced was a spreadsheet of resolutions and file sizes. The reason it
looked unknown is that **a `.tex` file has no header at all** - it is raw DXT block data from
byte zero, so every attempt to parse one finds nothing to parse.

**The header lives in a separate bank.** Every `x_textures.bnk` has a sibling
`x_texture_headers.bnk`, and the header there is 92 bytes, little-endian:

```
@0   u32  0xABCBBBF3          magic
@4   u32  4                   version
@8   u32  data size           bytes in the .tex payload
@12  u32  flags               2 = cubemap (six faces, so six times the size)
@16  u32  usage//purpose      1, 257, 225, ... not needed to decode
@20  u32  width
@24  u32  height
@28  u32  format              35 = DXT1, 39 = DXT5, 2 and 4 = uncompressed 32-bit
@32  u32  13                  constant
@36  u32  0
@40  u32  mip count
@44  u32  92                  header size
```

Verified by predicting the payload size of **every texture in the game from its header
alone: 9,561 of 9,561** across both libraries, mip chains and cubemaps included.

**There is no swizzling and no byte swapping**, despite the forum guess. Real DXT1 blocks
come out 90-100% `c0 > c1` as stored, and byte-swapping them drops that to 40-70%, which is
the signature of getting it wrong. The payload is PC-standard DXT from byte zero.

    python tools/tex.py list                          every texture, with size and format
    python tools/tex.py export <path.tex> <out.png>   top mip to PNG
    python tools/tex.py import <path.tex> <in.png>    re-encode, writes .tex + .header
    python tools/tex.py verify                        re-derive every size from its header
"""

import importlib.util
import io
import os
import struct
import sys

_spec = importlib.util.spec_from_file_location(
    "bnkextract", os.path.join(os.path.dirname(__file__), "bnk-extract.py"))
_be = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_be)

GAME = r"C:\Games\Fable 3"
MAGIC = 0xABCBBBF3
DXT1, DXT5 = 35, 39
BLOCK = {DXT1: 8, DXT5: 16}
PIXEL_FORMAT = {DXT1: "DXT1", DXT5: "DXT5"}

# (header index, header payload, texture index, texture payload) per texture library.
LIBRARIES = [
    (r"globals\globals_texture_headers.bnk", r"globals\globals_texture_headers.bnk.dat",
     r"globals\globals_textures.bnk", GAME + r"\data\globals\globals_textures.bnk.dat"),
    (r"art\gui\gui_texture_headers.bnk", r"art\gui\gui_texture_headers.bnk.dat",
     r"art\gui\gui_textures.bnk", GAME + r"\data\art\gui\gui_textures.bnk.dat"),
]


def _levels():
    p = GAME + r"\data\levels.bnk"
    return _be.read_index(open(p, "rb").read()), open(p + ".dat", "rb").read()


def _sub(idx, pl, name):
    e = next(x for x in idx if x["path"].lower() == name.lower())
    return _be.extract(e, pl)


def parse_header(h):
    magic, ver, dsize, flags, usage, w, ht, fmt, c13, z, mips, hsize = \
        struct.unpack_from("<12I", h, 0)
    if magic != MAGIC:
        raise ValueError("bad TEX header magic %08X" % magic)
    return dict(data_size=dsize, flags=flags, usage=usage, width=w, height=ht,
                format=fmt, mips=mips, cubemap=bool(flags & 2), raw=h)


def payload_size(w, h, mips, fmt, cubemap=False):
    """Bytes the payload must hold. Uncompressed formats are 4 bytes per pixel."""
    total = 0
    for m in range(mips):
        ww, hh = max(1, w >> m), max(1, h >> m)
        if fmt in BLOCK:
            total += ((ww + 3) // 4) * ((hh + 3) // 4) * BLOCK[fmt]
        else:
            total += ww * hh * 4
    return total * (6 if cubemap else 1)


def catalogue():
    """{lowercased path: (header dict, texture bank entry, payload path)}"""
    lidx, lpl = _levels()
    out = {}
    for hbnk, hdat, tbnk, tpath in LIBRARIES:
        try:
            hi = _be.read_index(_sub(lidx, lpl, hbnk))
            hd = _sub(lidx, lpl, hdat)
            ti = {e["path"].lower(): e for e in _be.read_index(_sub(lidx, lpl, tbnk))}
        except StopIteration:
            continue
        for e in hi:
            h = hd[e["offset"]:e["offset"] + e["size"]]
            t = ti.get(e["path"].lower())
            if t is not None:
                out[e["path"].lower()] = (parse_header(h), t, tpath)
    return out


def read_pixels(path):
    """Top mip as a Pillow image, by wrapping the raw payload in a DDS header."""
    from PIL import Image
    cat = catalogue()
    hit = cat.get(path.lower().replace("/", "\\"))
    if hit is None:
        raise SystemExit(path + ": not in any texture library")
    hdr, entry, tpath = hit
    if hdr["format"] not in PIXEL_FORMAT:
        raise SystemExit("format %d is uncompressed 32-bit; not handled yet" % hdr["format"])
    with open(tpath, "rb") as f:
        f.seek(entry["offset"])
        blob = f.read(entry["size"])
    top = payload_size(hdr["width"], hdr["height"], 1, hdr["format"])
    # Pillow's "bcn" raw decoder takes the block data directly: 1 = BC1 (DXT1),
    # 3 = BC3 (DXT5). No DDS wrapper, and nothing to get wrong in a hand-built header.
    bcn = 1 if hdr["format"] == DXT1 else 3
    im = Image.frombytes("RGBA", (hdr["width"], hdr["height"]), blob[:top], "bcn", bcn)
    return im, hdr


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 1

    if a[0] == "verify":
        ok = bad = 0
        for p, (h, e, _t) in catalogue().items():
            want = payload_size(h["width"], h["height"], h["mips"], h["format"], h["cubemap"])
            if want == h["data_size"] == e["size"]:
                ok += 1
            else:
                bad += 1
                if bad <= 5:
                    print(f"  MISMATCH {p}: header says {h['data_size']}, "
                          f"bank says {e['size']}, computed {want}")
        print(f"{ok} textures reproduce their payload size from the header alone, {bad} do not")
        return 0 if bad == 0 else 1

    if a[0] == "list":
        want = a[1].lower() if len(a) > 1 else ""
        n = 0
        for p, (h, _e, _t) in sorted(catalogue().items()):
            if want and want not in p:
                continue
            kind = {35: "DXT1", 39: "DXT5"}.get(h["format"], "raw%d" % h["format"])
            print(f"{h['width']:5}x{h['height']:<5} {kind:5} mips{h['mips']:<3}"
                  f"{' cube' if h['cubemap'] else '     '} {p}")
            n += 1
        print(f"-- {n} textures")
        return 0

    if a[0] == "export":
        im, hdr = read_pixels(a[1])
        im.convert("RGBA").save(a[2])
        print(f"{a[1]}: {hdr['width']}x{hdr['height']} "
              f"{PIXEL_FORMAT.get(hdr['format'])} mips {hdr['mips']} -> {a[2]}")
        return 0

    if a[0] == "import":
        from PIL import Image
        cat = catalogue()
        hit = cat.get(a[1].lower().replace("/", "\\"))
        if hit is None:
            raise SystemExit(a[1] + ": not in any texture library")
        hdr, _e, _t = hit
        if hdr["format"] not in PIXEL_FORMAT:
            raise SystemExit("only DXT1/DXT5 can be written")
        im = Image.open(a[2]).convert("RGBA").resize((hdr["width"], hdr["height"]))
        # One mip only: the header declares the count, so it must be updated to match.
        buf = io.BytesIO()
        im.save(buf, format="DDS", pixel_format=PIXEL_FORMAT[hdr["format"]])
        blocks = buf.getvalue()[128:]
        want = payload_size(hdr["width"], hdr["height"], 1, hdr["format"])
        blocks = blocks[:want].ljust(want, b"\0")
        head = bytearray(hdr["raw"])
        struct.pack_into("<I", head, 8, len(blocks))   # data size
        struct.pack_into("<I", head, 40, 1)            # mip count
        base = os.path.splitext(a[2])[0]
        open(base + ".tex", "wb").write(blocks)
        open(base + ".tex.header", "wb").write(bytes(head))
        print(f"wrote {base}.tex ({len(blocks)} bytes) and {base}.tex.header (92 bytes)")
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
