-- F3MOD v22 - non-modal HUD inspector.
--
-- The channel hunt is over. GUI.SetCounter is the quest-collectable HUD widget (chicken
-- counter, gnome counter), and the QMP010 multiplayer quest proves it takes a RAW STRING
-- label with %1 substitution:
--     GUI.SetCounter("QMP010PlayerOneScoreCounter", "P1 Score: %1", score)
-- Arbitrary text, on the HUD, persistent, updated at will, NO MODAL. This is the
-- inspector output channel.
--
-- New interaction model:
--   look at anyone       -> their stats appear on the HUD counter, live, silently
--   look away            -> the readout stays until the next target replaces it
--   target your dog      -> yes/no menu (modal, but you asked for it)
--
-- No more scan boxes at all. The seen-set is gone because there is nothing to spam.
--
-- One new call this version (SetCounter), per the one-unproven-call rule.
--
-- CAREFUL: errors propagate into the quest coroutine. pcall is unavailable. Nil-check all.

local VERSION = 62

-- Rescue, kept forever: the free camera eats all input in retail if it is ever on.
if Debug ~= nil and Debug.SetUseFreeCamera ~= nil then
    Debug.SetUseFreeCamera(false)
end

if F3MOD ~= nil and F3MOD.version == VERSION then
    return
end

local function has(t, k)
    return t ~= nil and t[k] ~= nil
end

if F3MOD ~= nil and F3MOD.worker ~= nil then
    F3MOD.worker.IsStillRunnable = function() return false end
end

local prev = F3MOD
F3MOD = {
    version = VERSION,
    inspect = (prev ~= nil and prev.inspect ~= nil) and prev.inspect or true,
}

local AGE_NAME = { [0] = "BABY", [1] = "CHILD", [2] = "ADULT", [3] = "ELDER", [4] = "NONE" }
local SEX_NAME = { [1] = "F", [2] = "M" }

local function box(text)
    if has(GUI, "DisplayMessageBox") then
        GUI.DisplayMessageBox(text)
    end
end

-- ask() and ask_amount() (the yes/no box and the betting spinner) are gone with the dog
-- menu. Both are modal and interrupt play; the F1 menu needs neither.

-- Short name: the tail of the type is the informative part, the level prefix is noise.
-- CreatureVillagerGypsyChildMaleMistpeak_MistPeakGypsyCampVillage_73959 -> GypsyChildMale
local function shortname(e)
    local n = tostring(e:GetName())
    local head = string.gsub(n, "_.*$", "")
    head = string.gsub(head, "^CreatureVillager", "")
    head = string.gsub(head, "^Creature", "")
    if head == "" then head = n end
    return head
end

-- One line for the HUD counter label. %1 carries the age scalar as the number.
local function hudline(e)
    local label = shortname(e)
    local scalar = 0
    if has(Age, "IsAvailable") and Age.IsAvailable(e) and has(Age, "GetAgeGroup") then
        local g = Age.GetAgeGroup(e)
        label = label .. " " .. tostring(AGE_NAME[g] or g)
        if has(Age, "GetAge") then
            scalar = Age.GetAge(e)
        end
    end
    if has(Gender, "Get") then
        local s = SEX_NAME[Gender.Get(e)]
        if s ~= nil then
            label = label .. " " .. s
        end
    end
    return label .. "  age %1", scalar
end

-- Complete every augment on the held weapons. After weapon-unlock.py, non-script
-- conditions answer to the empty tag; originally script-controlled ones keep their own
-- tag, so fire all known live tags too. Unmatched tags are a proven no-op. Covers both
-- the held ranged and melee weapon.
local WEAPON_TAGS = { "", "HadOrgyWithNumPeople", "JobGold", "DigSpot",
    "CRIMINAL_BROUGHT_IN", "SLAVE_BROUGHT_IN", "SHOOTING_RANGE_SCORE", "MORTAR_RANGE_SCORE" }
