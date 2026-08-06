-- Rebuilt from this install's own gamescripts_r.bnk, so the RunScript list matches
-- what the game actually ships. The community copy came from a different build and
-- called six scripts that do not exist here.
if GetPlatform() == Platform.Xbox360 then
    package.path = "Game:\\data\\Scripts\\Quests\\?.lua"
else
    assert(GetPlatform() == Platform.Win32)
    package.path = "data\\Scripts\\Quests\\?.lua"
end
RunScript("Quests/QuestManager.lua")
RunScript("Quests/LuaEnums.lua")
RunScript("Quests/GenericTriggers.lua")
RunScript("Quests/DemoStartupSettings.lua")
RunScript("Quests/SavedVariables.lua")
RunScript("Quests/MiscFunctions.lua")
RunScript("Quests/CommunityService.lua")
RunScript("Quests/ChapterProgress.lua")
RunScript("Quests/ScriptActivation.lua")
RunScript("Quests/Gameflow.lua")
RunScript("Quests/JobCoordinator.lua")
if not IsDemoModeActive(EDemoMode.DEMO_2010_ALLHANDS) and (not IsDemoModeActive(EDemoMode.DEMO_2010_SHOWCASE) and not IsDemoModeActive(EDemoMode.DEMO_2010_GDC)) then
    RunScript("Quests/JobCommonScript.lua")
    RunScript("Quests/JobBlacksmithManager.lua")
    RunScript("Quests/JobCookingManager.lua")
    RunScript("Quests/JobLuteHeroManager.lua")
    RunScript("Quests/JobExampleManager.lua")
    RunScript("Quests/JobGeneratedManager.lua")
    RunScript("Quests/JobGeneratedMetaManager.lua")
    RunScript("Quests/QR200_RulingCivilManager.lua")
    RunScript("Quests/QOTF_FetchManager.lua")
    RunScript("Quests/QOTA_AssassinateManager.lua")
    RunScript("Quests/QOTC_CourierManager.lua")
    RunScript("Quests/QOTE_EscortManager.lua")
    RunScript("Quests/QOTP_FetchPersonManager.lua")
    RunScript("Quests/QOTM_PayMeMoneyManager.lua")
    RunScript("Quests/QS_RelationshipQuestManager.lua")
    RunScript("Quests/QRCH_RulerCreatureHunterManager.lua")
    RunScript("Quests/QP_ProtestsQuestManager.lua")
    RunScript("Quests/QDRAG_SlaveManager.lua")
    RunScript("Quests/QDRAG_CriminalManager.lua")
end
RunScript("Quests/RegionLocking.lua")
RunScript("Quests/HeroTrackers.lua")
RunScript("Quests/ScriptDebug.lua")
RunScript("Miscellaneous/GuildNew.lua")
RunScript("Miscellaneous/GuildRoomsSingle.lua")
RunScript("Miscellaneous/GuildRoomsSingleRemote.lua")
RunScript("Miscellaneous/GuildCallbackFunctions.lua")
RunScript("Miscellaneous/GuildUtilityFunctions.lua")
RunScript("Miscellaneous/GuildItemListFunctions.lua")
RunScript("Miscellaneous/GuildButler.lua")
RunScript("Miscellaneous/GuildButlerTalkManager.lua")
RunScript("Miscellaneous/GuildButlerRoomEventMonitor.lua")
RunScript("Miscellaneous/GuildButlerRoomEventCustomFunctions.lua")
RunScript("Miscellaneous/GuildButlerSpeechSituationManager.lua")
RunScript("Miscellaneous/GuildTutorialCallbacks.lua")
RunScript("Miscellaneous/DLC_ItemAwardMonitor.lua")
RunScript("Miscellaneous/NewGame.lua")

-- The hook: everything above is stock.
RunScript("Quests/scriptactivation_additional.lua")
