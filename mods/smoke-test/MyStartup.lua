-- Smoke test: prove that a user script runs at all.
--
-- Install: copy to  <install>\data\scripts\startup\MyStartup.lua
-- No edit to dir.manifest is needed; it already declares scripts\startup\mystartup.lua,
-- and the shipped scripts\startup\startup.lua ends with
--   AddOptionalStartupScript("MyStartup.lua")
-- That line is present in gamescripts_r.bnk, which is the bank startup.vfsconfig actually
-- mounts, so the hook is in the code the retail game runs.
--
-- Three independent signals, because the first attempt at this test had only one and it
-- was the weakest of them.

-- 1. THE APPLICATION NAME. The primary signal, and the only one that needs nothing but a
--    function the shipped startup.lua itself calls four lines earlier. startup.lua sets
--    the name to "Fable III"; this runs later, so it wins. Check the window title and the
--    taskbar entry.
if SetApplicationName then
    SetApplicationName("Fable III [F3MOD]")
end

-- 2. A LOG FILE. Secondary, and no longer trusted: `io` appears exactly once in 797
--    shipped scripts, in a file with a hardcoded d:\Dev\ path, so it may well be a
--    development-only library. Guarded so its absence costs nothing.
local ABS_PATH = "C:\\Games\\Fable 3\\f3mod-smoke.txt"
local LOGS = { "f3mod-smoke.txt", "data\\f3mod-smoke.txt", "..\\f3mod-smoke.txt", ABS_PATH }

local function log(message)
    if io and io.open then
        for i = 1, #LOGS do
            local f = io.open(LOGS[i], "a")
            if f then
                f:write(message, "\n")
                f:close()
            end
        end
    end
    -- 3. THE CONSOLE. cprint is the game's own convention, 1690 uses across the corpus.
    --    Only visible with the debug console open.
    if cprint then cprint("[f3mod] " .. message) end
end

log("MyStartup.lua ran")
if GetApplicationName then log("application: " .. tostring(GetApplicationName())) end
if GetPlatform then log("platform: " .. tostring(GetPlatform())) end
log("io available: " .. tostring(io ~= nil))

-- Defer anything needing a world. GeneralScriptManager.CallFunction is how the shipped
-- StartupConsoleScript.lua defers its own work until after the hero exists. Renaming again
-- from inside the deferred callback distinguishes "startup ran" from "the scheduler is
-- also reachable", which are different amounts of good news.
if GeneralScriptManager and GeneralScriptManager.CallFunction then
    GeneralScriptManager.CallFunction(function()
        if SetApplicationName then
            SetApplicationName("Fable III [F3MOD-LIVE]")
        end
        local hero = GetLocalHero and GetLocalHero()
        log(hero and ("hero exists: " .. tostring(hero:GetName())) or "callback ran, no hero")
    end)
    log("deferred callback registered")
else
    log("GeneralScriptManager.CallFunction is not available at startup")
end
