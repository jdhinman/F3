-- Live-edit harness + entity inspector.
--
-- Two problems, two experiments in this version.
--
-- 1. NON-MODAL TEXT. GUI.DisplayInfoBoxParams with a raw string showed nothing. Every
--    shipped call passes a TEXT_ id as the second argument, and one of them also passes
--    TargetHero. So either the text must be a real localisation id, or the box needs to
--    know whose HUD to attach to. This fires the box with BOTH fixed - TargetHero set and
--    a genuine id, TEXT_GUI_CHEST_LOCKED - which isolates the mechanism from the text. If
--    a "chest locked" popup appears, the box works and only arbitrary strings are the
--    problem. If nothing appears, the box is unreachable from here and we stop.
--
-- 2. ON-DEMAND REPORTS. Debug.AddLuaDebugKeyFunc does not fire, so there are no hotkeys.
--    But the hero performing an expression posts MESSAGE_EVENT_EXPRESSION_PERFORMED, and
--    MessageEvents.IsMessageSentBy can see it. That is a player-driven trigger, which
--    makes a modal box acceptable: it only appears because you asked for it.
--
--    So: target someone, perform any expression, get their readout.
--
-- CAREFUL: errors propagate into the quest coroutine. pcall is unavailable. Nil-check all.

local VERSION = 13

local function has(t, k)
    return t ~= nil and t[k] ~= nil
end

local hero = GetLocalHero and GetLocalHero()
F3MOD_RUNS = (F3MOD_RUNS or 0) + 1

local function box(text)
    if has(GUI, "DisplayMessageBox") then
        GUI.DisplayMessageBox(text)
    end
end

local watchable = hero
    and not (GUI ~= nil and GUI.IsScreenFading ~= nil and GUI.IsScreenFading())
    and not (GUI ~= nil and GUI.IsAnyMenuOpen ~= nil and GUI.IsAnyMenuOpen())

-- ------------------------------------------------ experiment 1: is the info box usable ---
if F3MOD_STAGE_V ~= VERSION then
    F3MOD_STAGE_V = VERSION
    F3MOD_STAGE = 0
end

if F3MOD_STAGE == 0 and watchable and has(GUI, "DisplayInfoBoxParams") and EDisplayBoxStyle ~= nil then
    GUI.DisplayInfoBoxParams({
        ShowAButton = false,
        ShowYButton = false,
        DisplayBoxStyle = EDisplayBoxStyle.DBS_INFO_BOX,
        LifeTime = 8,
        TargetHero = hero,
    }, "TEXT_GUI_CHEST_LOCKED")
    F3MOD_STAGE = 1
    F3MOD_STAGE_AT = F3MOD_RUNS
elseif F3MOD_STAGE == 1 and (F3MOD_RUNS - (F3MOD_STAGE_AT or 0)) >= 8 and watchable then
    box("Test: sent an info box with a REAL text id and TargetHero set."
        .. "  Did a small popup about a locked chest appear?"
        .. "\n\nInspector: target someone and perform any expression.")
    F3MOD_STAGE = 2
end

-- ------------------------------------------------------------------------ inspector ---
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
    else
        out = out .. "  (no age component)"
    end
    if has(Gender, "Get") then
        out = out .. "  gender=" .. tostring(Gender.Get(e))
    end
    if has(PlayerFamily, "IsFamilyMember") and hero then
        out = out .. "  family=" .. tostring(PlayerFamily.IsFamilyMember(hero, e))
    end
    return out
end

-- Expression as the trigger. Debounced by run count rather than by message id, because
-- the id plumbing differs between call sites and a wrong guess here errors.
if F3MOD_STAGE == 2 and hero and has(MessageEvents, "IsMessageSentBy")
    and EMessageEventType ~= nil and watchable then

    local cooling = F3MOD_EXPR_AT ~= nil and (F3MOD_RUNS - F3MOD_EXPR_AT) < 3
    if not cooling then
        local performed = MessageEvents.IsMessageSentBy(
            EMessageEventType.MESSAGE_EVENT_EXPRESSION_PERFORMED, hero, nil)
        if performed then
            F3MOD_EXPR_AT = F3MOD_RUNS
            local t = has(Targeting, "GetTarget") and Targeting.GetTarget(hero) or nil
            if t ~= nil and t:IsAlive() then
                box(describe(t))
            else
                box("F3MOD: expression seen, but nothing is targeted.")
            end
        end
    end
end
