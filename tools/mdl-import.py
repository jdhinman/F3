"""Replace a Fable III mesh with new geometry, changing vertex and triangle counts.

    python tools/mdl-import.py index-verify              round-trip the nested models index
    python tools/mdl-import.py obj <model> <in.obj>      replace submesh 0 from an OBJ
    python tools/mdl-import.py revert                    put everything back

Editing a mesh in place (`mdl-patch.py`) only works while the counts stay put. Changing them
moves five things at once, and all five have to agree or the game gets a model that is
internally inconsistent:

1. the submesh preamble counts - `nTris`, `tVerts`, `nVerts`
2. the element table, whose entries carry a triangle range and a bounding box
3. the vertex and index buffers themselves
4. the **bank entry**: size, uncompressed size, chunk count and the per-chunk length table,
   inside `globals_models.bnk` - which is itself an entry inside `levels.bnk`
5. the model's bounding box in `globals_model_headers.bnk`, also nested in `levels.bnk`

The nested index is the awkward part. `globals_models.bnk` uses the **compressed-entry
form**: each entry is `hash, offset, realSize, size, numChunks` followed by `numChunks`
big-endian words giving **each chunk's uncompressed length**. Change the chunk count and
every following byte of the index shifts, so the whole thing has to be rebuilt and
re-deflated - with the per-64 KB-chunk framing from Hard Lesson 16, or the game reads a
truncated index and dies on launch.
"""

import importlib.util
import os
import struct
import subprocess
import sys
import zlib

import numpy as np

_here = os.path.dirname(os.path.abspath(__file__))


def _load(name, fn):
    spec = importlib.util.spec_from_file_location(name, os.path.join(_here, fn))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


mdl = _load("mdl", "mdl.py")
be = _load("be", "bnk-extract.py")
br = _load("br", "bnk-replace.py")

LEVELS = mdl.GAME + r"\data\levels.bnk"
MODELS_BNK = r"globals\globals_models.bnk"
MODELS_DAT = mdl.GAME + r"\data\globals\globals_models.bnk.dat"
HDR_BNK = r"globals\globals_model_headers.bnk"
HDR_DAT = r"globals\globals_model_headers.bnk.dat"
WORK = os.path.join(_here, "..", "work")


def levels_entry(path):
    les = be.read_index(open(LEVELS, "rb").read())
    lpl = open(LEVELS + ".dat", "rb").read()
    return be.extract(next(e for e in les if e["path"].lower() == path.lower()), lpl)


def inflate(raw):
    p, blob = 9, b""
    while p + 8 <= len(raw):
        c, _u = struct.unpack_from(">II", raw, p)
        p += 8
        if c == 0 or p + c > len(raw):
            break
        blob += raw[p:p + c]
        p += c
    return zlib.decompressobj().decompress(blob), raw[8]


def parse_models_index(inf, flag):
    """The inflated index of a compressed-entry bank."""
    lead, count = struct.unpack_from(">2I", inf, 0)
    q = 8
    entries = []
    for _ in range(count):
        h, off, real, size, nch = struct.unpack_from(">5I", inf, q)
        q += 20
        table = list(struct.unpack_from(">%dI" % nch, inf, q)) if nch else []
        q += 4 * nch
        entries.append(dict(hash=h, offset=off, real=real, size=size, chunks=table))
    for e in entries:
        (plen,) = struct.unpack_from(">I", inf, q)
        q += 4
        e["path"] = inf[q:q + plen - 1].decode("latin-1")
        q += plen
        e["meta"] = list(struct.unpack_from(">7I", inf, q))
        q += 28
    return lead, entries


def build_models_index(lead, entries):
    out = struct.pack(">2I", lead, len(entries))
    for e in entries:
        out += struct.pack(">5I", e["hash"], e["offset"], e["real"], e["size"], len(e["chunks"]))
        for c in e["chunks"]:
            out += struct.pack(">I", c)
    for e in entries:
        b = e["path"].encode("latin-1")
        out += struct.pack(">I", len(b) + 1) + b + b"\0"
        out += struct.pack(">7I", *e["meta"])
    return out


