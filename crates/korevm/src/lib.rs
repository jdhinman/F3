//! KoreVM: reader and disassembler for Fable III's Lua bytecode.
//!
//! KoreVM is a LuaPlus derivative on a Lua 5.1 base. The format is specified in
//! Notes/KoreVM.md; the four deviations that break stock tooling are the 7-bit opcode
//! field, the 87-opcode instruction set, chunk format 2, and 4-byte lua_Number.

pub mod chunk;
pub mod disasm;
pub mod opcodes;

pub use chunk::{parse, Chunk, Constant, Error, LocVar, Proto};
pub use opcodes::{Instruction, OPCODES};
