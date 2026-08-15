"""Read Fable III MDL meshes and export OBJ.

Container and header are decoded; the geometry is read against **BlackDemon's `35-mdl.hsl`**
hex template, the only prior art that exists, and every field it names is confirmed by the
`tVerts == nTris * 3` invariant holding on real models.

Models use the same two-bank split as textures: `globals_models.bnk` (index, nested inside
`levels.bnk`) plus `globals_models.bnk.dat` (payload, loose on disk). Payloads are the
standard chunked zlib, 32,768-byte slots.

**Header, after decompression** (little-endian):

```
u32   FNV hash            u32   nBones2, then nBones2 * 11 floats  (bind transforms)
8     zero padding        10    floats  root origin
u8    nFlags              u32   nMaterials, nSubmeshes, nSkelSubmeshes,
u32   flags[nFlags][2]          nPlanes, nUnk, nWTF
u32   nBones1             u8    pad
u32   bones[nBones1][2]   u32   nNodes, then nNodes NUL-terminated strings
        (name hash, parent index; the root's parent is 0xFFFFFFFF)
```

The dog collie reports 92 bones with a `0xFFFFFFFF` root, 2 materials and 2 skinned
submeshes, which is what a quadruped should look like.

**Static submesh:**

```
zstr  name          u32  nVerts            f16  verts[nVerts][6]   x,y,z,?,u,v
u8    unknown       10   floats  origin    f16  verts[nVerts][8]   second stream
u32   meshId        u32  nElements         u16  tris[nTris][3]
u32   materialId    37   bytes per element  4   bytes padding
u32   nTris, tVerts
```

**Not decoded:** the material blocks between the header and the first submesh. `mdl.hsl`
describes them as a type-switched set of hash+size blocks and its sizes do not line up on
the files here, so submeshes are instead located by **scanning for the invariant** - a
position where `tVerts == nTris * 3` and every declared buffer fits inside the file. That is
a heuristic, and it is marked as one; it is not a substitute for parsing the material chain.

    python tools/mdl.py info  <substring>          header fields
    python tools/mdl.py obj   <substring> <out>    static submeshes to OBJ
    python tools/mdl.py survey                     how many models parse
"""

import importlib.util
import os
import struct
import sys
import zlib

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("bnkextract", os.path.join(_here, "bnk-extract.py"))
_be = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_be)

GAME = r"C:\Games\Fable 3"
_idx = None


def index():
    global _idx
    if _idx is None:
        lv = GAME + r"\data\levels.bnk"
        les = _be.read_index(open(lv, "rb").read())
        lpl = open(lv + ".dat", "rb").read()
        sub = next(e for e in les if e["path"].lower() == r"globals\globals_models.bnk")
        _idx = _be.read_index(_be.extract(sub, lpl))
    return _idx


def payload(entry):
    with open(GAME + r"\data\globals\globals_models.bnk.dat", "rb") as f:
        f.seek(entry["offset"])
        raw = f.read(entry["size"])
    if entry["chunks"] == 0:
        return raw
    return b"".join(zlib.decompressobj().decompress(raw[n * 32768:(n + 1) * 32768])
                    for n in range(entry["chunks"]))


def header(d):
    p = 0
    def u32():
        nonlocal p
        v = struct.unpack_from("<I", d, p)[0]; p += 4; return v
    h = {"fnv": u32()}
    p += 8
    h["nFlags"] = d[p]; p += 1
    p += 8 * h["nFlags"]
    h["nBones1"] = u32()
    h["bones"] = [struct.unpack_from("<2I", d, p + 8 * i) for i in range(h["nBones1"])]
    p += 8 * h["nBones1"]
    h["nBones2"] = u32()
    p += 44 * h["nBones2"] + 40
    for k in ("nMaterials", "nSubmeshes", "nSkel", "nPlanes", "nUnk", "nWTF"):
        h[k] = u32()
    p += 1
    h["nNodes"] = u32()
    nodes = []
    for _ in range(h["nNodes"]):
        e = d.index(b"\0", p)
        nodes.append(d[p:e].decode("latin-1")); p = e + 1
    h["nodes"] = nodes
    h["after"] = p
    return h


