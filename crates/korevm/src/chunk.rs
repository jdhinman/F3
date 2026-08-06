//! Reader for KoreVM precompiled chunks (Lua 5.1 base, header format 2).
//!
//! Deviations from stock Lua 5.1, all verified in Notes/KoreVM.md:
//!   - header format version is 2, not 0
//!   - format 2 inserts a `funcname` string immediately after `source`
//!   - sizeof(lua_Number) is 4 (single-precision float), not 8

use crate::opcodes::Instruction;
use std::fmt;

pub const LUA_SIGNATURE: &[u8; 4] = b"\x1bLua";

#[derive(Debug)]
pub enum Error {
    BadSignature,
    UnsupportedVersion(u8),
    UnsupportedFormat(u8),
    /// Anything the reader can decode but was not built for, e.g. 8-byte numbers.
    UnsupportedHeader(&'static str, u8),
    UnknownConstantType(u8),
    UnexpectedEof { need: usize, at: usize },
    /// A size field that cannot be satisfied by the remaining bytes.
    ImplausibleSize { what: &'static str, size: u64, at: usize },
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::BadSignature => write!(f, "not a Lua chunk (missing \\27Lua signature)"),
            Error::UnsupportedVersion(v) => write!(f, "unsupported Lua version 0x{v:02X}, expected 0x51"),
            Error::UnsupportedFormat(v) => write!(f, "unsupported chunk format {v}, expected 2 (KoreVM)"),
            Error::UnsupportedHeader(what, v) => write!(f, "unsupported header field {what} = {v}"),
            Error::UnknownConstantType(t) => write!(f, "unknown constant type tag {t}"),
            Error::UnexpectedEof { need, at } => write!(f, "unexpected end of chunk: need {need} bytes at offset {at}"),
            Error::ImplausibleSize { what, size, at } => {
                write!(f, "implausible {what} count {size} at offset {at}")
            }
        }
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone)]
pub struct Header {
    pub version: u8,
    pub format: u8,
    pub little_endian: bool,
    pub size_int: u8,
    pub size_size_t: u8,
    pub size_instruction: u8,
    pub size_number: u8,
    pub integral: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Constant {
    Nil,
    Bool(bool),
    Number(f32),
    /// Lua strings are byte strings; keep them as bytes and render lossily.
    Str(Vec<u8>),
}

impl fmt::Display for Constant {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Constant::Nil => write!(f, "nil"),
            Constant::Bool(b) => write!(f, "{b}"),
            Constant::Number(n) => write!(f, "{n}"),
            Constant::Str(s) => write!(f, "{:?}", String::from_utf8_lossy(s)),
        }
    }
}

#[derive(Debug, Clone)]
pub struct LocVar {
    pub name: String,
    pub startpc: u32,
    pub endpc: u32,
}

#[derive(Debug, Clone)]
pub struct Proto {
    pub source: String,
    /// Format 2 only. `(main chunk)` for the top-level function.
    pub funcname: String,
    pub line_defined: u32,
    pub last_line_defined: u32,
    pub nups: u8,
    pub num_params: u8,
    pub is_vararg: u8,
    pub max_stack_size: u8,
    pub code: Vec<Instruction>,
    pub constants: Vec<Constant>,
    pub protos: Vec<Proto>,
    pub lineinfo: Vec<u32>,
    pub locvars: Vec<LocVar>,
    pub upvalues: Vec<String>,
}

impl Proto {
    /// Depth-first walk over this proto and every nested one.
    pub fn walk<'a>(&'a self, out: &mut Vec<&'a Proto>) {
        out.push(self);
        for p in &self.protos {
            p.walk(out);
        }
    }
}

#[derive(Debug, Clone)]
pub struct Chunk {
    pub header: Header,
    pub main: Proto,
    /// Byte length consumed, so a caller can walk a bank of concatenated chunks.
    pub size: usize,
}

struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8]> {
        if self.data.len() - self.pos < n {
            return Err(Error::UnexpectedEof { need: n, at: self.pos });
        }
        let s = &self.data[self.pos..self.pos + n];
        self.pos += n;
        Ok(s)
    }
    fn byte(&mut self) -> Result<u8> {
        Ok(self.take(1)?[0])
    }
    fn u32(&mut self) -> Result<u32> {
        let b = self.take(4)?;
        Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
    fn f32(&mut self) -> Result<f32> {
        let b = self.take(4)?;
        Ok(f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
    /// A size_t-prefixed string; the length includes a trailing NUL, and 0 means absent.
    fn string(&mut self) -> Result<Vec<u8>> {
        let at = self.pos;
        let len = self.u32()? as usize;
        if len == 0 {
            return Ok(Vec::new());
        }
        if len > self.data.len() - self.pos {
            return Err(Error::ImplausibleSize { what: "string length", size: len as u64, at });
        }
        let s = self.take(len)?;
        Ok(s[..len - 1].to_vec()) // drop the NUL
    }
    fn utf8(&mut self) -> Result<String> {
        Ok(String::from_utf8_lossy(&self.string()?).into_owned())
    }
    /// Reads a count and checks it against the bytes left, so a misparse fails here
    /// instead of allocating gigabytes.
    fn count(&mut self, what: &'static str, elem: usize) -> Result<usize> {
        let at = self.pos;
        let n = self.u32()? as usize;
        if elem > 0 && n.saturating_mul(elem) > self.data.len() - self.pos {
            return Err(Error::ImplausibleSize { what, size: n as u64, at });
        }
        Ok(n)
    }
}

fn read_header(r: &mut Reader) -> Result<Header> {
    if r.take(4)? != LUA_SIGNATURE {
        return Err(Error::BadSignature);
    }
    let version = r.byte()?;
    if version != 0x51 {
        return Err(Error::UnsupportedVersion(version));
    }
    let format = r.byte()?;
    if format != 2 {
        return Err(Error::UnsupportedFormat(format));
    }
    let endian = r.byte()?;
    if endian != 1 {
        return Err(Error::UnsupportedHeader("endianness", endian));
    }
    let size_int = r.byte()?;
    let size_size_t = r.byte()?;
    let size_instruction = r.byte()?;
    let size_number = r.byte()?;
    let integral = r.byte()?;
    if size_int != 4 {
        return Err(Error::UnsupportedHeader("sizeof(int)", size_int));
    }
    if size_size_t != 4 {
        return Err(Error::UnsupportedHeader("sizeof(size_t)", size_size_t));
    }
    if size_instruction != 4 {
        return Err(Error::UnsupportedHeader("sizeof(Instruction)", size_instruction));
    }
    if size_number != 4 {
        return Err(Error::UnsupportedHeader("sizeof(lua_Number)", size_number));
    }
    Ok(Header {
        version,
        format,
        little_endian: true,
        size_int,
        size_size_t,
        size_instruction,
        size_number,
        integral: integral != 0,
    })
}

fn read_proto(r: &mut Reader) -> Result<Proto> {
    let source = r.utf8()?;
    let funcname = r.utf8()?; // format 2 only
    let line_defined = r.u32()?;
    let last_line_defined = r.u32()?;
    let nups = r.byte()?;
    let num_params = r.byte()?;
    let is_vararg = r.byte()?;
    let max_stack_size = r.byte()?;

    let n = r.count("code", 4)?;
    let mut code = Vec::with_capacity(n);
    for _ in 0..n {
        code.push(Instruction(r.u32()?));
    }

    let n = r.count("constants", 1)?;
    let mut constants = Vec::with_capacity(n);
    for _ in 0..n {
        let t = r.byte()?;
        constants.push(match t {
            0 => Constant::Nil,
            1 => Constant::Bool(r.byte()? != 0),
            3 => Constant::Number(r.f32()?),
            4 => Constant::Str(r.string()?),
            other => return Err(Error::UnknownConstantType(other)),
        });
    }

    let n = r.count("protos", 1)?;
    let mut protos = Vec::with_capacity(n);
    for _ in 0..n {
        protos.push(read_proto(r)?);
    }

    let n = r.count("lineinfo", 4)?;
    let mut lineinfo = Vec::with_capacity(n);
    for _ in 0..n {
        lineinfo.push(r.u32()?);
    }

    let n = r.count("locvars", 1)?;
    let mut locvars = Vec::with_capacity(n);
    for _ in 0..n {
        locvars.push(LocVar { name: r.utf8()?, startpc: r.u32()?, endpc: r.u32()? });
    }

    let n = r.count("upvalues", 1)?;
    let mut upvalues = Vec::with_capacity(n);
    for _ in 0..n {
        upvalues.push(r.utf8()?);
    }

    Ok(Proto {
        source,
        funcname,
        line_defined,
        last_line_defined,
        nups,
        num_params,
        is_vararg,
        max_stack_size,
        code,
        constants,
        protos,
        lineinfo,
        locvars,
        upvalues,
    })
}

pub fn parse(data: &[u8]) -> Result<Chunk> {
    let mut r = Reader { data, pos: 0 };
    let header = read_header(&mut r)?;
    let main = read_proto(&mut r)?;
    Ok(Chunk { header, main, size: r.pos })
}
