//! Reader for Fable III GDB object databases (`globals.gdb` and friends).
//!
//! The layout is taken from BlackDemon's `GDB_Dump.cpp`, mirrored in
//! `reference/fable3mod/files/122-GDB_Dump.zip`. Reading the source rather than running the
//! 2013 binary is the same approach that recovered the BNK format from BnkBrowser.
//!
//! A GDB is a table of **objects**, each pointing at a **template** that names and types its
//! fields, plus a **label table** mapping 32-bit hashes to strings. So a field is
//! `label(template.hash[i])` and, for string fields, the value is `label(object.data[i])`.
//! That indirection is what turns the file into readable name/value pairs.
//!
//! Unlike the BNK format, **this file is little-endian**; the dumper's `endian32_swap` is
//! only there to print big-endian-looking hex.
//!
//! ```text
//! @0    u32   zero in every shipped GDB
//! @4    u32   object count
//! @8    u32   template block offset, relative to 0x18
//! @12   u32   index block offset, relative to the template block
//! @16   u32   name map count
//! @0x18       objects: u32 template pointer, then one u32 per template field
//!             templates: u8 component count, u16 field count, u8 pad,
//!                        then field-count hashes, then field-count (u16 order, u16 type)
//!             object hashes: u32 per object, ASCENDING (the engine binary-searches them)
//!             offset corrections: u16 per object, padded to 4 (see offset_corrections)
//!             name map: (u32 FNV-1 of the name, u32 object hash) per entry
//!             labels: u32 hash table size, u32 string region bytes, u32 count,
//!                     then count of (u32 hash, NUL-terminated string),
//!                     then the label index: one u32 per label (see LABEL_TABLE_SIZE)
//! ```

use std::collections::HashMap;

/// Field data types, from the `DTYPE` comment block in the reference dumper.
/// These are the literal u16 values, exactly as the reference dumper's comment block
/// writes them - 0400 means 0x0400, not 4. Reading them as small integers is wrong and
/// silently makes every field print as unknown.
pub const TYPE_BOOL: u16 = 0x0000;
pub const TYPE_DWORD: u16 = 0x0100;
pub const TYPE_GROUP_INDEX: u16 = 0x0200;
pub const TYPE_FLOAT: u16 = 0x0300;
/// The value is itself a label hash, so it resolves to a string.
pub const TYPE_STRING_HASH: u16 = 0x0400;
pub const TYPE_ENUM: u16 = 0x0500;
pub const TYPE_OBJECT_HASH_A: u16 = 0x0600;
pub const TYPE_OBJECT_HASH_B: u16 = 0x0700;

/// Slots in the label hash table. This is the first word of the label block header, and it
/// is 65536 in all 94 GDB files the game ships, including the ones with no labels at all -
/// so it is a fixed table size rather than anything derived from the contents.
pub const LABEL_TABLE_SIZE: u32 = 0x10000;

pub fn type_name(t: u16) -> &'static str {
    match t {
        TYPE_BOOL => "bool",
        TYPE_DWORD => "dword",
        TYPE_GROUP_INDEX => "groupindex",
        TYPE_FLOAT => "float",
        TYPE_STRING_HASH => "string",
        TYPE_ENUM => "enum",
        TYPE_OBJECT_HASH_A | TYPE_OBJECT_HASH_B => "object",
        _ => "?",
    }
}

#[derive(Debug)]
pub enum Error {
    Truncated(&'static str, usize),
    BadTemplate { object: usize, pointer: u32 },
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::Truncated(what, at) => write!(f, "truncated reading {what} at offset {at}"),
            Error::BadTemplate { object, pointer } => {
                write!(f, "object {object} points at template 0x{pointer:08X}, which does not exist")
            }
        }
    }
}
impl std::error::Error for Error {}
pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone)]
pub struct Field {
    pub hash: u32,
    /// How many array slots this field occupies; 0 or 1 is a scalar.
    pub array: u16,
    pub datatype: u16,
}

#[derive(Debug, Clone)]
pub struct Template {
    pub components: u8,
    pub fields: Vec<Field>,
}

#[derive(Debug, Clone)]
pub struct Object {
    pub number: usize,
    pub hash: u32,
    pub template_pointer: u32,
    /// One raw word per template field.
    pub data: Vec<u32>,
}

