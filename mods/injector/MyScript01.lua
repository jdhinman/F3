-- Live-edit harness + entity inspector.
--
-- Settled by v8: Debug.DrawText is inert in retail. The HUD script drew 122 frames and
-- nothing appeared, so the symbol survived the release build but the renderer did not.
-- Confirmed working channels are GUI.DisplayMessageBox (modal) and the per-frame
-- scheduler, GeneralScriptManager.AddScript, which v8 proved runs every tick.
--
-- This version does two things:
--   1. tests GUI.ShowTopBoxMessage, the last candidate for non-modal text
--   2. ships the entity inspector: look at someone, get their stats
--
-- The inspector reports only when the target CHANGES, so it cannot spam.
--
-- CAREFUL: errors propagate into the quest coroutine and GeneralScriptManager re-raises
-- them. pcall is in no shipped script. Nil-check everything.

local VERSION = 9

local function has(t, k)
    return t ~= nil and t[k] ~= nil
end

local function say(text)
    -- Prefer the non-modal banner if it renders raw strings; fall back to the modal box,
    -- which is proven. ShowTopBoxMessage(text, seconds, bool) per the shipped call sites.
    if has(GUI, "ShowTopBoxMessage") then
        GUI.ShowTopBoxMessage(text, 6, true)
    end
end

local function describe(e)
    local parts = "TARGET: " .. tostring(e:GetName())

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
        parts = parts .. "  age=" .. name .. "(" .. tostring(g) .. ")"
        if has(Age, "GetAge") then
            parts = parts .. " scalar=" .. tostring(Age.GetAge(e))
        end
    end

    if has(Gender, "Get") then
        parts = parts .. "  gender=" .. tostring(Gender.Get(e))
    end
    if has(PlayerFamily, "IsFamilyMember") then
        parts = parts .. "  family=" .. tostring(PlayerFamily.IsFamilyMember(GetLocalHero(), e))
    end
    return parts
end

-- ------------------------------------------------------------------ one-shot per edit ---
if F3MOD_VERSION ~= VERSION then
    local hero = GetLocalHero and GetLocalHero()
    local visible = hero
        and not (GUI ~= nil and GUI.IsScreenFading ~= nil and GUI.IsScreenFading())
        and not (GUI ~= nil and GUI.IsAnyMenuOpen ~= nil and GUI.IsAnyMenuOpen())
    if visible then
        say("F3MOD v9 - top box test. Inspector armed: target someone.")
        F3MOD_VERSION = VERSION
    end
end

-- ---------------------------------------------------------------------- the inspector ---
-- Runs once per second off the injector. Reports only on change.
local hero = GetLocalHero and GetLocalHero()
if hero and has(Targeting, "GetTarget") then
    local t = Targeting.GetTarget(hero)
    if t ~= nil and t:IsAlive() then
        local id = tostring(t:GetName())
        if id ~= F3MOD_LAST_TARGET then
            F3MOD_LAST_TARGET = id
            say(describe(t))
        end
    else
        F3MOD_LAST_TARGET = nil
    end
end
