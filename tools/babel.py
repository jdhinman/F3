"""Read and write Fable III BABEL text tables (`book.babel`).

This is the game's localisation store: every display name, description and line of
subtitle text. Nothing in the scene had decoded it - a search of the modding forums and the
wider web turns up no `.babel` documentation at all - and it was the last thing standing
between the writable GDB and genuinely new *words*.

    python tools/babel.py dump   <book.babel> [substring]
    python tools/babel.py get    <book.babel> <ID>
    python tools/babel.py verify <book.babel>            byte-identical round trip
    python tools/babel.py set    <book.babel> <ID> <text> <out.babel>
    python tools/babel.py add    <book.babel> <ID> <text> <out.babel>

**Everything is big-endian**, like BNK and unlike GDB.

```
@0    u32   0x5B010000                      version
@4    u32   record count
@8          records: u32 key, u32 chunkId, u32 byteOffset     <- sorted by key
      u32   chunk count
            per chunk: u32 chunkId, u32 compressedLen, u32 uncompressedLen, then the bytes
      u32   16384                           chunk size
      u32   count of the second index
            second index: u32 key, u32 chunkId, u24 offset    (11 bytes, sorted by key)
      ...   two further regions, not decoded, preserved verbatim
            trailing: (u32 key, u32 charCount, UTF-16BE) speaker tags, sorted by key
```

**The key is FNV-1 of the id string, exactly the hash `crates/gdb` already computes for
label strings.** That is the join: a GDB string field holds a label like
`INV_ITEM_WEAPON_DRAGONSTOMPER_NAME`, and the same hash indexes the text here.

A chunk decompresses to a run of `u32 charCount` + that many UTF-16BE code units, NUL
included in the count. A record's `byteOffset` is a byte offset into the *decompressed*
chunk.

> The one trap: **the zlib streams have no trailing checksum inside `compressedLen`.**
> `zlib.decompress` rejects them as truncated and the whole thing looks like a custom
> codec; `decompressobj().decompress()` on exactly `compressedLen` bytes returns exactly
> `uncompressedLen`. That single detail is most of the format.

Chunks are kept as raw compressed bytes and only recompressed when their contents change,
so an unmodified rebuild is byte-identical.
"""

import struct
import sys
import zlib

VERSION_WORD = 0x5B010000
CHUNK_SIZE = 16384


def fnv1(name):
    h = 0x811C9DC5
    for b in name.encode("latin-1"):
        h = ((h * 0x01000193) & 0xFFFFFFFF) ^ b
    return h


def _strings_in(blob):
    """Decode a chunk into [(offset, text)]."""
    out, p = [], 0
    while p + 4 <= len(blob):
        (n,) = struct.unpack_from(">I", blob, p)
        if n == 0 or p + 4 + 2 * n > len(blob):
            break
        out.append((p, blob[p + 4:p + 4 + 2 * n].decode("utf-16-be").rstrip("\0")))
        p += 4 + 2 * n
    return out