local function act_weapon(hero)
    if not (Carrying ~= nil and has(Carrying, "GetMeleeWeaponInAnySlot")
        and has(Carrying, "GetRangedWeaponInAnySlot")
        and has(CustomisableWeapon, "AddAmountForConditionalAugments")) then
        return
    end
    for _, w in ipairs({ Carrying.GetRangedWeaponInAnySlot(hero), Carrying.GetMeleeWeaponInAnySlot(hero) }) do
        if w ~= nil and w:IsAlive() then
            for _, tag in ipairs(WEAPON_TAGS) do
                CustomisableWeapon.AddAmountForConditionalAugments(w, tag, 1000000)
            end
        end
    end
    box("F3MOD: augments filled. Sheathe/redraw or fire the weapon to play each evolve tier.")
end


-- Bridge from the d3d9 proxy DLL (crates/bridge). The DLL owns the overlay and real
-- keyboard input; it cannot call into this VM (KoreVM has no luaL_ entry points), so it
-- writes a tiny Lua file and we execute it with RunScript - the same mechanism the
-- injector uses on this file, so it is proven to re-read from disk every time.
-- The DLL writes the file atomically (temp + move), so a partial read is not possible.
-- The file is seeded at install so RunScript never hits a missing path; there is no
-- pcall here, and an error would kill the worker.
-- Dog breed swap: the test that decides whether character records can be addressed by a
-- synthetic name. All three real breed names are in the GDB name map, and shipped code
-- both reads (IsUsingCharacterRecordWithName, miscfunctions.lua 6618) and writes
-- (SetCharacterRecord, oncarriedactionusebonuseffects.lua 183) them with literals, so the
-- call shapes are proven; only the alias string is unproven.
local DOG_BREEDS = { "DogBoxer", "DogCollet", "DogSetter" }

local function get_dog()
    local d = nil
    if GetLocalHeroDog ~= nil then
        d = GetLocalHeroDog()
    elseif GetDog ~= nil and GetLocalHero ~= nil then
        d = GetDog(GetLocalHero())
    end
    if d ~= nil and d:IsAlive() then
        return d
    end
    return nil
end

-- Read-only. Also remembers the answer so restore always has a real name to go back to.
function dog_identify()
    local d = get_dog()
    if d == nil then
        box("F3MOD: no dog found. Is the dog with you?")
        return nil
    end
    if not has(GraphicAppearanceMorph, "IsUsingCharacterRecordWithName") then
        box("F3MOD: IsUsingCharacterRecordWithName missing")
        return nil
    end
    for _, name in ipairs(DOG_BREEDS) do
        if GraphicAppearanceMorph.IsUsingCharacterRecordWithName(d, name) then
            F3MOD.dog_breed = name
            box("F3MOD: dog is " .. name .. " (remembered for restore)")
            return name
        end
    end
    box("F3MOD: dog matches none of Boxer/Collet/Setter")
    return nil
end

function dog_set(record, label)
    local d = get_dog()
    if d == nil then
        box("F3MOD: no dog found")
        return
    end
    if not has(GraphicAppearanceMorph, "SetCharacterRecord") then
        box("F3MOD: SetCharacterRecord missing")
        return
    end
    -- Capture the original first so restore is always possible, even if this swap is the
    -- one that goes wrong.
    if F3MOD.dog_breed == nil then
        dog_identify()
    end
    GraphicAppearanceMorph.SetCharacterRecord(d, record)
    box("F3MOD: sent " .. label .. " (" .. record .. "). If the dog changed breed the record"
        .. " resolved; if it vanished, pick 'Dog: restore original'.")
end

function dog_restore()
    local name = F3MOD.dog_breed or "DogCollet"
    local d = get_dog()
    if d ~= nil and has(GraphicAppearanceMorph, "SetCharacterRecord") then
        GraphicAppearanceMorph.SetCharacterRecord(d, name)
        box("F3MOD: restored dog to " .. name)
    end
end

