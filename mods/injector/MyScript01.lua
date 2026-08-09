-- Live-edit harness + entity inspector.
--
-- Channel status, all settled in game:
--   GUI.DisplayMessageBox     WORKS - modal, arbitrary strings. The only text channel.
--   per-frame AddScript       WORKS - 122 frames confirmed
--   GUI.ShowTopBoxMessage     INERT - nothing rendered. Probably wants a localised id.
--   Debug.DrawText            INERT - symbol survives retail, renderer does not
--   SetApplicationName, io    inert / absent
--
-- So every report costs a modal box, which is far too intrusive to fire on every target
-- change. Two fixes tried here, in order of preference:
--   1. a hotkey, so reports happen on demand. Debug.AddLuaDebugKeyFunc has 46 shipped
--      call sites but the forum could never get it working; Debug.SetDebugKeyboardInputEnabled
--      is called by no shipped script and is the obvious missing step, so try it first.
--   2. failing that, auto-report only for CHILD entities, which are rare and are the
--      thing actually being researched.
--
-- CAREFUL: errors propagate into the quest coroutine. pcall is unavailable. Nil-check all.

local VERSION = 11

local function has(t, k)
    return t ~= nil and t[k] ~= nil
end

local function box(text)
    if has(GUI, "DisplayMessageBox") then
        GUI.DisplayMessageBox(text)
    end
end

local hero = GetLocalHero and GetLocalHero()

local function describe(e)
    local out = "TARGET: " .. tostring(e:GetName())
    if has(Age, "IsAvailable") and Age.IsAvailable(e) and has(Age, "GetAgeGroup") then
        local g = Age.GetAgeGroup(e)
        local name = "?"
        if EAgeGroup ~= nil then
            if g == EAgeGroup.EAGE_GROUP_BABY then name = "BABY"
            elseif g == EAgeGroup.EAGE_GROUP_CHILD then name = "CHILD"
            elseif g == EAgeGroup.EAGE_GROUP_ADULT then name = "ADULT"
            elseif g == EAgeGroup.EAGE_GROUP_ELDER then name = "ELDER"
            elseif g == EAgeGroup.EAGE_GROUP_NONE then name = "NONE" end
        end
        out = out .. "  age=" .. name .. "(" .. tostring(g) .. ")"
        if has(Age, "GetAge") then
            out = out .. " scalar=" .. tostring(Age.GetAge(e))
        end
    end
    if has(Gender, "Get") then
        out = out .. "  gender=" .. tostring(Gender.Get(e))
    end
    if has(Villager, "IsAvailable") and Villager.IsAvailable(e) then
        out = out .. "  villager=yes"
    end
    if has(PlayerFamily, "IsFamilyMember") and hero then
        out = out .. "  family=" .. tostring(PlayerFamily.IsFamilyMember(hero, e))
    end
    return out
end

local function inspect()
    if hero == nil or not has(Targeting, "GetTarget") then return end
    local t = Targeting.GetTarget(hero)
    if t ~= nil and t:IsAlive() then
        box(describe(t))
    else
        box("F3MOD: nothing targeted")
    end
end

-- ------------------------------------------------------------------- hotkey attempt ---
-- KB_I is not bound by any shipped script, so it cannot collide.
if F3MOD_KEY_V ~= VERSION and has(Debug, "AddLuaDebugKeyFunc") and EInputKey ~= nil then
    if has(Debug, "SetDebugKeyboardInputEnabled") then
        Debug.SetDebugKeyboardInputEnabled(true)
    end
    Debug.AddLuaDebugKeyFunc(EInputKey.KB_I, inspect)
    F3MOD_KEY_V = VERSION
end

-- ------------------------------------------------------------------------ announce ---
if F3MOD_VERSION ~= VERSION then
    local watchable = hero
        and not (GUI ~= nil and GUI.IsScreenFading ~= nil and GUI.IsScreenFading())
        and not (GUI ~= nil and GUI.IsAnyMenuOpen ~= nil and GUI.IsAnyMenuOpen())
    if watchable then
        box("F3MOD v11. Press I with someone targeted to inspect them."
            .. "  Children auto-report. Top box is dead, so boxes are all we have.")
        F3MOD_VERSION = VERSION
    end
end

-- ------------------------------------------- fallback: auto-report children only ---
-- Rare enough not to be a nuisance, and they are the entities under study.
if hero and has(Targeting, "GetTarget") then
    local t = Targeting.GetTarget(hero)
    if t ~= nil and t:IsAlive() then
        local id = tostring(t:GetName())
        if id ~= F3MOD_LAST_TARGET then
            F3MOD_LAST_TARGET = id
            local is_child = has(Age, "IsAvailable") and Age.IsAvailable(t)
                and has(Age, "GetAgeGroup") and EAgeGroup ~= nil
                and Age.GetAgeGroup(t) == EAgeGroup.EAGE_GROUP_CHILD
            if is_child then
                box(describe(t))
            end
        end
    else
        F3MOD_LAST_TARGET = nil
    end
end