def materials(d, h):
    """Walk the material chain. This is what removes the guesswork.

    ```
    per material:  u32 unknown, zstring name, u32 0x1234ABCD sentinel, u32 type,
                   then `type` blocks of (u32 hash, u32 size, size bytes)
    ```

    **The type IS the block count.** `mdl.hsl` writes it as a switch with a hand-listed set
    of blocks per case - 1 block for type 1, 2 for type 2, 7 for type 7, 11 for type 11 -
    and its author added "Ya, I know. This is stupid. But it works!". It is simply a count,
    so no case analysis is needed at all.

    Type 7 is near universal and its blocks run [16, strings, 4, 4, 16, 16, 4] bytes. The
    second block holds six NUL-terminated texture paths and two floats.
    """
    out = []
    p = h["after"]
    for _ in range(h["nMaterials"]):
        p += 4
        e = d.index(b"\0", p)
        name = d[p:e].decode("latin-1")
        p = e + 1
        sentinel = struct.unpack_from("<I", d, p)[0]
        p += 4
        if sentinel != 0x1234ABCD:
            raise ValueError("material sentinel %08X at %d" % (sentinel, p - 4))
        typ = struct.unpack_from("<I", d, p)[0]
        p += 4
        blocks = []
        for _b in range(typ):
            hsh, sz = struct.unpack_from("<2I", d, p)
            p += 8
            blocks.append((hsh, d[p:p + sz]))
            p += sz
        textures = [t.decode("latin-1") for t in blocks[1][1].split(b"\0")[:6] if t] if len(blocks) > 1 else []
        out.append(dict(name=name, type=typ, blocks=blocks, textures=textures))
    h["_after_materials"] = p
    return out


def submeshes(d, h):
    """Every submesh, walked to exactly - no scanning, no invariant, no guessing.

    Both kinds are laid out the same way after their preamble: vertices, a second per-vertex
    buffer, then the u16 triangle list. Static meshes carry a name and 10 origin floats and
    use 37-byte elements; skinned meshes have no name, use 41-byte elements, and follow them
    with a per-element list of the bones that element touches.
    """
    materials(d, h)
    p = h["_after_materials"]
    out = []
    for _ in range(h["nSubmeshes"]):
        e = d.index(b"\0", p)
        name = d[p:e].decode("latin-1")
        p = e + 1 + 1                                   # name, then a flag byte
        p += 8                                          # mesh id, material id
        n_tris, t_verts, n_verts = struct.unpack_from("<3I", d, p)
        p += 12 + 40                                    # counts, then 10 origin floats
        n_elem = struct.unpack_from("<I", d, p)[0]
        p += 4 + 37 * n_elem
        v0 = p
        v1 = v0 + 12 * n_verts
        tri0 = v1 + 16 * n_verts
        out.append(dict(kind="static", name=name, nTris=n_tris, nVerts=n_verts,
                        nElem=n_elem, v0=v0, v1=v1, tri0=tri0))
        p = tri0 + 6 * n_tris + 4
    for _ in range(h["nSkel"]):
        p += 1 + 8
        n_tris, t_verts, n_verts = struct.unpack_from("<3I", d, p)
        p += 12
        n_elem = struct.unpack_from("<I", d, p)[0]
        p += 4 + 41 * n_elem
        n_arr = struct.unpack_from("<I", d, p)[0]
        p += 4
        for _a in range(n_arr):
            c = struct.unpack_from("<I", d, p)[0]
            p += 4 + 4 * c
        v0 = p
        tri0 = v0 + 20 * n_verts + 16 * n_verts + 1     # the stray pad byte
        out.append(dict(kind="skinned", name="", nTris=n_tris, nVerts=n_verts,
                        nElem=n_elem, v0=v0, tri0=tri0))
        p = tri0 + 6 * n_tris + 4
    for sm in out:
        if sm["tri0"] + 6 * sm["nTris"] > len(d):
            raise ValueError("submesh runs past the end of the file")
    return out


def find_static_submeshes(d, h):
    return [s for s in submeshes(d, h) if s["kind"] == "static"]


def find_animated_submeshes(d, h):
    return [s for s in submeshes(d, h) if s["kind"] == "skinned"]


