//! Reader and writer for Fable III BNK banks.
//!
//! A bank is an index (`x.bnk`) plus a payload (`x.bnk.dat`). Everything is big-endian.
//! The format is specified in `Notes/Formats.md`, recovered by decompiling BnkBrowser.
//!
//! The writer only emits the uncompressed-entry form (`compressed_flag = 0`), which is
//! what the community's own DLC bank uses and what the game accepts for script content.
//! Reading handles both forms.

use flate2::read::ZlibDecoder;
use flate2::write::ZlibEncoder;
use flate2::Compression;
use std::io::{Read, Write};

/// Chunk size the index is split into before compression.
const INDEX_CHUNK: usize = 65536;

/// Payload entries start on a 16-byte boundary, and the payload is padded to one at the
/// end. Read off the community DLC bank, where every offset is 16-aligned and the seventh
/// metadata word is 16 on every entry, which is what that word appears to record.
pub const ALIGN: usize = 16;

/// The metadata a real bank carries when nothing else is known about it.
pub const DEFAULT_META: [u32; 7] = [0, 0, 0, 0, 0, 0, ALIGN as u32];

fn align_up(n: usize) -> usize {
    (n + ALIGN - 1) / ALIGN * ALIGN
}

#[derive(Debug)]
pub enum Error {
    Truncated(&'static str),
    BadVersion(u32),
    Zlib(std::io::Error),
    Io(std::io::Error),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::Truncated(what) => write!(f, "index truncated reading {what}"),
            Error::BadVersion(v) => write!(f, "unsupported bank version {v}, expected 4"),
            Error::Zlib(e) => write!(f, "zlib: {e}"),
            Error::Io(e) => write!(f, "io: {e}"),
        }
    }
}
impl std::error::Error for Error {}
impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::Io(e)
    }
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone)]
pub struct Entry {
    pub path: String,
    pub hash: u32,
    pub offset: u32,
    /// Stored size in the payload.
    pub size: u32,
    /// Size after decompression. Equals `size` for uncompressed entries.
    pub real_size: u32,
    /// Zlib chunks in the payload; 0 for uncompressed entries.
    pub num_chunks: u32,
    /// The seven trailing big-endian words after each path. Carried through verbatim on a
    /// repack, because their meaning is unknown and guessing at them would be worse.
    pub meta: [u32; 7],
}

#[derive(Debug)]
pub struct Bank {
    pub version: u32,
    pub compressed_flag: u8,
    /// The first word of the inflated index, which the reader in BnkBrowser ignores.
    pub leading_word: u32,
    pub entries: Vec<Entry>,
}

/// FNV-1 over the lowercased path: multiply, then XOR.
pub fn path_hash(path: &str) -> u32 {
    let mut h: u32 = 2166136261;
    for b in path.to_lowercase().bytes() {
        h = h.wrapping_mul(16777619) ^ b as u32;
    }
    h
}

/// Paths are stored with backslashes; accept either on input.
pub fn normalise(path: &str) -> String {
    path.replace('/', "\\")
}

struct Cursor<'a> {
    d: &'a [u8],
    p: usize,
}

