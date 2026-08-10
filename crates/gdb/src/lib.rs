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
//! @0    u32   (unread)
//! @4    u32   object count
//! @8    u32   template block offset, relative to 0x18
//! @12   u32   index block offset, relative to the template block
//! @16   u32   unknown-hash count
//! @0x18       objects: u32 template pointer, then one u32 per template field
//!             templates: u8 component count, u16 field count, u8 pad,
//!                        then field-count hashes, then field-count (u16 array, u16 type)
//!             object hashes: u32 per object
//!             unknown words: u16 per object, padded to 4
//!             unknown table: (u32 float bits, u32 hash) per entry
//!             labels: u32 pad, u32 index size, u32 count,
//!                     then count of (u32 hash, NUL-terminated string)
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
    let _ = c.u32("header word 0")?;
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
    // each object's pointer holds.
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

    // Object hashes, in object order.
    for i in 0..num_objects {
        objects[i].hash = c.u32("object hash")?;
    }
    // One u16 per object, purpose unknown, then padding to a 4-byte boundary.
    c.p += num_objects * 2;
    if c.p % 4 > 0 {
        c.p += 2;
    }
    // Unknown float/hash table.
    c.p += unknown_count * 8;

    // Labels: the hash-to-string table that makes everything else readable.
    let _pad = c.u32("label pad")?;
    let _index_size = c.u32("label index size")?;
    let label_count = c.u32("label count")? as usize;

    let mut labels = HashMap::with_capacity(label_count);
    for _ in 0..label_count {
        let hash = c.u32("label hash")?;
        let start = c.p;
        while c.p < d.len() && d[c.p] != 0 {
            c.p += 1;
        }
        let text = String::from_utf8_lossy(&d[start..c.p]).into_owned();
        c.p += 1; // NUL
        labels.insert(hash, text);
    }

    Ok(Database { objects, templates, labels })
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