def rebuild_static_submesh(d, sm, pos, uv, nrm, tris):
    """Emit a complete static submesh block with whatever counts the new geometry has.

    Everything not derived from the geometry - the name, the flag byte, the mesh and material
    ids, the 10 origin floats and the element's leading marker - is carried over from the
    original so nothing is invented. The element's triangle range and bounding box ARE
    rewritten, because both describe the new geometry.
    """
    name = sm["name"].encode("latin-1")
    # walk back over the preamble to recover the fields we keep
    q = sm["v0"] - 37 * sm["nElem"] - 4
    ids = d[q - 40 - 12 - 8:q - 40 - 12]
    flag = d[q - 40 - 12 - 8 - 1]
    elem0 = d[q + 4:q + 4 + 37]

    n_tris, n_verts = len(tris), len(pos)
    out = bytearray()
    out += name + b"\0"
    out += bytes([flag])
    out += ids
    out += struct.pack("<3I", n_tris, n_tris * 3, n_verts)
    # The submesh's own 10 floats are its BOUNDS, not an origin: bbox min, bbox max, centre,
    # then the radius as the half-diagonal. Verified on occlusionwall, whose values are
    # exactly (-10,-0.071,0) (10,0.071,20) (0,0,10) 14.142. Copying the original model's
    # here left a 2.35-tall obelisk declaring a 0.95-tall barrel, and the engine culled it -
    # the props rendered as nothing at all.
    lo0, hi0 = pos.min(0), pos.max(0)
    ctr = (lo0 + hi0) / 2.0
    rad = float(np.linalg.norm((hi0 - lo0) / 2.0))
    out += struct.pack("<10f", *lo0, *hi0, *ctr, rad)
    out += struct.pack("<I", 1)                       # one element covering everything
    lo, hi = lo0, hi0
    el = bytearray(elem0)
    struct.pack_into("<2I", el, 5, n_tris, 0)         # triangle count, start
    struct.pack_into("<6f", el, 13, *lo, *hi)
    out += bytes(el)

    a = np.zeros((n_verts, 6), dtype="<f2")
    a[:, 0:3] = pos
    a[:, 3] = 1.0                                     # the per-vertex shading scalar
    a[:, 4:6] = uv
    out += a.tobytes()
    # Stream B is 6 bytes of f16 normal, 2 bytes of padding, then a 4 x int16 TANGENT
    # normalised to 32767 with the fourth component carrying handedness. Writing zeros
    # there gives a zero-length tangent, the shader's TBN matrix degenerates, and the model
    # renders as nothing at all - which is exactly what happened.
    b = np.zeros((n_verts, 8), dtype="<f2")
    b[:, 0:3] = nrm
    bb = bytearray(b.tobytes())
    tan = tangents(pos, uv, nrm, tris)
    for i in range(n_verts):
        struct.pack_into("<4h", bb, 16 * i + 8, *tan[i])
    out += bytes(bb)
    # Fable III winds its triangles OPPOSITE to the stored vertex normals: measured across
    # untouched game meshes, the winding-derived face normal agrees with the stored normal
    # on 0.0% to 0.3% of triangles. An OBJ from any normal tool winds the other way, which
    # makes every face backfacing and the whole model invisible - the props simply vanish.
    flipped = np.asarray(tris, dtype="<u2")[:, [0, 2, 1]]
    out += np.ascontiguousarray(flipped).tobytes()
    out += b"\0\0\0\0"
    return bytes(out)


def tangents(pos, uv, nrm, tris):
    """Per-vertex tangent in the game's 4 x int16 form, normalised to 32767.

    Standard UV-gradient tangent, accumulated per vertex, Gram-Schmidt orthogonalised
    against the normal. The fourth component is the handedness sign. Where the UVs are
    degenerate and no tangent can be derived, any unit vector perpendicular to the normal
    will do - what matters is that it is not zero.
    """
    t = np.asarray(tris, dtype=np.int64)
    acc = np.zeros((len(pos), 3), dtype="f8")
    bit = np.zeros((len(pos), 3), dtype="f8")
    p0, p1, p2 = pos[t[:, 0]], pos[t[:, 1]], pos[t[:, 2]]
    w0, w1, w2 = uv[t[:, 0]], uv[t[:, 1]], uv[t[:, 2]]
    e1, e2 = p1 - p0, p2 - p0
    d1, d2 = w1 - w0, w2 - w0
    denom = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    r = np.where(np.abs(denom) < 1e-12, 0.0, 1.0 / np.where(denom == 0, 1, denom))
    tdir = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) * r[:, None]
    bdir = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) * r[:, None]
    for k in range(3):
        np.add.at(acc, t[:, k], tdir)
        np.add.at(bit, t[:, k], bdir)
    n = np.asarray(nrm, dtype="f8")
    tan = acc - n * np.einsum("ij,ij->i", n, acc)[:, None]
    ln = np.linalg.norm(tan, axis=1)
    # fall back to any perpendicular where the UVs gave us nothing
    bad = ln < 1e-8
    if bad.any():
        alt = np.tile(np.array([1.0, 0.0, 0.0]), (bad.sum(), 1))
        flip = np.abs(n[bad][:, 0]) > 0.9
        alt[flip] = [0.0, 1.0, 0.0]
        perp = np.cross(n[bad], alt)
        tan[bad] = perp
        ln[bad] = np.linalg.norm(perp, axis=1)
    ln[ln == 0] = 1.0
    tan = tan / ln[:, None]
    hand = np.where(np.einsum("ij,ij->i", np.cross(n, tan), bit) < 0.0, -1.0, 1.0)
    q = np.clip(np.rint(tan * 32767.0), -32767, 32767).astype(np.int16)
    return [(int(q[i, 0]), int(q[i, 1]), int(q[i, 2]), int(32767 * hand[i])) for i in range(len(pos))]


