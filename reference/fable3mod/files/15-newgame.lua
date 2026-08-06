QuestManager.NewThread(GameflowThreadBase, "NewGameManager")
	
function NewGameManager:Init()

end
function NewGameManager:StateEnum()

end
function NewGameManager:InitialSetup()

end
function NewGameManager:Update()

	while not GUILevel.IsLevelLoaded("PVP_GUI\\FrontEnd") do
		coroutine.yield()
	end 
	
	coroutine.yield()
	
	SetInitialHeroEntityName("CreatureHero")
	GUIPlayer.ChangePlayerEntityType(GetLocalHero(), "CreatureHero")
	
	SetInitialWorldName("Fable3")
	SetInitialLevelName("Albion\\BowerstoneCastle")
	--SetInitialScenarioName("DefaultScenario")
	SetInitialScenarioName("GOOD")
	SetGameflowScriptEnum("QC180")
	SetGameflowScriptState("THERESA")
	SetLevelNameStartsWithACS("Albion\\BowerstoneCastle")
	SetOpeningLoadingScreen(true)
	
	SetSavingAsAllowed(true)
	TutorialManager.SetToPlayNewExpressionLearnedTutorials(true)
	TutorialManager.SetTutorialsEnabled(true)
	self:SetDefaultCamera()
	
	GameComponentSwitchManager.SwitchToMainGameFromRetailFrontEnd()
	self:Terminate()
	coroutine.yield()
	
end
function NewGameManager:OnExit()
	
	-- Initiate BubbleMode functions --
	GeneralScriptManager.AddScript(BubbleMode)
	
end

QuestManager.AddQuestThread(NewGameManager:new(), QuestManager.UpdateLists.GUI)

-- Testing stuff --
BubbleMode = {}
function BubbleMode:Init()
end
function BubbleMode:Update()

	--ScriptFunction.FinishActiveCutscenes()
	Gameflow.RoadToRule.UNLOCK_EVERYTHING(GetLocalHero())
	Debug.AddAllDLC1Items()
	Debug.AddAllDLC2Items()
	QO100_UndergroundTown:State_ACCEPTED_SkipTo()
	Money.Add(GetLocalHero(), 10000000, 0)
	--Layers.DeactivateLayer("Layer_QO100_FactorySim")
	--Layers.DeactivateLayer("Layer_Understone_Locked")
	--Layers.ActivateLayer("Layer_Understone_Open")
	
	
	self:Terminate()
	coroutine.yield()
	
end
function BubbleMode:OnExit()
end