-- Adult creature type for a child type. Ambient children are ...Child... and their adult
-- counterpart is ...Generic...; the hero's own children are a different naming scheme
-- entirely (HerosSon / HerosDaughter) whose adults are "CreatureVillager" for males and
-- "CreatureVillagerGenericFemale" for females - the pair used by opinionsdebug.lua, and the
-- only ones present in the GDB name map (there is no CreatureVillagerGenericMale).
-- typ is only a hint: it comes from the entity NAME, which equals the creature type for
-- world-placed NPCs but not for anything spawned with a custom name (our F3Son/F3Daughter
-- reported "F3Daughter is not a Child type"). Creature.GetCreatureType is no help - it
-- returns a broad enum (CREATURE_VILLAGER), not the specific type. So fall back to sex,
-- which is all the adult type actually depends on.
function adult_type_for(typ, entity)
    if string.find(typ, "HerosSon", 1, true) then
        return "CreatureVillager"
    end
    if string.find(typ, "HerosDaughter", 1, true) then
        return "CreatureVillagerGenericFemale"
    end
    local a = string.gsub(typ, "Child", "Generic")
    if a ~= typ then
        return a
    end
    if entity ~= nil and has(Gender, "Get") then
        if Gender.Get(entity) == 1 then
            return "CreatureVillagerGenericFemale"
        end
        return "CreatureVillager"
    end
    return nil
end

-- Adoption. PlayerFamily.Adopt is NOT exposed in retail (checked in game), but shipped code
-- uses two variants and AdoptWithSpouse is the other one; Villager.AddChild/AddParent are a
-- further fallback since they are a different namespace. Returns the name of whatever
-- worked so the caller can report it instead of guessing.
function adopt_into_family(hero, spouse, kid)
    local used = "none"
    -- The adopt calls take THREE entities. Passing nil for the spouse crashed the game -
    -- native code dereferences it. Every shipped call site passes a real, live spouse, so
    -- if we do not have one, skip adoption entirely and only set the parent link.
    local have_spouse = spouse ~= nil and spouse:IsAlive()
    if have_spouse then
        if has(PlayerFamily, "Adopt") then
            PlayerFamily.Adopt(hero, spouse, kid)
            used = "Adopt"
        elseif has(PlayerFamily, "AdoptWithSpouse") then
            PlayerFamily.AdoptWithSpouse(hero, spouse, kid)
            used = "AdoptWithSpouse"
        end
    else
        used = "no spouse, parent link only"
    end
    -- Parent/child links. NOTE the asymmetry, and do not "tidy" it: every shipped call
    -- passes a VILLAGER as AddChild's first argument (a spouse or another villager), never
    -- the hero. Calling Villager.AddChild(hero, ...) crashed the game - the hero has no
    -- Villager component. The hero is only ever named as a PARENT, via AddParent.
    if has(Villager, "AddChild") and spouse ~= nil and spouse:IsAlive() then
        Villager.AddChild(spouse, kid)
        if used == "none" then used = "Villager.AddChild only" end
    end
    if has(Villager, "AddParent") then
        Villager.AddParent(kid, hero)
        if spouse ~= nil and spouse:IsAlive() then
            Villager.AddParent(kid, spouse)
        end
    end
    return used
end

-- Adult character record aliases (27 per sex) generated by tools/record-chain.py used to
-- live here. They worked - the meshes swapped and the sexes came out right - but the
-- skeleton stayed a child's, so the tables are no longer used. Regenerate them from the
-- tool if per-entity appearance swapping is ever wanted:
--   python tools/record-chain.py CreatureVillagerGypsyMaleMistpeak

local BRIDGE_PATH = "scripts\\MyMod\\F3Bridge.lua"

