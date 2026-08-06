-- Smoke test: prove that a user script runs at all.
--
-- Install: copy to  <install>\data\scripts\startup\MyStartup.lua
-- No edit to dir.manifest is needed. The shipped scripts\startup\startup.lua ends with
--   AddOptionalStartupScript("MyStartup.lua")
-- and dir.manifest already declares scripts\startup\mystartup.lua, which does not exist.
--
-- Success looks like: f3mod-smoke.txt appears next to Fable3.exe. If it does not, nothing
-- below this line is worth debugging yet; the hook itself is the thing under test.
--
-- Every call here was read out of the game's own decompiled scripts, so the names are
-- the engine's, not guesses.

-- The game's working directory is unknown, and a diagnostic that might have written its
-- output somewhere we did not look is worthless. Write to every candidate; whichever
-- succeeds also tells us what the working directory is.
-- ABS_PATH is the one certain answer. Edit it to your install if it differs.
local ABS_PATH = "C:\\Games\\Fable 3\\f3mod-smoke.txt"
local LOGS = { "f3mod-smoke.txt", "data\\f3mod-smoke.txt", "..\\f3mod-smoke.txt", ABS_PATH }

local function log(message)
    -- io is available: gameface\qbtext.lua calls io.open in the shipped scripts.
    if io and io.open then
        for i = 1, #LOGS do
            local f = io.open(LOGS[i], "a")
            if f then
                f:write(message, "\n")
                f:close()
            end
        end
    end
    -- cprint is the game's own console convention, 1690 uses across the corpus.
    if cprint then cprint("[f3mod] " .. message) end
end

log("MyStartup.lua ran")

-- GetPlatform and GetApplicationName are both called by the shipped startup.lua, so they
-- exist this early. Anything hero-related does not: there is no hero at startup.
if GetApplicationName then log("application: " .. tostring(GetApplicationName())) end
if GetPlatform then log("platform: " .. tostring(GetPlatform())) end

-- Defer anything that needs a world. GeneralScriptManager.CallFunction is how the shipped
-- StartupConsoleScript.lua defers its own work until after the hero exists.
if GeneralScriptManager and GeneralScriptManager.CallFunction then
    GeneralScriptManager.CallFunction(function()
        local hero = GetLocalHero and GetLocalHero()
        if hero then
            log("hero exists: " .. tostring(hero:GetName()))
        else
            log("deferred callback ran, but no hero")
        end
    end)
    log("deferred callback registered")
else
    log("GeneralScriptManager.CallFunction is not available at startup")
end
