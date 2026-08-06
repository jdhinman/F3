# korevm

Reader and disassembler for Fable III's KoreVM Lua bytecode. Format spec: `Notes/KoreVM.md`.

## Use

```bash
cargo build --release
```

```bash
target/release/koredis work/scripts/scripts/ai/aibase.lua
```

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
- `bin/koredis.rs` - the CLI.

Every size field is checked against the bytes remaining before it is used to allocate, so a
misparse fails at the field that caused it instead of trying to reserve gigabytes.

## Confidence

The encoding, the opcode numbering and the chunk layout are [VERIFIED] against the corpus:
all 797 compiled chunks parse to their exact byte length with zero leftovers, and no
instruction in 966,899 decodes to an opcode outside 0..=86.

Per-opcode *operand modes* (which operand is a register, a constant, or RK) are [INFERRED]
from Lua 5.1 and LuaPlus semantics by name, not read out of `luaP_opmodes`. A wrong mode
mislabels an operand in the listing; it cannot desynchronise the decode, because every
instruction is a fixed 4 bytes.