-- The menu itself. The DLL only reports keypresses; everything below is Lua, so it stays
-- live-editable. Rendering goes through GUI.SetCounter, the same non-modal HUD widget the
-- inspector uses - no D3D drawing, so nothing to corrupt and nothing for the game's
-- anti-tamper to object to.
local MENU = {
    -- Money.Add with INCOME_TYPE_SCRIPT is the shipped form that shows the gold popup;
    -- AddSilent deliberately shows nothing, which just looked like a failure.
    { "Gold +50,000", function(h)
        if has(Money, "Add") and EMoneyChangeType ~= nil then
            Money.Add(h, 50000, EMoneyChangeType.INCOME_TYPE_SCRIPT)
        elseif has(Money, "AddSilent") then
            Money.AddSilent(h, 50000, 0)
        end
    end },
    { "Refill health", function(h)
        if has(Health, "FillHealth") then Health.FillHealth(h) end
    end },
    { "Guild seals +50", function(h)
        if has(Stats, "ModifyGuildSeals") and has(Stats, "GetNumberOfGuildSeals") then
            Stats.ModifyGuildSeals(h, 50)
            if has(GUI, "SetGuildSealCounterValue") then
                GUI.SetGuildSealCounterValue(h, Stats.GetNumberOfGuildSeals(h))
            end
        end
    end },
    { "Evolve held weapon", act_weapon },
    -- Age the last NPC the inspector looked at past the ~18 boundary, which is what flips
    -- CHILD to ADULT. Fixed value so no modal input box is needed.
    { "Age last NPC -> 25", function()
        local subj = F3MOD.target
        if subj ~= nil and subj:IsAlive() and has(Age, "IsAvailable") and Age.IsAvailable(subj)
            and has(Age, "SetAge") then
            Age.SetAge(subj, 25)
        end
    end },
    -- Child growth. The mesh-swap version (SetCharacterRecord + SetScale + SetVoiceType)
    -- is gone: it produced an adult-looking body on a child SKELETON, and no amount of
    -- scaling fixes proportions. Replacement below is the real thing. -> [[Child System]]
    -- Read-only probe. GetChildrenOnThisLevel takes just the hero (shipped shape:
    -- GetChildrenOnThisLevel(QuestManager.HeroEntity)), so it works even when the marriage
    -- has not registered - which it had not, because Marry needs a home set first.
    { "Family: report (read only)", function(hero)
        if not has(PlayerFamily, "GetChildrenOnThisLevel") then
            box("F3MOD: GetChildrenOnThisLevel unavailable")
            return
        end
        local kids = PlayerFamily.GetChildrenOnThisLevel(hero)
        if kids == nil or table.getn(kids) == 0 then
            box("F3MOD: no children on this level. Spawn some with the instant family,"
                .. " or look at a child and use the looked-at grow-up.")
            return
        end
        local desc = ""
        for i = 1, table.getn(kids) do
            local k = kids[i]
            if k ~= nil and k:IsAlive() then
                local g = has(Age, "GetAgeGroup") and Age.GetAgeGroup(k) or -1
                local mine = has(PlayerFamily, "IsParentOf") and PlayerFamily.IsParentOf(hero, k)
                desc = desc .. shortname(k) .. "/" .. tostring(AGE_NAME[g] or g)
                    .. "/mine=" .. tostring(mine) .. "  "
            end
        end
        box("F3MOD: children (" .. tostring(table.getn(kids)) .. "): " .. desc)
    end },
    -- Grow up whatever child you are LOOKING AT, and relink it. Using the target sidesteps
    -- the spouse lookup entirely; the parent link only needs the hero.
    -- Grow up EVERY child nearby. SearchTools is a general entity finder that this project
    -- never found on its own; it comes from the published "Automatic houses management" mod
    -- (Nexus 26), which is a 2575-line working script, so the shapes are proven in retail:
    --   local s = SearchTools.StartNewSearch("creature")   -- also "object"/"marker"/"all"
    --   SearchTools.FilterWithinDistanceOfPos(s, pos, radius)
    --   local results = SearchTools.GetSearchResults(s)    -- plain array of entities
    -- Radius 25 keeps it to the immediate street rather than the whole level.
    { "GROW UP all children near", function(hero)
        if SearchTools == nil or not (has(SearchTools, "StartNewSearch")
            and has(SearchTools, "FilterWithinDistanceOfPos")
            and has(SearchTools, "GetSearchResults")) then
            box("F3MOD: SearchTools unavailable in this build.")
            return
        end
        local s = SearchTools.StartNewSearch("creature")
        SearchTools.FilterWithinDistanceOfPos(s, hero:GetPosition(), 25)
        local found = SearchTools.GetSearchResults(s)
        if found == nil or table.getn(found) == 0 then
            box("F3MOD: search returned nothing.")
            return
        end
        local grown, failed = 0, 0
        for i = 1, table.getn(found) do
            local e = found[i]
            if e ~= nil and e:IsAlive() and has(Age, "GetAgeGroup") and Age.GetAgeGroup(e) == 1 then
                local full = tostring(e:GetName())
                local adult = adult_type_for(string.gsub(full, "_.*$", ""), e)
                if adult ~= nil then
                    ScriptFunction.PutEntityInLimbo(e)
                    local made = Debug.CreateEntityAtEntitysPosition(adult, full, hero)
                    if made ~= nil and made:IsAlive() then
                        grown = grown + 1
                    else
                        failed = failed + 1
                    end
                end
            end
        end
        box("F3MOD: scanned " .. tostring(table.getn(found)) .. " creatures nearby, grew "
            .. tostring(grown) .. ", failed " .. tostring(failed) .. ".")
    end },
    { "GROW UP looked-at child", function(hero)
        local subj = F3MOD.target
        if subj == nil or not subj:IsAlive() then
            box("F3MOD: look at a child first.")
            return
        end
        local full = tostring(subj:GetName())
        local typ = string.gsub(full, "_.*$", "")
        local adult = adult_type_for(typ, subj)
        if adult == nil then
            box("F3MOD: " .. typ .. " has no adult counterpart I can derive.")
            return
        end
        local was_mine = has(PlayerFamily, "IsParentOf") and PlayerFamily.IsParentOf(hero, subj)
        -- Look the spouse up BEFORE limboing the child, while the family is still intact.
        -- adopt_into_family needs a real one: the adopt calls crash on a nil spouse.
        local spouse = nil
        if was_mine and has(PlayerFamily, "GetOrCreatePrimarySpouse") then
            spouse = PlayerFamily.GetOrCreatePrimarySpouse(hero, hero:GetPosition(), true)
        end
        ScriptFunction.PutEntityInLimbo(subj)
        local made = Debug.CreateEntityAtEntitysPosition(adult, full, hero)
        F3MOD.target = nil
        if made == nil or not made:IsAlive() then
            box("F3MOD: replacement was not created.")
            return
        end
        local used = "not attempted"
        if was_mine then
            used = adopt_into_family(hero, spouse, made)
        end
        local now_mine = has(PlayerFamily, "IsParentOf") and PlayerFamily.IsParentOf(hero, made)
        box("F3MOD: " .. typ .. " -> " .. adult .. ". was mine=" .. tostring(was_mine)
            .. ", relink=" .. used .. ", now mine=" .. tostring(now_mine))
    end },
    -- Instant family for testing the grow-up without playing to marriage. This is
    -- Debug.CreateInstantFamily (opinionsdebug.lua 775) re-implemented rather than called:
    -- the shipped one reads QuestManager.HeroEntity, which is nil outside a quest, and a
    -- nil index would kill the worker since there is no pcall. Same calls, hero-derived
    -- position, plus progress reporting so a failure says which step.
    { "Debug: create instant family", function(hero)
        -- Report exactly which call is missing rather than a blanket "unavailable";
        -- otherwise a nil check tells us nothing about which assumption was wrong.
        local missing = ""
        if not has(Debug, "CreateEntityAtEntitysPosition") then missing = missing .. "CreateEntityAtEntitysPosition " end
        if not has(Debug, "CreateEntityAtPosition") then missing = missing .. "CreateEntityAtPosition " end
        if PlayerFamily == nil then missing = missing .. "PlayerFamily " end
        if not has(PlayerFamily, "Marry") then missing = missing .. "Marry " end
        if not has(PlayerFamily, "GetChildren") then missing = missing .. "GetChildren " end
        if not has(PlayerFamily, "GetOrCreatePrimarySpouse") then missing = missing .. "GetOrCreatePrimarySpouse " end
        if missing ~= "" then
            box("F3MOD: missing -> " .. missing)
            return
        end
        local pos = hero:GetPosition()
        -- Set a home BEFORE marrying. The shipped married-couple builder does this and
        -- CreateInstantFamily does not, which is why the marriage never registered and
        -- GetOrCreatePrimarySpouse came back empty. Shape from opinionsdebug.lua 758-762.
        local home = "no home set"
        if has(GUI, "GetLevelIDForLevel") and PlayerProperties ~= nil
            and has(PlayerProperties, "GetEmptyHousePlayerOwnsInLevel")
            and has(PlayerProperties, "SetHomeForMarriageOrAdoption")
            and ScriptFunction ~= nil and has(ScriptFunction, "GetLevelName") then
            local level_id = GUI.GetLevelIDForLevel("fable3", ScriptFunction.GetLevelName())
            local building_id = PlayerProperties.GetEmptyHousePlayerOwnsInLevel(hero, level_id)
            if building_id ~= nil then
                PlayerProperties.SetHomeForMarriageOrAdoption(hero, building_id)
                home = "home set"
            else
                home = "no empty house owned here"
            end
        end
        -- Shipped logic: a male hero gets a wife, otherwise a husband. Male is 2 here.
        local hero_male = has(Gender, "Get") and Gender.Get(hero) == 2
        local spouse_type = hero_male and "CreatureVillagerGenericFemale" or "CreatureVillager"
        -- CreateEntityAtEntitysPosition is the creator already proven working by the adult
        -- replacement; prefer it and fall back to the position form.
        local spouse
        if has(Debug, "CreateEntityAtEntitysPosition") then
            spouse = Debug.CreateEntityAtEntitysPosition(spouse_type, "F3Spouse", hero)
        else
            spouse = Debug.CreateEntityAtPosition(spouse_type, "F3Spouse", pos)
        end
        if spouse == nil or not spouse:IsAlive() then
            box("F3MOD: spouse (" .. spouse_type .. ") was not created.")
            return
        end
        local mk = function(t, n)
            if has(Debug, "CreateEntityAtEntitysPosition") then
                return Debug.CreateEntityAtEntitysPosition(t, n, hero)
            end
            return Debug.CreateEntityAtPosition(t, n, pos)
        end
        local son = mk("CreatureVillagerHerosSon", "F3Son")
        local daughter = mk("CreatureVillagerHerosDaughter", "F3Daughter")
        PlayerFamily.Marry(hero, spouse)
        local n = 0
        for _, kid in ipairs({ son, daughter }) do
            if kid ~= nil and kid:IsAlive() then
                F3MOD.adopt_used = adopt_into_family(hero, spouse, kid)
                n = n + 1
                -- Shipped code seeds affection so they behave like real family.
                if OpinionReaction ~= nil and has(OpinionReaction, "SetAxisValue")
                    and EOpinionAxes ~= nil then
                    OpinionReaction.SetAxisValue(kid, hero, EOpinionAxes.EOA_LOVE, 0.8)
                end
            end
        end
        if OpinionReaction ~= nil and has(OpinionReaction, "SetAxisValue") and EOpinionAxes ~= nil then
            OpinionReaction.SetAxisValue(spouse, hero, EOpinionAxes.EOA_LOVE, 0.8)
        end
        box("F3MOD: " .. home .. "; spouse + " .. tostring(n) .. " child(ren), linked via "
            .. tostring(F3MOD.adopt_used) .. ". Now run Family: report.")
    end },
    { "Dog: what breed?", function() dog_identify() end },
    { "Dog -> Setter (real name)", function() dog_set("DogSetter", "real name") end },
    -- THE ALIAS TEST. "n_rtphaa" is not a name in any shipped file; it is an 8-char string
    -- built by crates/gdb fnvpre whose FNV-1 hash equals FNV-1("DogCollet") exactly
    -- (0C0980D0). If the dog turns into a collie, the engine resolves character records
    -- through the GDB name map by hash, which means every one of the 1,619 records is
    -- addressable even though 1,546 of their names are unknown. -> [[Child System]]
    { "Dog -> Collet via ALIAS", function() dog_set("n_rtphaa", "ALIAS of DogCollet") end },
    { "Dog: restore original", function() dog_restore() end },
    { "Toggle inspector", function()
        F3MOD.inspect = not F3MOD.inspect
    end },
}