pub struct Database {
    pub objects: Vec<Object>,
    pub templates: HashMap<u32, Template>,
    pub labels: HashMap<u32, String>,
    /// (name hash, object hash) pairs; see the parse comment for the hash function.
    pub name_map: Vec<(u32, u32)>,

    // Everything below exists so a parsed file can be written back byte for byte. Anything
    // this reader does not fully understand is kept verbatim rather than regenerated -
    // the template block is copied as raw bytes, and the per-object u16 array whose meaning
    // is still unknown is preserved rather than invented.
    header0: u32,
    header5: u32,
    template_block: Vec<u8>,
    /// Slots in the label hash table; always `LABEL_TABLE_SIZE` in shipped files.
    label_table_size: u32,
    /// Labels in file order. The map loses ordering, and ordering is part of the bytes -
    /// it is also the insertion order the label index is built from.
    label_order: Vec<(u32, String)>,
}

/// The 32-bit FNV-1 the engine uses for by-name object lookups. Case-sensitive.
pub fn fnv1(name: &str) -> u32 {
    let mut h: u32 = 0x811C9DC5;
    for b in name.bytes() {
        h = h.wrapping_mul(0x01000193) ^ b as u32;
    }
    h
}

struct Cur<'a> {
    d: &'a [u8],
    p: usize,
}

impl<'a> Cur<'a> {
    fn u32(&mut self, what: &'static str) -> Result<u32> {
        if self.d.len() - self.p < 4 {
            return Err(Error::Truncated(what, self.p));
        }
        let v = u32::from_le_bytes([self.d[self.p], self.d[self.p + 1], self.d[self.p + 2], self.d[self.p + 3]]);
        self.p += 4;
        Ok(v)
    }
    fn u16(&mut self, what: &'static str) -> Result<u16> {
        if self.d.len() - self.p < 2 {
            return Err(Error::Truncated(what, self.p));
        }
        let v = u16::from_le_bytes([self.d[self.p], self.d[self.p + 1]]);
        self.p += 2;
        Ok(v)
    }
    fn u8(&mut self, what: &'static str) -> Result<u8> {
        if self.d.len() - self.p < 1 {
            return Err(Error::Truncated(what, self.p));
        }
        let v = self.d[self.p];
        self.p += 1;
        Ok(v)
    }
}

/// Field count sits in the low three bytes of the template header word, read the way the
/// reference dumper reads it: `b0 + b1 + b2*256`.
fn template_size(d: &[u8], at: usize) -> Result<usize> {
    if d.len() - at < 3 {
        return Err(Error::Truncated("template header", at));
    }
    Ok(d[at] as usize + d[at + 1] as usize + d[at + 2] as usize * 256)
}

