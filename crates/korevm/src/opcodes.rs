//! The KoreVM opcode set and instruction encoding.
//!
//! Encoding, verified in Notes/KoreVM.md: SIZE_OP=7, SIZE_A=8, SIZE_B=8, SIZE_C=9,
//! laid out least-significant-first as A(0..7) C(8..16) B(17..24) OP(25..31).

pub const SIZE_OP: u32 = 7;
pub const SIZE_A: u32 = 8;
pub const SIZE_B: u32 = 8;
pub const SIZE_C: u32 = 9;

pub const POS_A: u32 = 0;
pub const POS_C: u32 = POS_A + SIZE_A; // 8
pub const POS_B: u32 = POS_C + SIZE_C; // 17
pub const POS_OP: u32 = POS_B + SIZE_B; // 25

pub const SIZE_BX: u32 = SIZE_B + SIZE_C; // 17
pub const MAXARG_BX: u32 = (1 << SIZE_BX) - 1;
pub const MAXARG_SBX: i32 = (MAXARG_BX >> 1) as i32;

/// 1 << (SIZE_C - 1). Note B is only 8 bits, so B can never carry the RK bit;
/// that is why the `_BK` opcode variants exist at all.
pub const BITRK: u32 = 1 << (SIZE_C - 1); // 256

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum OpMode {
    ABC,
    ABx,
    AsBx,
}

/// Where an operand's value comes from, for printing.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Arg {
    /// Unused by this opcode.
    N,
    /// A plain register or small integer immediate.
    U,
    /// A register.
    R,
    /// A constant index.
    K,
    /// Register-or-constant: >= BITRK selects K(x - BITRK).
    RK,
}

pub struct OpInfo {
    pub name: &'static str,
    pub mode: OpMode,
    pub b: Arg,
    pub c: Arg,
}

const fn abc(name: &'static str, b: Arg, c: Arg) -> OpInfo {
    OpInfo { name, mode: OpMode::ABC, b, c }
}
const fn abx(name: &'static str, b: Arg) -> OpInfo {
    OpInfo { name, mode: OpMode::ABx, b, c: Arg::N }
}
const fn asbx(name: &'static str) -> OpInfo {
    OpInfo { name, mode: OpMode::AsBx, b: Arg::U, c: Arg::N }
}

use Arg::{K, N, R, RK, U};