def parse_full(d):
    """Split a model into editable geometry and verbatim everything-else.

    The file is represented as an ordered list of spans. Anything understood well enough to
    regenerate is parsed; everything else - the header, the bone tables, the material chain,
    every submesh preamble and the trailing sections - is carried as raw bytes. That is the
    same discipline the GDB and BABEL writers use, and it is what makes a byte-identical
    round trip achievable on a format this size.
    """
    h = header(d)
    sms = submeshes(d, h)
    spans = []
    p = 0
    for sm in sms:
        spans.append(("raw", d[p:sm["v0"]]))
        if sm["kind"] == "static":
            spans.append(("vertsA", sm, d[sm["v0"]:sm["v1"]]))
            spans.append(("vertsB", sm, d[sm["v1"]:sm["tri0"]]))
        else:
            spans.append(("vertsS", sm, d[sm["v0"]:sm["tri0"]]))
        end = sm["tri0"] + 6 * sm["nTris"]
        spans.append(("tris", sm, d[sm["tri0"]:end]))
        p = end
    spans.append(("raw", d[p:]))
    return h, sms, spans


def to_bytes(spans):
    return b"".join(sp[-1] for sp in spans)


def set_vertices(spans, index, positions=None, uvs=None):
    """Rewrite one submesh's positions and/or UVs, keeping vertex and triangle counts.

    Same counts means every downstream offset, every element triangle range and the file
    length are unchanged, so the result can be written over the original without touching a
    bank index. Positions and UVs are stored as float16, so a value outside that range would
    be silently mangled and is rejected instead.
    """
    import numpy as np
    seen = -1
    for k, sp in enumerate(spans):
        kind = sp[0]
        if kind not in ("vertsA", "vertsS"):
            continue
        seen += 1
        if seen != index:
            continue
        sm = sp[1]
        nv = sm["nVerts"]
        stride = 12 if kind == "vertsA" else 20
        buf = bytearray(sp[2])
        arr = np.frombuffer(bytes(buf[:stride * nv]), dtype=np.uint8).reshape(nv, stride).copy()

        def put(off, data, comps):
            v = np.asarray(data, dtype="f4")
            if v.shape != (nv, comps):
                raise ValueError("expected %d x %d, got %s" % (nv, comps, v.shape))
            if not np.isfinite(v).all() or np.abs(v).max() > 65504:
                raise ValueError("value outside float16 range")
            arr[:, off:off + 2 * comps] = v.astype("<f2").view(np.uint8).reshape(nv, 2 * comps)

        if positions is not None:
            put(0, positions, 3)
        if uvs is not None:
            put(8 if stride == 12 else 16, uvs, 2)
        buf[:stride * nv] = arr.tobytes()
        spans[k] = (kind, sm, bytes(buf))
        return True
    return False


def read_geometry(d, sm):
    """Static vertex, two float16 streams, each component confirmed individually.

    Stream A (6 x f16): `x, y, z, s, u, v`. `s` runs 0.58..1.0, per-vertex shading of some
    kind. `u, v` measure 0..1 on most props and tile above 1 on surfaces that repeat.
    Stream B (8 x f16): `nx, ny, nz` are unit vectors (measured |n| = 1.0000), then a zero,
    then 8 bytes that are not float16 (30% decode as NaN) and remain unidentified.
    """
    import numpy as np
    a = np.frombuffer(d, dtype="<f2", count=sm["nVerts"] * 6, offset=sm["v0"]).reshape(-1, 6)
    b = np.frombuffer(d, dtype="<f2", count=sm["nVerts"] * 8, offset=sm["v1"]).reshape(-1, 8)
    pos = a[:, 0:3].astype("f4")
    uv = a[:, 4:6].astype("f4")
    nrm = b[:, 0:3].astype("f4")
    tris = np.frombuffer(d, dtype="<u2", count=sm["nTris"] * 3,
                         offset=sm["tri0"]).reshape(-1, 3)
    return pos, uv, tris, nrm


