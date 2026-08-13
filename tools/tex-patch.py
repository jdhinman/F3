"""Replace a texture inside a Fable III texture bank, in place.

    python tools/tex-patch.py apply  <internal\\path.tex> <image.png>
    python tools/tex-patch.py revert <internal\\path.tex>
    python tools/tex-patch.py revert-all

The image is re-encoded to the texture's **existing** width, height, format and mip count,
so the payload is exactly the same number of bytes as the one it replaces. That means the
new blocks can be written straight over the old ones at the entry's offset in the loose
`.bnk.dat`, and **no bank index and no header has to change** - which is the whole point,
because the texture bank indexes live nested inside `levels.bnk` and rewriting one is a far
bigger operation than this deserves.

Backups are per texture, under `work/tex-backup/`, so revert is exact.

Quit the game before applying: textures are read from the bank at load.
"""

import importlib.util
import io
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("tex", os.path.join(_here, "tex.py"))
tex = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tex)

BACKUP = os.path.join(_here, "..", "work", "tex-backup")


def _slot(path):
    cat = tex.catalogue()
    hit = cat.get(path.lower().replace("/", "\\"))
    if hit is None:
        raise SystemExit(path + ": not in any texture library")
    hdr, entry, payload = hit
    return hdr, entry, payload


def encode(hdr, image_path):
    """Re-encode to the exact byte length the slot already holds, mip chain included."""
    from PIL import Image
    if hdr["format"] not in tex.PIXEL_FORMAT:
        raise SystemExit("format %d is not DXT1/DXT5" % hdr["format"])
    if hdr["cubemap"]:
        raise SystemExit("cubemaps are not handled")
    src = Image.open(image_path).convert("RGBA")
    out = b""
    for m in range(hdr["mips"]):
        w, h = max(1, hdr["width"] >> m), max(1, hdr["height"] >> m)
        # DXT works on 4x4 blocks; a mip smaller than that still occupies one block.
        mw, mh = max(4, w), max(4, h)
        buf = io.BytesIO()
        src.resize((mw, mh), Image.LANCZOS).save(
            buf, format="DDS", pixel_format=tex.PIXEL_FORMAT[hdr["format"]])
        out += buf.getvalue()[128:128 + tex.payload_size(w, h, 1, hdr["format"])]
    want = hdr["data_size"]
    if len(out) != want:
        raise SystemExit("encoded %d bytes but the slot holds %d" % (len(out), want))
    return out


def apply(path, image_path):
    hdr, entry, payload = _slot(path)
    os.makedirs(BACKUP, exist_ok=True)
    safe = path.lower().replace("\\", "_").replace("/", "_").replace(" ", "_")
    bak = os.path.join(BACKUP, safe + ".orig")
    with open(payload, "r+b") as f:
        f.seek(entry["offset"])
        original = f.read(entry["size"])
        if not os.path.exists(bak):
            open(bak, "wb").write(original)
        blocks = encode(hdr, image_path)
        f.seek(entry["offset"])
        f.write(blocks)
    print(f"{path}: wrote {len(blocks)} bytes at offset {entry['offset']} "
          f"({hdr['width']}x{hdr['height']} {tex.PIXEL_FORMAT[hdr['format']]}, "
          f"{hdr['mips']} mip(s)); backup {bak}")


def revert(path):
    hdr, entry, payload = _slot(path)
    safe = path.lower().replace("\\", "_").replace("/", "_").replace(" ", "_")
    bak = os.path.join(BACKUP, safe + ".orig")
    if not os.path.exists(bak):
        print(path + ": no backup", file=sys.stderr)
        return 1
    data = open(bak, "rb").read()
    with open(payload, "r+b") as f:
        f.seek(entry["offset"])
        f.write(data)
    os.remove(bak)
    print(f"{path}: restored {len(data)} bytes")
    return 0


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 1
    if a[0] == "apply" and len(a) == 3:
        apply(a[1], a[2])
        return 0
    if a[0] == "revert" and len(a) == 2:
        return revert(a[1])
    if a[0] == "revert-all":
        if not os.path.isdir(BACKUP):
            print("nothing to revert")
            return 0
        cat = tex.catalogue()
        n = 0
        for p in list(cat):
            safe = p.replace("\\", "_").replace("/", "_").replace(" ", "_")
            if os.path.exists(os.path.join(BACKUP, safe + ".orig")):
                revert(p)
                n += 1
        print(f"reverted {n} texture(s)")
        return 0
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
