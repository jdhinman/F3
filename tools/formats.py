"""Survey and crack the Fable III formats that turned out to be thin wrappers.

    python tools/formats.py survey            classify every extension in every bank
    python tools/formats.py ghf   <out.raw>   gunzip a heightfield, report its grid
    python tools/formats.py adb   <out.bin>   LhCoMpRe -> zlib -> LhBiNaRy
    python tools/formats.py audio <out.wav>   xWMA -> PCM via ffmpeg

Four formats the community listed as unknown are wrappers around something standard, and
the survey is what found them - dumping the first sixteen bytes of one sample per extension,
across every bank, in one pass.

| Ext | What it actually is |
|---|---|
| **GHF** | plain **gzip**. Inflates ~480x to a heightfield: `f32 scaleX, f32 scaleY, ..., u32 w, u32 h`, then **14 bytes per cell**. Grids seen: 385x385, 577x641, 673x769 |
| **WAV** | a 4-byte `xwma` prefix in front of a **standard RIFF/xWMA** file, `fmt` tag `0x0161` = WMAv2. **ffmpeg decodes it directly.** Not XMA2 |
| **ADB** | `LhCoMpRe` + `SsEd`, u32 version, **BE u32 uncompressed len, BE u32 compressed len**, then a plain **zlib** stream. Inflates to an inner `LhBiNaRy####` container |
| **SAVE** | XML. So is `AI_CONFIG`, `AMP`, `MKT`, `VFSCONFIG`, `ENGINE_LEVEL`, `LIST` |

> The community checklist said *"WAV: audio, XMA2. No XMA2 codec exists"*. It is not XMA2 and
> it never was. Strip four bytes and any modern ffmpeg reads it.

Middleware, so documented outside this project rather than by it: `AIMRT`/`FDL`/`PDL` are
Kynogon (Kynapse) navigation, `HAVOK_SCENARIO` is a Havok packfile, `BIK` is Bink.
"""

import gzip
import importlib.util
import os
import struct
import subprocess
import sys
import zlib

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("bnkextract", os.path.join(_here, "bnk-extract.py"))
_be = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_be)

GAME = r"C:\Games\Fable 3"


def sample(ext, want=1, max_size=3_000_000):
    """First `want` entries with that extension, from anywhere in the install."""
    out = []
    for root, _dirs, files in os.walk(GAME):
        for f in files:
            if not f.lower().endswith(".bnk"):
                continue
            p = os.path.join(root, f)
            if not os.path.exists(p + ".dat"):
                continue
            try:
                entries = _be.read_index(open(p, "rb").read())
            except Exception:
                continue
            hits = [e for e in entries
                    if e["path"].lower().endswith("." + ext) and 8 < e["size"] < max_size]
            if not hits:
                continue
            payload = open(p + ".dat", "rb").read()
            for e in hits[:want]:
                out.append((e["path"], _be.extract(e, payload)))
                if len(out) >= want:
                    return out
    return out


def ghf(blob):
    """gzip -> (scaleX, scaleY, width, height, cells). 14 bytes per cell."""
    raw = gzip.decompress(blob)
    sx, sy = struct.unpack_from("<2f", raw, 0)
    w, h = struct.unpack_from("<2I", raw, 12)
    return dict(scale=(sx, sy), width=w, height=h, body=raw[20:], raw=raw)


def adb(blob):
    """LhCoMpRe header then a zlib stream; the payload is an LhBiNaRy container."""
    if blob[:8] != b"LhCoMpRe":
        raise ValueError("not an ADB")
    ulen, clen = struct.unpack_from(">2I", blob, 16)
    out = zlib.decompressobj().decompress(blob[24:24 + clen])
    if len(out) != ulen:
        raise ValueError("declared %d, got %d" % (ulen, len(out)))
    return out


def xwma(blob):
    """Strip the 4-byte 'xwma' tag; what remains is a standard RIFF file."""
    if blob[:4] != b"xwma":
        raise ValueError("not an xWMA wav")
    return blob[4:]


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 1

    if a[0] == "survey":
        import re
        seen = {}
        for root, _dirs, files in os.walk(GAME):
            for f in files:
                if not f.lower().endswith(".bnk"):
                    continue
                p = os.path.join(root, f)
                if not os.path.exists(p + ".dat"):
                    continue
                try:
                    entries = _be.read_index(open(p, "rb").read())
                except Exception:
                    continue
                payload = None
                for e in entries:
                    ext = e["path"].rsplit(".", 1)[-1].lower()
                    if ext in seen or not (8 < e["size"] < 4_000_000):
                        continue
                    if payload is None:
                        payload = open(p + ".dat", "rb").read()
                    try:
                        seen[ext] = _be.extract(e, payload)
                    except Exception:
                        pass
        print(f"{'ext':12} {'first 16 bytes':50} what")
        for ext in sorted(seen):
            d = seen[ext]
            note = []
            if d[:2] == b"\x1f\x8b":
                note.append("GZIP")
            if d[:8] == b"LhCoMpRe":
                note.append("LhCoMpRe+zlib")
            if d[:4] == b"xwma":
                note.append("xWMA (RIFF)")
            pr = sum(1 for b in d[:4000] if 32 <= b < 127 or b in (9, 10, 13))
            if pr > 0.90 * min(len(d), 4000):
                note.append("TEXT")
            m = re.match(rb"^[\x20-\x7e]{4,8}", d[:8])
            if m:
                note.append("magic %r" % m.group().decode())
            print(f"{ext:12} {d[:16].hex(' '):50} {', '.join(note) or 'binary'}")
        return 0

    if a[0] == "ghf":
        path, blob = sample("ghf")[0]
        g = ghf(blob)
        open(a[1], "wb").write(g["raw"])
        print(f"{path}: {len(blob)} -> {len(g['raw'])} bytes, grid {g['width']}x{g['height']}, "
              f"scale {g['scale']}, {len(g['body'])/(g['width']*g['height']):.2f} bytes/cell")
        return 0

    if a[0] == "adb":
        path, blob = sample("adb")[0]
        out = adb(blob)
        open(a[1], "wb").write(out)
        print(f"{path}: {len(blob)} -> {len(out)} bytes, inner container {out[:12]!r}")
        return 0

    if a[0] == "audio":
        path, blob = sample("wav")[0]
        tmp = a[1] + ".xwma"
        open(tmp, "wb").write(xwma(blob))
        r = subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                            "-i", tmp, a[1]], capture_output=True, text=True)
        if r.returncode:
            print(r.stderr[:400], file=sys.stderr)
            return 1
        print(f"{path}: {len(blob)} bytes xWMA -> {os.path.getsize(a[1])} bytes PCM at {a[1]}")
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
