"""Replace one entry's payload in a BNK bank, in place, without repacking it.

    python tools/bnk-replace.py apply  <bank.bnk> <internal\\path> <new file>
    python tools/bnk-replace.py revert <bank.bnk>

`levels.bnk.dat` is 2.1 GB. Rebuilding it to change one 4.7 MB entry is neither fast nor
safe, and the existing GDB tools sidestepped the problem by only ever writing dwords in
place at a fixed offset - which stops working the moment a record or a label is added and
the file gets longer.

So: append the new blob at the end of the payload (16-aligned, the alignment every entry
in a shipped bank uses), and rewrite just that entry's offset and size words inside the
index. Nothing else moves, so no other entry can be disturbed. The old bytes stay where
they were, orphaned and unreferenced.

Revert is exact: the 39 KB index is backed up before the first apply, so restoring it and
truncating the payload to its recorded length puts the bank back byte for byte.
"""

import json
import os
import struct
import sys
import zlib

ALIGN = 16


def inflate_index(data):
    """Returns (inflated bytes, compressed_flag). Chunk payloads concatenate into ONE
    zlib stream - see Notes/Formats.md."""
    flag = data[8]
    p, blob = 9, b""
    while p + 8 <= len(data):
        clen, _ = struct.unpack_from(">II", data, p)
        p += 8
        if clen == 0 or p + clen > len(data):
            break
        blob += data[p:p + clen]
        p += clen
    return bytearray(zlib.decompressobj().decompress(blob)), flag


def deflate_index(inflated):
    """Rewrap an inflated index. One zlib stream described as 64 KB chunks, which is how
    the reader wants it: it concatenates the chunk payloads before inflating, so the split
    only has to add up. Level 9 to match the 78 DA header every shipped bank has."""
    comp = zlib.compress(inflated, 9)
    body, written, remaining = b"", 0, len(inflated)
    while written < len(comp):
        uncomp = min(remaining, 65536)
        if remaining <= 65536:
            take = len(comp) - written
        else:
            take = max(1, min(len(comp) - written, len(comp) * uncomp // max(1, len(inflated))))
        body += struct.pack(">II", take, uncomp) + comp[written:written + take]
        written += take
        remaining -= uncomp
    return struct.pack(">II", len(body) + 9, 4) + bytes([0]) + body


def entry_table(inflated, flag):
    """Walk the entry table, returning (index, byte position of its offset word, path)."""
    (count,) = struct.unpack_from(">I", inflated, 4)
    q, fixed = 8, []
    for i in range(count):
        if flag:
            (chunks,) = struct.unpack_from(">I", inflated, q + 16)
            fixed.append((i, q))
            q += 20 + chunks * 4
        else:
            fixed.append((i, q))
            q += 12
    paths = []
    for _ in range(count):
        (plen,) = struct.unpack_from(">I", inflated, q)
        q += 4
        paths.append(inflated[q:q + plen - 1].decode("latin-1"))
        q += plen + 28
    return [(i, pos, paths[i]) for i, pos in fixed]


def backup_path(bank):
    return bank + ".preclone-backup"


def state_path(bank):
    return bank + ".preclone-state.json"


def apply(bank, want, source):
    want = want.replace("/", "\\").lower()
    blob = open(source, "rb").read()
    raw = open(bank, "rb").read()
    inflated, flag = inflate_index(raw)
    if flag:
        print("this bank uses the compressed-entry form; not handled", file=sys.stderr)
        return 1
    hit = next((t for t in entry_table(inflated, flag) if t[2].lower() == want), None)
    if hit is None:
        print(f"{want}: not in {bank}", file=sys.stderr)
        return 1
    _i, pos, path = hit

    # Back up before the first write only, so repeated applies still revert to stock.
    if not os.path.exists(backup_path(bank)):
        dat_len = os.path.getsize(bank + ".dat")
        with open(backup_path(bank), "wb") as f:
            f.write(raw)
        with open(state_path(bank), "w") as f:
            json.dump({"dat_length": dat_len}, f)
        print(f"backed up index and recorded payload length {dat_len}")

    with open(bank + ".dat", "r+b") as f:
        f.seek(0, os.SEEK_END)
        end = f.tell()
        pad = (-end) % ALIGN
        f.write(b"\0" * pad)
        offset = end + pad
        f.write(blob)
    struct.pack_into(">II", inflated, pos + 4, offset, len(blob))

    rewrapped = deflate_index(bytes(inflated))
    # Re-read what we are about to write. The index is the one part of the bank a mistake
    # would make unrecoverable without the backup, and it costs a millisecond to check.
    back, backflag = inflate_index(rewrapped)
    if back != inflated or backflag != flag:
        print("index rewrap did not round trip; refusing to write", file=sys.stderr)
        return 1
    with open(bank, "wb") as f:
        f.write(rewrapped)
    print(f"{path}: now at offset {offset}, {len(blob)} bytes (was elsewhere in the payload)")
    return 0


def revert(bank):
    if not os.path.exists(backup_path(bank)):
        print("no backup; nothing to revert", file=sys.stderr)
        return 1
    with open(state_path(bank)) as f:
        dat_len = json.load(f)["dat_length"]
    with open(backup_path(bank), "rb") as f:
        raw = f.read()
    with open(bank, "wb") as f:
        f.write(raw)
    with open(bank + ".dat", "r+b") as f:
        f.truncate(dat_len)
    os.remove(backup_path(bank))
    os.remove(state_path(bank))
    print(f"restored {bank} and truncated payload to {dat_len}")
    return 0


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    if sys.argv[1] == "revert":
        return revert(sys.argv[2])
    if sys.argv[1] == "apply" and len(sys.argv) == 5:
        return apply(sys.argv[2], sys.argv[3], sys.argv[4])
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
