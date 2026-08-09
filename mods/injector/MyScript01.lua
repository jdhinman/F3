-- F3MOD v20 - RESCUE + menu without the trap.
--
-- v19's free camera captured ALL keyboard input, including the yes/no box's own keys, so
-- the menu could not be answered and the player was stuck inside it. The camera is driven
-- by the debug key system (F1-F9 in freecamera.lua), which does not work in retail, so
-- there is no way to fly OR to leave. It is not a usable feature; it is a trap.
--
-- This bootstrap runs every 60 frames regardless of any stuck box, so its first job is
-- the rescue: force the free camera OFF unconditionally. Then it retires the old worker,
-- stuck or not - a worker blocked inside AskYesNoQuestion still yields every frame, so
-- the scheduler still consults IsStillRunnable and drops it.
--
-- Menu changes:
--   free camera REMOVED
--   heal added (Health.FillHealth - shipped call)
--   menu now pauses the inspector while it is open, and the inspector ignores the dog
--
-- CAREFUL: errors propagate into the quest coroutine. pcall is unavailable. Nil-check all.

local VERSION = 20

-- ------------------------------------------------------------------------- RESCUE ---
-- Before the version check, so it runs EVERY 60 frames forever. Idempotent and cheap.
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

F3MOD = { version = VERSION, inspect = true }

local AGE_NAME = { [0] = "BABY", [1] = "CHILD", [2] = "ADULT", [3] = "ELDER", [4] = "NONE" }

local function box(text)
    if has(GUI, "DisplayMessageBox") then
        GUI.DisplayMessageBox(text)
    end
end

local function ask(text)
    if has(GUI, "AskYesNoQuestion") then
        return GUI.AskYesNoQuestion(text, F3MOD) == true
    end
    return false
end

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

function F3MOD.menu(hero)
    if not ask("F3MOD MENU - open it?") then
        return
    end
    if ask("Give 10,000 gold?") and has(Money, "Add") then
        Money.Add(hero, 10000, 0)
    end
    if ask("Refill health?") and Health ~= nil and has(Health, "FillHealth") then
        Health.FillHealth(hero)
    end
    if ask("Inspector " .. (F3MOD.inspect and "is ON. Turn it OFF?" or "is OFF. Turn it ON?")) then
        F3MOD.inspect = not F3MOD.inspect
    end
    box("F3MOD: menu closed.")
end

if GeneralScriptManager ~= nil and has(GeneralScriptManager, "AddScript") then
    local w = { _Name = "F3MOD_WORKER" }

    function w:Update()
        local seen = {}
        local last_id = nil
        local menu_cool = 0

        while true do
            local hero = GetLocalHero and GetLocalHero()
            local boxed = has(GUI, "IsDisplayBoxActive") and GUI.IsDisplayBoxActive()
            if menu_cool > 0 then
                menu_cool = menu_cool - 1
            end

            if hero and not boxed and has(Targeting, "GetTarget") then
                local t = Targeting.GetTarget(hero)
                if t ~= nil and t:IsAlive() then
                    local dog = GetDog ~= nil and GetDog(hero) or nil
                    if dog ~= nil and t == dog then
                        if menu_cool == 0 then
                            menu_cool = 300
                            F3MOD.menu(hero)
                        end
                    else
                        local id = tostring(t:GetName())
                        if id ~= last_id then
                            last_id = id
                            if F3MOD.inspect and not seen[id] then
                                seen[id] = true
                                box(F3MOD.describe(t))
                            end
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

box("F3MOD v20. Free camera is OFF and removed from the menu - it eats all input in"
    .. " retail. Dog = menu. Inspector: new entities once each.")
