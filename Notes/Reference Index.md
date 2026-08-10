---
title: "Reference Index"
description: "Every external source, local artefact and API surface this project depends on, with where to find it"
updated: 2026-08-06
confidence: verified
tags:
  - reference
---

Everything is mirrored locally. The forum is on plain HTTP with a broken certificate and the
key threads are 2013-2015, so **prefer the local mirror**; the web links are for provenance and
for checking whether anything new appeared.

## Local artefacts

| Path | What | Committed |
|---|---|---|
| `work/scripts/` | 803 scripts from `gamescripts.bnk` (debug build, full symbols) | no, regenerate |
| `work/scripts_r/` | 770 scripts from `gamescripts_r.bnk` - **the bank retail mounts** | no |
| `work/guiscripts/` | 157 entries from `guiscripts.bnk`; 22 are plaintext Lua | no |
| `work/decompiled/` | Decompiled corpus. **This is the API documentation** | no |
| `reference/fable3mod/` | 186 forum topics, 86 attachments | yes |
| `reference/injector/source/` | Community injector Lua, readable | yes (bank is not) |
| `mods/injector/MyScript01.lua` | The live mod. Editing this is the whole loop | yes |

Regenerate the corpus:

```bash
pwsh -File tools/bnk-extract.ps1 -Bnk "C:\Games\Fable 3\data\gamescripts_r.bnk" -Out .\work\scripts_r
cargo run --release -p korevm --bin koredec -- --out-dir work/decompiled --root work/scripts_r work/scripts_r/scripts/**/*.lua
```

## The corpus is the API documentation

Every question about an engine call is answered by grepping `work/decompiled/`. This is how
each working channel was found and how each dead one was predicted.

```bash
grep -rhoE "(^|[^A-Za-z0-9_.])Age\.[A-Za-z_]+" work/decompiled/scripts | sort | uniq -c | sort -rn
grep -rhoE 'GUI\.SetCounter\([^)]*\)' work/decompiled/scripts | sort -u
```

## Tools in this repo

| Command | Purpose |
|---|---|
| `koredec` | KoreVM bytecode -> Lua source |
| `koredis` | disassembler, `--opcodes` histogram |
| `bnkinfo` / `bnkpack` | read and write BNK banks |
| `gdbdump` | read GDB object databases, incl. straight out of a bank |
| `tools/syntax-check.py` | Lua 5.1 parse check. **Run before every push** |
| `tools/mod-uninstall.ps1` | restore the install to stock |

## External sources

| Source | Why it matters |
|---|---|
| [fable3mod forums](http://fable3mod.com/forums/) | The primary archive. HTTP only. Mirrored |
| [Improved Script Injector](https://www.nexusmods.com/fableIII/mods/12) | The injection method we use |
| [F3M mod menu](https://www.nexusmods.com/fableIII/mods/38) | External .exe that writes MyScript01.lua, **not** an in-game menu |
| [F3M source](https://github.com/NorbiRobin/F3M) | .exe and README only, no Lua |
| [RandomGamers Fable 3](https://randomgamers.org/?page_id=46) | Confirms the community workflow is ours |
| [PCGamingWiki Fable III](https://www.pcgamingwiki.com/wiki/Fable_III) | Install-level fixes |

**The community never solved in-game text.** Their documented loop is `DisplayMessageBox` plus
Escape. The non-modal HUD channel found here appears to be new ground, so the web is unlikely
to answer UI questions - the corpus is the better source.

## Key people in the archive

- **Artofeel** - injection method, GFWL emu port, the age/`AgeComponent` claim that turned out correct
- **Keshire** - KoreVM opcode tables, `postscriptsloaded` rewrite, `pairs(Debug)` introspection trick
- **BlackDemon** - `BnkBrowser` (BNK format) and `GDB_Dump.cpp` (GDB format), both decompiled/read rather than run

## Related

- [[Hard Lessons]] · [[Lua Scripting]] · [[Formats]] · [[Preservation]]
