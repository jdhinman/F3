Gameflow.HerosParent = "_Mother"
Gameflow.Fable2HeroEndGender = "_Mother"

if not Layers.IsLayerActive("QD030_MistpeakValleyDemonDoorTransition") then
	QuestTracker.SetAsCompleted(GetLocalHero(), "QD030_MistpeakValleyDemonDoor")
	Layers.ActivateLayer("QD030_MistpeakValleyDemonDoorTransition")
end

if not Layers.IsLayerActive("QD020_BrightwallDemonDoorTransition") then
	QuestTracker.SetAsCompleted(GetLocalHero(), "QD020_BrightwallDemonDoor")
	Layer.ActivateLayer("QD020_BrightwallDemonDoorTransition")
end
