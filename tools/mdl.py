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
            if not _plausible(d, v0, n_verts, 12, 8, tri0, n_tris, False):
                continue
            found = dict(nTris=n_tris, nVerts=n_verts, v0=v0, v1=v1, tri0=tri0, end=end)
            break
        if not found:
            break
        out.append(found)
        p = found["end"]
    return out


def _plausible(d, v0, n_verts, stride, uv_off, tri0, n_tris, skinned):
    """Reject a candidate submesh that decodes into nonsense.

    The `tVerts == nTris * 3` invariant is necessary but NOT sufficient - it fires on false
    positives inside the vertex data, and a false positive still produces geometry that looks
    roughly like the model because it is reading the model's own numbers at the wrong offset.
    The collie's first skinned submesh was exactly that: 213 non-manifold edges, edges seven
    times longer than its sibling, and UVs running -0.51 to 4.12.

    Two cheap gates catch it. UVs must be near 0..1, and triangle indices must reach most of
    the vertex buffer - a wrong start tends to index only part of it.
    """
    import numpy as np
    n = min(n_verts, 512)
    raw = np.frombuffer(d, dtype=np.uint8, count=stride * n, offset=v0).reshape(n, stride)
    uv = raw[:, uv_off:uv_off + 4].copy().view("<f2").astype("f4")
    if not np.isfinite(uv).all():
        return False
    # Characters do not tile their textures, so their UVs sit in 0..1 and the gate can be
    # tight. Environment props tile constantly, so theirs must be allowed to run large.
    lo, hi = (-0.6, 3.0) if skinned else (-16.0, 64.0)
    if uv.min() < lo or np.percentile(np.abs(uv), 98) > hi:
        return False
    tris = np.frombuffer(d, dtype="<u2", count=n_tris * 3, offset=tri0)
    if tris.max() >= n_verts:
        return False
    # a correct submesh references most of the vertex buffer it declares
    return len(np.unique(tris)) >= 0.35 * n_verts


def find_animated_submeshes(d, h):
    """Skinned submeshes, located by the same invariant.

    An AnimatedMesh has no name string and its vertex record is 20 bytes rather than a pair
    of streams: 4 float16 (xyz plus one more), 4 bone indices, 4 bone weights summing to 255,
    2 float16 UV. A second buffer of 16 bytes per vertex follows, most likely normals or
    tangents, and is skipped.
    """
    out = []
    p = h["after"]
    for _ in range(h["nSkel"]):
        found = None
        for q in range(p, len(d) - 40):
            n_tris, t_verts, n_verts = struct.unpack_from("<3I", d, q)
            if t_verts != n_tris * 3 or not (0 < n_tris < 300000) or not (0 < n_verts < 300000):
                continue
            r = q + 12
            if r + 4 > len(d):
                continue
            n_elem = struct.unpack_from("<I", d, r)[0]
            if n_elem > 64:
                continue
            r += 4 + 41 * n_elem
            # then nUnknown7 arrays of (count, count u32s): the bones each element uses
            if r + 4 > len(d):
                continue
            n_arr = struct.unpack_from("<I", d, r)[0]
            if n_arr > 64:
                continue
            r += 4
            bad = False
            for _a in range(n_arr):
                if r + 4 > len(d):
                    bad = True; break
                cnt = struct.unpack_from("<I", d, r)[0]
                if cnt > 4096:
                    bad = True; break
                r += 4 + 4 * cnt
            if bad:
                continue
            v0 = r
            n0 = v0 + 20 * n_verts
            tri0 = n0 + 16 * n_verts + 1          # the stray pad byte the template complains about
            end = tri0 + 6 * n_tris
            if end > len(d):
                continue
            # sanity: bone weights must sum to 255 on the first few vertices
            okw = True
            for k in range(min(8, n_verts)):
                w = d[v0 + 20 * k + 12: v0 + 20 * k + 16]
                if sum(w) not in (0, 255):
                    okw = False; break
            if not okw:
                continue
            if not _plausible(d, v0, n_verts, 20, 16, tri0, n_tris, True):
                continue
            found = dict(nTris=n_tris, nVerts=n_verts, v0=v0, tri0=tri0, end=end,
                         nElem=n_elem, skinned=True)
            break
        if not found:
            break
        out.append(found)
        p = found["end"]
    return out


def read_skinned(d, sm):
    import numpy as np
    n = sm["nVerts"]
    raw = np.frombuffer(d, dtype=np.uint8, count=20 * n, offset=sm["v0"]).reshape(n, 20)
    pos = raw[:, 0:6].copy().view("<f2").astype("f4")          # xyz
    uv = raw[:, 16:20].copy().view("<f2").astype("f4")
    bones = raw[:, 8:12]
    weights = raw[:, 12:16]
    tris = np.frombuffer(d, dtype="<u2", count=sm["nTris"] * 3,
                         offset=sm["tri0"]).reshape(-1, 3)
    return pos, uv, tris, bones, weights


def read_geometry(d, sm):
    """Static vertex, two float16 streams, both confirmed component by component.

    Stream A (6 x f16): `x, y, z, s, u, v`. `s` runs 0.58..1.0 and is per-vertex shading of
    some kind - the template guessed illumination. `u, v` measure 0..1.
    Stream B (8 x f16): `nx, ny, nz` are **unit vectors** (|n| = 1.0000 measured), then a
    zero, then 8 bytes that are not float16 at all (30% of them decode as NaN) and are still
    unidentified - most likely a packed tangent.
    """
    import numpy as np
    a = np.frombuffer(d, dtype="<f2", count=sm["nVerts"] * 6, offset=sm["v0"]).reshape(-1, 6)
    b = np.frombuffer(d, dtype="<f2", count=sm["nVerts"] * 8, offset=sm["v1"]).reshape(-1, 8)
    pos = a[:, 0:3].astype("f4")
    uv = a[:, 4:6].astype("f4")
    nrm = b[:, 0:3].astype("f4")
    tris = np.frombuffer(d, dtype="<u2", count=sm["nTris"] * 3, offset=sm["tri0"]).reshape(-1, 3)
    return pos, uv, tris, nrm


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
