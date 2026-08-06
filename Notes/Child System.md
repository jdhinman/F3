---
title: "Child System"
description: "What Fable III's children do, where the age data reportedly lives, and what growing them up would actually require"
updated: 2026-08-06
confidence: verified
tags:
  - target
  - gameplay
---

The project's target feature.

The Lua side is now **[VERIFIED]** by reading the game's own decompiled scripts - the age model,
the API that changes it, and what does and does not ship. **Nothing has been run in game**, so
every claim about behaviour at runtime remains a prediction.

## What the game does today

Fable III lets the hero marry and have children. A child is born as a baby and grows **once**, into a
child. Then it stops, permanently. There is no adulthood, no continued ageing, and no generational
play.

This is a well-known complaint rather than an obscure gap, which matters for two reasons: there is
demonstrated player demand, and there is a decent chance someone has already tried, so
[[Prior Art|check before building]].

## Where the data reportedly lives

Traced to its source: **Artofeel** on the fable3mod forums, 2014-02-18, in a thread about making
children killable. Retrieved 2026-08-05. Paraphrasing closely:

- *"killable children is hardcoded with AGE parameter"*
- set age for all children above 18 and *"they will be killable and they no more will be children"*
- GDB route: edit `globals.gdb`, main children offset **`101BF01F`**, find **`AgeComponent`**, change
  `Age` to **> 18** - or to **0**, which yields a month-old baby
- hex route: offset **`0019176C`**, change the value to **> 12 (hex)**, or to 0
- *"this offsets for latest DLC"*
- **"this effects only for new children's, not to already exist"**

Three things in that are load-bearing:

1. **Age is not cosmetic.** The author says being a child is *hardcoded against the AGE parameter*,
   and that crossing 18 stops them being children. That is a real category boundary, not a label.
2. **It only affects newly created children.** Existing saves keep their existing children unchanged,
   which shapes any mod's testing plan and its user instructions.
3. **The offsets are version-specific** - quoted as being for the latest DLC. They will not be
   trusted until re-derived locally.

> [!warning] The author never tested the consequences
> The same post says outright *"I never tested!!"* about what happens afterwards. So we have a
> located field and a stated threshold, and **no evidence at all** about whether the result is a
> functioning adult.

**[UNKNOWN]** whether the two quoted offsets are the same field reached two ways, or two different
things. They are not obviously related.

## Read from the game's own source  **[VERIFIED]** 2026-08-06

Everything below this line is read out of the decompiled scripts, not inferred from a symbol
index. → [[KoreVM|the decompiler]], output in `work/decompiled/`.

### The age model is two values, not one

```lua
EAgeGroup = { EAGE_GROUP_BABY = 0, EAGE_GROUP_CHILD = 1, EAGE_GROUP_ADULT = 2,
              EAGE_GROUP_ELDER = 3, EAGE_GROUP_NONE = 4 }
```

and the engine-side API the scripts call:

| Call | Uses | What it is |
|---|---|---|
| `Age.GetAgeGroup(entity)` | 82 | the **category**, one of the five above |
| `Age.IsAvailable(entity)` | 24 | does this entity have an age component at all |
| `Age.SetAgeGroup(entity, group)` | 4 | **set the category** |
| `Age.GetAge(entity)` / `Age.SetAge(entity, n)` | 4 / 2 | a **scalar** age |
| `Age.SetAgeWithinAgeGroup(entity, n)` | 1 | the scalar, interpreted inside the current category |

**That two-level model resolves the forum ambiguity.** Artofeel's "AGE parameter" and the claim
that crossing 18 stops something being a child are describing a scalar; the thing the AI actually
tests is the *group*. They are related but not the same field, which is the most likely
explanation for the two unrelated-looking offsets.

### `Debug.MakeChildGrowUpThroughTime` does not grow anything

The whole function:

```lua
function Debug.MakeChildGrowUpThroughTime()
    Timing.SetDayCount(Timing.GetDayCount() + 200)
end
```

It winds the world clock forward 200 days. **Growth is time-driven inside the engine**; this is a
fast-forward to reach it, which is exactly what its name says once you read it. The plan of
"call the one debug function" was based on the name alone, and the name was honest - we were not.

The real conversion is engine-side and has a script entry point:

```lua
PlayerFamily.ConvertAllBabiesToChildren(player)
```

called at the end of `Debug.CreateFamily` in `ai/opinionsdebug.lua`, after `PlayerFamily.Marry`,
creating a `CreatureHerosBaby`, and `PlayerFamily.AdoptWithSpouse`.

### One step exists, and only one

The engine posts **`MESSAGE_EVENT_BABY_TO_CHILD`**, which is what `QU090_ChildGrownICS` waits on
before playing its cutscene. Searching every message the scripts reference turns up
`BABY_TO_CHILD`, `CHILD_ADOPTED`, `CHILD_SENT_TO_ORPHANAGE`, `DIVORCE`, `NEW_MARITAL_HOME` -
**and nothing past child**. There is no `CHILD_TO_ADULT`, no second cutscene, no `ConvertChildren`
call to match `ConvertAllBabiesToChildren`.

