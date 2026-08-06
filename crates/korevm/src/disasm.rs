//! Listing-style disassembler, modelled on `luac -l -l` output.

use crate::chunk::{Chunk, Constant, Proto};
use crate::opcodes::{index_k, is_k, Arg, Instruction, OpMode};
use std::fmt::Write;

pub struct Options {
    /// Print constants, locals and upvalues after each function's code.
    pub verbose: bool,
}

impl Default for Options {
    fn default() -> Self {
        Options { verbose: true }
    }
}

pub fn chunk(c: &Chunk, opts: &Options) -> String {
    let mut s = String::new();
    let h = &c.header;
    let _ = writeln!(
        s,
        "; KoreVM chunk: Lua 0x{:02X} format {} {} int={} size_t={} instr={} number={} integral={}",
        h.version,
        h.format,
        if h.little_endian { "LE" } else { "BE" },
        h.size_int,
        h.size_size_t,
        h.size_instruction,
        h.size_number,
        h.integral as u8
    );
    let mut protos = Vec::new();
    c.main.walk(&mut protos);
    for (i, p) in protos.iter().enumerate() {
        proto(&mut s, p, i, opts);
    }
    s
}

fn proto(s: &mut String, p: &Proto, index: usize, opts: &Options) {
    let name = if p.funcname.is_empty() { "?" } else { p.funcname.as_str() };
    let _ = writeln!(s);
    let _ = writeln!(
        s,
        "function #{index} {} <{}:{}-{}> ({} instructions)",
        name, p.source, p.line_defined, p.last_line_defined, p.code.len()
    );
    let _ = writeln!(
        s,
        "; {} params, {} slots, {} upvalues, {} locals, {} constants, {} functions, vararg={}",
        p.num_params,
        p.max_stack_size,
        p.nups,
        p.locvars.len(),
        p.constants.len(),
        p.protos.len(),
        p.is_vararg
    );

    for (pc, ins) in p.code.iter().enumerate() {
        let line = p.lineinfo.get(pc).copied().unwrap_or(0);
        let _ = writeln!(s, "\t{}\t[{}]\t{}", pc + 1, line, instruction(*ins, pc, p));
    }

    if !opts.verbose {
        return;
    }
    if !p.constants.is_empty() {
        let _ = writeln!(s, "constants ({}):", p.constants.len());
        for (i, k) in p.constants.iter().enumerate() {
            let _ = writeln!(s, "\t{i}\t{k}");
        }
    }
    if !p.locvars.is_empty() {
        let _ = writeln!(s, "locals ({}):", p.locvars.len());
        for (i, v) in p.locvars.iter().enumerate() {
            let _ = writeln!(s, "\t{i}\t{}\t{}\t{}", v.name, v.startpc, v.endpc);
        }
    }
    if !p.upvalues.is_empty() {
        let _ = writeln!(s, "upvalues ({}):", p.upvalues.len());
        for (i, u) in p.upvalues.iter().enumerate() {
            let _ = writeln!(s, "\t{i}\t{u}");
        }
    }
}

/// Renders one instruction, with a trailing comment naming any constants it touches.
pub fn instruction(ins: Instruction, pc: usize, p: &Proto) -> String {
    let Some(info) = ins.info() else {
        return format!("UNKNOWN_{}\t; raw 0x{:08X}", ins.opcode(), ins.0);
    };
    let mut out = format!("{:<14}", info.name);
    let mut comment = String::new();

    match info.mode {
        OpMode::ABx => {
            let _ = write!(out, "{} {}", ins.a(), ins.bx());
            if info.b == Arg::K {
                note(&mut comment, konst(p, ins.bx()));
            }
        }
        OpMode::AsBx => {
            let target = pc as i64 + 1 + ins.sbx() as i64 + 1;
            let _ = write!(out, "{} {}", ins.a(), ins.sbx());
            note(&mut comment, format!("to {target}"));
        }
        OpMode::ABC => {
            let _ = write!(out, "{}", ins.a());
            if info.b != Arg::N {
                let _ = write!(out, " {}", operand(ins.b(), info.b));
            }
            if info.c != Arg::N {
                let _ = write!(out, " {}", operand(ins.c(), info.c));
            }
            if let Some(k) = konst_of(p, ins.b(), info.b) {
                note(&mut comment, k);
            }
            if let Some(k) = konst_of(p, ins.c(), info.c) {
                note(&mut comment, k);
            }
        }
    }

    if comment.is_empty() {
        out
    } else {
        format!("{out}\t; {comment}")
    }
}

fn operand(v: u32, kind: Arg) -> String {
    match kind {
        Arg::K => format!("-{}", v + 1), // luac prints constants as negative indices
        Arg::RK if is_k(v) => format!("-{}", index_k(v) + 1),
        _ => v.to_string(),
    }
}

fn konst_of(p: &Proto, v: u32, kind: Arg) -> Option<String> {
    match kind {
        Arg::K => Some(konst(p, v)),
        Arg::RK if is_k(v) => Some(konst(p, index_k(v))),
        _ => None,
    }
}

fn konst(p: &Proto, i: u32) -> String {
    match p.constants.get(i as usize) {
        Some(Constant::Str(s)) => format!("{:?}", String::from_utf8_lossy(s)),
        Some(k) => k.to_string(),
        None => format!("<k{i} out of range>"),
    }
}

fn note(dst: &mut String, s: String) {
    if !dst.is_empty() {
        dst.push_str(" ");
    }
    dst.push_str(&s);
}
