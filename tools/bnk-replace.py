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
    """Rewrap an inflated index: ONE continuing zlib stream, flushed at every 64 KB
    boundary so each chunk decodes to exactly its declared uncompressed length on its own.

    This is the part that must be exactly right. BnkBrowser concatenates every chunk
    payload before inflating, so any split that adds up satisfies it - and an arbitrary
    split is what the first version did. **The game does not read it that way.** It
    inflates chunk by chunk, so a chunk that declares 65536 and only yields 11787 leaves it
    with a truncated index; the result is a black screen and a crash on launch, with
    nothing in any log.

    Z_SYNC_FLUSH keeps the compressor's dictionary across blocks, which is why the shipped
    framing has one big chunk and then small ones. Doing it this way reproduces the game's
    own packer on levels.bnk to within a single byte: 27179, 3885, 3881, 4469 against its
    27179, 3885, 3881, 4470.
    """
    co = zlib.compressobj(9)
    body = b""
    for off in range(0, max(len(inflated), 1), 65536):
        block = inflated[off:off + 65536]
        last = off + 65536 >= len(inflated)
        part = co.compress(block) + co.flush(zlib.Z_FINISH if last else zlib.Z_SYNC_FLUSH)
        body += struct.pack(">II", len(part), len(block)) + part
    return struct.pack(">II", len(body) + 9, 4) + bytes([0]) + body


def chunks_decode_individually(raw):
    """The check that would have caught the black-screen bug. Feed each chunk to a
    continuing inflater on its own and require it to produce exactly its declared
    uncompressed length - which is how the game reads an index, and is a stronger
    condition than the whole thing inflating."""
    d = zlib.decompressobj()
    p = 9
    while p + 8 <= len(raw):
        clen, ulen = struct.unpack_from(">II", raw, p)
        p += 8
        if clen == 0 or p + clen > len(raw):
            break
        if len(d.decompress(raw[p:p + clen])) != ulen:
            return False
        p += clen
    return True


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
    if not chunks_decode_individually(rewrapped):
        print("index chunks do not decode to their declared lengths; refusing to write",
              file=sys.stderr)
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
