"""Universal weapon-augment unlock for Fable III.

Converts every leaf weapon condition that has no ScriptTag into a ScriptControlled
(Type 5) condition with requirement 0, in all three globals.gdb copies (base + 2 DLC).
After one restart, the injector mod completes any weapon with a single empty-tag
AddAmountForConditionalAugments call. Script-tagged conditions are left alone (already
live-completable).

  python tools/weapon-unlock.py dry      # report what would change, write nothing
  python tools/weapon-unlock.py apply     # patch + write undo log
  python tools/weapon-unlock.py revert    # restore from undo log

GDB is read-only at runtime (record metatable has only getters), so this edits the
on-disk banks; the game must be fully quit before apply/revert and relaunched after.
In-place dword writes only, sizes unchanged, no bank repack. An undo log records every
(file, offset, old, new) so revert is exact.
"""

import importlib.util
import json
import os
import struct
import sys

SCRIPT_BASE = 0xD13B9689  # INV_ITEM_WEAPON__CONDITION_* ScriptControlled base (Type 5, ScriptTag "")
UNDO = os.path.join(os.path.dirname(__file__), "weapon-unlock-undo.json")

# The three banks carrying a globals.gdb. Where inside the payload it sits is looked up in
# the bank index rather than hardcoded: tools/bnk-replace.py relocates an entry to the end
# of the payload when its size changes, which leaves the old bytes in place but orphaned.
# A hardcoded offset would then patch the copy the game no longer reads and report success.
BANKS = [
    r"C:\Games\Fable 3\data\levels.bnk",
    r"C:\Games\Fable 3\DLC\traitors_keep\Content\dlc2free.bnk",
    r"C:\Games\Fable 3\DLC\understone_quest\Content\dlc_freeforall.bnk",
]
ENTRY = r"globals\globals.gdb"


