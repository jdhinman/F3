---
title: "Open Questions"
description: "The work queue, ordered by what unblocks the most"
updated: 2026-08-06
confidence: verified
tags:
  - moc
---

Answered questions move out of this note and into the note that owns them.

## 1. What are the real character record names?

The only thing between here and a working child-growth mod. `Age.SetAge` past ~18 already
flips an NPC to adult and the AI follows; the body needs
`GraphicAppearanceMorph.SetCharacterRecord` with a name that actually exists.

- `crates/gdb` reads `globals.gdb` out of `levels.bnk`. Searching object *names* for creature
  types found nothing.
- Next: search the **label table**, and locate the dog-breed records that
  `oncarriedactionusebonuseffects.lua` passes to the same call. Those are known-good record
  names; find them in the GDB and the object shape they belong to is the search target.
- Capture the original record via `IsUsingCharacterRecordWithName` before any swap.

→ [[Child System]]

## 2. Does `Debug.CreateInstantFamily()` work in retail?

Confirmed present. If it builds a real hero family on demand, the child mod can be developed
without playing to marriage. Untried, and it writes to save state, so test on a throwaway save.

## 3. Do the age changes persist across save and load?

Never tested. Determines whether the mod must reapply on load, which the per-frame worker can
do trivially.

## 4. Why does our own injector bank hang the game?

The community bank works; ours hangs. Ruled out: script content, index framing,
`ScriptCode.DEMO001`, quest loading. The remaining difference was the zlib compression level
(`78 9C` vs `78 DA`), now fixed but never retested. Low priority - the community bank works and
mod logic lives in the loose file.

## 5. Can we ship fixes for Lionhead's own bugs?

5 sites compare against `EAgeGroup.EAGE_CHILD`, which does not exist. One makes a branch of
child home behaviour dead in every copy of the game. Live function replacement is Lionhead's
own `WatchDog` pattern, so this is buildable now and would be the first bugfix mod for F3.

## 6. Citizen AI and lifesim via the 39 group minds

The original priority-3 goal, untouched. AI files trigger `Debug.ReloadAI` on change.

## Related

- [[Child System]] · [[Hard Lessons]] · [[Reference Index]] · [[Lua Scripting]]
