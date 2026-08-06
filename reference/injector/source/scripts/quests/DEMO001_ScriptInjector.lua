module(...,package.seeall)

QuestManager.NewQuestQuestThread("DEMO001_ScriptInjector")

function DEMO001_ScriptInjector:Init()

end

function DEMO001_ScriptInjector:State_START_SkipTo()

end

function DEMO001_ScriptInjector:State_START_Main()
	while true do
		coroutine.yield()

		-- executed once per 60 frames (one second on 60fps rendering)
		if mod_last_run == nil or mod_last_run + 60 < Timing.GetWorldFrame() then
			RunScript("scripts\\MyMod\\MyScript01.lua")
			mod_last_run = Timing.GetWorldFrame()
		end
		
		-- executed only when screen is fading
		if GUI.IsScreenFading() then
			RunScript("scripts\\MyMod\\MyScript02.lua")
		end

		-- DEBUG: script execution test
		-- Money.Add(GetLocalHero(), 1, 2)
	end
end

function DEMO001_ScriptInjector:OnExit()

end
