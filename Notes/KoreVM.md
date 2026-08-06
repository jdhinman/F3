---
title: "KoreVM"
description: "Fable III's Lua VM, identified and specified: a LuaPlus derivative with 87 opcodes and a 7-bit opcode field"
updated: 2026-08-05
confidence: verified
tags:
  - finding
  - format
  - scripting
---

> [!success] The thing the community said it needed
> From the fable3mod "Lua decompiler?" thread: *"We have a disassembler, but there's still a few
> quirks that need to be ironed out before someone can take that and turn it into a decompiler.
> Plus we need someone that's capable of that."*
>
> **This note is those quirks, written down.** The encoding is fully specified below, the opcode
> table is complete and indexed, and the VM is identified by lineage rather than treated as a
> mystery.

**[VERIFIED]** by reading `lopcodes.h` / `lopcodes.c` (Keshire's KoreVM opcode set) and
cross-checking every value against `ChunkSpy_KVM.lua`'s own working configuration. Both are
[[Preservation|captured from the forum]] and extracted under
`reference/fable3mod/extracted/`.

## What KoreVM actually is

Not "rearranged Lua". **A LuaPlus derivative.** The tell is the opcode set:

| Opcode family | What it means |
|---|---|
| `OP_NEWSTRUCT`, `OP_SETSLOT{,N,I,S,MT}`, `OP_GETSLOT{,MT}`, `OP_SELFSLOT{,MT}`, `OP_CHECKTYPE{,S}` | **LuaPlus structs** - typed slot-based objects, not in stock Lua |
| `OP_BOR`, `OP_BXOR`, `OP_BSHL`, `OP_BSHR` | bitwise operators, absent from Lua 5.1 |
| `_BK` suffix (`OP_ADD_BK`, `OP_EQ_BK`, `OP_SETTABLE_BK`...) | operand **B is a constant**, specialised to skip an RK decode |
| `_S` / `_N` (`OP_GETTABLE_S`, `OP_SETTABLE_N`...) | table access specialised by **string** or **number** key |
| `_I` / `_C` / `_M` (`OP_CALL_I`, `OP_CALL_C`, `OP_CALL_M`) | call specialised by callee kind |
| `_R1` (`OP_CALL_I_R1`, `OP_GETFIELD_R1`...) | single-return-register fast paths |

**This matters enormously.** LuaPlus is open source, so the reference semantics for every one of
these exist and do not need reverse engineering. The specialised forms all *lower* to a handful of
core operations, which makes a decompiler's job much smaller than 87 opcodes suggests.

The base is still Lua 5.1: signature `\27Lua`, version byte `0x51`.

## Instruction encoding  **[VERIFIED]**

This is the part that breaks every stock Lua tool, and it is only four numbers.

| Field | KoreVM | Stock Lua 5.1 |
|---|---|---|
| `SIZE_OP` | **7** | 6 |
| `SIZE_A` | 8 | 8 |
| `SIZE_B` | **8** | 9 |
| `SIZE_C` | 9 | 9 |

Field order, least significant first: **`A` (0-7), `C` (8-16), `B` (17-24), `OP` (25-31)**.
`Bx` = `B`+`C` = 17 bits. `BITRK` = `1 << (SIZE_C - 1)` = **256**.

```
 31                    25 24            17 16          8 7          0
+------------------------+----------------+-------------+------------+
|         OP (7)         |      B (8)     |    C (9)    |   A (8)    |
+------------------------+----------------+-------------+------------+
```

A 7-bit opcode field allows 128 opcodes; 87 are defined. Stock Lua's 6-bit field allows 64, which is
why the opcode set could not simply be extended in place - and why a vanilla `luac`/decompiler
mis-decodes every single instruction rather than failing loudly.

## The opcode table, complete and indexed  **[VERIFIED]**

| # | Opcode | # | Opcode | # | Opcode |
|---|---|---|---|---|---|
| 0 | `GETFIELD` | 29 | `CALL_M` | 58 | `SETLIST` |
| 1 | `TEST` | 30 | `CALL` | 59 | `CLOSE` |
| 2 | `CALL_I` | 31 | `TAILCALL` | 60 | `CLOSURE` |
| 3 | `CALL_C` | 32 | `GETUPVAL` | 61 | `VARARG` |
| 4 | `EQ` | 33 | `SETUPVAL` | 62 | `TAILCALL_I_R1` |
| 5 | `EQ_BK` | 34 | `ADD` | 63 | `CALL_I_R1` |
| 6 | `GETGLOBAL` | 35 | `ADD_BK` | 64 | `SETUPVAL_R1` |
| 7 | `MOVE` | 36 | `SUB` | 65 | `TEST_R1` |
| 8 | `SELF` | 37 | `SUB_BK` | 66 | `NOT_R1` |
| 9 | `RETURN` | 38 | `MUL` | 67 | `GETFIELD_R1` |
| 10 | `GETTABLE_S` | 39 | `MUL_BK` | 68 | `SETFIELD_R1` |
| 11 | `GETTABLE_N` | 40 | `DIV` | 69 | `NEWSTRUCT` |
| 12 | `GETTABLE` | 41 | `DIV_BK` | 70 | `DATA` |
| 13 | `LOADBOOL` | 42 | `MOD` | 71 | `SETSLOTN` |
| 14 | `TFORLOOP` | 43 | `MOD_BK` | 72 | `SETSLOTI` |
| 15 | `SETFIELD` | 44 | `POW` | 73 | `SETSLOT` |
| 16 | `SETTABLE_S` | 45 | `POW_BK` | 74 | `SETSLOTS` |
| 17 | `SETTABLE_S_BK` | 46 | `NEWTABLE` | 75 | `SETSLOTMT` |
| 18 | `SETTABLE_N` | 47 | `UNM` | 76 | `CHECKTYPE` |
| 19 | `SETTABLE_N_BK` | 48 | `NOT` | 77 | `CHECKTYPES` |
| 20 | `SETTABLE` | 49 | `LEN` | 78 | `GETSLOT` |
| 21 | `SETTABLE_BK` | 50 | `LT` | 79 | `GETSLOTMT` |
| 22 | `TAILCALL_I` | 51 | `LT_BK` | 80 | `SELFSLOT` |
| 23 | `TAILCALL_C` | 52 | `LE` | 81 | `SELFSLOTMT` |
| 24 | `TAILCALL_M` | 53 | `LE_BK` | 82 | `OPCODE_MAX` |
| 25 | `LOADK` | 54 | `CONCAT` | 83 | `BOR` |
| 26 | `LOADNIL` | 55 | `TESTSET` | 84 | `BXOR` |
| 27 | `SETGLOBAL` | 56 | `FORPREP` | 85 | `BSHL` |
| 28 | `JMP` | 57 | `FORLOOP` | 86 | `BSHR` |

Note `82 = OP_OPCODE_MAX` sits **inside** the range with four bitwise ops after it, so it is a
sentinel left in place rather than a real terminator. Do not treat 82 as the opcode count.

`lopcodes.c` carries the matching `luaP_opnames` table and `luaP_opmodes`, built with
`opmode(t,a,b,c,m) = ((t)<<7) | ((a)<<6) | ((b)<<4) | ((c)<<2) | (m)` - note the **`<<7`**, widened
from stock Lua's `<<6` to match the 7-bit opcode.

## Why the existing decompiler falls short, and what a real one needs

Keshire's [[Prior Art|Fable3LUADecompiler]] (MIT, forked into `third_party/`) was adapted from a Call
of Duty decompiler. Its own README: good at *"rebuilding widgets and menus"*, poor at *"decompiling
big blocks of code used for functionality"*, and *"condition/loop detection could be improved."*

That diagnosis is a **control-flow reconstruction** problem, not a decoding problem. Decoding is
solved by the four numbers above. What is missing is the standard decompiler back end:

1. **Lower the specialised opcodes.** `GETFIELD`, `GETTABLE_S/N`, `GETFIELD_R1` all become
   `R(A) := R(B)[k]`. Collapsing the 87 down to roughly Lua 5.1's 38 core operations first makes
   everything after it simpler.
2. **Build a CFG** from `JMP`, the comparison-then-`JMP` idiom, `TEST`/`TESTSET`, `FORPREP`/`FORLOOP`
   and `TFORLOOP`.
3. **Structure it** - reduce the CFG into `if`/`else`, `while`, numeric `for`, generic `for`,
   `repeat`, and short-circuit `and`/`or` from the `TESTSET` pattern.
4. **Rebuild expressions** by symbolic execution over registers, so temporaries collapse back into
   nested expressions.
5. **Name things** from the debug data, where present - see below.

None of that is novel research. It is the well-trodden path taken by `unluac`, `luadec` and every
Lua decompiler, applied to a documented instruction set.

## Chunk header: two more deviations, found by measurement  **[VERIFIED]**

`lopcodes.h` specifies the *instruction* encoding. The **chunk header** deviates too, and neither
deviation appears in any forum post found so far. Read directly from the inflated bank:

```
1B 4C 75 61 51 02 01 04 04 04 04 00
 \27 L  u  a  |  |  |  |  |  |  |  +-- integral flag = 0
              |  |  |  |  |  |  +----- sizeof(lua_Number) = 4   <-- stock Lua 5.1: 8
              |  |  |  |  |  +-------- sizeof(Instruction) = 4
              |  |  |  |  +----------- sizeof(size_t)      = 4
              |  |  |  +-------------- sizeof(int)         = 4
              |  |  +----------------- endianness = 1 (little)
              |  +-------------------- format version = 2       <-- stock Lua 5.1: 0
              +----------------------- version = 0x51 (Lua 5.1)
```

| Field | KoreVM | Stock Lua 5.1 |
|---|---|---|
| format version | **2** | 0 |
| `sizeof(lua_Number)` | **4** (single-precision float) | 8 (double) |

**Both break stock tooling independently of the opcode changes.** A loader that assumes format 0
rejects the chunk; one that assumes 8-byte doubles mis-reads every numeric constant and desynchronises
from there. Any decompiler must read numbers as **4-byte floats**.

### What `format = 2` changes  **[VERIFIED]** - solved 2026-08-05

**Format 2 inserts one extra string, `funcname`, immediately after `source`.** That is the entire
difference. From `ChunkSpy_KVM.lua`'s proto reader:

```lua
func.source   = LoadString()
func.funcname = LoadString()    -- not present in stock Lua 5.1
func.linedefined = LoadInt()
```

**Proto layout, KoreVM format 2:**

```
string   source
string   funcname            <-- the only structural addition
int      linedefined
int      lastlinedefined
byte     nups
byte     numparams
byte     is_vararg
byte     maxstacksize
         code, constants, protos, lineinfo, locvars, upvalues   (Lua 5.1 order, unchanged)
```

Verified by re-parsing the first chunk of `gamescripts.bnk.dat` with this layout. Every field lands
on a sane value, which a wrong layout does not do:

| Field | Value |
|---|---|
| `source` | `d:\Pulse\work\f3-daily-build-PC\Deploy\Fable2_win32\data\scripts\AI\AIBase.lua` |
| **`funcname`** | **`(main chunk)`** |
| `linedefined` / `lastlinedefined` | 0 / 0 |
| `nups`, `numparams` | 0, 0 |
| `is_vararg` | 2 (`VARARG_ISVARARG`) |
| `maxstacksize` | 20 |
| `sizecode` | 467 instructions |

`(main chunk)` is Lua's own name for a top-level function, and `linedefined = 0` with
`is_vararg = 2` is exactly right for one. The layout is correct.

This was the misparse behind the earlier garbage read: what looked like `linedefined = 13` was the
**length prefix of the `funcname` string**, and everything after it was shifted.

> [!success] The specification is now complete
> Four deviations, all verified: the 7-bit opcode field with A/C/B/OP ordering, the 87-opcode
> LuaPlus-derived instruction set, `format = 2` adding `funcname`, and 4-byte floats for
> `lua_Number`. Nothing about the container or the encoding remains unknown. What is left is
> **writing the decompiler back end**, which is ordinary work.

## The debug-data advantage, now confirmed  **[VERIFIED]** 2026-08-05

> [!success] The debug build ships, and it is decisive
> The hypothesis was that `gamescripts.bnk` retains compiler debug data while `gamescripts_r.bnk` is
> stripped. **Tested and confirmed.**

Both banks are a **single zlib stream** (`78 DA`) wrapping concatenated Lua chunks. Inflating each
and inspecting the first chunk:

| | `gamescripts.bnk.dat` | `gamescripts_r.bnk.dat` |
|---|---|---|
| chunk header | identical (`fmt=2`, `Number=4`) | identical |
| top-level `source` string | **present, 79 chars** | **length 0, absent** |
| build-path strings in first ~114 KB inflated | **122** | **0** |

The recovered source path:

```
d:\Pulse\work\f3-daily-build-PC\Deploy\Fable2_win32\data\scripts\AI\AIBase.lua
```

**What this means for the decompiler.** `source` is exactly what `luac -s` removes, alongside line
numbers and local variable names. Its presence means the non-stripped bank should also carry
`lineinfo`, `locvars` and `upvalue` names. A decompiler targeting `gamescripts.bnk` therefore emits
**named locals and real line numbers**, not `local_1`-style algebra - which is the difference between
readable source and a puzzle, and it removes the hardest part of the job before it starts.

**Work from `gamescripts.bnk`, never `gamescripts_r.bnk`.**

> [!note] A build-system fossil
> `d:\Pulse\work\f3-daily-build-PC\Deploy\**Fable2_win32**\` - Lionhead's build machine, their "Pulse"
> build system, and a Fable **2** directory inside a Fable **3** daily build. Fable 3 was built on the
> Fable 2 codebase, which independently supports [[Lua Scripting|using Fable 2's decompilable scripts
> as a Rosetta stone]].
>
> Compare Anniversary shipping its own studio database credentials. Both games leaked their build
> environment into retail.

## The debug-data advantage nobody has exploited

Stripped scripts (`_r`) lose line numbers and local variable names. From the same thread:
*"There shouldn't be a difference between the script and script_r other than one contains compiler
debug information. Which is REALLY helpful as it contains line information and local variables."*

**This install ships both banks**, and the non-`_r` one is 1.37 MB larger.
→ [[Formats|the install census]]

**[INFERRED]** decompiling `gamescripts.bnk` rather than `gamescripts_r.bnk` should produce output
with real local names and line numbers, which is the difference between readable source and algebra.
**Test this before writing any decompiler code** - it may change what the decompiler needs to do.

## Two shortcuts worth taking first

**Fable 2 as a Rosetta stone.** Fable 2 does not use KoreVM and has a working decompiler, and
*"a lot of the scripts are the same between the two games."* Reading F2's readable source next to
F3's disassembly gives ground truth for free.

**Plaintext survivors.** *"They actually put plaintext, uncompiled lua in copies of certain files.
Like `scriptactivation.lua`."* Every such file is a worked example of compiled-versus-source.

## Related

- [[Lua Scripting]] · [[Formats]] · [[Prior Art]] · [[Preservation]] · [[Open Questions]]
