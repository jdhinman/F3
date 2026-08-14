"""Write a modified MDL back into the game, in place.

    python tools/mdl-patch.py scale  <substring> <factor>
    python tools/mdl-patch.py revert <substring>
    python tools/mdl-patch.py verify <substring>

Model payloads are **chunked zlib in fixed 32,768-byte slots**: chunk *n* always begins at
`offset + n*32768`, and only the final chunk is short. That is what makes an in-place write
possible. Keep the same split of the uncompressed data, recompress each piece, and pad each
slot back to the length it had - padding after a zlib stream's end is ignored by the
decompressor. The entry keeps its exact byte count, so **no bank index changes at all**,
which matters here because `globals_models.bnk` is nested inside `levels.bnk`.

The geometry edit itself keeps vertex and triangle counts identical, so every downstream
offset and element range in the model is untouched.

Quit the game before patching; models are read from the bank at load.
"""

import importlib.util
import os
import struct
import sys
import zlib

import numpy as np

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("mdl", os.path.join(_here, "mdl.py"))
mdl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mdl)

DAT = mdl.GAME + r"\data\globals\globals_models.bnk.dat"
BACKUP = os.path.join(_here, "..", "work", "mdl-backup")


def entry_for(sub):
    hits = [e for e in mdl.index() if sub.lower() in e["path"].lower()]
    if not hits:
        raise SystemExit(sub + ": no model matches")
    return hits[0]


def raw_slots(entry):
    """The compressed bytes and, per chunk, its uncompressed length and slot length."""
    with open(DAT, "rb") as f:
        f.seek(entry["offset"])
        raw = f.read(entry["size"])
    pieces = []
    for n in range(entry["chunks"]):
        start = n * 32768
        slot = raw[start:start + 32768]
        out = zlib.decompressobj().decompress(slot)
        pieces.append((len(out), len(slot)))
    return raw, pieces


def repack(data, pieces):
    """Recompress `data` using the original per-chunk split and slot sizes."""
    out = b""
    p = 0
    for ulen, slotlen in pieces:
        piece = data[p:p + ulen]
        p += ulen
        comp = zlib.compress(piece, 9)
        if len(comp) > slotlen:
            raise SystemExit("chunk grew from %d to %d compressed bytes; cannot patch in place"
                             % (slotlen, len(comp)))
        out += comp.ljust(slotlen, b"\0")
    if p != len(data):
        raise SystemExit("chunk split does not cover the data")
    return out


def backup_path(entry):
    safe = entry["path"].lower().replace("\\", "_").replace("/", "_").replace(" ", "_")
    return os.path.join(BACKUP, safe + ".orig")


def write_back(entry, blob):
    os.makedirs(BACKUP, exist_ok=True)
    with open(DAT, "r+b") as f:
        f.seek(entry["offset"])
        original = f.read(entry["size"])
        bak = backup_path(entry)
        if not os.path.exists(bak):
            open(bak, "wb").write(original)
        if len(blob) != entry["size"]:
            raise SystemExit("repacked to %d bytes, slot holds %d" % (len(blob), entry["size"]))
        f.seek(entry["offset"])
        f.write(blob)


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 1

    if a[0] == "revert":
        e = entry_for(a[1])
        bak = backup_path(e)
        if not os.path.exists(bak):
            print("no backup for " + e["path"], file=sys.stderr)
            return 1
        with open(DAT, "r+b") as f:
            f.seek(e["offset"])
            f.write(open(bak, "rb").read())
        os.remove(bak)
        print("restored " + e["path"])
        return 0

    e = entry_for(a[1])
    data = mdl.payload(e)
    raw, pieces = raw_slots(e)

    if a[0] == "verify":
        # Recompress the untouched model: the payload must come back identical and the
        # entry must keep its exact size. That is the gate for any real edit.
        blob = repack(data, pieces)
        again = b""
        for n in range(e["chunks"]):
            again += zlib.decompressobj().decompress(blob[n * 32768:(n + 1) * 32768])
        print(f"{e['path']}")
        print(f"   {e['chunks']} chunks, entry {e['size']} bytes -> repacked {len(blob)} "
              f"(same: {len(blob) == e['size']})")
        print(f"   payload round trip identical: {again == data}")
        return 0 if again == data and len(blob) == e["size"] else 1

    if a[0] == "scale":
        factor = float(a[2])
        h, sms, spans = mdl.parse_full(data)
        n = 0
        for sm in sms:
            if sm["kind"] == "static":
                pos, uv, tris, nrm = mdl.read_geometry(data, sm)
            else:
                pos, uv, tris, _b, _w = mdl.read_skinned(data, sm)
            mdl.set_vertices(spans, n, positions=pos * factor)
            n += 1
        out = mdl.to_bytes(spans)
        if len(out) != len(data):
            raise SystemExit("edit changed the file length")
        write_back(e, repack(out, pieces))
        # Read it straight back out of the bank and confirm the change landed.
        check = mdl.payload(e)
        h2, sms2, _ = mdl.parse_full(check)
        p2 = (mdl.read_geometry(check, sms2[0])[0] if sms2[0]["kind"] == "static"
              else mdl.read_skinned(check, sms2[0])[0])
        print(f"{e['path']}: scaled x{factor}, {len(sms)} submesh(es)")
        print(f"   re-read from the bank, submesh 0 bbox now "
              f"{np.round(p2.min(0), 3)} .. {np.round(p2.max(0), 3)}")
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