impl<'a> Cursor<'a> {
    fn u32(&mut self, what: &'static str) -> Result<u32> {
        if self.d.len() - self.p < 4 {
            return Err(Error::Truncated(what));
        }
        let v = u32::from_be_bytes([self.d[self.p], self.d[self.p + 1], self.d[self.p + 2], self.d[self.p + 3]]);
        self.p += 4;
        Ok(v)
    }
    fn u8(&mut self, what: &'static str) -> Result<u8> {
        if self.d.len() - self.p < 1 {
            return Err(Error::Truncated(what));
        }
        let v = self.d[self.p];
        self.p += 1;
        Ok(v)
    }
    fn take(&mut self, n: usize, what: &'static str) -> Result<&'a [u8]> {
        if self.d.len() - self.p < n {
            return Err(Error::Truncated(what));
        }
        let s = &self.d[self.p..self.p + n];
        self.p += n;
        Ok(s)
    }
}

/// Inflate the index body. The chunk payloads concatenate into ONE zlib stream; treating
/// each as its own stream caps recovery at the first chunk and silently loses the rest.
fn inflate_index(body: &[u8]) -> Result<Vec<u8>> {
    let mut c = Cursor { d: body, p: 0 };
    let mut compressed = Vec::new();
    let mut expected = 0usize;
    while c.p + 8 <= body.len() {
        let comp_len = c.u32("chunk compressed length")? as usize;
        let uncomp_len = c.u32("chunk uncompressed length")? as usize;
        if comp_len == 0 || c.p + comp_len > body.len() {
            break;
        }
        compressed.extend_from_slice(c.take(comp_len, "chunk payload")?);
        expected += uncomp_len;
    }
    let mut out = Vec::with_capacity(expected);
    ZlibDecoder::new(&compressed[..]).read_to_end(&mut out).map_err(Error::Zlib)?;
    Ok(out)
}

pub fn read_index(bytes: &[u8]) -> Result<Bank> {
    let mut c = Cursor { d: bytes, p: 0 };
    let _total = c.u32("total size")?;
    let version = c.u32("version")?;
    if version != 4 {
        return Err(Error::BadVersion(version));
    }
    let compressed_flag = c.u8("compressed flag")?;
    let index = inflate_index(&bytes[c.p..])?;

    let mut e = Cursor { d: &index, p: 0 };
    let leading_word = e.u32("leading word")?;
    let count = e.u32("file count")? as usize;

    let mut entries = Vec::with_capacity(count);
    for _ in 0..count {
        let (hash, offset, real_size, size, num_chunks) = if compressed_flag != 0 {
            let hash = e.u32("hash")?;
            let offset = e.u32("offset")?;
            let real_size = e.u32("real size")?;
            let size = e.u32("size")?;
            let num_chunks = e.u32("chunk count")?;
            e.take(num_chunks as usize * 4, "chunk table")?;
            (hash, offset, real_size, size, num_chunks)
        } else {
            let hash = e.u32("hash")?;
            let offset = e.u32("offset")?;
            let size = e.u32("size")?;
            (hash, offset, size, size, 0)
        };
        entries.push(Entry {
            path: String::new(),
            hash,
            offset,
            size,
            real_size,
            num_chunks,
            meta: [0; 7],
        });
    }
    for entry in entries.iter_mut() {
        let len = e.u32("path length")? as usize;
        let raw = e.take(len.saturating_sub(1), "path")?;
        e.u8("path terminator")?;
        entry.path = String::from_utf8_lossy(raw).into_owned();
        for m in entry.meta.iter_mut() {
            *m = e.u32("path metadata")?;
        }
    }
    Ok(Bank { version, compressed_flag, leading_word, entries })
}

/// One file to place in a bank.
pub struct Input {
    pub path: String,
    pub data: Vec<u8>,
    pub meta: [u32; 7],
}

/// Build a bank. Returns `(index, payload)` for `x.bnk` and `x.bnk.dat`.
///
/// Entries are stored uncompressed, so the payload is just the files back to back. That is
/// the form the community's DLC bank uses, and it keeps the writer free of assumptions
/// about the game's chunked-zlib layout.
pub fn write_bank(inputs: &[Input], leading_word: u32) -> Result<(Vec<u8>, Vec<u8>)> {
    let mut payload = Vec::new();
    let mut entries = Vec::with_capacity(inputs.len());
    for input in inputs {
        let path = normalise(&input.path);
        payload.resize(align_up(payload.len()), 0);
        let offset = payload.len() as u32;
        payload.extend_from_slice(&input.data);
        entries.push(Entry {
            hash: path_hash(&path),
            offset,
            size: input.data.len() as u32,
            real_size: input.data.len() as u32,
            num_chunks: 0,
            path,
            meta: input.meta,
        });
    }

    payload.resize(align_up(payload.len()), 0);

    // The inflated index: header, the fixed-size entry table, then the paths.
    let mut index = Vec::new();
    index.extend_from_slice(&leading_word.to_be_bytes());
    index.extend_from_slice(&(entries.len() as u32).to_be_bytes());
    for e in &entries {
        index.extend_from_slice(&e.hash.to_be_bytes());
        index.extend_from_slice(&e.offset.to_be_bytes());
        index.extend_from_slice(&e.size.to_be_bytes());
    }
    for e in &entries {
        let bytes = e.path.as_bytes();
        index.extend_from_slice(&((bytes.len() + 1) as u32).to_be_bytes());
        index.extend_from_slice(bytes);
        index.push(0);
        for m in e.meta {
            index.extend_from_slice(&m.to_be_bytes());
        }
    }

    // Compress the index as ONE continuing zlib stream, flushed at every 64 KB boundary so
    // that each chunk decodes to exactly its declared uncompressed length by itself.
    //
    // The split is NOT free to be arbitrary, whatever the BnkBrowser reader implies.
    // BnkBrowser concatenates every chunk payload before inflating, so any split that adds
    // up satisfies it. The game inflates chunk by chunk, and a chunk that declares 65536
    // but only yields 11787 leaves it with a truncated index - black screen, crash on
    // launch, nothing in any log. That cost a session. This only ever mattered for indexes
    // over 64 KB, which is why repacking the community DLC bank never caught it.
    //
    // Sync-flushing keeps the dictionary across blocks, which is why a shipped index has
    // one big chunk followed by small ones. Done this way, rewrapping levels.bnk
    // reproduces the game's own packer to within a byte: 27179, 3885, 3881, 4469 against
    // its 27179, 3885, 3881, 4470.
    //
    // Best compression, so the stream header is 78 DA, which is what every shipped bank
    // has; the default level emits 78 9C. Both are valid, but matching what the game has
    // demonstrably read for fifteen years costs nothing.
    let mut encoder = ZlibEncoder::new(Vec::new(), Compression::best());
    let mut body = Vec::new();
    let mut lengths: Vec<usize> = Vec::new();
    let mut consumed = 0usize;
    for block in index.chunks(INDEX_CHUNK) {
        encoder.write_all(block).map_err(Error::Zlib)?;
        encoder.flush().map_err(Error::Zlib)?;
        let so_far = encoder.get_ref().len();
        lengths.push(so_far - consumed);
        consumed = so_far;
    }
    let compressed = encoder.finish().map_err(Error::Zlib)?;
    // finish() emits the stream tail, which belongs to the final chunk.
    if let Some(last) = lengths.last_mut() {
        *last += compressed.len() - consumed;
    }
    let mut at = 0usize;
    for (block, &comp) in index.chunks(INDEX_CHUNK).zip(lengths.iter()) {
        body.extend_from_slice(&(comp as u32).to_be_bytes());
        body.extend_from_slice(&(block.len() as u32).to_be_bytes());
        body.extend_from_slice(&compressed[at..at + comp]);
        at += comp;
    }

    let mut out = Vec::with_capacity(body.len() + 9);
    let total = (body.len() + 9) as u32;
    out.extend_from_slice(&total.to_be_bytes());
    out.extend_from_slice(&4u32.to_be_bytes());
    out.push(0); // uncompressed entries
    out.extend_from_slice(&body);
    Ok((out, payload))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Each index chunk must decode to exactly its declared uncompressed length when fed
    /// to a continuing inflater, because that is how the GAME reads it. Our own reader
    /// concatenates first and cannot tell the difference, so only a test at this level
    /// catches a bad split - and a bad split is a black screen on launch.
    #[test]
    fn index_chunks_each_decode_to_their_declared_length() {
        // Big enough to need several chunks, and compressible like a real path table.
        let inputs: Vec<Input> = (0..20000)
            .map(|i| Input {
                path: format!("art\\gui\\gameface\\widget{i:05}.lua"),
                data: vec![0u8; 4],
                meta: DEFAULT_META,
            })
            .collect();
        let (index, _payload) = write_bank(&inputs, 0).expect("write");

        let mut p = 9usize;
        let mut d = flate2::Decompress::new(true);
        let mut chunks = 0;
        while p + 8 <= index.len() {
            let comp = u32::from_be_bytes(index[p..p + 4].try_into().unwrap()) as usize;
            let uncomp = u32::from_be_bytes(index[p + 4..p + 8].try_into().unwrap()) as usize;
            p += 8;
            if comp == 0 || p + comp > index.len() {
                break;
            }
            let before = d.total_out();
            let mut out = vec![0u8; uncomp + 64];
            d.decompress(&index[p..p + comp], &mut out, flate2::FlushDecompress::Sync)
                .expect("inflate chunk");
            assert_eq!(
                (d.total_out() - before) as usize,
                uncomp,
                "chunk {chunks} declared {uncomp} but did not produce it on its own"
            );
            p += comp;
            chunks += 1;
        }
        assert!(chunks > 1, "test needs a multi-chunk index, got {chunks}");
        // And it must still read back.
        let bank = read_index(&index).expect("read back");
        assert_eq!(bank.entries.len(), 20000);
    }

    #[test]
    fn hash_is_fnv1_over_the_lowercased_path() {
        // Multiply-then-xor, and case must not matter.
        assert_eq!(path_hash("Scripts\\Quests\\A.lua"), path_hash("scripts\\quests\\a.lua"));
        let mut h: u32 = 2166136261;
        for b in b"abc" {
            h = h.wrapping_mul(16777619) ^ *b as u32;
        }
        assert_eq!(path_hash("abc"), h);
    }

    /// Rebuild the community DLC bank from its own contents and compare payloads byte for
    /// byte. This is the only available check against a bank the game actually loads, so
    /// it is the one that matters: it pins the alignment, the ordering and the hashes.
    #[test]
    fn rebuilds_the_community_bank_byte_for_byte() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../reference/injector");
        let index_path = dir.join("ScriptInjector.bnk");
        if !index_path.exists() {
            // The bank pair is game-format data and is not committed. Regenerate it by
            // unzipping reference/fable3mod/files/167-Fable3_ScriptInjector.zip and
            // copying DLC/10_ScriptInjector/Content/ScriptInjector.bnk{,.dat} here.
            eprintln!("skipping: {} not present", index_path.display());
            return;
        }
        let index = std::fs::read(&index_path).unwrap();
        let payload = std::fs::read(dir.join("ScriptInjector.bnk.dat")).unwrap();
        let bank = read_index(&index).unwrap();

        let inputs: Vec<Input> = bank
            .entries
            .iter()
            .map(|e| Input {
                path: e.path.clone(),
                data: payload[e.offset as usize..(e.offset + e.size) as usize].to_vec(),
                meta: e.meta,
            })
            .collect();
        let (our_index, our_payload) = write_bank(&inputs, bank.leading_word).unwrap();

        assert_eq!(our_payload.len(), payload.len(), "payload length differs");
        assert_eq!(our_payload, payload, "payload bytes differ");

        // The index is zlib-compressed, so the bytes depend on the compressor and are not
        // expected to match. Every decoded field must.
        let ours = read_index(&our_index).unwrap();
        assert_eq!(ours.compressed_flag, bank.compressed_flag);
        assert_eq!(ours.leading_word, bank.leading_word);
        assert_eq!(ours.entries.len(), bank.entries.len());
        for (a, b) in ours.entries.iter().zip(bank.entries.iter()) {
            assert_eq!((&a.path, a.hash, a.offset, a.size, a.meta), (&b.path, b.hash, b.offset, b.size, b.meta));
        }
    }