def load_obj(path):
    V, VT, F, FT = [], [], [], []
    for line in open(path, encoding="latin-1"):
        w = line.split()
        if not w:
            continue
        if w[0] == "v":
            V.append([float(x) for x in w[1:4]])
        elif w[0] == "vt":
            VT.append([float(x) for x in w[1:3]])
        elif w[0] == "f":
            idx = [t.split("/") for t in w[1:4]]
            F.append([int(t[0]) - 1 for t in idx])
            FT.append([int(t[1]) - 1 if len(t) > 1 and t[1] else int(t[0]) - 1 for t in idx])
    V = np.array(V, dtype="f4")
    tris = np.array(F, dtype=np.int64)
    uv = np.zeros((len(V), 2), dtype="f4")
    if VT:
        VT = np.array(VT, dtype="f4")
        for tri, tt in zip(F, FT):
            for a, b_ in zip(tri, tt):
                if b_ < len(VT):
                    uv[a] = VT[b_]
    # flat normals, accumulated per vertex
    nrm = np.zeros_like(V)
    e1 = V[tris[:, 1]] - V[tris[:, 0]]
    e2 = V[tris[:, 2]] - V[tris[:, 0]]
    fn = np.cross(e1, e2)
    for k in range(3):
        np.add.at(nrm, tris[:, k], fn)
    ln = np.linalg.norm(nrm, axis=1)
    ln[ln == 0] = 1
    nrm /= ln[:, None]
    return V, uv, nrm, tris.astype("<u2")


def chunk_split(data, target=49152):
    """Split so each piece compresses under the 32,768-byte slot the format allows."""
    pieces, p = [], 0
    while p < len(data):
        n = min(target, len(data) - p)
        while n > 1024 and len(zlib.compress(data[p:p + n], 9)) > 32768:
            n //= 2
        pieces.append(data[p:p + n])
        p += n
    return pieces


def write_model(entry_path, new_bytes):
    """Append the payload, then rewrite the nested index and levels.bnk around it."""
    pieces = chunk_split(new_bytes)
    blob = b""
    for i, pc in enumerate(pieces):
        c = zlib.compress(pc, 9)
        if len(c) > 32768:
            raise SystemExit("a chunk will not fit its 32,768-byte slot")
        blob += c if i == len(pieces) - 1 else c.ljust(32768, b"\0")

    with open(MODELS_DAT, "r+b") as f:
        f.seek(0, os.SEEK_END)
        end = f.tell()
        pad = (-end) % 16
        f.write(b"\0" * pad)
        offset = end + pad
        f.write(blob)

    raw = levels_entry(MODELS_BNK)
    inf, flag = inflate(raw)
    lead, entries = parse_models_index(inf, flag)
    hit = next(e for e in entries if e["path"].lower() == entry_path.lower())
    hit["offset"] = offset
    hit["real"] = len(new_bytes)
    hit["size"] = len(blob)
    hit["chunks"] = [len(p) for p in pieces]
    rebuilt = build_models_index(lead, entries)
    assert flag, "models bank should use the compressed-entry form"
    tmp = os.path.join(WORK, "globals_models.bnk")
    # globals_models.bnk uses the compressed-entry form; writing flag 0 would make the
    # reader parse 3-field entries and walk straight off the end of the index.
    open(tmp, "wb").write(br.deflate_index(rebuilt, compressed_flag=flag))
    r = subprocess.run([sys.executable, os.path.join(_here, "bnk-replace.py"), "apply",
                        LEVELS, MODELS_BNK, tmp], capture_output=True, text=True)
    if r.returncode:
        raise SystemExit("index write failed: " + (r.stderr or r.stdout)[:300])
    return offset, len(blob)


