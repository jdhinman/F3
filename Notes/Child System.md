---
title: "Child System"
description: "What Fable III's children do, where the age data reportedly lives, and what growing them up would actually require"
updated: 2026-08-05
confidence: documented
tags:
  - target
  - gameplay
---

The project's target feature. **[DOCUMENTED] only** - nothing verified against the install yet.

## What the game does today

Fable III lets the hero marry and have children. A child is born as a baby and grows **once**, into a
child. Then it stops, permanently. There is no adulthood, no continued ageing, and no generational
play.

This is a well-known complaint rather than an obscure gap, which matters for two reasons: there is
demonstrated player demand, and there is a decent chance someone has already tried, so
[[Prior Art|check before building]].

## Where the data reportedly lives

Community reports point at `globals.gdb`:

- an **`AgeComponent`** on the child entity
- a quoted "main children offset" of **`101BF01F`**
- the described fix is to set Age above **18**
- a hex-editor route is offered as an alternative to the GDB editor

**[UNKNOWN]** whether that offset is stable across game versions, and whether "Age > 18" is a
threshold the engine actually branches on or just a number someone changed.

## The hard question nobody has answered

**Does raising the age value produce a functioning adult, or a broken child?**

An NPC is not just an age number. Growing one up plausibly needs all of:

| Concern | Why it might break |
|---|---|
| Mesh and skeleton | child and adult bodies are different assets; scaling a child is not an adult |
| Animation set | child animation may not exist for adult actions, and vice versa |
| Dialogue and voice | children have their own lines; an adult using them reads as broken |
| AI and schedules | village-member behaviour may be gated on being an adult |
| Save compatibility | an entity changing category mid-save is a classic corruption source |

**Assume the naive edit produces something visibly wrong.** The interesting work is what happens
after that, and the honest first milestone is *finding out precisely how it breaks*.

## Two routes, and they are complementary

**Data route - `globals.gdb`.** Change the age or the growth definition directly. Static, applies at
load, no runtime code. Simplest to try, easiest to get wrong silently.

**Script route - Lua.** [[Prior Art|Scripts run on a schedule and hot-reload]], so a script could
observe a child entity, drive a transition, or swap what the data route cannot express. Far more
capable, and the reason this platform was chosen over Anniversary.

The likely answer is both: data defines what an adult child *is*, script drives the transition and
patches up whatever the data model cannot say.

## First milestones, in order

1. **Find a child entity in a real save or level** and read what the game actually stores about it.
2. **Establish the Lua API surface** - what can a script see and call? Without this the script route
   is speculation.
3. **Change the age by the documented route** and observe, in game, exactly what breaks.
4. Only then decide whether "grow up" means a category change, an asset swap, or a new entity.

## Related

- [[Prior Art]] · [[Open Questions]]
