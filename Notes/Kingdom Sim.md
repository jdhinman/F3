---
title: "Kingdom Sim"
description: "Design research for a ruling-phase overhaul: the problem, the reachable substrate, and the evidence that town wealth is a real simulation variable"
updated: 2026-08-10
confidence: documented
tags:
  - design
  - target
---

Candidate flagship mod. **Not built.** This is the research that says it is worth building
and that it is reachable.

## The problem is the game's biggest broken promise

Kingdom management was Fable III's headline marketing claim, and it is the most-criticised
part of the shipped game. From contemporary criticism:

- *"you only play around four days of an entire year after you become king"*
- *"the only options for issuing a national tax policy are High, Low, or The Same. You can
  only set it once, right at the beginning"*
- ruling is *"widely criticised as one of the game's most disappointing aspects, failing to
  deliver on the promised depth of kingdom management that was heavily marketed"*

Mechanically it is one number (the treasury) and a countdown. Ten binary decisions, each
"good but costs gold" versus "evil but profits", then the act ends. Villages never visibly
respond, and there is nothing to *do* as king between decisions.

**Nothing in the scene addresses it.** The published mods are ReShade presets, a DXVK/perf
bundle, house-management automation, and augment reworks. → [[Prior Art]]

## Town wealth is a real simulation variable  **[VERIFIED from data]**

The important question was whether village state is a live simulation or a cosmetic number.
It is live. From `globals.gdb`:

- **Scale is a float, -100 to +100**, with most content banded at ±20
  (`MinTownWealthLevel` / `MaxTownWealthLevel`).
- **Gift tables are gated by it**: records carrying `MinTownWealthLevel` sit under a
  `GiftItem` parent, so what villagers give and receive changes with town wealth.
- **Money scales with it**: `DefaultMoneyAtMaxTownWealth` appears at 24,000 / 60,000 /
  700,000 on different records - villagers and shops carry more when the town is rich.
- **Decoration feeds back into it**: `DecorationToWealthMultiplier` (0.005),
  `MaxDecorationWealthChangeLimit` (20), `GiftValueToWealthMultiplier` (0.005).
- **Villagers talk about it**: `TEXT_AI_GOSSIP_TOWN_WEALTH_LOW/MEDIUM/VERYHIGH_CONV` and
  `TEXT_AI_SHOP_WEALTH_VERYLOW/MEDIUM/VERYHIGH` are voiced, banded lines.

So writing a village's wealth produces audible and economic change, not a hidden stat.
**[UNKNOWN]** whether it also changes anything *visual* (building condition, dress, props).
That is one five-minute in-game test: set a village to +100, walk around.

## The reachable substrate

| System | Calls | What it gives |
|---|---|---|
| `Treasury` | `Get/Add/Remove/AddSilent/RemoveSilent/Show/Hide` | the royal purse, readable and writable |
| `Village` | `SetWealthIndex`, `AdjustWealthIndex`, `SetShopsCanOpen`, `SetHasSheriff`, `SetRespawnGuards`, `GetNumberOfGuardsDesired`, `GetListOfVillagersWithoutHomes`, `GetDeadVillagerList`, `SetVillageFamiliarityWithHero` | per-town live state |
| `Stats` | `StoreJudgementDecision(hero, name, bool)`, `GetJudgementDecision`, `HasJudgementDecision` | **arbitrary named decisions, persisted in the save** |
| `VillageCrimeManager` | 29 functions | crime and fines per town |
| `JobCoordinator` | 51 functions | jobs, and the shipped ruling selection logic |
| `EconomyManager` | `Get/Set/AdjustVillageWealth` | the economy behind the wealth index |

Villages are found the way the shipped code does it, using the `SearchTools` API learned
from the Automatic Houses mod:

```lua
local s = SearchTools.FilterWithEC(SearchTools.StartNewSearch("marker"), Village.GetECType())
for _, village in pairs(SearchTools.GetSearchResults(s)) do
    Village.AdjustWealthIndex(village, delta, false, true)
end
```

The judgement store is the quiet win: the name is an arbitrary string, so **our own
decisions persist in the save for free**, with no new save format work.

## Shape of the mod

Invert what the shipped game does. Decisions stop being a treasury counter and become
*policies applied to places*, with consequences you can see and that generate more decisions.

1. **Decisions land on towns.** Approving the sewage plant lifts Bowerstone Industrial's
   wealth and drops Brightwall's, instead of moving one global number.
2. **Towns drift.** Each in-game day, wealth, crime, guards and homelessness move according
   to policy. Treasury income derives from town wealth rather than a scripted figure.
3. **Situations generate decisions.** A town with rising crime and no sheriff petitions you.
   That is an endless ruling phase driven by state, not a list of ten scripted choices.
4. **It does not end.** Rule for as long as you want, past the coronation act.

The F1 menu is already a working in-game UI to drive all of it. → [[Bridge DLL]]

## Risks

- The visual question above. If wealth changes nothing visible, the feedback is gossip,
  gift tables and shop money only - still real, but less striking.
- Balancing an economy is design work, not reverse engineering, and is the bulk of the time.
- Ruling-phase quests may fight a persistent layer; the mod likely has to run *after* the
  coronation act rather than replace it.

## Related

- [[Prior Art]] · [[Child System]] · [[Bridge DLL]] · [[Reference Index]]