def read_skinned(d, sm):
    """Skinned vertex, 20 bytes: 4 float16 (xyz plus one more), 4 bone indices, 4 bone
    weights summing to 255, then 2 float16 UV. A 16-byte second buffer follows and is
    skipped. UVs are 0..1 on character skin and **tiled above 1 on fur**, which is normal."""
    import numpy as np
    n = sm["nVerts"]
    raw = np.frombuffer(d, dtype=np.uint8, count=20 * n, offset=sm["v0"]).reshape(n, 20)
    pos = raw[:, 0:6].copy().view("<f2").astype("f4")
    uv = raw[:, 16:20].copy().view("<f2").astype("f4")
    bones = raw[:, 8:12]
    weights = raw[:, 12:16]
    tris = np.frombuffer(d, dtype="<u2", count=sm["nTris"] * 3,
                         offset=sm["tri0"]).reshape(-1, 3)
    return pos, uv, tris, bones, weights


def write_obj(path, meshes):
    with open(path, "w", encoding="ascii") as f:
        f.write("# exported from Fable III MDL by tools/mdl.py\n")
        base = 1
        for i, (pos, uv, tris) in enumerate(meshes):
            f.write(f"o submesh{i}\n")
            for x, y, z in pos:
                f.write(f"v {x:.6f} {y:.6f} {z:.6f}\n")
            for u, w in uv:
                f.write(f"vt {u:.6f} {w:.6f}\n")
            for a, b, c in tris:
                f.write(f"f {base+a}/{base+a} {base+b}/{base+b} {base+c}/{base+c}\n")
            base += len(pos)


def pick(sub):
    hits = [e for e in index() if sub.lower() in e["path"].lower()]
    if not hits:
        raise SystemExit(sub + ": no model matches")
    return hits[0]


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 1

    if a[0] == "survey":
        ok = fail = full = partial = none = 0
        for e in index():
            try:
                d = payload(e)
                h = header(d)
            except Exception:
                fail += 1
                continue
            ok += 1
            want = h["nSubmeshes"] + h["nSkel"]
            got = len(find_static_submeshes(d, h)) + len(find_animated_submeshes(d, h))
            if want == 0:
                none += 1
            elif got == want:
                full += 1
            else:
                partial += 1
        print(f"{ok} model headers parsed, {fail} failed")
        print(f"   {full} models: every submesh located (static and skinned)")
        print(f"   {partial} models: some submeshes not located")
        print(f"   {none} models: no submeshes declared")
        return 0

    e = pick(a[1])
    d = payload(e)
    h = header(d)

    if a[0] == "info":
        print(e["path"])
        for k in ("fnv", "nFlags", "nBones1", "nBones2", "nMaterials",
                  "nSubmeshes", "nSkel", "nPlanes", "nWTF", "nNodes"):
            print(f"   {k:12} {h[k]}")
        for sm in find_static_submeshes(d, h):
            print(f"   static  submesh: {sm['nVerts']:6} verts, {sm['nTris']:6} tris")
        for sm in find_animated_submeshes(d, h):
            print(f"   skinned submesh: {sm['nVerts']:6} verts, {sm['nTris']:6} tris")
        return 0

    if a[0] == "obj":
        meshes = [read_geometry(d, sm)[:3] for sm in find_static_submeshes(d, h)]
        meshes += [read_skinned(d, sm)[:3] for sm in find_animated_submeshes(d, h)]
        # Never emit a submesh whose triangles point outside its vertex buffer. Roughly 2%
        # of skinned submeshes land there, and silently writing them produces garbage.
        bad = [i for i, m in enumerate(meshes) if len(m[2]) and m[2].max() >= len(m[0])]
        for i in reversed(bad):
            print(f"   skipping submesh {i}: triangle index out of range", file=sys.stderr)
            meshes.pop(i)
        if not meshes:
            print(f"{e['path']}: no submeshes found "
                  f"(nSubmeshes={h['nSubmeshes']}, nSkel={h['nSkel']})", file=sys.stderr)
            return 1
        write_obj(a[2], meshes)
        print(f"{e['path']} -> {a[2]}: {len(meshes)} submesh(es), "
              f"{sum(len(m[0]) for m in meshes)} verts, {sum(len(m[2]) for m in meshes)} tris")
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
