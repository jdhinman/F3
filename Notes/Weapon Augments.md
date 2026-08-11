---
title: "Weapon Augments"
description: "How Fable III weapon evolution (conditional augments) works, fully reverse engineered, and how to complete any of it live or by GDB patch"
updated: 2026-08-09
confidence: verified
tags:
  - reference
  - target
---

Fable III weapons evolve by satisfying **conditional augments**: the three coloured gem
tracks on a weapon (e.g. Scattershot's Hard Hitter / Scattergun / Donor). Each track is a
GDB condition record. This note is the complete decode: what every requirement is, and
the only two ways to complete one. All of it is verified in game and against the retail
`Fable3.exe`.

## The data model

Each condition is a GDB object with `ConditionTag` `INV_ITEM_WEAPON_<WEAPON>_CONDITION_<X>`,
an `Augment` pointer (the reward), a `RequiredValue` (or `NumberToKill` / `NumberToHit`),
a `parent`, and inherited `Type` and `ScriptTag` fields. The **Type enum** selects which
augment class the engine builds; the factory at `Fable3.exe` VA `0x1068590` switches on
`Type-1` through a jump table at `0x10688EC`.

Requirement numbers live only in the GDB, not the exe. Field-name lookups use the same
**FNV-1** the whole engine uses (basis `0x811C9DC5`, prime `0x01000193`, case-sensitive;
see [[Formats]]).

## The two, and only two, completion channels  **[VERIFIED by RE]**

The Lua surface that can affect augment progress is exactly:

- `CustomisableWeapon.AddAmountForConditionalAugments(weapon, scriptTag, amount)` -
  increments the augments whose **ScriptTag matches** `scriptTag`. Shipped call sites pass
  real tags (`SHOOTING_RANGE_SCORE`, `HadOrgyWithNumPeople`). This is the engine's
  `ApplyFromScript` path.
- `CustomisableWeapon.DebugSetIsWaitingToLevelUp(weapon, true)` + using the weapon - plays
  the level-up **ceremony** and applies augments **already met**. It cannot invent progress
  for an unmet condition (tested: triggers the animation, evolves nothing). `combatdebug.lua`
  line 597 is the shipped call site.

Everything else that fills a track (kills, gold spent, morality, gifts) is incremented by
**native C++ event hooks** with no Lua entry point. **GDB records are read-only at runtime**
- the `RecordPtrMetatable` in the exe exposes only getters (`GetString`, `GetS32`,
  `GetEnum`, ...), no setter - so a condition's Type or parent cannot be changed in memory.

Consequence, exact: **a condition is live-completable iff it has a ScriptTag (Type 5).**
Any other Type must be satisfied by real gameplay, or converted on disk (below).

## Type taxonomy  **[VERIFIED]** (counts over all named weapon conditions)

| Type | Meaning | Live? |
|---|---|---|
| 1 | Kill N of a creature type (`ExclusiveCreatureTag`, e.g. IsLargeCreature) | no |
| 2 | Spouses | no |
| 3 | Flourish hits (`NumberToHit`) | no |
| 5 | **ScriptControlled** (has `ScriptTag`) | **YES** |
| 6 / 7 | Good / Evil morality threshold | no |
| 10 | Kill chickens | no |
| 12 | Marry | no |
| 13 | Kill/interact children | no |
| 14 | Break crates | no |
| 15 / 16 | Love / Friend interactions | no |
| 18 | Fatness | no |
| 21 | Evil touch expressions | no |
| 22 | Elemental / augment-kills | no |
| 23 | Spend personal gold | no |
| 25 | Quest / ledge / completion | no |
| 26 | Gift to N players (GFWL - dead) | no |
| 27 | Sex (men/women) | no |
| 0xFFFFFFFF | FriendsPlaying (GFWL - dead) | no |

The seven live Type-5 tags in the shipped data: `HadOrgyWithNumPeople`, `CRIMINAL_BROUGHT_IN`,
`SLAVE_BROUGHT_IN`, `JobGold`, `DigSpot`, `SHOOTING_RANGE_SCORE`, `MORTAR_RANGE_SCORE`.

## The cheat, in two moves

1. **One-time GDB pass** - `tools/weapon-unlock.py apply`. For every named weapon leaf
   condition with no ScriptTag, it rewrites `parent` to the ScriptControlled base
   `0xD13B9689`, sets `RequiredValue`/`NumberToKill`/`NumberToHit` to 0, and forces any own
   `Type` field to 5. All three `globals.gdb` copies (base + Understone + Traitor's Keep;
   the game loads the newest DLC's, which is why the 2014 forum offsets were "for latest
   DLC"). ~1000 dword writes, in place, no repack. Writes an undo log; `revert` restores
   exactly. **GDB loads once at startup, so this needs one quit/relaunch - the last one.**
2. **Then, forever, live** - in the injector menu, "Complete ALL augments on held weapons"
   fires `AddAmountForConditionalAugments(weapon, "", 1000000)`. The empty tag matches every
   reparented condition (empty string hashes to the FNV basis on both sides); requirement 0
   means it completes immediately. Sheathe/redraw or fire to play the ceremony per tier.

Weapons that were already Type-5 (orgy, dig, shooting range, criminals, slaves, jobs, mortar)
never needed the pass - they complete live with their own tag.

## Provenance / partial history

Scattershot was the first solved, the long way: patch its three requirements to 0
(`tools/augment-patch.py`), reparent Scattergun+Donor to ScriptControlled, empty-tag tick.
Hard Hitter completed on a single real flourish; all three evolved. The Perforator repeated
it (Spending done by hand, Orgy+Evil via the same reparent). `weapon-unlock.py` generalises
that to every weapon so it never has to be done per weapon again.

## Related

- [[Formats]] (GDB, FNV-1) - [[Lua Scripting]] - [[Hard Lessons]] - [[Reference Index]]
