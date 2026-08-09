-- F3MOD - entity inspector.
--
-- Built only from calls the v16 bisect proved safe:
--   MessageEvents.GetMostRecentMessageID
--   MessageEvents.IsMessageSentBy(MESSAGE_EVENT_EXPRESSION_PERFORMED, hero, watermark)
--   Targeting.GetTarget                     (confirmed returning entities, 120 frames)
--   GUI.DisplayMessageBox                   (the only working text channel)
--   GeneralScriptManager.AddScript          (per-frame Update)
--
-- Deliberately NOT used: MESSAGE_EVENT_ONE_TO_ONE_EXPRESSION_PERFORMED,
-- MESSAGE_EVENT_EXPRESSION_MENU_OPENED and MESSAGE_EVENT_INTERACTED_WITH. v15 called all
-- three and its worker died; v16 called neither and survived every phase. They are the
-- only difference, so they stay out until something needs them.
--
-- USE: target someone, perform any expression, get their readout.
--
-- If the trigger never fires, silence would be ambiguous again, so after 30 seconds
-- without a single detection it says so once. Silence is never left to mean two things.
--
-- CAREFUL: errors propagate into the quest coroutine. pcall is unavailable. Nil-check all.

local VERSION = 17

if F3MOD ~= nil and F3MOD.version == VERSION then
    return
end

local function has(t, k)
    return t ~= nil and t[k] ~= nil
end

if F3MOD ~= nil and F3MOD.worker ~= nil then
    F3MOD.worker.IsStillRunnable = function() return false end
end

F3MOD = { version = VERSION }

local AGE_NAME = { [0] = "BABY", [1] = "CHILD", [2] = "ADULT", [3] = "ELDER", [4] = "NONE" }

function F3MOD.describe(e)
    local hero = GetLocalHero and GetLocalHero()
    local out = tostring(e:GetName())

    if has(Age, "IsAvailable") and Age.IsAvailable(e) and has(Age, "GetAgeGroup") then
        local g = Age.GetAgeGroup(e)
        out = out .. "\nage group: " .. tostring(AGE_NAME[g] or "?") .. " (" .. tostring(g) .. ")"
        if has(Age, "GetAge") then
            out = out .. "   age scalar: " .. tostring(Age.GetAge(e))
        end
    else
        out = out .. "\nno age component"
    end

    if has(Gender, "Get") then
        out = out .. "\ngender: " .. tostring(Gender.Get(e))
    end
    if has(PlayerFamily, "IsFamilyMember") and hero then
        out = out .. "   family: " .. tostring(PlayerFamily.IsFamilyMember(hero, e))
    end
    if has(Health, "IsAvailable") and Health.IsAvailable(e) and has(Health, "Get") then
        out = out .. "\nhealth: " .. tostring(Health.Get(e))
    end
    return out
end

if GeneralScriptManager ~= nil and has(GeneralScriptManager, "AddScript") then
    local w = { _Name = "F3MOD_WORKER" }

    function w:Update()
        local frames, detections = 0, 0
        local warned = false
        local last = nil
        if has(MessageEvents, "GetMostRecentMessageID") then
            last = MessageEvents.GetMostRecentMessageID()
        end

        while true do
            frames = frames + 1
            local hero = GetLocalHero and GetLocalHero()
            local boxed = has(GUI, "IsDisplayBoxActive") and GUI.IsDisplayBoxActive()

            if hero and last ~= nil and not boxed and EMessageEventType ~= nil
                and has(MessageEvents, "IsMessageSentBy")
                and EMessageEventType.MESSAGE_EVENT_EXPRESSION_PERFORMED ~= nil then

                if MessageEvents.IsMessageSentBy(
                    EMessageEventType.MESSAGE_EVENT_EXPRESSION_PERFORMED, hero, last) then

                    last = MessageEvents.GetMostRecentMessageID()
                    detections = detections + 1

                    local t = has(Targeting, "GetTarget") and Targeting.GetTarget(hero) or nil
                    if t ~= nil and t:IsAlive() and has(GUI, "DisplayMessageBox") then
                        GUI.DisplayMessageBox(F3MOD.describe(t))
                    elseif has(GUI, "DisplayMessageBox") then
                        GUI.DisplayMessageBox("F3MOD: expression seen, nothing targeted.")
                    end
                end
            end

            -- Make silence mean exactly one thing.
            if not warned and frames > 1800 and detections == 0 and not boxed
                and has(GUI, "DisplayMessageBox") then
                warned = true
                GUI.DisplayMessageBox("F3MOD: 30s, no expression detected. The worker is"
                    .. " alive (frames=" .. frames .. ") so the trigger is what does not fire.")
            end

            coroutine.yield()
        end
    end

    F3MOD.worker = w
    GeneralScriptManager.AddScript(w)
end

if has(GUI, "DisplayMessageBox") then
    GUI.DisplayMessageBox("F3MOD v17. Target someone, perform any expression, read them.")
end