    /// The index stream must start 78 DA, like every bank the game ships. 78 9C is equally
    /// valid zlib and equally readable by anything conformant, but there is no upside to
    /// handing the engine a variant it has never been given before.
    #[test]
    fn index_stream_header_matches_the_shipped_banks() {
        let inputs = vec![Input {
            path: "scripts/quests/a.lua".into(),
            data: b"print('a')".to_vec(),
            meta: DEFAULT_META,
        }];
        let (index, _) = write_bank(&inputs, 0).unwrap();
        // 4 total + 4 version + 1 flag + 4 compLen + 4 uncompLen = 17
        assert_eq!(&index[17..19], &[0x78, 0xDA], "index zlib header is not 78 DA");
    }

    #[test]
    fn round_trips_through_its_own_reader() {
        let inputs = vec![
            Input { path: "scripts/quests/a.lua".into(), data: b"print('a')".to_vec(), meta: [1, 2, 3, 4, 5, 6, 7] },
            Input { path: "scripts/quests/b.lua".into(), data: vec![0u8; 5000], meta: [0; 7] },
        ];
        let (index, payload) = write_bank(&inputs, 0).unwrap();
        let bank = read_index(&index).unwrap();
        assert_eq!(bank.compressed_flag, 0);
        assert_eq!(bank.entries.len(), 2);
        assert_eq!(bank.entries[0].path, "scripts\\quests\\a.lua");
        assert_eq!(bank.entries[0].meta, [1, 2, 3, 4, 5, 6, 7]);
        for (e, i) in bank.entries.iter().zip(inputs.iter()) {
            let start = e.offset as usize;
            assert_eq!(&payload[start..start + e.size as usize], &i.data[..]);
        }
    }
}
