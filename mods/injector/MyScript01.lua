-- Probe, run once per 60 frames by DEMO001_ScriptInjector.
--
-- One-shot on purpose. A per-second effect would distort a playthrough, and once the
-- question "did this run at all" is answered, repeating it buys nothing.
--
-- Signal: gold jumps by exactly 1234, once. Unmistakable, and needs neither the debug
-- console nor the io library, whose presence in a release build is still unknown.

if not F3MOD_PROBE_DONE then
    local hero = GetLocalHero and GetLocalHero()
    if hero then
        Money.Add(hero, 1234, 0)
        F3MOD_PROBE_DONE = true

        if io and io.open then
            local f = io.open("C:\Games\Fable 3\f3mod-inject.txt", "a")
            if f then
                f:write("probe fired, money now ", tostring(Money.Get(hero)), "\n")
                f:close()
            end
        end
    end
end
