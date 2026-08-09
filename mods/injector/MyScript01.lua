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

local VERSION = 23

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

local function ask(text)
    if has(GUI, "AskYesNoQuestion") then
        return GUI.AskYesNoQuestion(text, F3MOD) == true
    end
    return false
end

-- Numeric input via the betting/haggling spinner. Shape copied from the chicken-racing
-- bet in qv020. caller.LastPosted is the watermark it advances; seed it or the first
-- call could match a stale reply.
local function ask_amount(title, minv, maxv, step, default)
    if not (has(GUI, "AskForAmount") and EAdjusterTypes ~= nil and has(MessageEvents, "GetMostRecentMessageID")) then
        return nil
    end
    F3MOD.LastPosted = MessageEvents.GetMostRecentMessageID()
    local hero = GetLocalHero and GetLocalHero()
    local amount, accepted = GUI.AskForAmount(F3MOD, {
        Type = EAdjusterTypes.ADJUSTER_TYPE_MONEY,
        MinVal = minv,
        MaxVal = maxv,
        Increment = step,
        DefaultVal = default,
        ShowSign = false,
        Title = title,
        SelectionText = title,
        ShowEstimate = false,
        PlayerEntity = hero,
    }, title, default)
    if accepted then
        return amount
    end
    return nil
end

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

function F3MOD.menu(hero)
    if not ask("F3MOD MENU - open it?") then
        return
    end
    if ask("Set gold to an exact amount?") and has(Money, "Get") then
        local current = Money.Get(hero)
        local wanted = ask_amount("Set gold", 0, 1000000, 100, current)
        if wanted ~= nil and wanted ~= current then
            if wanted > current and has(Money, "AddSilent") then
                Money.AddSilent(hero, wanted - current, 0)
            elseif wanted < current and has(Money, "RemoveSilent") then
                Money.RemoveSilent(hero, current - wanted, 0)
            end
        end
    end
    if ask("Refill health?") and Health ~= nil and has(Health, "FillHealth") then
        Health.FillHealth(hero)
    end
    if ask("HUD inspector " .. (F3MOD.inspect and "is ON. Turn it OFF?" or "is OFF. Turn it ON?")) then
        F3MOD.inspect = not F3MOD.inspect
    end
    box("F3MOD: menu closed.")
end

if GeneralScriptManager ~= nil and has(GeneralScriptManager, "AddScript") then
    local w = { _Name = "F3MOD_WORKER" }

    function w:Update()
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
                    elseif F3MOD.inspect and has(GUI, "SetCounter") then
                        local id = tostring(t:GetName())
                        if id ~= last_id then
                            last_id = id
                            local label, num = hudline(t)
                            GUI.SetCounter("F3MODInspector", label, num)
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

box("F3MOD v23. Menu gains numeric input: set your gold to an exact figure with the"
    .. " betting spinner. Dog = menu.")
