-- Grow the hero's children from child to adult.
--
-- Install: copy to  <install>\data\scripts\startup\MyStartup.lua
-- Run the smoke test first (mods/smoke-test). If that does not produce a log, this will
-- not run either and you will be debugging the wrong thing.
--
-- UNTESTED. Nothing in this file has been run in game. It is written against API names
-- read out of the game's own decompiled scripts, which makes the names right; it does not
-- make the behaviour right.
--
-- Why this works at all, if it works: every adult AI gate in the shipped behaviours is an
-- ordinal test against the age group, e.g.
--     if ... and EAgeGroup.EAGE_GROUP_CHILD < Age.GetAgeGroup(self.Entity) then
-- so raising the group is what unlocks adult behaviour. See Notes/Child System.md.

local CHECK_EVERY_FRAMES = 60
local LOG = "f3mod-growup.txt"

local function log(message)
    local f = io.open(LOG, "a")
    if f then
        f:write(message, "\n")
        f:close()
    end
    if cprint then cprint("[growup] " .. message) end
end

-- Promote one child. Returns true if it changed something.
local function GrowUp(child)
    if not (child and child:IsAlive()) then return false end
    if not Age.IsAvailable(child) then return false end
    if Age.GetAgeGroup(child) ~= EAgeGroup.EAGE_GROUP_CHILD then return false end

    Age.SetAgeGroup(child, EAgeGroup.EAGE_GROUP_ADULT)
    -- Youngest adult rather than an arbitrary point in the band. SetAgeWithinAgeGroup is
    -- how the bonus-effect item adjusts age, so the scalar is separate from the group.
    if Age.SetAgeWithinAgeGroup then
        Age.SetAgeWithinAgeGroup(child, 0)
    end
    log("promoted " .. tostring(child:GetName()))
    return true
end

local function GrowUpAllChildren()
    local hero = GetLocalHero()
    if not (hero and PlayerFamily.IsAvailable(hero)) then return 0 end

    -- GetChildren takes two arguments: the parent, and the family member asking. The
    -- shipped scripts call it as GetChildren(spouse, self.Entity) and iterate with ipairs.
    local spouse = PlayerFamily.GetOrCreatePrimarySpouse(hero)
    if not spouse then return 0 end
    local children = PlayerFamily.GetChildren(hero, spouse)
    if children == nil then return 0 end

    local changed = 0
    for i, child in ipairs(children) do
        if GrowUp(child) then changed = changed + 1 end
    end
    return changed
end

-- A table with an Update method is the game's own unit of scheduling: AddScript turns
-- Update into a coroutine and resumes it once per tick, so coroutine.yield() is one frame.
-- See miscellaneous/GeneralScriptManager.lua.
local Watcher = { _Name = "GrowUpWatcher" }

-- The scheduler resumes Update with coroutine.resume and re-raises whatever comes back
-- (GeneralScriptManager.Update ends with `if not successful_run then error(error_message) end`),
-- so an error here becomes a game-wide error rather than a quiet stop. Wrap it. pcall does
-- not appear anywhere in the shipped scripts, so do not assume it exists.
local function protected(f)
    if pcall then return pcall(f) end
    return true, f()
end

function Watcher:Update()
    log("watcher started")
    while true do
        local ok, result = protected(GrowUpAllChildren)
        if not ok then
            log("error: " .. tostring(result))
        elseif result and result > 0 then
            log("promoted " .. result .. " child/children")
        end
        for i = 1, CHECK_EVERY_FRAMES do
            coroutine.yield()
        end
    end
end

if GeneralScriptManager and GeneralScriptManager.AddScript then
    GeneralScriptManager.AddScript(Watcher)
    log("registered")
else
    log("GeneralScriptManager.AddScript unavailable; nothing registered")
end
