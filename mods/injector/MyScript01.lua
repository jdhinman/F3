-- Live-edit harness. Re-read and re-run once per 60 frames by DEMO001_ScriptInjector,
-- so saving this file applies within about a second. No restart.
--
-- Globals persist between runs (one Lua state), which is what makes the VERSION guard
-- work and what lets the HUD script below survive across edits.
--
-- CAREFUL: an error here propagates into the quest coroutine that calls us, and
-- GeneralScriptManager.Update re-raises it. That can take the injector down until a
-- reload. pcall is not in any shipped script so its presence is unverified. Therefore:
-- nil-check everything, index nothing blindly, and keep this file boring.

local VERSION = 4

-- ------------------------------------------------------------------ what exists ---
-- Retail may have stripped the Debug table. Nothing here assumes it did not.
local function has(t, k)
    return t ~= nil and t[k] ~= nil
end

local BITS = {
    { 1, Debug ~= nil },
    { 2, has(Debug, "DrawText") },
    { 4, has(Debug, "CreateInstantFamily") },
    { 8, has(Debug, "CreateFamily") },
    { 16, has(Debug, "SetUseFreeCamera") },
    { 32, has(Age, "SetAgeGroup") },
    { 64, has(PlayerFamily, "GetChildren") },
    { 128, has(Inventory, "AddItemOfType") },
}

local mask = 0
for i = 1, #BITS do
    if BITS[i][2] then mask = mask + BITS[i][1] end
end

F3MOD_TEXT = "F3MOD v" .. VERSION .. "  api=" .. mask
    .. "\nDebug=" .. tostring(Debug ~= nil)
    .. "  DrawText=" .. tostring(has(Debug, "DrawText"))
    .. "\nCreateInstantFamily=" .. tostring(has(Debug, "CreateInstantFamily"))
    .. "  SetAgeGroup=" .. tostring(has(Age, "SetAgeGroup"))

-- ------------------------------------------------------- a HUD that persists ---
-- Debug.DrawText lasts one frame, and this file only runs once a second, so drawing
-- from here would flash for a single frame. Register a scheduled script instead: its
-- Update becomes a coroutine resumed every tick, so it can draw every frame.
-- Registered once and kept across edits; later edits just change F3MOD_TEXT.
if has(Debug, "DrawText") and not F3MOD_HUD and GeneralScriptManager ~= nil then
    F3MOD_HUD = { _Name = "F3MOD_HUD" }
    function F3MOD_HUD:Update()
        while true do
            if F3MOD_TEXT ~= nil then
                Debug.DrawText(F3MOD_TEXT, CI32Vector2(30, 120), 0, true)
            end
            coroutine.yield()
        end
    end
    GeneralScriptManager.AddScript(F3MOD_HUD)
end

-- ----------------------------------------------- fallback: report through gold ---
-- With no io, no console and possibly no DrawText, the only channel left is state we
-- can see. Encode the same answer as a gold delta: 20000 + mask.
if F3MOD_VERSION ~= VERSION then
    local hero = GetLocalHero and GetLocalHero()
    local visible = hero
        and Money.IsAvailable(hero)
        and not (GUI ~= nil and GUI.IsScreenFading ~= nil and GUI.IsScreenFading())
        and not (GUI ~= nil and GUI.IsAnyMenuOpen ~= nil and GUI.IsAnyMenuOpen())

    if visible then
        if not has(Debug, "DrawText") then
            Money.Add(hero, 20000 + mask, 0)
        end
        F3MOD_VERSION = VERSION
    end
end
