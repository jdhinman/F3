-- F3MOD - entity inspector.
--
-- Trigger: TARGET CHANGE. Not expressions.
--
-- Expressions were the wrong bet. v11 already proved target-change detection works - that
-- is how the child readout appeared - and I moved away from it to avoid modal spam, then
-- spent several rounds chasing a trigger that has never once fired. The spam problem has
-- an easy fix that does not require a new mechanism: report each entity only once, and
-- stop after a cap. So this goes back to what works.
--
-- Everything here is proven in game:
--   Targeting.GetTarget            v16: returned entities on 120 of 120 frames
--   GUI.DisplayMessageBox          the only working text channel
--   GeneralScriptManager.AddScript per-frame Update
--
-- USE: target people. Each new one is reported once. After 25 distinct entities it goes
-- quiet by itself.
--
-- CAREFUL: errors propagate into the quest coroutine. pcall is unavailable. Nil-check all.

local VERSION = 18

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
            out = out .. "    age scalar: " .. tostring(Age.GetAge(e))
        end
    else
        out = out .. "\nno age component"
    end

    if has(Gender, "Get") then
        out = out .. "\ngender: " .. tostring(Gender.Get(e))
    end
    if has(PlayerFamily, "IsFamilyMember") and hero then
        out = out .. "    family: " .. tostring(PlayerFamily.IsFamilyMember(hero, e))
    end
    return out
end

if GeneralScriptManager ~= nil and has(GeneralScriptManager, "AddScript") then
    local w = { _Name = "F3MOD_WORKER" }

    function w:Update()
        local seen = {}
        local reports = 0
        local last_id = nil

        while true do
            local hero = GetLocalHero and GetLocalHero()
            local boxed = has(GUI, "IsDisplayBoxActive") and GUI.IsDisplayBoxActive()

            if hero and not boxed and has(Targeting, "GetTarget") then
                local t = Targeting.GetTarget(hero)
                if t ~= nil and t:IsAlive() then
                    local id = tostring(t:GetName())
                    if id ~= last_id then
                        last_id = id
                        if not seen[id] and reports < 25 and has(GUI, "DisplayMessageBox") then
                            seen[id] = true
                            reports = reports + 1
                            GUI.DisplayMessageBox(F3MOD.describe(t))
                        end
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

if has(GUI, "DisplayMessageBox") then
    GUI.DisplayMessageBox("F3MOD v18. Target people - each new one is reported once."
        .. " Goes quiet after 25.")
end