def locate(bank, entry=ENTRY):
    """(payload path, offset, size) for one entry, read from the bank's own index."""
    spec = importlib.util.spec_from_file_location(
        "bnkextract", os.path.join(os.path.dirname(__file__), "bnk-extract.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    with open(bank, "rb") as f:
        entries = mod.read_index(f.read())
    want = entry.replace("/", "\\").lower()
    hit = next((e for e in entries if e["path"].lower() == want), None)
    if hit is None:
        raise SystemExit(f"{entry}: not in {bank}")
    if hit["chunks"]:
        raise SystemExit(f"{entry} in {bank} is chunk-compressed; in-place patching is unsafe")
    return bank + ".dat", hit["offset"], hit["size"]


GDBS = [locate(b) for b in BANKS]


def fnv(s):
    h = 0x811C9DC5
    for c in s.encode():
        h = ((h * 0x01000193) ^ c) & 0xFFFFFFFF
    return h


def parse(d):
    u32 = lambda o: struct.unpack_from("<I", d, o)[0]
    u16 = lambda o: struct.unpack_from("<H", d, o)[0]
    count = u32(4)
    tb = u32(8) + 0x18
    idx = u32(12) + tb
    def ts(tp):
        return u16(tb + tp + 1)
    def tf(tp):
        n = u16(tb + tp + 1)
        return [u32(tb + tp + 4 + 4 * i) for i in range(n)]
    p = 0x18
    objs = []
    for _ in range(count):
        tp = u32(p)
        objs.append((tp, p + 4))
        p += 4 + 4 * ts(tp)
    oh = [u32(idx + 4 * i) for i in range(count)]
    byh = {oh[i]: i for i in range(count)}
    lp = idx + 4 * count
    lp += (2 * count + 3) & ~3
    lp += u32(0x10) * 8
    lp += 4 + 4
    lcnt = u32(lp)
    lp += 4
    labels = {}
    for _ in range(lcnt):
        h = u32(lp)
        lp += 4
        st = lp
        while d[lp] != 0:
            lp += 1
        labels[h] = d[st:lp].decode("latin1")
        lp += 1
    return count, objs, oh, byh, labels, tf


def collect(path, base, size):
    """Return list of (offset, oldval, newval, why) edits for one GDB copy."""
    with open(path, "rb") as f:
        f.seek(base)
        d = f.read(size)
    count, objs, oh, byh, labels, tf = parse(d)
    u32 = lambda o: struct.unpack_from("<I", d, o)[0]
    def fld(i, name):
        tp, doff = objs[i]
        fh = fnv(name)
        for j, h in enumerate(tf(tp)):
            if h == fh:
                return doff + 4 * j
        return None
    def sval(i, name):
        o = fld(i, name)
        return labels.get(u32(o), "") if o is not None else None
    def inh_scripttag(i, depth=0):
        v = sval(i, "ScriptTag")
        if v:
            return v
        po = fld(i, "parent")
        if po is not None and depth < 6:
            ph = u32(po)
            if ph in byh:
                return inh_scripttag(byh[ph], depth + 1)
        return v

    edits = []
    for i in range(count):
        ct = sval(i, "ConditionTag")
        if not ct or not ct.startswith("INV_ITEM_WEAPON_") or "_CONDITION_" not in ct:
            continue
        weapon = ct[len("INV_ITEM_WEAPON_"):].split("_CONDITION_")[0]
        if weapon == "":
            continue  # base template record, not a leaf; leave its inheritance intact
        if inh_scripttag(i):
            continue  # already live-completable via its ScriptTag
        po = fld(i, "parent")
        if po is None:
            continue
        cur_parent = u32(po)
        if cur_parent != SCRIPT_BASE:
            edits.append((base + po, cur_parent, SCRIPT_BASE, f"{weapon}/{ct.split('_CONDITION_')[-1]} parent"))
        # zero any requirement field present on the leaf
        for rn in ("RequiredValue", "NumberToKill", "NumberToHit"):
            ro = fld(i, rn)
            if ro is not None and u32(ro) != 0:
                edits.append((base + ro, u32(ro), 0, f"{weapon}/{ct.split('_CONDITION_')[-1]} {rn}"))
        # if the leaf carries its OWN Type field, force it to 5 so the reparent's class wins
        to = fld(i, "Type")
        if to is not None and u32(to) != 5:
            edits.append((base + to, u32(to), 5, f"{weapon}/{ct.split('_CONDITION_')[-1]} Type"))
    return edits


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "dry"
    if mode == "revert":
        if not os.path.exists(UNDO):
            print("no undo log; nothing to revert")
            return 1
        log = json.load(open(UNDO))
        for path, off, old, new in log:
            with open(path, "r+b") as f:
                f.seek(off)
                cur = struct.unpack("<I", f.read(4))[0]
                if cur != new:
                    print(f"{path}@{off}: expected {new}, found {cur} - skipping")
                    continue
                f.seek(off)
                f.write(struct.pack("<I", old))
        print(f"reverted {len(log)} words")
        os.remove(UNDO)
        return 0

    all_edits = []
    for path, base, size in GDBS:
        e = collect(path, base, size)
        all_edits.append((path, e))
        print(f"{os.path.basename(path)}: {len(e)} word(s) to patch")

    if mode == "dry":
        for path, e in all_edits:
            for off, old, new, why in e[:12]:
                print(f"  {os.path.basename(path)}@{off}: {old} -> {new}  ({why})")
            if len(e) > 12:
                print(f"  ... +{len(e) - 12} more")
        print("dry run: nothing written")
        return 0

    if mode != "apply":
        print(__doc__)
        return 1

    log = []
    for path, e in all_edits:
        with open(path, "r+b") as f:
            for off, old, new, why in e:
                f.seek(off)
                cur = struct.unpack("<I", f.read(4))[0]
                if cur == new:
                    continue
                if cur != old:
                    print(f"{path}@{off}: expected {old}, found {cur} - ABORT")
                    return 1
                f.seek(off)
                f.write(struct.pack("<I", new))
                log.append((path, off, old, new))
    json.dump(log, open(UNDO, "w"))
    print(f"patched {len(log)} words across {len(GDBS)} GDB copies; undo log at {UNDO}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
