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


HDR_BNK = r"globals\globals_model_headers.bnk"
HDR_DAT = r"globals\globals_model_headers.bnk.dat"
LEVELS = mdl.GAME + r"\data\levels.bnk"


def update_header_bbox(model_path, pos_min, pos_max):
    """Rewrite the model's declared bounding sphere and bbox in globals_model_headers.

    The engine culls and does spatial queries against this box, and the decoder never writes
    it, so geometry that outgrows its declared bounds is a real hazard - almost certainly
    part of why the scaled dog went invisible. The header is a fixed 115 bytes, so the
    payload keeps its size and only levels.bnk's entry for it has to be rewritten.
    """
    _bespec = importlib.util.spec_from_file_location("be", os.path.join(_here, "bnk-extract.py"))
    be = importlib.util.module_from_spec(_bespec); _bespec.loader.exec_module(be)
    les = be.read_index(open(LEVELS, "rb").read())
    lpl = open(LEVELS + ".dat", "rb").read()
    hidx = be.read_index(be.extract(next(e for e in les if e["path"].lower() == HDR_BNK), lpl))
    hdat = bytearray(be.extract(next(e for e in les if e["path"].lower() == HDR_DAT), lpl))
    hit = next((e for e in hidx if e["path"].lower() == model_path.lower()), None)
    if hit is None:
        return False
    o = hit["offset"]
    centre = [(a + b) / 2.0 for a, b in zip(pos_min, pos_max)]
    radius = max(((b - a) / 2.0 for a, b in zip(pos_min, pos_max)))
    radius = (sum(((b - a) / 2.0) ** 2 for a, b in zip(pos_min, pos_max))) ** 0.5
    struct.pack_into("<4f", hdat, o + 28, centre[0], centre[1], centre[2], radius)
    struct.pack_into("<6f", hdat, o + 44, *pos_min, *pos_max)
    tmp = os.path.join(_here, "..", "work", "model_headers.dat")
    open(tmp, "wb").write(bytes(hdat))
    import subprocess
    r = subprocess.run([sys.executable, os.path.join(_here, "bnk-replace.py"), "apply",
                        LEVELS, HDR_DAT, tmp], capture_output=True, text=True)
    if r.returncode:
        raise SystemExit("header write failed: " + r.stderr[:300])
    return True


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
        # A SKINNED mesh cannot be scaled by touching its vertices. Its positions live in
        # bind-pose space and the engine transforms them through the per-bone bind matrices
        # in the header (nBones2 x 11 floats). Scale the vertices without scaling those and
        # the skinning solves to nonsense: the dog went invisible and the Sanctuary, which
        # renders it on a pedestal, froze. Static meshes have no such coupling.
        if any(sm["kind"] == "skinned" for sm in sms) and "--force" not in a:
            print(f"{e['path']}: has skinned submeshes. Scaling vertices alone breaks "
                  f"skinning, because positions are in bind-pose space and the bone bind "
                  f"transforms would still be at the old scale. Use a static model, or "
                  f"pass --force if you know what you are doing.", file=sys.stderr)
            return 1
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
        allp = []
        for sm in sms2:
            allp.append(mdl.read_geometry(check, sm)[0] if sm["kind"] == "static"
                        else mdl.read_skinned(check, sm)[0])
        allp = np.vstack(allp)
        if update_header_bbox(e["path"], allp.min(0).tolist(), allp.max(0).tolist()):
            print(f"   model header bbox updated to {np.round(allp.min(0),3)} .. "
                  f"{np.round(allp.max(0),3)}")
        else:
            print("   WARNING: no model header entry found; bbox left stale", file=sys.stderr)
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
