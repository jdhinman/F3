"""Patch weapon augment requirements inside globals.gdb in levels.bnk.dat.

In-place dword writes, sizes unchanged, so no bank repack is needed. The game reads
globals.gdb once at startup: quit the game before applying, relaunch after.

  python tools/augment-patch.py status   # show current vs stock values
  python tools/augment-patch.py apply    # set every requirement to 0
  python tools/augment-patch.py revert   # restore stock values

Offsets were located by walking the GDB object table for the condition records'
object hashes and indexing the field data word by the field-name FNV-1 hash. The
expected-stock check makes a wrong offset a hard error instead of a corruption.
"""

import struct
import sys

# Three copies of globals.gdb exist: base game plus one per DLC. The game loads the
# newest DLC's copy, so all three must agree or the patch silently does nothing.
BASE = r"C:\Games\Fable 3\data\levels.bnk.dat"
DLC2 = r"C:\Games\Fable 3\DLC\traitors_keep\Content\dlc2free.bnk.dat"
DLC1 = r"C:\Games\Fable 3\DLC\understone_quest\Content\dlc_freeforall.bnk.dat"

# (file, absolute offset, stock value, patched value, label)
PATCHES = [
    (BASE, 60266736, 200, 0, "base: Hard Hitter flourish hits"),
    (BASE, 60443880, 10, 0, "base: Scattergun large-enemy kills"),
    (BASE, 61284156, 5, 0, "base: Donor LIVE gift recipients"),
    (DLC2, 254267188, 200, 0, "traitors_keep: Hard Hitter flourish hits"),
    (DLC2, 254457244, 10, 0, "traitors_keep: Scattergun large-enemy kills"),
    (DLC2, 255354500, 5, 0, "traitors_keep: Donor LIVE gift recipients"),
    (DLC1, 293163528, 200, 0, "understone: Hard Hitter flourish hits"),
    (DLC1, 293342968, 10, 0, "understone: Scattergun large-enemy kills"),
    (DLC1, 294193556, 5, 0, "understone: Donor LIVE gift recipients"),
    # Reparent the two event-driven conditions onto the ScriptControlled base
    # (D13B9689: Type 5, ScriptTag "", RequiredValue 1). Their counters then tick from
    # Lua via AddAmountForConditionalAugments with an empty tag, instead of waiting on
    # kill events or the dead GFWL gift service. The Augment pairing lives on the child
    # record, so it survives the reparent.
    (BASE, 60443892, 0xA68D6EE6, 0xD13B9689, "base: Scattergun parent -> ScriptControlled"),
    (BASE, 61284160, 0x2A6F2DAB, 0xD13B9689, "base: Donor parent -> ScriptControlled"),
    (DLC2, 254457256, 0xA68D6EE6, 0xD13B9689, "traitors_keep: Scattergun parent -> ScriptControlled"),
    (DLC2, 255354504, 0x2A6F2DAB, 0xD13B9689, "traitors_keep: Donor parent -> ScriptControlled"),
    (DLC1, 293342980, 0xA68D6EE6, 0xD13B9689, "understone: Scattergun parent -> ScriptControlled"),
    (DLC1, 294193560, 0x2A6F2DAB, 0xD13B9689, "understone: Donor parent -> ScriptControlled"),
]


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "status"
    if mode not in ("status", "apply", "revert"):
        print(__doc__)
        return 1
    for path, off, stock, patched, label in PATCHES:
        with open(path, "r+b" if mode != "status" else "rb") as f:
            f.seek(off)
            cur = struct.unpack("<I", f.read(4))[0]
            if mode == "status":
                state = "stock" if cur == stock else ("patched" if cur == patched else "UNEXPECTED")
                print(f"{off}: {cur} ({state}) - {label}")
                continue
            want_old, want_new = (stock, patched) if mode == "apply" else (patched, stock)
            if cur == want_new:
                print(f"{off}: already {want_new} - {label}")
                continue
            if cur != want_old:
                print(f"{off}: expected {want_old}, found {cur} - REFUSING to write. {label}")
                return 1
            f.seek(off)
            f.write(struct.pack("<I", want_new))
            print(f"{off}: {want_old} -> {want_new} - {label}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
