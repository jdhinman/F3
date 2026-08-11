"""Walk a Fable III creature type to the character records that draw it, and name them.

    python tools/record-chain.py CreatureVillagerGypsyChildMaleMistpeak
    python tools/record-chain.py --diff <childType> <adultType>

Character records hold the body (TorsoModel/HeadModel/LegsModel/...). The chain is

    creature type -> GraphicAppearanceMorphComponent -> CharacterFolder
                  -> ListItem(s) -> character record(s)

Records are keyed in the GDB name map by FNV-1 of a name, and 1,546 of the 1,619 names are
not recoverable from any shipped file. They do not need to be: the engine resolves a record
by the hash of whatever string you pass, so an 8-char alias with the same hash addresses the
same record. VERIFIED in game 2026-08-10 - passing alias "n_rtphaa" (FNV-1 == DogCollet)
turned the hero's dog into a collie.

Aliases printed here can be pasted straight into GraphicAppearanceMorph.SetCharacterRecord.
"""

import struct
import subprocess
import sys

BANK = r"C:\Games\Fable 3\data\levels.bnk"
ENTRY = r"globals\globals.gdb"
GDBDUMP = r"target\release\gdbdump.exe"
FNVPRE = r"target\release\fnvpre.exe"

# Character records all descend from this parent; used to tell a record from any other object.
RECORD_PARENT = 0xD1B9689 if False else 0x9C8A1C10


def fnv1(s):
    h = 0x811C9DC5
    for c in s.encode():
        h = ((h * 0x01000193) ^ c) & 0xFFFFFFFF
    return h


def dump(*args):
    return subprocess.run(
        [GDBDUMP, "--bank", BANK, "--entry", ENTRY, *args],
        capture_output=True, text=True,
    ).stdout


def name_map():
    """object hash -> name hash."""
    out = {}
    for line in dump("--namemap").splitlines():
        parts = line.split()
        if len(parts) == 2 and len(parts[0]) == 8 and len(parts[1]) == 8:
            try:
                out[int(parts[1], 16)] = int(parts[0], 16)
            except ValueError:
                pass
    return out


def fields_of(obj_hash):
    """[(field name, pointed-to object hash or None)] for one object.

    gdbdump prints object fields as `Name  object  -> DEADBEEF`, so the arrow and the hash
    are separate tokens; only lines carrying an arrow are object pointers.
    """
    text = dump("--hash", f"{obj_hash:08X}")
    want = f"hash {obj_hash:08X}"
    fields, inside = [], False
    for line in text.splitlines():
        if line.startswith("OBJECT"):
            inside = want in line
            continue
        if not (inside and line.startswith("    ")):
            continue
        parts = line.split()
        if not parts:
            continue
        target = None
        if "->" in parts:
            try:
                target = int(parts[parts.index("->") + 1], 16)
            except (IndexError, ValueError):
                target = None
        fields.append((parts[0], target))
    return fields


def follow(obj_hash, field):
    for name, target in fields_of(obj_hash):
        if name == field:
            return target
    return None


def records_for(type_name, nm):
    """creature type name -> list of character record object hashes."""
    nh = fnv1(type_name)
    obj = None
    for o, n in nm.items():
        if n == nh:
            obj = o
            break
    if obj is None:
        print(f"  {type_name}: not in the name map")
        return []
    morph = follow(obj, "GraphicAppearanceMorphComponent")
    if morph is None:
        print(f"  {type_name}: object {obj:08X} has no GraphicAppearanceMorphComponent")
        return []
    folder = follow(morph, "CharacterFolder")
    if folder is None:
        print(f"  {type_name}: morph {morph:08X} has no CharacterFolder")
        return []
    recs = [t for k, t in fields_of(folder) if k == "ListItem" and t is not None]
    print(f"  {type_name}: obj={obj:08X} morph={morph:08X} folder={folder:08X} "
          f"records={[f'{r:08X}' for r in recs]}")
    return recs


def alias_for(name_hash):
    out = subprocess.run([FNVPRE, f"{name_hash:08X}"], capture_output=True, text=True).stdout
    parts = out.split()
    return parts[1] if len(parts) >= 2 else "?"


def report(type_name, nm):
    recs = records_for(type_name, nm)
    for r in recs:
        nh = nm.get(r)
        if nh is None:
            print(f"    record {r:08X}: no name-map entry (cannot be addressed by name)")
            continue
        print(f"    record {r:08X}  namehash={nh:08X}  alias={alias_for(nh)}")
    return recs


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 1
    nm = name_map()
    print(f"name map: {len(nm)} entries")
    if args[0] == "--diff" and len(args) == 3:
        print("CHILD:")
        report(args[1], nm)
        print("ADULT:")
        report(args[2], nm)
    else:
        for t in args:
            report(t, nm)
    return 0


if __name__ == "__main__":
    sys.exit(main())
