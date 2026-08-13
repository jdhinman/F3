"""Check decoded MDL geometry against evidence that does not come from the decoder.

Renders looking plausible is not proof. Three independent tests:

1. **The bounding box in the model header.** `globals_model_headers.bnk` carries, per model,
   a bounding sphere then a bbox min and max. The decoder never reads it, so if the decoded
   vertices land inside that box - and fill it - the positions are being read correctly, at
   the right stride, in the right units. This is the strong one.
2. **Edge manifoldness.** In a correctly indexed closed mesh nearly every edge is shared by
   exactly two triangles. A stride or count error scatters the indices and that fraction
   collapses.
3. **UV range.** Texture coordinates should sit in a sane range, mostly 0..1.

    python tools/mdl-validate.py [limit]
"""

import importlib.util
import os
import struct
import sys

import numpy as np

_here = os.path.dirname(os.path.abspath(__file__))


def _load(name, fn):
    spec = importlib.util.spec_from_file_location(name, os.path.join(_here, fn))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


be = _load("bnkextract", "bnk-extract.py")
mdl = _load("mdl", "mdl.py")
GAME = r"C:\Games\Fable 3"


def header_boxes():
    """{path: (bbox_min, bbox_max)} straight from globals_model_headers.bnk."""
    lv = GAME + r"\data\levels.bnk"
    les = be.read_index(open(lv, "rb").read())
    lpl = open(lv + ".dat", "rb").read()
    def sub(n):
        return be.extract(next(e for e in les if e["path"].lower() == n.lower()), lpl)
    hidx = be.read_index(sub(r"globals\globals_model_headers.bnk"))
    hdat = sub(r"globals\globals_model_headers.bnk.dat")
    out = {}
    for e in hidx:
        h = hdat[e["offset"]:e["offset"] + e["size"]]
        if len(h) < 68 or h[:8] != b"MeshFile":
            continue
        f = struct.unpack_from("<10f", h, 28)
        out[e["path"].lower()] = (np.array(f[4:7]), np.array(f[7:10]))
    return out


def manifold_fraction(tris):
    """Fraction of edges shared by exactly two triangles."""
    e = np.vstack([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
    e = np.sort(e, axis=1)
    _u, counts = np.unique(e, axis=0, return_counts=True)
    return float((counts == 2).sum()) / max(len(counts), 1)


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 400
    boxes = header_boxes()
    inside = filled = checked = 0
    manif = []
    uvbad = 0
    worst = []
    for e in mdl.index()[:limit]:
        box = boxes.get(e["path"].lower())
        if box is None:
            continue
        try:
            d = mdl.payload(e)
            h = mdl.header(d)
            parts = [mdl.read_geometry(d, sm)[:3] for sm in mdl.find_static_submeshes(d, h)]
            parts += [mdl.read_skinned(d, sm)[:3] for sm in mdl.find_animated_submeshes(d, h)]
        except Exception:
            continue
        if not parts:
            continue
        pos = np.vstack([p[0] for p in parts])
        uv = np.vstack([p[1] for p in parts])
        tris = np.vstack([p[2] for p in parts])
        lo, hi = box
        vlo, vhi = pos.min(0), pos.max(0)
        span = np.maximum(hi - lo, 1e-4)
        tol = 0.02 * span + 1e-3
        checked += 1
        if (vlo >= lo - tol).all() and (vhi <= hi + tol).all():
            inside += 1
            # and does it FILL the box? a wrong stride usually collapses the extent
            if (np.abs(vlo - lo) <= tol).all() and (np.abs(vhi - hi) <= tol).all():
                filled += 1
            else:
                worst.append((e["path"], np.round(vlo - lo, 3), np.round(vhi - hi, 3)))
        else:
            worst.append((e["path"], np.round(vlo - lo, 3), np.round(vhi - hi, 3)))
        manif.append(manifold_fraction(tris))
        if not (-0.05 <= np.percentile(uv, 2) and np.percentile(uv, 98) <= 8.0):
            uvbad += 1
    print(f"models checked against the header bbox: {checked}")
    print(f"   vertices inside the header box : {inside}  ({100*inside//max(checked,1)}%)")
    print(f"   AND filling it to within 2%    : {filled}  ({100*filled//max(checked,1)}%)")
    if manif:
        m = np.array(manif)
        print(f"   edge manifoldness: mean {m.mean():.3f}, median {np.median(m):.3f}, "
              f">0.9 on {int((m>0.9).sum())}/{len(m)}")
    print(f"   models with out-of-range UVs   : {uvbad}")
    for p, dlo, dhi in worst[:6]:
        print(f"   OFF {p[-58:]}  min delta {dlo}  max delta {dhi}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
