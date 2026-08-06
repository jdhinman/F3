# Fable III - modding research & toolchain

**Goal: extend Fable III's family and child systems, on a platform that actually lets us run code.**

An **Obsidian vault** and toolchain, in the same shape as the
[Fable Anniversary project](https://github.com/jdhinman/fa): research notes with explicit confidence
markers, tools that verify their own claims against a real install, and a composability layer so mods
stack instead of overwriting each other.

## Why Fable III rather than Anniversary

The Anniversary project reached a hard ceiling: there is no supported way to run new code. Its
UnrealScript compiler ships but crashes when a mod package is declared, and the only working route is
native DLL injection against hard-coded addresses. Fable III does not have that problem.

| | Fable Anniversary | Fable III |
|---|---|---|
| Run our own code | unsolved | **Lua, hot-reloadable, no relaunch** |
| Iteration loop | rebuild, relaunch, hope | **edit file, see it live** |
| Children | **no such system** | baby to child, then stops |
| Data store | `game.bin` (decoded by that project) | `globals.gdb` (partly understood) |

## The target

Fable III children grow **once** - baby to child - and then stop permanently. They never reach
adulthood. That is a long-standing complaint rather than an obscure gap, and the age field has
already been located by the community in `globals.gdb`'s `AgeComponent`.

So the goal is **completing a progression that already exists and already has a known field**, not
inventing a life simulation from nothing.

## Layout

| Path | What |
|---|---|
| `Home.md` | Vault entry point |
| `Atlas/` | Maps of content and open questions |
| `Notes/` | Atomic notes - one format, finding or concept each |
| `reference/` | Captured third-party material, mirrored for preservation |
| `tools/` | Our scripts |

## Trust model

Inherited from the Anniversary project, because it earned its keep there - six confidently wrong
conclusions were caught by it.

| Marker | Means |
|---|---|
| **[VERIFIED]** | Observed directly on this machine, by reading the actual bytes |
| **[DOCUMENTED]** | Stated by community sources, not independently confirmed |
| **[INFERRED]** | Reasoned from evidence - a hypothesis to test |
| **[UNKNOWN]** | Open question, recorded so it isn't mistaken for settled |

> [!warning] Nothing here is [VERIFIED] yet
> The game is still installing. Every claim currently in this vault is **[DOCUMENTED]** from web
> research and must be checked against the real install before it is trusted.

## Status

Started 2026-08-05. Game not yet installed, no local verification performed.