pub fn parse(d: &[u8]) -> Result<Database> {
    let mut c = Cur { d, p: 0 };
    let header0 = c.u32("header word 0")?;
    let num_objects = c.u32("object count")? as usize;
    let template_data_offset = c.u32("template offset")? as usize;
    let index_data_offset = c.u32("index offset")? as usize;
    let unknown_count = c.u32("unknown count")? as usize;

    // Objects. Each names its template, whose size says how many data words follow.
    c.p = 0x18;
    let mut objects = Vec::with_capacity(num_objects);
    for number in 0..num_objects {
        let template_pointer = c.u32("object template pointer")?;
        let size = template_size(d, template_data_offset + 0x18 + template_pointer as usize)?;
        let mut data = Vec::with_capacity(size);
        for _ in 0..size {
            data.push(c.u32("object data")?);
        }
        objects.push(Object { number, hash: 0, template_pointer, data });
    }

    // Templates, keyed by their offset from the start of the template block, which is what
    // each object's pointer holds. The raw bytes are kept too: object template pointers are
    // offsets into this block, so writing it back verbatim keeps every pointer valid.
    let template_start = c.p;
    let mut templates = HashMap::new();
    while c.p - template_start < index_data_offset {
        let key = (c.p - template_start) as u32;
        let components = c.u8("template components")?;
        let count = c.u16("template field count")? as usize;
        let _pad = c.u8("template pad")?;

        let mut hashes = Vec::with_capacity(count);
        for _ in 0..count {
            hashes.push(c.u32("template hash")?);
        }
        let mut fields = Vec::with_capacity(count);
        for hash in hashes {
            let array = c.u16("field array count")?;
            let datatype = c.u16("field type")?;
            fields.push(Field { hash, array, datatype });
        }
        templates.insert(key, Template { components, fields });
    }
    let template_block = d[template_start..c.p].to_vec();

    // Object hashes, in object order.
    for i in 0..num_objects {
        objects[i].hash = c.u32("object hash")?;
    }
    // One u16 per object: the record-offset correction. See `offset_corrections`. It is
    // recomputed on write, so it is only skipped here.
    c.p += 2 * num_objects;
    if c.p % 4 > 0 {
        c.p += 2;
    }
    // Name map: (FNV-1 hash of the object's name, object hash). This is how the engine
    // resolves by-name lookups like SetCharacterRecord("SirWalterBeck_Sick"); the names
    // themselves are not stored, only their hashes, which is why they never show up in
    // the label table. FNV-1 32-bit, offset basis 0x811C9DC5, prime 0x01000193,
    // case-sensitive - verified against HeroStatueComponent/HeroStatueNatalComponent
    // label hashes and seven shipped SetCharacterRecord literals.
    let mut name_map = Vec::with_capacity(unknown_count);
    for _ in 0..unknown_count {
        let name_hash = c.u32("name map name hash")?;
        let obj_hash = c.u32("name map object hash")?;
        name_map.push((name_hash, obj_hash));
    }

    // Labels: the hash-to-string table that makes everything else readable. The header is
    // the hash table size, the byte length of the string region, and the label count. The
    // string region length is recomputed on write, so it is read only to skip past.
    let label_table_size = c.u32("label table size")?;
    let _label_region_bytes = c.u32("label region length")?;
    let label_count = c.u32("label count")? as usize;

    let mut labels = HashMap::with_capacity(label_count);
    let mut label_order = Vec::with_capacity(label_count);
    for _ in 0..label_count {
        let hash = c.u32("label hash")?;
        let start = c.p;
        while c.p < d.len() && d[c.p] != 0 {
            c.p += 1;
        }
        let text = String::from_utf8_lossy(&d[start..c.p]).into_owned();
        c.p += 1; // NUL
        labels.insert(hash, text.clone());
        label_order.push((hash, text));
    }

    // Header word 5 is never read by anything here, but it is part of the file. Both it
    // and word 0 are zero in every shipped GDB.
    let header5 = u32::from_le_bytes([d[0x14], d[0x15], d[0x16], d[0x17]]);

    // The trailing label index is regenerated on write from `label_order`, so it is not
    // kept. `label_index_bytes` is the reconstruction; `gdbwrite --verify` is the proof.

    Ok(Database {
        objects, templates, labels, name_map,
        header0, header5, template_block, label_table_size,
        label_order,
    })
}

impl Database {
    pub fn label(&self, hash: u32) -> Option<&str> {
        self.labels.get(&hash).map(|s| s.as_str())
    }

    pub fn template_of(&self, o: &Object) -> Option<&Template> {
        self.templates.get(&o.template_pointer)
    }

    /// An object's name is not its hash - it is the value of its first string-typed
    /// field, which is how the reference dumper resolves names too.
    pub fn name_of(&self, o: &Object) -> Option<&str> {
        let t = self.template_of(o)?;
        for (i, f) in t.fields.iter().enumerate() {
            if f.datatype == TYPE_STRING_HASH {
                let raw = *o.data.get(i)?;
                if raw != 0xC59D_1C81 {
                    if let Some(s) = self.label(raw) {
                        return Some(s);
                    }
                }
            }
        }
        None
    }