local function menu_draw()
    if not has(GUI, "SetCounter") then
        return
    end
    if not F3MOD.open then
        -- Blank the line rather than leave a stale menu on the HUD.
        GUI.SetCounter("F3MODMenu", " ", 0)
        return
    end
    local i = F3MOD.sel or 1
    GUI.SetCounter("F3MODMenu",
        "F3MOD  [" .. MENU[i][1] .. "]   F1 close, up/down, Enter", i)
end

-- key: 1=F1 toggle, 2=up, 3=down, 4=enter
local function menu_key(hero, key)
    local n = #MENU
    if key == 1 then
        F3MOD.open = not F3MOD.open
        F3MOD.sel = F3MOD.sel or 1
    elseif F3MOD.open then
        if key == 2 then
            F3MOD.sel = ((F3MOD.sel or 1) - 2) % n + 1
        elseif key == 3 then
            F3MOD.sel = (F3MOD.sel or 1) % n + 1
        elseif key == 4 then
            MENU[F3MOD.sel or 1][2](hero)
        end
    end
    menu_draw()
end

local function poll_bridge(hero)
    if RunScript == nil then
        return
    end
    RunScript(BRIDGE_PATH)
    if type(F3KEY) ~= "table" or F3KEY.seq == nil then
        return
    end
    if F3KEY.seq == 0 or F3KEY.seq == F3MOD.last_seq then
        return
    end
    F3MOD.last_seq = F3KEY.seq
    menu_key(hero, F3KEY.key)