/// Indexed by opcode number, 0..=86. Order taken verbatim from KoreVM `lopcodes.h`.
///
/// Operand modes are derived from Lua 5.1 / LuaPlus semantics by name, not read out of
/// `luaP_opmodes`; treat the mode column as [INFERRED] where the raw numbering is [VERIFIED].
/// A wrong mode only mis-labels an operand, it never desynchronises the decode.
pub static OPCODES: [OpInfo; 87] = [
    abc("GETFIELD", R, K),        // 0
    abc("TEST", N, U),            // 1
    abc("CALL_I", U, U),          // 2
    abc("CALL_C", U, U),          // 3
    abc("EQ", RK, RK),            // 4
    abc("EQ_BK", K, RK),          // 5
    abx("GETGLOBAL", K),          // 6
    abc("MOVE", R, N),            // 7
    abc("SELF", R, RK),           // 8
    abc("RETURN", U, N),          // 9
    abc("GETTABLE_S", R, RK),     // 10
    abc("GETTABLE_N", R, RK),     // 11
    abc("GETTABLE", R, RK),       // 12
    abc("LOADBOOL", U, U),        // 13
    abc("TFORLOOP", N, U),        // 14
    abc("SETFIELD", K, RK),       // 15
    abc("SETTABLE_S", RK, RK),    // 16
    abc("SETTABLE_S_BK", K, RK),  // 17
    abc("SETTABLE_N", RK, RK),    // 18
    abc("SETTABLE_N_BK", K, RK),  // 19
    abc("SETTABLE", RK, RK),      // 20
    abc("SETTABLE_BK", K, RK),    // 21
    abc("TAILCALL_I", U, U),      // 22
    abc("TAILCALL_C", U, U),      // 23
    abc("TAILCALL_M", U, U),      // 24
    abx("LOADK", K),              // 25
    abc("LOADNIL", R, N),         // 26
    abx("SETGLOBAL", K),          // 27
    asbx("JMP"),                  // 28
    abc("CALL_M", U, U),          // 29
    abc("CALL", U, U),            // 30
    abc("TAILCALL", U, U),        // 31
    abc("GETUPVAL", U, N),        // 32
    abc("SETUPVAL", U, N),        // 33
    abc("ADD", R, RK),            // 34
    abc("ADD_BK", K, RK),         // 35
    abc("SUB", R, RK),            // 36
    abc("SUB_BK", K, RK),         // 37
    abc("MUL", R, RK),            // 38
    abc("MUL_BK", K, RK),         // 39
    abc("DIV", R, RK),            // 40
    abc("DIV_BK", K, RK),         // 41
    abc("MOD", R, RK),            // 42
    abc("MOD_BK", K, RK),         // 43
    abc("POW", R, RK),            // 44
    abc("POW_BK", K, RK),         // 45
    abc("NEWTABLE", U, U),        // 46
    abc("UNM", R, N),             // 47
    abc("NOT", R, N),             // 48
    abc("LEN", R, N),             // 49
    abc("LT", RK, RK),            // 50
    abc("LT_BK", K, RK),          // 51
    abc("LE", RK, RK),            // 52
    abc("LE_BK", K, RK),          // 53
    abc("CONCAT", R, R),          // 54
    abc("TESTSET", R, U),         // 55
    asbx("FORPREP"),              // 56
    asbx("FORLOOP"),              // 57
    abc("SETLIST", U, U),         // 58
    abc("CLOSE", N, N),           // 59
    abx("CLOSURE", U),            // 60
    abc("VARARG", U, N),          // 61
    abc("TAILCALL_I_R1", U, U),   // 62
    abc("CALL_I_R1", U, U),       // 63
    abc("SETUPVAL_R1", U, N),     // 64
    abc("TEST_R1", N, U),         // 65
    abc("NOT_R1", R, N),          // 66
    abc("GETFIELD_R1", R, K),     // 67
    abc("SETFIELD_R1", K, RK),    // 68
    abc("NEWSTRUCT", U, U),       // 69
    abx("DATA", U),               // 70
    abc("SETSLOTN", U, N),        // 71
    abc("SETSLOTI", U, U),        // 72
    abc("SETSLOT", U, RK),        // 73
    abc("SETSLOTS", U, RK),       // 74
    abc("SETSLOTMT", U, RK),      // 75
    abc("CHECKTYPE", U, U),       // 76
    abc("CHECKTYPES", U, U),      // 77
    abc("GETSLOT", R, U),         // 78
    abc("GETSLOTMT", R, U),       // 79
    abc("SELFSLOT", R, U),        // 80
    abc("SELFSLOTMT", R, U),      // 81
    abc("OPCODE_MAX", U, U),      // 82 - sentinel left in place, not a terminator
    abc("BOR", R, RK),            // 83
    abc("BXOR", R, RK),           // 84
    abc("BSHL", R, RK),           // 85
    abc("BSHR", R, RK),           // 86
];

#[derive(Copy, Clone, Debug)]
pub struct Instruction(pub u32);

impl Instruction {
    #[inline]
    pub fn opcode(self) -> u32 {
        (self.0 >> POS_OP) & ((1 << SIZE_OP) - 1)
    }
    #[inline]
    pub fn a(self) -> u32 {
        (self.0 >> POS_A) & ((1 << SIZE_A) - 1)
    }
    #[inline]
    pub fn b(self) -> u32 {
        (self.0 >> POS_B) & ((1 << SIZE_B) - 1)
    }
    #[inline]
    pub fn c(self) -> u32 {
        (self.0 >> POS_C) & ((1 << SIZE_C) - 1)
    }
    /// Bx is B and C taken together as one 17-bit field.
    #[inline]
    pub fn bx(self) -> u32 {
        (self.0 >> POS_C) & MAXARG_BX
    }
    #[inline]
    pub fn sbx(self) -> i32 {
        self.bx() as i32 - MAXARG_SBX
    }
    pub fn info(self) -> Option<&'static OpInfo> {
        OPCODES.get(self.opcode() as usize)
    }
}

/// True when an RK operand refers to the constant table.
#[inline]
pub fn is_k(x: u32) -> bool {
    x & BITRK != 0
}
#[inline]
pub fn index_k(x: u32) -> u32 {
    x & !BITRK
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn field_layout_round_trips() {
        let raw = (30u32 << POS_OP) | (7 << POS_B) | (300 << POS_C) | 42;
        let i = Instruction(raw);
        assert_eq!(i.opcode(), 30);
        assert_eq!(i.a(), 42);
        assert_eq!(i.b(), 7);
        assert_eq!(i.c(), 300);
    }

    #[test]
    fn bx_covers_b_and_c() {
        let i = Instruction((25u32 << POS_OP) | (0xFF << POS_B) | (0x1FF << POS_C) | 1);
        assert_eq!(i.bx(), MAXARG_BX);
    }

    #[test]
    fn opcode_table_is_complete() {
        assert_eq!(OPCODES.len(), 87);
        assert_eq!(OPCODES[82].name, "OPCODE_MAX");
        assert_eq!(OPCODES[86].name, "BSHR");
    }
}
