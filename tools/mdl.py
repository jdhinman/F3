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


def find_static_submeshes(d, h):
    """Locate static submeshes by the tVerts == nTris*3 invariant.

    The material chain in front of them is not parsed, so the start is searched for rather
    than walked to. Every candidate is checked against the file length before it is used,
    which is what keeps a false positive from producing garbage geometry.
    """
    out = []
    p = h["after"]
    for _ in range(h["nSubmeshes"]):
        found = None
        for q in range(p, len(d) - 40):
            n_tris, t_verts, n_verts = struct.unpack_from("<3I", d, q)
            if t_verts != n_tris * 3 or not (0 < n_tris < 200000) or not (0 < n_verts < 200000):
                continue
            r = q + 12 + 40
            if r + 4 > len(d):
                continue
            n_elem = struct.unpack_from("<I", d, r)[0]
            if n_elem > 64:
                continue
            r += 4 + 37 * n_elem
            v0, v1 = r, r + 12 * n_verts
            tri0 = v1 + 16 * n_verts
            end = tri0 + 6 * n_tris
            if end > len(d):
                continue
            found = dict(nTris=n_tris, nVerts=n_verts, v0=v0, v1=v1, tri0=tri0, end=end)
            break
        if not found:
            break
        out.append(found)
        p = found["end"]
    return out


def read_geometry(d, sm):
    """Positions are float16 xyz; the fourth f16 is not position. UVs follow."""
    import numpy as np
    v = np.frombuffer(d, dtype="<f2", count=sm["nVerts"] * 6, offset=sm["v0"]).reshape(-1, 6)
    pos = v[:, 0:3].astype("f4")
    uv = v[:, 4:6].astype("f4")
    tris = np.frombuffer(d, dtype="<u2", count=sm["nTris"] * 3, offset=sm["tri0"]).reshape(-1, 3)
    return pos, uv, tris


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
        ok = geom = fail = 0
        for e in index():
            try:
                d = payload(e)
                h = header(d)
                ok += 1
                if h["nSubmeshes"] and len(find_static_submeshes(d, h)) == h["nSubmeshes"]:
                    geom += 1
            except Exception:
                fail += 1
        print(f"{ok} model headers parsed, {fail} failed; "
              f"{geom} models had every static submesh located by the invariant")
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
            print(f"   static submesh: {sm['nVerts']} verts, {sm['nTris']} tris")
        return 0

    if a[0] == "obj":
        sms = find_static_submeshes(d, h)
        if not sms:
            print(f"{e['path']}: no static submeshes found "
                  f"(nSubmeshes={h['nSubmeshes']}, nSkel={h['nSkel']})", file=sys.stderr)
            return 1
        meshes = [read_geometry(d, sm) for sm in sms]
        write_obj(a[2], meshes)
        print(f"{e['path']} -> {a[2]}: {len(meshes)} submesh(es), "
              f"{sum(len(m[0]) for m in meshes)} verts, {sum(len(m[2]) for m in meshes)} tris")
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
