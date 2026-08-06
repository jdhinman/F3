---
title: "Script Corpus"
description: "The 803 extracted game scripts, what the AI and lifesim architecture looks like, and where to modify it"
updated: 2026-08-05
confidence: verified
tags:
  - finding
  - scripting
  - ai
---

> [!success] The whole game's script corpus is extracted
> **803 of 803 files, 0 failures, 16.3 MB**, using [[Formats|the recovered BNK format]]. 797 are
> `.lua`. A 400-file sample was 400/400 valid Lua chunks with 367 carrying `source` strings, so
> **the debug symbols survive**. → [[KoreVM]]

Everything below is **[VERIFIED]** from the extracted tree, not from forum posts.

## Shape of the corpus

| Folder | Files | What lives there |
|---|---|---|
| `ai` | **278** | behaviours, group minds, combat styles and states |
| `miscellaneous` | 258 | enums, managers, shared systems |
| `quests` | 176 | quest logic, including the largest files in the game |
| `gameface` | 33 | UI |
| `camera` | 23 | camera modes |
| `startup` | 20 | boot, including E3 and GDC demo startups |
| `worldmap` | 15 | the sanctuary world map, family display |

The `ai` subtree breaks down as **165 behaviours**, 57 at the root (managers and group minds),
20 combat styles, 15 combat sequences, 13 combat states, 8 combat group minds.

Largest single scripts are quests: `miscfunctions.lua` (392 KB), `qc010_opening.lua` (313 KB),
`questmanager.lua` (245 KB).

## The lifesim architecture

Fable III runs NPC life through **"group minds"** - per-location coordinators that recruit nearby
NPCs and assign them behaviours. There are **39** of them:

**Places and livelihoods:** `VillageGroupMind`, `HomeGroupMind`, `ShopGroupMind`, `StallGroupMind`,
`BarGroupMind`, `BarmanJobGroupMind`, `FarmGroupMind`, `FactoryGroupMind`, `CoachHouseGroupMind`,
`GypsyCampGroupMind`, `CampGroupMind`, `BenchGroupMind`, `OrphanageGroupMind`, `PrisonCellGroupMind`,
`MonkGroupMind`, `BardGroupMind`

**Social:** `ConversationGroupMind`, `CommotionConversationGroupMind`, `VillagerDanceGroupMind`,
`FamilyDivorceGroupMind`, `FollowGroupMind`, `PairedGroupMind`, `TagGroupMind`, `DuelingGroupMind`,
`LarpGroupMind`, `CrateCarryingGroupMind`

**Combat and factions:** `CombatGroupMind` plus per-faction variants (bandit, beetle, highwayman,
hobbe, hollow men, wolf), `GuardGroupMind`, `LuciensGuardGroupMind`, `ThugGroupMind`,
`CultistGroupMind`, `MortarGroupMind`

**This is the layer to modify for citizen AI.** A group mind decides *who does what where*; the
behaviours under `ai/behaviours/` decide *how*. Both are plain Lua we now hold.

Supporting managers at `ai/` root include `aibase.lua` (117 KB), `aimanager.lua` (96 KB),
`groupmindmanager.lua`, and `behaviourgrouppreparetoruns.lua`.

## Economy and town simulation

The economy surface is thinner than the social one but real: `ShopGroupMind`, `StallGroupMind`,
`BehaviourShopBase` (with an `AreShopsOff` switch), `BehaviourBarmanOpenShopUI`, the job system
(`JobCoordinator`, `JobCommonScript`, `JobBlacksmithManager`, `JobLuteHeroManager`,
`BehaviourBarmanJob`, `BehaviourFarmer`), and `miscellaneous` enums for town demand, shop types,
treasury, property and rent.

**[UNKNOWN]** how much of the economy is Lua versus native. The enums are Lua; whether the demand and
pricing *simulation* is scripted or engine-side has not been checked. **Read
`miscellaneous/towndemandenums.lua` and the shop group mind before assuming either way.**

## Family and children

Already surveyed in [[Child System]]. The extracted tree confirms it: `behaviourparentchildinteraction`,
`behaviourchildlabour`, `behaviourspouse` (post-childbirth, honeymoon, `GetLineAboutChild`),
`familydivorcegroupmind`, `orphanagegroupmind`, `worldmap/family.lua`, plus the quests
`qu080_childbirthics` and `qu090_childgrownics`.

## What to do with this

1. **Decompile it.** The corpus is compiled KoreVM with symbols. [[KoreVM|The spec is complete]];
   the decompiler back end is the remaining work.
2. **Read the enums first.** `miscellaneous/` holds ~258 files, many of them plain enum tables that
   may decompile trivially even with an imperfect decompiler, and they name everything else.
3. **Modify by injection, not by repacking.** [[Lua Scripting|The injector]] loads plain-text Lua from
   `data\scripts\`, so behaviour can be replaced without rebuilding a bank.

> [!note] Decompiling is for *reading*, not for shipping
> New code goes in as plain-text Lua. The decompiler exists so we can understand what to override,
> which is a research tool rather than part of the mod pipeline.

## Related

- [[Formats]] · [[KoreVM]] · [[Lua Scripting]] · [[Child System]] · [[Preservation]]