end

-- The dog-targeted yes/no menu is gone. F1 through the DLL bridge replaces it, so there
-- is no reason to keep a modal chain that interrupted play and had to be walked in order.

if GeneralScriptManager ~= nil and has(GeneralScriptManager, "AddScript") then
    local w = { _Name = "F3MOD_WORKER" }

    function w:Update()
        local last_id = nil
        local refresh = 0
        local bridge_tick = 0

        -- Clear HUD widgets left behind by earlier diagnostic builds. SetCounter widgets
        -- persist until explicitly removed, so a counter that stopped being updated stays
        -- frozen on screen forever. RemoveCounter shape from subgamebarmanjob.lua.
        if has(GUI, "RemoveCounter") then
            GUI.RemoveCounter("F3MODLook")
        end

        while F3MOD ~= nil and F3MOD.worker == self do
            local hero = GetLocalHero and GetLocalHero()
            local boxed = has(GUI, "IsDisplayBoxActive") and GUI.IsDisplayBoxActive()

            -- Poll the DLL bridge every tick (~15 Hz). Menu navigation needs to feel
            -- immediate, and one small file read per tick is cheap.
            bridge_tick = bridge_tick + 1
            if hero and bridge_tick >= 1 then
                bridge_tick = 0
                poll_bridge(hero)
            end

            -- Inspector only. Targeting the dog no longer opens anything; F1 does.
            if hero and not boxed and F3MOD.inspect and has(Targeting, "GetTarget")
                and has(GUI, "SetCounter") then
                local t = Targeting.GetTarget(hero)
                if t ~= nil and t:IsAlive() then
                    F3MOD.target = t
                    local id = tostring(t:GetName())
                    -- Refresh once a second even without a change, so edits made through
                    -- the menu show up without retargeting.
                    refresh = refresh + 1
                    if id ~= last_id or refresh >= 60 then
                        last_id = id
                        refresh = 0
                        local label, num = hudline(t)
                        GUI.SetCounter("F3MODInspector", label, num)
                    end
                else
                    last_id = nil
                end
            end

            coroutine.yield()
        end
    end

    F3MOD.worker = w
    GeneralScriptManager.AddScript(w)
end

box("F3MOD v62. New: GROW UP all children near - uses SearchTools, an entity finder"
    .. " learned from the Automatic Houses mod. Stand in a village and fire it.")