    /// Read one field of an object as a display string, resolving labels where the type
    /// says the value is itself a hash.
    pub fn field_value(&self, o: &Object, index: usize) -> String {
        let Some(t) = self.template_of(o) else { return "<no template>".into() };
        let Some(f) = t.fields.get(index) else { return "<no field>".into() };
        let Some(&raw) = o.data.get(index) else { return "<no data>".into() };
        match f.datatype {
            TYPE_STRING_HASH if raw == 0xC59D_1C81 => "".into(),
            TYPE_STRING_HASH => match self.label(raw) {
                Some(s) => s.to_string(),
                None => format!("<hash {raw:08X}>"),
            },
            TYPE_FLOAT => format!("{}", f32::from_bits(raw)),
            TYPE_BOOL => if raw != 0 { "true".into() } else { "false".into() },
            TYPE_OBJECT_HASH_A | TYPE_OBJECT_HASH_B => match self.label(raw) {
                Some(s) => format!("-> {s}"),
                None => format!("-> {raw:08X}"),
            },
            _ => format!("{raw}"),
        }
    }

    pub fn field_name(&self, o: &Object, index: usize) -> String {
        let Some(t) = self.template_of(o) else { return "?".into() };
        let Some(f) = t.fields.get(index) else { return "?".into() };
        match self.label(f.hash) {
            Some(s) => s.to_string(),
            None => format!("<hash {:08X}>", f.hash),
        }
    }

    /// Objects whose name contains `needle`, case-insensitively.
    pub fn find(&self, needle: &str) -> Vec<&Object> {
        let n = needle.to_lowercase();
        self.objects
            .iter()
            .filter(|o| self.name_of(o).map(|s| s.to_lowercase().contains(&n)).unwrap_or(false))
            .collect()
    }
}

/// Pull a file out of a bank by its internal path. Entries are stored uncompressed in the
/// banks that carry GDBs, which is why this can hand back a plain slice.
pub fn from_bank(index: &[u8], payload: &[u8], path: &str) -> Option<Vec<u8>> {
    let bank = bnk::read_index(index).ok()?;
    let want = bnk::normalise(path).to_lowercase();
    let e = bank.entries.iter().find(|e| e.path.to_lowercase() == want)?;
    let start = e.offset as usize;
    let end = start + e.size as usize;
    if end > payload.len() || e.num_chunks != 0 {
        return None;
    }
    Some(payload[start..end].to_vec())
}

// -------------------------------------------------------------------------------------
// Writing. Nothing in the scene can ADD a GDB record: the community editor edits values
// and re-links nodes, and its author noted that copy/paste was still a wanted feature.
// Being able to append objects is the difference between changing the Scattershot and
// defining a new weapon.
//
// The correctness bar is a byte-identical round trip: parse(x).to_bytes() == x. Blocks that
// are not fully understood (the template block, the per-object u16 array) are written back
// verbatim rather than regenerated, so they cannot drift.
// -------------------------------------------------------------------------------------

impl Database {
    /// Serialize back to GDB bytes. Offsets and counts are recomputed from the current
    /// contents, so this is correct after objects have been appended.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut objects_block: Vec<u8> = Vec::new();
        for o in &self.objects {
            objects_block.extend_from_slice(&o.template_pointer.to_le_bytes());
            for w in &o.data {
                objects_block.extend_from_slice(&w.to_le_bytes());
            }
        }

        let mut out: Vec<u8> = Vec::with_capacity(objects_block.len() + self.template_block.len() + 0x1000);
        // Header. Word 2 is the template block offset relative to 0x18, i.e. the size of the
        // objects block; word 3 is the index offset relative to the template block, i.e. the
        // size of the template block.
        out.extend_from_slice(&self.header0.to_le_bytes());
        out.extend_from_slice(&(self.objects.len() as u32).to_le_bytes());
        out.extend_from_slice(&(objects_block.len() as u32).to_le_bytes());
        out.extend_from_slice(&(self.template_block.len() as u32).to_le_bytes());
        out.extend_from_slice(&(self.name_map.len() as u32).to_le_bytes());
        out.extend_from_slice(&self.header5.to_le_bytes());

        out.extend_from_slice(&objects_block);
        out.extend_from_slice(&self.template_block);

        for o in &self.objects {
            out.extend_from_slice(&o.hash.to_le_bytes());
        }
        for w in self.offset_corrections() {
            out.extend_from_slice(&w.to_le_bytes());
        }
        if out.len() % 4 > 0 {
            out.extend_from_slice(&[0, 0]);
        }
        for (name_hash, obj_hash) in &self.name_map {
            out.extend_from_slice(&name_hash.to_le_bytes());
            out.extend_from_slice(&obj_hash.to_le_bytes());
        }

