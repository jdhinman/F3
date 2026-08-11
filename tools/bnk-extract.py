"""Pull one entry out of a BNK bank. Python twin of crates/bnk, for research work
where a REPL beats a rebuild.

    python tools/bnk-extract.py <bank.bnk> <internal\\path> <out file>

Format is in Notes/Formats.md. Everything is big-endian; the index chunks concatenate
into ONE zlib stream, they are not independent streams.
"""

import struct
import sys
import zlib


def read_index(data):
    _total, _version = struct.unpack_from(">II", data, 0)
    compressed_flag = data[8]
    p = 9
    blob = b""
    while p + 8 <= len(data):
        clen, _ulen = struct.unpack_from(">II", data, p)
        p += 8
        if clen == 0 or p + clen > len(data):
            break
        blob += data[p:p + clen]
        p += clen
    # decompressobj, not decompress: the concatenated chunks can carry trailing padding
    # that a strict one-shot inflate rejects.
    inflated = zlib.decompressobj().decompress(blob)

    q = 4  # first word ignored
    (count,) = struct.unpack_from(">I", inflated, q)
    q += 4
    entries = []
    for _ in range(count):
        if compressed_flag:
            h, off, real, size, chunks = struct.unpack_from(">IIIII", inflated, q)
            q += 20 + chunks * 4
        else:
            h, off, size = struct.unpack_from(">III", inflated, q)
            q += 12
            real, chunks = size, 0
        entries.append({"hash": h, "offset": off, "real": real, "size": size, "chunks": chunks})
    for e in entries:
        (plen,) = struct.unpack_from(">I", inflated, q)
        q += 4
        e["path"] = inflated[q:q + plen - 1].decode("latin-1")
        q += plen
        e["meta"] = struct.unpack_from(">7I", inflated, q)
        q += 28
    return entries


def extract(entry, payload):
    if entry["chunks"] == 0:
        return payload[entry["offset"]:entry["offset"] + entry["size"]]
    # Compressed entries hold one zlib stream per chunk, each in a fixed 32768-byte slot.
    out = b""
    for n in range(entry["chunks"]):
        start = entry["offset"] + n * 32768
        out += zlib.decompressobj().decompress(payload[start:start + 32768])
    return out


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    bank, want = sys.argv[1], sys.argv[2].replace("/", "\\").lower()
    with open(bank, "rb") as f:
        index = f.read()
    entries = read_index(index)
    hit = next((e for e in entries if e["path"].lower() == want), None)
    if hit is None:
        print(f"{want}: not found. {len(entries)} entries, e.g.:")
        for e in entries[:10]:
            print("   ", e["path"])
        return 1
    with open(bank + ".dat", "rb") as f:
        payload = f.read()
    blob = extract(hit, payload)
    if len(sys.argv) > 3:
        with open(sys.argv[3], "wb") as f:
            f.write(blob)
        print(f"{hit['path']}: {len(blob)} bytes -> {sys.argv[3]}")
    else:
        print(f"{hit['path']}: offset {hit['offset']}, size {hit['size']}, chunks {hit['chunks']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
