-- Live-edit harness. Re-read once per 60 frames by DEMO001_ScriptInjector.
--
-- The probe answered: mask 255, so the whole Debug namespace survives retail, including
-- DrawText, CreateInstantFamily and Age.SetAgeGroup. Gold is a confirmed channel but a
-- terrible one - it costs a save-affecting side effect per message. This version tries to
-- get real text on screen, so the rest of the work has a proper output channel.
--
-- Two candidates, both now known to exist:
--   Debug.DrawText          - freecamera.lua drives it from a scheduled Update, exactly
--                             the shape used below. Lasts one frame, so it must be drawn
--                             every tick, which is why it cannot be called from this file.
--   GUI.DisplayMessageBox   - Keshire read the whole Debug table off these on the forum,
--                             so it renders arbitrary strings, not just localised ids.
--
-- CAREFUL: an error here propagates into the quest coroutine and GeneralScriptManager
-- re-raises it. pcall is in no shipped script. Nil-check everything.

local VERSION = 7

local function has(t, k)
    return t ~= nil and t[k] ~= nil
end

F3MOD_TEXT = "F3MOD v" .. VERSION .. " - text channel live"

-- ------------------------------------------------------- persistent on-screen text ---
-- Registered once and kept across edits; later edits only reassign F3MOD_TEXT.
if has(Debug, "DrawText") and F3MOD_HUD == nil and GeneralScriptManager ~= nil then
    F3MOD_HUD = { _Name = "F3MOD_HUD" }
    function F3MOD_HUD:Update()
        while true do
            if F3MOD_TEXT ~= nil then
                Debug.DrawText(F3MOD_TEXT, CI32Vector2(20, 100), 0, true)
            end
            coroutine.yield()
        end
    end
    GeneralScriptManager.AddScript(F3MOD_HUD)
end

-- ---------------------------------------------------------------- one-shot per edit ---
if F3MOD_VERSION ~= VERSION then
    local hero = GetLocalHero and GetLocalHero()
    local visible = hero
        and Money ~= nil
        and Money.IsAvailable ~= nil
        and Money.IsAvailable(hero)
        and not (GUI ~= nil and GUI.IsScreenFading ~= nil and GUI.IsScreenFading())
        and not (GUI ~= nil and GUI.IsAnyMenuOpen ~= nil and GUI.IsAnyMenuOpen())

    if visible then
        -- Debug text may be suppressed while the game's own GUI is hidden.
        if has(Debug, "SetDrawGUI") then
            Debug.SetDrawGUI(true)
        end

        -- One message box, once. Intrusive by design: it is the loudest channel we have.
        if has(GUI, "DisplayMessageBox") then
            GUI.DisplayMessageBox("F3MOD v7 text channel works")
        end

        -- Small and distinctive, so a silent screen still tells us the file ran.
        Money.Add(hero, 7, 0)
        F3MOD_VERSION = VERSION
    end
end
