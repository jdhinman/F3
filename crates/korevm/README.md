# korevm

Reader and disassembler for Fable III's KoreVM Lua bytecode. Format spec: `Notes/KoreVM.md`.

## Use

```bash
cargo build --release
```

`koredec` decompiles to Lua source; `koredis` disassembles.

```bash
target/release/koredec work/scripts/scripts/ai/aibase.lua
```

```bash
target/release/koredis work/scripts/scripts/ai/aibase.lua
```

`koredec`:
- `--out-dir <dir>` writes one file per input; add `--root <dir>` to keep the input tree's
  layout instead of flattening it.
- `--summary` prints one line per file with its note count. A note is a construct the
  decompiler could not recover; clean means none.

`koredis`:
- `--summary` prints one line per file (protos, instructions, bytes left over, source path).
  Trailing bytes must be 0; anything else means the layout is wrong for that chunk.
- `--brief` suppresses the constant, local and upvalue dumps.
- `--opcodes` prints an opcode-frequency histogram over the files given.

Get the corpus first:

```bash
pwsh -File tools/bnk-extract.ps1 -Bnk "C:\Games\Fable 3\data\gamescripts.bnk" -Out .\work\scripts
```

## Layout

- `opcodes.rs` - instruction encoding and the 87-entry opcode table.
- `chunk.rs` - header and proto reader for chunk format 2.
- `disasm.rs` - `luac -l -l` style listing.
- `ast.rs` - Lua syntax tree and pretty printer.
- `decompile.rs` - lowering, expression rebuild, control-flow structuring.
- `bin/koredis.rs`, `bin/koredec.rs` - the two CLIs.

Every size field is checked against the bytes remaining before it is used to allocate, so a
misparse fails at the field that caused it instead of trying to reserve gigabytes.

## Validating the output

Two checks, both reproducible:

```bash
python tools/syntax-check.py work/decompiled
```

parses every emitted file with a real Lua 5.1 parser (`lupa.lua51` -> `loadstring`), which
catches structural mistakes that reading the output does not.

```bash
python tools/ground-truth.py work/scripts/scripts/quests/scriptactivation.txt work/decompiled/scripts/quests/scriptactivation.lua
```

compares against original source, for the handful of scripts Fable III shipped as plaintext
next to their compiled form.

## Confidence

The encoding, the opcode numbering and the chunk layout are [VERIFIED] against the corpus:
all 797 compiled chunks parse to their exact byte length with zero leftovers, and no
instruction in 966,899 decodes to an opcode outside 0..=86.

Per-opcode *operand modes* (which operand is a register, a constant, or RK) are [INFERRED]
from Lua 5.1 and LuaPlus semantics by name, not read out of `luaP_opmodes`. A wrong mode
mislabels an operand in the listing; it cannot desynchronise the decode, because every
instruction is a fixed 4 bytes.

Decompiler output is [VERIFIED] to the extent stated and no further: **797 of 797 files emit
valid Lua 5.1**, and **745 of 797 come back with nothing unrecovered**. The remaining 52 carry
135 notes between them, each marking one construct at one pc. Validity is machine-checked;
*semantic* equivalence is only directly confirmed on the one file that ships as both source
and bytecode, where the token multisets match exactly.

A note in the output is a defect the decompiler is admitting to. Silence is not proof of
correctness, but a note is proof of a gap.