def _emit(strings):
    """Encode [(text)] back into chunk bytes, returning (bytes, [offset per string])."""
    buf, offs = bytearray(), []
    for s in strings:
        offs.append(len(buf))
        u = (s + "\0").encode("utf-16-be")
        buf += struct.pack(">I", len(u) // 2) + u
    return bytes(buf), offs


class Babel:
    def __init__(self, data):
        self.raw = data
        (self.version, count) = struct.unpack_from(">2I", data, 0)
        p = 8
        self.records = [list(struct.unpack_from(">3I", data, p + 12 * i)) for i in range(count)]
        p += 12 * count

        (nchunks,) = struct.unpack_from(">I", data, p)
        p += 4
        # (chunkId, compressed bytes, uncompressed length). Kept compressed so an
        # untouched chunk is re-emitted byte for byte.
        self.chunks = []
        for _ in range(nchunks):
            cid, clen, ulen = struct.unpack_from(">3I", data, p)
            p += 12
            self.chunks.append([cid, data[p:p + clen], ulen])
            p += clen
        # Everything past the chunks is preserved verbatim: a second 11-byte index over the
        # same keys, two further regions, and the trailing speaker-tag block. None of it is
        # needed to read or write display text, and inventing bytes there would be a guess.
        self.tail = data[p:]
        self._decoded = {}

    # -- reading -------------------------------------------------------------------
    def chunk_text(self, cid):
        if cid not in self._decoded:
            for c, blob, ulen in self.chunks:
                if c == cid:
                    self._decoded[cid] = zlib.decompressobj().decompress(blob)
                    break
            else:
                return None
        return self._decoded[cid]

    def get(self, key):
        for k, cid, off in self.records:
            if k == key:
                blob = self.chunk_text(cid)
                if blob is None or off + 4 > len(blob):
                    return None
                (n,) = struct.unpack_from(">I", blob, off)
                return blob[off + 4:off + 4 + 2 * n].decode("utf-16-be").rstrip("\0")
        return None

    def items(self):
        for k, cid, off in self.records:
            blob = self.chunk_text(cid)
            if blob is None or off + 4 > len(blob):
                continue
            (n,) = struct.unpack_from(">I", blob, off)
            yield k, blob[off + 4:off + 4 + 2 * n].decode("utf-16-be").rstrip("\0")

    # -- writing -------------------------------------------------------------------
    def _rewrite_chunk(self, cid, mutate):
        """Rebuild one chunk through `mutate(list_of_(offset,text))`, fixing every record
        that points into it. Offsets move, so they have to be remapped, not patched."""
        blob = self.chunk_text(cid)
        entries = _strings_in(blob)
        texts = mutate([t for _o, t in entries])
        new, offs = _emit(texts)
        remap = {old: offs[i] for i, (old, _t) in enumerate(entries)}
        for r in self.records:
            if r[1] == cid and r[2] in remap:
                r[2] = remap[r[2]]
        comp = zlib.compress(new, 9)
        for c in self.chunks:
            if c[0] == cid:
                c[1], c[2] = comp, len(new)
        self._decoded[cid] = new

    def set_text(self, key, text):
        """Replace the text an existing id resolves to."""
        for k, cid, off in self.records:
            if k == key:
                entries = _strings_in(self.chunk_text(cid))
                idx = [i for i, (o, _t) in enumerate(entries) if o == off]
                if not idx:
                    return False
                i = idx[0]

                def mutate(texts, i=i, text=text):
                    texts[i] = text
                    return texts
                self._rewrite_chunk(cid, mutate)
                return True
        return False

    def add(self, key, text):
        """Add a new id. It goes in a chunk of its own with a fresh chunk id, so no
        existing chunk is disturbed, and the record is INSERTED in key order because the
        record table is sorted and the engine binary-searches it - the same rule the GDB
        object and name tables turned out to have."""
        if any(r[0] == key for r in self.records):
            return False
        cid = max(c[0] for c in self.chunks) + 1
        while any(c[0] == cid for c in self.chunks):
            cid += 1
        new, offs = _emit([text])
        self.chunks.append([cid, zlib.compress(new, 9), len(new)])
        at = 0
        while at < len(self.records) and self.records[at][0] < key:
            at += 1
        self.records.insert(at, [key, cid, offs[0]])
        self._decoded[cid] = new
        return True

    def to_bytes(self):
        out = bytearray()
        out += struct.pack(">2I", self.version, len(self.records))
        for k, cid, off in self.records:
            out += struct.pack(">3I", k, cid, off)
        out += struct.pack(">I", len(self.chunks))
        for cid, blob, ulen in self.chunks:
            out += struct.pack(">3I", cid, len(blob), ulen)
            out += blob
        out += self.tail
        return bytes(out)


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 1
    cmd = a[0]
    b = Babel(open(a[1], "rb").read())

    if cmd == "verify":
        out = b.to_bytes()
        same = out == b.raw
        print(f"round trip {'OK: byte identical' if same else 'FAILED'}, "
              f"{len(out)} vs {len(b.raw)} bytes, "
              f"{len(b.records)} records, {len(b.chunks)} chunks")
        if not same:
            at = next((i for i, (x, y) in enumerate(zip(out, b.raw)) if x != y), None)
            print("first difference at", at)
        return 0 if same else 1

    if cmd == "dump":
        want = a[2].lower() if len(a) > 2 else ""
        n = 0
        for k, t in b.items():
            if want and want not in t.lower():
                continue
            print(f"{k:08X}  {t!r}")
            n += 1
        print(f"-- {n} strings")
        return 0

    if cmd == "get":
        print(repr(b.get(fnv1(a[2]))))
        return 0

    if cmd in ("set", "add"):
        ident, text, out = a[2], a[3], a[4]
        key = fnv1(ident)
        ok = b.set_text(key, text) if cmd == "set" else b.add(key, text)
        if not ok:
            print(f"{cmd} failed for {ident}", file=sys.stderr)
            return 1
        blob = b.to_bytes()
        open(out, "wb").write(blob)
        # Re-read what was written: a file that cannot be read back is not a file.
        check = Babel(open(out, "rb").read()).get(key)
        print(f"{ident} ({key:08X}) -> {check!r}; wrote {out} ({len(blob)} bytes, "
              f"was {len(b.raw)})")
        return 0 if check == text else 1

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