def update_header_bbox(model_path, lo, hi):
    hraw = levels_entry(HDR_BNK)
    hidx = be.read_index(hraw)
    hdat = bytearray(levels_entry(HDR_DAT))
    hit = next((e for e in hidx if e["path"].lower() == model_path.lower()), None)
    if hit is None:
        return False
    o = hit["offset"]
    centre = [(a + b) / 2.0 for a, b in zip(lo, hi)]
    radius = (sum(((b - a) / 2.0) ** 2 for a, b in zip(lo, hi))) ** 0.5
    struct.pack_into("<4f", hdat, o + 28, centre[0], centre[1], centre[2], radius)
    struct.pack_into("<6f", hdat, o + 44, *lo, *hi)
    tmp = os.path.join(WORK, "model_headers.dat")
    open(tmp, "wb").write(bytes(hdat))
    r = subprocess.run([sys.executable, os.path.join(_here, "bnk-replace.py"), "apply",
                        LEVELS, HDR_DAT, tmp], capture_output=True, text=True)
    if r.returncode:
        raise SystemExit("header write failed: " + (r.stderr or r.stdout)[:300])
    return True


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 1

    if a[0] == "index-verify":
        raw = levels_entry(MODELS_BNK)
        inf, flag = inflate(raw)
        lead, entries = parse_models_index(inf, flag)
        again = build_models_index(lead, entries)
        same = again == inf
        print(f"nested models index: {len(entries)} entries, {len(inf)} bytes inflated")
        print(f"   rebuild byte-identical: {same}")
        if not same:
            at = next((i for i, (x, y) in enumerate(zip(again, inf)) if x != y), None)
            print(f"   first difference at {at}, lengths {len(again)} vs {len(inf)}")
        return 0 if same else 1

    if a[0] == "revert":
        r = subprocess.run([sys.executable, os.path.join(_here, "bnk-replace.py"),
                            "revert", LEVELS], capture_output=True, text=True)
        print(r.stdout.strip() or r.stderr.strip())
        print("NOTE: appended model payloads are left in globals_models.bnk.dat but are "
              "unreferenced once the index is restored.")
        return 0

    if a[0] == "obj":
        e = next((x for x in mdl.index() if a[1].lower() in x["path"].lower()), None)
        if e is None:
            raise SystemExit(a[1] + ": no model matches")
        d = mdl.payload(e)
        h, sms, spans = mdl.parse_full(d)
        target = next((i for i, s in enumerate(sms) if s["kind"] == "static"), None)
        if target is None:
            raise SystemExit("no static submesh to replace")
        sm = sms[target]
        pos, uv, nrm, tris = load_obj(a[2])
        if tris.max() >= len(pos):
            raise SystemExit("OBJ has a face index past the end of its vertex list")
        block = rebuild_static_submesh(d, sm, pos, uv, nrm, tris)
        start = sm["v0"] - 37 * sm["nElem"] - 4 - 40 - 12 - 8 - 1 - (len(sm["name"]) + 1)
        end = sm["tri0"] + 6 * sm["nTris"] + 4
        new = d[:start] + block + d[end:]
        # prove it before writing it
        h2 = mdl.header(new)
        sms2 = mdl.submeshes(new, h2)
        p2, uv2, t2, n2 = mdl.read_geometry(new, sms2[target])
        if len(p2) != len(pos) or len(t2) != len(tris):
            raise SystemExit("rebuilt model does not read back with the new counts")
        off, size = write_model(e["path"], new)
        allp = np.vstack([(mdl.read_geometry(new, s)[0] if s["kind"] == "static"
                           else mdl.read_skinned(new, s)[0]) for s in sms2])
        update_header_bbox(e["path"], allp.min(0).tolist(), allp.max(0).tolist())
        print(f"{e['path']}")
        print(f"   was {sm['nVerts']} verts / {sm['nTris']} tris  ->  "
              f"{len(pos)} verts / {len(tris)} tris")
        print(f"   payload {len(d)} -> {len(new)} bytes, written at offset {off} ({size} packed)")
        print(f"   bbox {np.round(allp.min(0),3)} .. {np.round(allp.max(0),3)}")
        # mdl.index() is cached, and the index has just been rewritten underneath it.
        # Without dropping the cache this compares against the pre-write entry and reports a
        # mismatch that is not real.
        mdl._idx = None
        check = mdl.payload(next(x for x in mdl.index() if x["path"] == e["path"]))
        print(f"   re-read from the bank: {'identical' if check == new else 'MISMATCH'}")
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
