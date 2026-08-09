-- F3MOD bootstrap.
--
-- Thin on purpose. The injector re-reads and re-compiles this file every 60 frames, and
-- that shows up in game as a one-frame audio scratch. So this file installs a per-frame
-- worker once and then early-outs on every later run; all the real work happens in the
-- worker, which is resumed by the scheduler and costs nothing to keep running.
--
-- Channel findings, all established in game. Nothing here is speculative:
--   GUI.DisplayMessageBox     WORKS with arbitrary strings. Modal, Escape to close.
--   GeneralScriptManager      WORKS. Per-frame Update via AddScript.
--   GUI.DisplayInfoBoxParams  DEAD. Tried raw string, then a real TEXT_ id plus
--                             TargetHero. Nothing rendered either way.
--   GUI.ShowTopBoxMessage     DEAD with raw strings.
--   Debug.DrawText            DEAD. Renderer stripped from retail; 122 frames drew nothing.
--   Debug.AddLuaDebugKeyFunc  DEAD. No hotkeys, even with SetDebugKeyboardInputEnabled.
--   SetApplicationName, io    DEAD.
--
-- The web says the community never solved this either: their documented workflow is this
-- same file, edited in Notepad, reporting through DisplayMessageBox and closed with
-- Escape. The modal box is the state of the art, so the goal is to only ever show one the
-- player asked for.
--
-- The trigger is an expression. The previous attempt passed nil as the third argument to
-- IsMessageSentBy; it is not optional, it is a watermark from GetMostRecentMessageID, so
-- the call never matched. Fixed here.
--
-- CAREFUL: errors propagate into the quest coroutine. pcall is unavailable. Nil-check all.

local VERSION = 14

if F3MOD ~= nil and F3MOD.version == VERSION then
    return -- already installed; keep the per-second cost to one comparison
end

local function has(t, k)
    return t ~= nil and t[k] ~= nil
end

-- Retire any worker from a previous edit. GeneralScriptManager.Update drops a script
-- whose IsStillRunnable returns false.
if F3MOD ~= nil and F3MOD.worker ~= nil then
    F3MOD.worker.IsStillRunnable = function() return false end
end

F3MOD = { version = VERSION }

function F3MOD.describe(e)
    local hero = GetLocalHero and GetLocalHero()
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

-- ------------------------------------------------------------------ per-frame worker ---
if GeneralScriptManager ~= nil and has(GeneralScriptManager, "AddScript") then
    local w = { _Name = "F3MOD_WORKER" }

    function w:Update()
        -- Watermark, so only expressions performed AFTER this point count.
        local last = nil
        if has(MessageEvents, "GetMostRecentMessageID") then
            last = MessageEvents.GetMostRecentMessageID()
        end

        while true do
            local hero = GetLocalHero and GetLocalHero()
            local quiet = hero
                and not (has(GUI, "IsScreenFading") and GUI.IsScreenFading())
                and not (has(GUI, "IsAnyMenuOpen") and GUI.IsAnyMenuOpen())
                and not (has(GUI, "IsDisplayBoxActive") and GUI.IsDisplayBoxActive())

            if quiet and last ~= nil and has(MessageEvents, "IsMessageSentBy")
                and EMessageEventType ~= nil then

                local performed = MessageEvents.IsMessageSentBy(
                    EMessageEventType.MESSAGE_EVENT_EXPRESSION_PERFORMED, hero, last)

                if performed then
                    last = MessageEvents.GetMostRecentMessageID()
                    local t = has(Targeting, "GetTarget") and Targeting.GetTarget(hero) or nil
                    if t ~= nil and t:IsAlive() and has(GUI, "DisplayMessageBox") then
                        GUI.DisplayMessageBox(F3MOD.describe(t))
                    end
                end
            end

            coroutine.yield()
        end
    end

    F3MOD.worker = w
    GeneralScriptManager.AddScript(w)
end

-- One announcement, so it is obvious the new version took.
if has(GUI, "DisplayMessageBox") then
    GUI.DisplayMessageBox("F3MOD v14 installed. Target someone and perform an expression"
        .. " to inspect them. This box will not appear again on its own.")
end