        let mut label_region: Vec<u8> = Vec::new();
        for (hash, text) in &self.label_order {
            label_region.extend_from_slice(&hash.to_le_bytes());
            label_region.extend_from_slice(text.as_bytes());
            label_region.push(0);
        }
        out.extend_from_slice(&self.label_table_size.to_le_bytes());
        out.extend_from_slice(&(label_region.len() as u32).to_le_bytes());
        out.extend_from_slice(&(self.label_order.len() as u32).to_le_bytes());
        out.extend_from_slice(&label_region);
        out.extend_from_slice(&self.label_index_bytes());
        out
    }

    /// The one u16 per object in the index block, which nothing in the scene had decoded -
    /// the community's own GDBEditor calls it `partition`, groups records by it in a tree
    /// "for research purposes", and says in as many words that it does not know what it is.
    ///
    /// It is a **random-access accelerator for a variable-length record array**. Records
    /// are not fixed size, so the offset of object `i` normally means walking every record
    /// before it. Instead the engine estimates the offset with one multiply and a shift,
    /// and this array holds the exact correction:
    ///
    /// ```text
    /// stride  = (1024 * objectsBlockWords) / objectCount      integer division
    /// word[i] = startOfRecord(i) - ((i * stride) >> 10)       both in u32 words
    /// ```
    ///
    /// Two bytes per object instead of four for a full offset table, and O(1) indexing.
    /// The correction is signed and small (-586..1886 in `globals.gdb`) because it only
    /// tracks how far the running record size has drifted from the file's mean.
    ///
    /// Verified exactly on **every GDB in the installation: 147 files, 2,069,537 objects,
    /// no exceptions.** The shift is 10 and nothing else: 8, 9, 11, 12 and 16 each fit
    /// under half the files, because a shift that is too small quietly matches any file
    /// whose stride happens to be even at that precision.
    ///
    /// This is why a new record must be **inserted in hash order and the whole array
    /// recomputed**: inserting changes every later record's start *and* the stride, so a
    /// clone that copied its source object's word would leave every following object
    /// pointing at the wrong bytes.
    fn offset_corrections(&self) -> Vec<u16> {
        let n = self.objects.len();
        let mut out = Vec::with_capacity(n);
        if n == 0 {
            return out;
        }
        let total: u64 = self.objects.iter().map(|o| 1 + o.data.len() as u64).sum();
        let stride = (1024 * total) / n as u64;
        let mut start: i64 = 0;
        for (i, o) in self.objects.iter().enumerate() {
            let estimate = ((i as u64 * stride) >> 10) as i64;
            out.push((start - estimate) as u16);
            start += 1 + o.data.len() as i64;
        }
        out
    }

    /// Rebuild the trailing label index.
    ///
    /// It is an open-addressing hash table of `label_table_size` slots, keyed on
    /// `hash & (size - 1)`, resolving collisions by linear probing forward one slot at a
    /// time and wrapping. Labels are inserted **in file order**, and the table is then
    /// serialized by walking slots 0..size and emitting the label's byte offset (relative
    /// to the start of the label string region) for every occupied slot. Empty slots emit
    /// nothing, which is why the block is exactly one u32 per label rather than one per
    /// slot, and why it looks *almost* sorted by `hash & 0xFFFF`: the ~1,789 apparent
    /// inversions are displaced entries sitting past a run of collisions.
    ///
    /// Verified byte-identical against **all 94 GDB files** the game ships, from
    /// `morphs.gdb` (0 labels) to `globals.gdb` (28,739, longest probe run 24).
    fn label_index_bytes(&self) -> Vec<u8> {
        let size = self.label_table_size as usize;
        let mut table: Vec<u32> = vec![u32::MAX; size];
        let mut offset: u32 = 0;
        for (hash, text) in &self.label_order {
            // Every shipped file uses 65536, but do not let a non-power-of-two size mask
            // silently wrong.
            let mut slot = if size.is_power_of_two() {
                (*hash as usize) & (size - 1)
            } else {
                (*hash as usize) % size
            };
            while table[slot] != u32::MAX {
                slot = (slot + 1) % size;
            }
            table[slot] = offset;
            offset += 4 + text.len() as u32 + 1;
        }
        let mut out = Vec::with_capacity(self.label_order.len() * 4);
        for slot in table {
            if slot != u32::MAX {
                out.extend_from_slice(&slot.to_le_bytes());
            }
        }
        out
    }

    /// Add a new object that reuses an existing object's template, copying its field
    /// values as the starting point. Reusing a template is what keeps this safe: template
    /// pointers are offsets into a block written back verbatim, so no pointer moves.
    ///
    /// The new object is **inserted in object-hash order, not appended**. Object hashes are
    /// in ascending order in all 93 GDBs the game ships with any objects at all, which is
    /// what lets the engine find a record by binary search; appending breaks that
    /// invariant, and a record past the break is unreachable however correct its bytes are.
    /// Inserting is safe because nothing addresses an object by index - `parent` fields and
    /// the name map both hold object hashes - and the per-object offset corrections are
    /// recomputed from scratch on write. See `offset_corrections`.
    ///
    /// Returns the new object's index. The caller sets field values with `set_field` and
    /// gives it a name with `set_name`.
    pub fn clone_object(&mut self, src_index: usize, new_hash: u32) -> Option<usize> {
        let src = self.objects.get(src_index)?;
        let new = Object {
            number: 0,
            hash: new_hash,
            template_pointer: src.template_pointer,
            data: src.data.clone(),
        };
        let at = self.objects.partition_point(|o| o.hash < new_hash);
        self.objects.insert(at, new);
        for (n, o) in self.objects.iter_mut().enumerate() {
            o.number = n;
        }
        Some(at)
    }

    /// Set one field of an object by field name, if its template has that field.
    pub fn set_field(&mut self, index: usize, field: &str, value: u32) -> bool {
        let want = fnv1(field);
        let Some(obj) = self.objects.get(index) else { return false };
        let Some(t) = self.templates.get(&obj.template_pointer) else { return false };
        let Some(slot) = t.fields.iter().position(|f| f.hash == want) else { return false };
        self.objects[index].data[slot] = value;
        true
    }

    /// Make `name` resolve to this object, the way SetCharacterRecord("DogCollet") does.
    ///
    /// Only a name-map entry is needed: the map stores (FNV-1 of the name, object hash) and
    /// never the string, which is exactly why an 8-char alias with a colliding hash works.
    /// So naming a new object needs no label at all.
    ///
    /// The entry is **inserted in name-hash order**. The name map is sorted by name hash in
    /// all 140 shipped GDBs that have more than one entry, and the engine binary-searches
    /// it: appending produced a record that was present, complete and correct in the file
    /// and still reported missing by `GDB.RecordExists` in game. Same trap as the object
    /// hash array, one table over. → Hard Lesson 17
    pub fn set_name(&mut self, index: usize, name: &str) -> bool {
        let Some(obj) = self.objects.get(index) else { return false };
        let hash = fnv1(name);
        let at = self.name_map.partition_point(|(n, _)| *n < hash);
        self.name_map.insert(at, (hash, obj.hash));
        true
    }

    /// Add a label string, returning the hash a string field should be set to. If the
    /// string is already in the table its existing hash comes back and nothing is added.
    ///
    /// A label's hash is FNV-1 of its own text, case-sensitive - true for all 28,739
    /// labels in `globals.gdb`. So the hash is not a free choice, and two different
    /// strings that collide cannot both live in the table. That is the one case this
    /// refuses: a collision would make the engine resolve the new hash to the old string.
    /// Rename and try again; there is no way to represent it.
    ///
    /// The trailing index is rebuilt from scratch by `to_bytes`, so appending here is all
    /// there is to it.
    pub fn add_label(&mut self, text: &str) -> Option<u32> {
        let hash = fnv1(text);
        match self.labels.get(&hash) {
            Some(existing) if existing == text => return Some(hash),
            Some(_) => return None, // collision with a different string
            None => {}
        }
        // Leave headroom rather than let a nearly full table degenerate into a linear
        // scan. 28,739 of 65,536 are used in globals.gdb, so this is not a live concern.
        if self.label_order.len() + 1 >= self.label_table_size as usize {
            return None;
        }
        self.labels.insert(hash, text.to_string());
        self.label_order.push((hash, text.to_string()));
        Some(hash)
    }
}