So the earlier framing was half right. The *baby to child* machinery ships complete, including its
cutscene. **The child to adult step was never built at all.** That is what this mod has to add.

### The AI is already age-aware, and the gates are ordinal

38 script files gate behaviour on `Age.GetAgeGroup`, and the adult gates are comparisons rather
than equality tests:

```lua
if ... and EAgeGroup.EAGE_GROUP_CHILD < Age.GetAgeGroup(self.Entity) then
```

Fifteen such ordinal gates against `EAGE_GROUP_CHILD`, versus thirteen equality tests. Sitting on
benches, answering doors, using furniture, fleeing like an adult: all of it reads "group is above
child" rather than "group equals adult".

> [!success] This is the finding that makes a script mod viable
> Raising an entity's age group to `EAGE_GROUP_ADULT` **unlocks the adult behaviour set without
> touching a single behaviour script**, because the scripts were already written to a threshold.
> And `Age.SetAgeGroup` is not a theoretical binding: the shipped game calls it in three places to
> promote freshly spawned guards.

```lua
local guard = Debug.CreateEntityAtPosition(entity_name, "sheriff", pos)
if guard then
    guard:SetLayerToEntitysLayer(entity)
    Age.SetAgeGroup(guard, EAgeGroup.EAGE_GROUP_ADULT)
    Gender.Set(guard, EGender.EG_MALE)
    Villager.SetVillage(guard, entity)
```

### The mesh problem has a Lua answer too

The worry was that a child and an adult are different assets and no script can bridge them. But
the game swaps a live entity's appearance at runtime, in front of the player:

```lua
GraphicAppearanceMorph.SetCharacterRecord(entity, "<character record name>")
```

21 call sites. The **dog breed changer** uses it on a dog the player is looking at, with an FX
burst and a one-frame blink to cover the swap. `newgame.lua` uses it on the hero. There is also
`GraphicAppearanceMorph.IsUsingCharacterRecordWithName` to read the current one back.

Hero children are distinct creature types - `CreatureHerosBaby`, `CreatureVillagerHerosSon`,
`CreatureVillagerHerosDaughter` - so **[UNKNOWN]** whether a character-record swap alone is enough
or whether the creature type also has to change. But "you cannot change how an NPC looks from Lua"
is now answered: you can.

### Five shipped bugs, found in passing

`EAgeGroup.EAGE_CHILD` is not a member of the enum - the member is `EAGE_GROUP_CHILD`. Five sites
test against it, so they are comparing against `nil`:

| File | Effect |
|---|---|
| `behaviourhomebase.lua:82` | `== EAGE_CHILD` is **never true**; that child branch is dead |
| `behaviourgiveplayerreward.lua:193` | `~= EAGE_CHILD` is **always true**; the guard does nothing |
| `behaviourrespondtocrime.lua` x3 | same, always true - children respond to crime like adults |

Harmless-looking, but `behaviourhomebase.lua:82` means a piece of child home behaviour has never
run in any copy of the game.

## The machinery already exists  **[DOCUMENTED]** - found 2026-08-05

> [!warning] Superseded - read the verified section above first
> This section was written from `functions.txt`, a symbol index. Reading the actual scripts
> corrected it on two points: the "debug function that triggers it" only winds the clock forward,
> and the shipped machinery covers **baby to child only**. The cutscene and quest below are real;
> what they play is the first step, not the one this mod needs.

Recovered from `functions.txt`, a 707 KB index of **15,104 Lua function signatures** grouped by source
file, mirrored from the fable3mod forums. → [[Preservation]]

| Symbol | Source file |
|---|---|
| **`Debug.MakeChildGrowUpThroughTime()`** | `./ai/opinionsdebug.lua` |
| **`Debug.PlayChildGrownUpICS()`** | debug ICS players |
| **`QU090_ChildGrownICS:PlayChildGrownCutscene(self)`** | `./quests/qu090_childgrownics.lua` |
| `QU080_ChildBirthICS:PlayScene(self,spouse,baby)` | `./quests/qu080_childbirthics.lua` |
| `Debug.CreateHeroChildren()`, `Debug.CreateInstantFamily()`, `Debug.CreateSpouse()`, `Debug.CreateFamily(player,world_name,level_name)` | `./ai/opinionsdebug.lua` |
| `Debug.TogglePregnancyCertainty()`, `Debug.ResetCurrentRelationshipStage(hero,stage)` | `./ai/opinionsdebug.lua` |

`QU090_ChildGrownICS` is a **complete quest** - `Init`, a state machine, camera setup,
`SetChildAndParentPositions`, `GetParent`, `GetMaritalHomeMarkers`, `CheckLineOfSight`. Someone built
the entire child-grown-up scene.

### The surrounding family simulation is also richer than expected

| Area | Evidence |
|---|---|
| Parent/child AI | `behaviourparentchildinteraction.lua` - `BehaviourChildTalkToParent`, `BehaviourParentTalkToChild` |
| Child labour | `behaviourchildlabour.lua` - goto table, work at table, clean floor, hammer, carry |
| Spouse AI | `behaviourspouse.lua` - `BehaviourSpousePostChildBirth`, `BehaviourSpouseHoneymoonPeriod`, `GetLineAboutChild(self,child)` |
| Divorce | `familydivorcegroupmind.lua` |
| Orphanage | `orphanagegroupmind.lua` |
| Family queries | `ScriptFunction.IsPlayersChild(entity)`, `GetNonHeroParentForChild`, `GetNannyForChild`, `GetNonHeroGuardianForChild` |
| World map | `worldmap/family.lua` - `NewFamilyMember(mesh_id,offset,is_child)` |

Note `NewFamilyMember` takes a **`mesh_id`** and an **`is_child`** flag, which is the first hint that
child and adult family members are distinct meshes rather than one scaled model.

### The one-line-mod theory, and why it was wrong

The plan was: `Debug.MakeChildGrowUpThroughTime()` is a `Debug.*` call in the same namespace as the
injector's worked example, so drop one line in `MyScript01.lua`. **Reading it killed that plan** -
it only advances the clock, and the clock only ever drives baby to child.

Worth keeping as the shape of the mistake: a symbol index gives you names, and names invite you to
believe a function does what it is called. It took the decompiler to find out that this one does
one line of arithmetic.

**[UNKNOWN]** and still not to be assumed:

- whether these `Debug.*` functions survive in the **retail** build or were stripped. Nothing here
  has been run in game.
- whether `Age.SetAgeGroup` on an existing child re-runs whatever the engine does on a category
  change, or just writes the field
- whether a character-record swap is enough, or the creature type has to change too

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

Step 2 is done: the Lua API surface is established, read out of the game's own scripts rather than
guessed. What remains is all execution.

1. ~~Find a child entity and read what the game stores about it.~~ Partly answered from source: an
   age **group** plus a scalar age, on an age component, gated by `Age.IsAvailable`.
2. ~~**Establish the Lua API surface.**~~ **Done** - see above. `Age.SetAgeGroup`,
   `Age.SetAgeWithinAgeGroup`, `GraphicAppearanceMorph.SetCharacterRecord`,
   `PlayerFamily.GetChildren`, `ScriptFunction.IsPlayersChild`.
3. **Get anything at all running in game.** Still nothing has been executed. Set up the injector
   and confirm a `print` reaches a log before trusting any of this.
4. **Call `Age.SetAgeGroup(child, EAGE_GROUP_ADULT)` on a real child** and observe. The prediction
   from the source is: adult AI unlocks, appearance does not change. Confirming *that specific
   split* is the honest first milestone, and it is falsifiable.
5. Then `GraphicAppearanceMorph.SetCharacterRecord` for appearance, and find out whether the
   creature type has to change as well.

## Sketch of the mod, from the verified API

Not tested, not run. Written down so step 4 has something concrete to run.

```lua
-- Promote the player's children from child to adult.
-- Every adult AI gate in the shipped scripts reads `EAGE_GROUP_CHILD < GetAgeGroup(e)`,
-- so the category change is what unlocks behaviour; the record swap is cosmetic.
local function GrowUpChild(child)
    if not Age.IsAvailable(child) then return false end
    if Age.GetAgeGroup(child) ~= EAgeGroup.EAGE_GROUP_CHILD then return false end
    Age.SetAgeGroup(child, EAgeGroup.EAGE_GROUP_ADULT)
    Age.SetAgeWithinAgeGroup(child, 0)   -- youngest adult, not a middle-aged one
    return true
end

local function GrowUpAllChildren()
    local hero = GetLocalHero()
    if not PlayerFamily.IsAvailable(hero) then return end
    local spouse = PlayerFamily.GetOrCreatePrimarySpouse(hero)
    local children = PlayerFamily.GetChildren(hero, spouse)
    if children == nil then return end
    for i, child in ipairs(children) do
        if child and child:IsAlive() then GrowUpChild(child) end
    end
end
```

`PlayerFamily.GetChildren` takes **two** arguments - a parent and the other family member whose
perspective is being asked about - and returns a plain array. The shipped scripts iterate it with
`ipairs` and measure it with `#`, so the loop above matches how `familydivorcegroupmind.lua`,
`behaviourspouse.lua` and `behaviournanny.lua` already use it. `GetChildrenOnThisLevel` is the
variant to prefer if only loaded entities should be touched.

## Related

- [[Prior Art]] · [[Open Questions]]
