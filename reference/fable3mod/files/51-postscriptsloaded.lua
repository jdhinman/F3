--[[ There were probably comments here
I'm using the debug retail post scripts
and following the line numbers.

This is going to be time consuming. But we
can't be having bugs with this one. It's
too important!


]]--
WatchDog = {}

-- function [0] definition (level 2)
function WatchDog:AddFunctionReplacementWatchDog(watch_dog)
	local name = nil
	
	for watch_dog_name,watch_dog_table in pairs(WatchDog) do
		if watch_dog_table == watch_dog then
			name = watch_dog_name
		else
		end
	end
	--[Keshire] I don't think this is right
	if name then
		name = "WatchDog_" .. name
		watch_dog._Name = name
		
		local already_running = false
		
		local l = GeneralScriptManager.CurrentlyRunningScripts
		if l then
			if l.value._Name == name then
				already_running = true
			else
				
				l = l.next
			
			end
		elseif not already_running then
			GeneralScriptManager.AddScript(watch_dog)
		end
	else
			Debug.Error("Could not find item in WatchDog table")
	end
end
  
-- function [1] definition (level 2)  
function ApplyWatchDogsWithVersionGreaterThan(applied_watchdog_version)

	if applied_watchdog_version == 0 then
	
		applied_watchdog_version = 1
		
	end
	
	if applied_watchdog_version == 1 then
	
		GeneralScriptManager.AddScript(WatchDog.ChestyChessLevelLoad)
		GeneralScriptManager.AddScript(WatchDog.ChestyChessLiveFakeGame)
		GeneralScriptManager.AddScript(WatchDog.SakerFightMercenaries)
		GeneralScriptManager.AddScript(WatchDog.CaptureNigelRenegadeCaptains)
		GeneralScriptManager.AddScript(WatchDog.ReEnableEliseThread)
		GeneralScriptManager.AddScript(WatchDog.StopSamDisablingHollows)
		GeneralScriptManager.AddScript(WatchDog.HittableJammy)
		GeneralScriptManager.AddScript(WatchDog.LibraryDoorRegionLock)
		GeneralScriptManager.AddScript(WatchDog.MissingPlayCutscene)
		GeneralScriptManager.AddScript(WatchDog.MarriageDuringCustomVillagerQuestStart)
		GeneralScriptManager.AddScript(WatchDog.MarriageDuringCustomVillagerQuestStart2)
		GeneralScriptManager.AddScript(WatchDog.PreventSamuelPromiseSceneWhilstCriminal)
		GeneralScriptManager.AddScript(WatchDog.MarriageMillfieldsTurnOffCreatureGens)
		GeneralScriptManager.AddScript(WatchDog.QC090_WarehouseVaultline)
		GeneralScriptManager.AddScript(WatchDog.DervishSlavesLockout)
		GeneralScriptManager.AddScript(WatchDog.TableTopSetHeroAsNonInteractable)
		GeneralScriptManager.AddScript(WatchDog.QC100_WalterBallsTriggerFix)
		GeneralScriptManager.AddScript(WatchDog.BalvForestMultipleStatueFixUp)
		GeneralScriptManager.AddScript(WatchDog.QC100_WalterFirstBarrierPush)
		GeneralScriptManager.AddScript(WatchDog.TableTopCutoutsHittableFixUp)
		GeneralScriptManager.AddScript(WatchDog.QC015_FirstBatEncounterBug)
		GeneralScriptManager.AddScript(WatchDog.ChestyChessInteractTeleport)
		GeneralScriptManager.AddScript(WatchDog.QO170_UpdatingBreadCrumbTrail)
		GeneralScriptManager.AddScript(WatchDog.GTMCounterFixUp)
		GeneralScriptManager.AddScript(WatchDog.GoldDoorGTMCounterOldRepositoryFixUp)
		GeneralScriptManager.AddScript(WatchDog.ArrowBlockShockPuzzleFixUp)
		GeneralScriptManager.AddScript(WatchDog.SkormRuinsGTMCounterFixUp)
		GeneralScriptManager.AddScript(WatchDog.NewMillfieldsStatueGTMCounterFixUp)
		GeneralScriptManager.AddScript(WatchDog.BalverinesPart2BalverineSafetyNet)
		GeneralScriptManager.AddScript(WatchDog.MoveBernardBack)
		GeneralScriptManager.AddScript(WatchDog.BowerstoneRenownBreakPrimaryQuestUpdate)
		GeneralScriptManager.AddScript(WatchDog.FinalHobbeBattleHeroInteraction)
		GeneralScriptManager.AddScript(WatchDog.RulingPart1IndustrialChild)
		GeneralScriptManager.AddScript(WatchDog.RulingPart2OptionalPrimary)
		GeneralScriptManager.AddScript(WatchDog.MissingPlayCameraCut)
		GeneralScriptManager.AddScript(WatchDog.RelationshipCourierRecipientCleanUp)
		GeneralScriptManager.AddScript(WatchDog.SamMaxSpikeRoomFixUp)
		GeneralScriptManager.AddScript(WatchDog.LayerFixUpMovedToWatchdog)
		GeneralScriptManager.AddScript(WatchDog.AddChickenChaserCallBack)
		GeneralScriptManager.AddScript(WatchDog.RulingPart1CrowdDeletion)
		
		DLC_ItemAwardMonitorThread = DLC_ItemAwardMonitor:new()
		
		QuestManager.AddQuestThread(DLC_ItemAwardMonitorThread, QuestManager.UpdateLists.MAIN_GAME)
		QuestManager.AddQuestThread(DLC_ItemAwardMonitorThread, QuestManager.UpdateLists.GUI)
		
		applied_watchdog_version = 2
		
	end
	
	if applied_watchdog_version == 2 then
	
		GeneralScriptManager.AddScript(WatchDog.RulingPt2HenchmanTriggerFixUp)
		GeneralScriptManager.AddScript(WatchDog.QC080DieWhenLostAllRoundsFixUp)
		GeneralScriptManager.AddScript(WatchDog.QC090QuestSuspensionFixUp)
		GeneralScriptManager.AddScript(WatchDog.TableTopCompleteBreadyTrailFixUp)
		GeneralScriptManager.AddScript(WatchDog.QO040EndInteractionThreadsFixUp)
		GeneralScriptManager.AddScript(WatchDog.QC020NoSirWalterFixUp)
		GeneralScriptManager.AddScript(WatchDog.QC010_OpeningJudgementBlackScreen)
		GeneralScriptManager.AddScript(WatchDog.QO020GnomesGargoyleAlreadyPickedUpFixUp)
		GeneralScriptManager.AddScript(WatchDog.TableTopAddTimerToFixNoVaultIssue)
		GeneralScriptManager.AddScript(WatchDog.AddChickenChaserFadeInReplacement)
		GeneralScriptManager.AddScript(WatchDog.GuildSealsRequired_GypsiesRenownBreak)
		GeneralScriptManager.AddScript(WatchDog.GuildSealsRequired_BowerstoneRenownBreak)
		GeneralScriptManager.AddScript(WatchDog.MapTutorialMapAbilityFix)
		GeneralScriptManager.AddScript(WatchDog.QO080HollowmenDieWhenLost)
		GeneralScriptManager.AddScript(WatchDog.QO060NastySpousePlacement)
		GeneralScriptManager.AddScript(WatchDog.QO170DieWhenLost)
		GeneralScriptManager.AddScript(WatchDog.QO160_RogueScriptRule)
		GeneralScriptManager.AddScript(WatchDog.QO040_CantCompleteChickenChaser)
		GeneralScriptManager.AddScript(WatchDog.ButlerTalkManagerRecoveryThread)
		GeneralScriptManager.AddScript(WatchDog.ButlerEventMonitorRecoveryThread)
		GeneralScriptManager.AddScript(WatchDog.AuroraFlitSwitchGTMFixUp)
		GeneralScriptManager.AddScript(WatchDog.RoadToRuleLoaderRecoveryThread)
		GeneralScriptManager.AddScript(WatchDog.BalverineForestDieWhenLost)
		GeneralScriptManager.AddScript(WatchDog.QC020_GivingSingleItemsAway)
		GeneralScriptManager.AddScript(WatchDog.CleanUpMapTutorialSpeech)
		GeneralScriptManager.AddScript(WatchDog.CleanUpSurplussCrateCarriers)
		GeneralScriptManager.AddScript(WatchDog.DestroyFactoryWorkersIfSchoolOpened)
		GeneralScriptManager.AddScript(WatchDog.LockedOutsideSamuelPromise)
		GeneralScriptManager.AddScript(WatchDog.GonDAchievementFixUp)
		GeneralScriptManager.AddScript(WatchDog.MarketBattleDisableSimIcons)
		
		applied_watchdog_version = 3
		
	end
	
	WatchDog.AddFunctionReplacementWatchDog(WatchDog.ChestyChessLoadSaveAnimatedPieces)
	
	return applied_watchdog_version
	
end
  
  
AddFunctionsInTableToPermanentsTables(WatchDog, "WatchDog")

if not IsLoadedFromSaveGame() then
	PlutoPermanentsLoadTable = nil
end

--[[ There were probably comments here






]]--

WatchDog.ChestyChessLoadSaveAnimatedPieces = {}
-- function [2] definition
function WatchDog.ChestyChessLoadSaveAnimatedPieces:Update()
	if IsLevelLoaded("optional\\sunset house") then
		local name_filter = function(entity)
			if string.find(entity:GetName(), "ChessPiece") then
				return true
			else
				return false
			end
		end

		local search = SearchTools.StartNewSearch("creature")
		SearchTools.FilterWithScriptFilter(search, name_filter)
		local remaining_pieces = SearchTools.GetSearchResults(search)

		local paused_idle = 
		{
			Type = EScriptableAction.PLAY_ANIMATION_HOLD_LAST_FRAME,
			Priority = EActionPriority.PRIORITY_INTERACTION,
			SpeedMultiplier = 1,
			Anim = "ChessIdle"
		}
		local chesty = ScriptFunction.GetEntityWithName("QO130_Chesty")
		local chesty_thread = QuestManager.EntitiesWithQuestThread[GetIDFromEntity(chesty)]
		
		for _,piece in pairs(remaining_pieces) do
			local piece_thread = QuestManager.EntitiesWithQuestThread[GetIDFromEntity(piece)]
			piece_thread:Tint()
			--[Keshire] Not sure
			if chesty_thread.CurrentState > chesty_thread.States.AFTER_BATTLE 
				or chesty_thread.CurrentState <= chesty_thread.States.END then
				Action.FinishAllActions(piece)
				Action.SetCurrentAction(piece, paused_idle)
			end
		end
	end
end



WatchDog.ChestyChessLiveFakeGame = {}
-- function [3] definition
function WatchDog.ChestyChessLiveFakeGame:Update()
	local rule_activated = false
	--[Keshire] I think this whole thing is WRONG!
	while rule_activated do
		coroutine.yield()
		local quest = QuestManager.GetQuestInstanceWithName("QO130_Chess")
		if quest then
		
			if Gameflow and Gameflow.Chess then
				if Gameflow.Chess.InFakeGame then
					if quest.ChestyOpened and not rule_activated then
						Player.AddGlobalScriptRules(EInteractiveCutsceneRule.CUTSCENE_RULE_NO_HERO_MOVE,"QO130_FakeGameNoMove",EInteractiveCutsceneRuleScope.CUTSCENE_RULE_SCOPE_ALWAYS)
							--"QO130_FakeGameNoMove",
							--EInteractiveCutsceneRuleScope.CUTSCENE_RULE_SCOPE_ALWAYS)
						rule_activated = true
					end
				elseif Gameflow.Chess.InFakeGame ~= rule_activated then	
					if rule_activated then
						Player.RemoveGlobalScriptRules(EInteractiveCutsceneRule.CUTSCENE_RULE_NO_HERO_MOVE,"QO130_FakeGameNoMove",EInteractiveCutsceneRuleScope.CUTSCENE_RULE_SCOPE_ALWAYS)
							--"QO130_FakeGameNoMove",
							--EInteractiveCutsceneRuleScope.CUTSCENE_RULE_SCOPE_ALWAYS)
							
					break end
				break end
			end
		end
	end
end


WatchDog.ChestyChessLevelLoad = {}
function WatchDog.ChestyChessLevelLoad:Update() end

WatchDog.HittableJammy = {}
function WatchDog.HittableJammy:Update() end

WatchDog.SakerFightMercenaries = {}
--[[
00015F  0000000C           [049] getglobal      0   0        ; WatchDog
000163  000B0086           [050] getfield_r1    0   0   11   ; SakerFightMercenaries
000167  000D1988           [051] setfield_r1    0   12  269  ; _Name "WatchDog_SakerFightMercenaries"
--[Keshire] Is this right?? Let's go with it for now since it matches the replacement naming...
]]--
WatchDog.SakerFightMercenaries._Name = "WatchDog_SakerFightMercenaries"
function WatchDog.SakerFightMercenaries:Update() end

WatchDog.CaptureNigelRenegadeCaptains = {}
function WatchDog.CaptureNigelRenegadeCaptains:Update() end

WatchDog.ReEnableEliseThread = {}
function WatchDog.ReEnableEliseThread:Update() end

WatchDog.StopSamDisablingHollows = {}
WatchDog.StopSamDisablingHollows._Name = "WatchDog_StopSamDisablingHollows"
function WatchDog.StopSamDisablingHollows:Update() end

WatchDog.LibraryDoorRegionLock = {}
function WatchDog.LibraryDoorRegionLock:Update() end

WatchDog.MissingPlayCutscene = {}
WatchDog.MissingPlayCutscene._Name = "WatchDog_MissingPlayCutscene"
function WatchDog.MissingPlayCutscene:Update() end

WatchDog.MarriageDuringCustomVillagerQuestStart = {}
WatchDog.MarriageDuringCustomVillagerQuestStart._Name = "WatchDog_MarriageDuringCustomVillagerQuestStart"
function WatchDog.MarriageDuringCustomVillagerQuestStart:Update() end

WatchDog.MarriageDuringCustomVillagerQuestStart2 = {}
WatchDog.MarriageDuringCustomVillagerQuestStart2._Name = "WatchDog_MarriageDuringCustomVillagerQuestStart2"
function WatchDog.MarriageDuringCustomVillagerQuestStart2:Update() end

WatchDog.PreventSamuelPromiseSceneWhilstCriminal = {}
function WatchDog.PreventSamuelPromiseSceneWhilstCriminal:Update() end

WatchDog.MarriageMillfieldsTurnOffCreatureGens = {}
function WatchDog.MarriageMillfieldsTurnOffCreatureGens:Update() end

WatchDog.QC090_WarehouseVaultline = {}
WatchDog.QC090_WarehouseVaultline._Name = "WatchDog_QC090_WarehouseVaultline"
function WatchDog.QC090_WarehouseVaultline:Update() end

WatchDog.DervishSlavesLockout = {}
WatchDog.DervishSlavesLockout._Name = "WatchDog_DervishSlavesLockout"
function WatchDog.DervishSlavesLockout:Update() end

WatchDog.TableTopSetHeroAsNonInteractable = {}
function WatchDog.TableTopSetHeroAsNonInteractable:Update() end

WatchDog.QC100_WalterBallsTriggerFix = {}
WatchDog.QC100_WalterBallsTriggerFix._Name = "WatchDog_QC100_WalterBallsTriggerFix"
function WatchDog.QC100_WalterBallsTriggerFix:Update() end

WatchDog.BalvForestMultipleStatueFixUp = {}
function WatchDog.BalvForestMultipleStatueFixUp:Update() end

WatchDog.QC100_WalterFirstBarrierPush = {}
WatchDog.QC100_WalterFirstBarrierPush._Name = "WatchDog_QC100_WalterFirstBarrierPush"
function WatchDog.QC100_WalterFirstBarrierPush:Update() end

WatchDog.TableTopCutoutsHittableFixUp = {}
function WatchDog.TableTopCutoutsHittableFixUp:Update() end

WatchDog.QC015_FirstBatEncounterBug = {}
WatchDog.QC015_FirstBatEncounterBug._Name = "WatchDog_QC015_FirstBatEncounterBug"
function WatchDog.QC015_FirstBatEncounterBug:Update() end

WatchDog.ChestyChessInteractTeleport = {}
WatchDog.ChestyChessInteractTeleport._Name = "WatchDog_ChestyChessInteractTeleport"
function WatchDog.ChestyChessInteractTeleport:Update() end

WatchDog.QO170_UpdatingBreadCrumbTrail = {}
WatchDog.QO170_UpdatingBreadCrumbTrail._Name = "Watchdog_QO170_UpdatingBreadCrumbTrail"
function WatchDog.QO170_UpdatingBreadCrumbTrail:Update() end
function WatchDog.QO170_UpdatingBreadCrumbTrail:GetPageThread(entity_name) end

WatchDog.GTMCounterFixUp = {}
function WatchDog.GTMCounterFixUp:Update() end

WatchDog.ArrowBlockShockPuzzleFixUp = {}
function WatchDog.ArrowBlockShockPuzzleFixUp:Update() end

WatchDog.GoldDoorGTMCounterOldRepositoryFixUp = {}
function WatchDog.GoldDoorGTMCounterOldRepositoryFixUp:Update() end

WatchDog.SkormRuinsGTMCounterFixUp = {}
function WatchDog.SkormRuinsGTMCounterFixUp:Update() end

WatchDog.NewMillfieldsStatueGTMCounterFixUp = {}
function WatchDog.NewMillfieldsStatueGTMCounterFixUp:Update() end

WatchDog.BalverinesPart2BalverineSafetyNet = {}
WatchDog.BalverinesPart2BalverineSafetyNet._Name = "WatchDog_BalverinesPart2BalverineSafetyNet"
function WatchDog.BalverinesPart2BalverineSafetyNet:Update() end

WatchDog.MoveBernardBack = {}
function WatchDog.MoveBernardBack:Update() end

WatchDog.AddChickenChaserCallBack = {}
WatchDog.AddChickenChaserCallBack._Name = "WatchDog_WatchDog.AddChickenChaserCallBack" -- [Keshire] WTF?? That can't be working right...
function WatchDog.AddChickenChaserCallBack:Update() end

WatchDog.AddChickenChaserFadeInReplacement = {}
WatchDog.AddChickenChaserFadeInReplacement._Name = "WatchDog_AddChickenChaserFadeInReplacement"
function WatchDog.AddChickenChaserFadeInReplacement:Update() end

WatchDog.QO040_CantCompleteChickenChaser = {}
WatchDog.QO040_CantCompleteChickenChaser._Name = "WatchDog_QO040_CantCompleteChickenChaser"
function WatchDog.QO040_CantCompleteChickenChaser:Update() end

WatchDog.BowerstoneRenownBreakPrimaryQuestUpdate = {}
function WatchDog.BowerstoneRenownBreakPrimaryQuestUpdate:Update() end

WatchDog.FinalHobbeBattleHeroInteraction = {}
function WatchDog.FinalHobbeBattleHeroInteraction.Update() end

WatchDog.RulingPart1IndustrialChild = {}
WatchDog.RulingPart1IndustrialChild._Name = "WatchDog_RulingPart1IndustrialChild"
function WatchDog.RulingPart1IndustrialChild:Update() end

WatchDog.RulingPart2OptionalPrimary = {}
WatchDog.RulingPart2OptionalPrimary._Name = "Watchdog_RulingPart2OptionalPrimary"
function WatchDog.RulingPart2OptionalPrimary:Update() end

WatchDog.MissingPlayCameraCut = {}
WatchDog.MissingPlayCameraCut._Name = "WatchDog_MissingPlayCameraCut"
function WatchDog.MissingPlayCameraCut:Update() end

WatchDog.RelationshipCourierRecipientCleanUp = {}
function WatchDog.RelationshipCourierRecipientCleanUp:Update() end

WatchDog.SamMaxSpikeRoomFixUp = {}
function WatchDog.SamMaxSpikeRoomFixUp:Update() end

WatchDog.RulingPart1CrowdDeletion = {}
WatchDog.RulingPart1CrowdDeletion._Name = "Watchdog_RulingPart1CrowdDeletion"
function WatchDog.RulingPart1CrowdDeletion:Update() end

WatchDog.LayerFixUpMovedToWatchdog = {}
function WatchDog.LayerFixUpMovedToWatchdog:Update() end

WatchDog.TableTopEmotionTableFixUp = {}
function WatchDog.TableTopEmotionTableFixUp:Update() end

WatchDog.RulingPt2HenchmanTriggerFixUp = {}
function WatchDog.RulingPt2HenchmanTriggerFixUp:Update() end

WatchDog.QC080DieWhenLostAllRoundsFixUp = {}
function WatchDog.QC080DieWhenLostAllRoundsFixUp:Update() end

WatchDog.QC090QuestSuspensionFixUp = {}
function WatchDog.QC090QuestSuspensionFixUp:Update() end

WatchDog.TableTopCompleteBreadyTrailFixUp = {}
function WatchDog.TableTopCompleteBreadyTrailFixUp:Update() end

WatchDog.QO040EndInteractionThreadsFixUp = {}
function WatchDog.QO040EndInteractionThreadsFixUp:Update() end

WatchDog.QC020NoSirWalterFixUp = {}
function WatchDog.QC020NoSirWalterFixUp:Update() end

WatchDog.QC010_OpeningJudgementBlackScreen = {}
WatchDog.QC010_OpeningJudgementBlackScreen._Name = "WatchDog_QC010OpeningJudgementBlackScreen"
function WatchDog.QC010_OpeningJudgementBlackScreen:Update() end

WatchDog.QO020GnomesGargoyleAlreadyPickedUpFixUp = {}
function WatchDog.QO020GnomesGargoyleAlreadyPickedUpFixUp:Update() end

WatchDog.TableTopAddTimerToFixNoVaultIssue = {}
function WatchDog.TableTopAddTimerToFixNoVaultIssue:Update() end

WatchDog.GuildSealsRequired_GypsiesRenownBreak = {}
function WatchDog.GuildSealsRequired_GypsiesRenownBreak:Update() end

WatchDog.GuildSealsRequired_BowerstoneRenownBreak = {}
function WatchDog.GuildSealsRequired_BowerstoneRenownBreak:Update() end

WatchDog.MapTutorialMapAbilityFix = {}
function WatchDog.MapTutorialMapAbilityFix:Update() end

WatchDog.QO080HollowmenDieWhenLost = {}
WatchDog.QO080HollowmenDieWhenLost._Name = "WatchDog_QO080HollowmenDieWhenLost"
function WatchDog.QO080HollowmenDieWhenLost:Update() end

WatchDog.QO060NastySpousePlacement = {}
WatchDog.QO060NastySpousePlacement._Name = "WatchDog_QO060NastySpousePlacement"
function WatchDog.QO060NastySpousePlacement:Update() end

WatchDog.QO170DieWhenLost = {}
WatchDog.QO170DieWhenLost._Name = "WatchDog_QO170DieWhenLost"
function WatchDog.QO170DieWhenLost:Update() end

WatchDog.QO160_RogueScriptRule = {}
WatchDog.QO160_RogueScriptRule._Name = "WatchDog_QO160_RogueScriptRule"
function WatchDog.QO160_RogueScriptRule:Update() end

WatchDog.ButlerTalkManagerRecoveryThread = {}
function WatchDog.ButlerTalkManagerRecoveryThread:Update() end

WatchDog.ButlerEventMonitorRecoveryThread = {}
function WatchDog.ButlerEventMonitorRecoveryThread:Update() end

WatchDog.AuroraFlitSwitchGTMFixUp = {}
WatchDog.AuroraFlitSwitchGTMFixUp._Name = "WatchDog_AuroraFlitSwitchGTMFixUp"
function WatchDog.AuroraFlitSwitchGTMFixUp:Update() end

WatchDog.RoadToRuleLoaderRecoveryThread = {}
function WatchDog.RoadToRuleLoaderRecoveryThread:Update() end

WatchDog.BalverineForestDieWhenLost = {}
WatchDog.BalverineForestDieWhenLost._Name = "WatchDog_BalverineForestDieWhenLost"
function WatchDog.BalverineForestDieWhenLost:Update() end

WatchDog.QC020_GivingSingleItemsAway = {}
WatchDog.QC020_GivingSingleItemsAway._Name = "WatchDog_QC020_GivingSingleItemsAway"
function WatchDog.QC020_GivingSingleItemsAway:Update() end

WatchDog.CleanUpMapTutorialSpeech = {}
function WatchDog.CleanUpMapTutorialSpeech:Update() end

WatchDog.CleanUpSurplussCrateCarriers = {}
function WatchDog.CleanUpSurplussCrateCarriers:Update() end

WatchDog.DestroyFactoryWorkersIfSchoolOpened = {}
function WatchDog.DestroyFactoryWorkersIfSchoolOpened:Update() end
function WatchDog.DestroyFactoryWorkersIfSchoolOpened:DestroyVillagersOfJobTypeWithNoWorkplace(village_entity,job_type) end

WatchDog.LockedOutsideSamuelPromise = {}
WatchDog.LockedOutsideSamuelPromise._Name = "WatchDog_LockedOutsideSamuelPromise"
function WatchDog.LockedOutsideSamuelPromise:Update() end

WatchDog.GonDAchievementFixUp = {}
WatchDog.GonDAchievementFixUp._Name = "WatchDog_GonDAchievementFixUp"
function WatchDog.GonDAchievementFixUp:Update() end

WatchDog.MarketBattleDisableSimIcons = {}
WatchDog.MarketBattleDisableSimIcons._Name = "WatchDog_MarketBattleDisableSimIcons"
function WatchDog.MarketBattleDisableSimIcons:Update() end

function ScriptFunction:Ghost(entity,alpha,r_tint,g_tint,b_tint) end
function ScriptFunction:Unghost(entity,time,alpha,r_tint,g_tint,b_tint) end
function ScriptFunction:CanTravelToRoadToRuleLevel(hero_entity,ignore_fade_checks) end
function ScriptFunction:AddUpgradeStatToWeapon(params) end
function Orchestra:UpdateInstantChangeValues(self) end
function Orchestra:ListenForSpecialMessages(self,messages) end
function BehaviourBase:MoveToEntityNoWait(self,entity,radius,speed,deceleration_time,reset_constraints,check_for_arrival) end
function BehaviourCombat:SlowExit(self,maintained_modes) end
function InteractiveCutsceneGroupMind:SetAsActive(self) end
function GUI_RoomEventsMonitor:PromoteDLCOnGUIEntry(self) end
function GUI_RoomEventsMonitor:PromoteDLC(self) end
function JobCoordinator:ForceCommunityJobOnPlayer(village,player_entity,debt_to_pay) end
function GenericTriggerMarker:OnLevelLoad(self) end
function QuestManager:GetSaveTable() end
function QuestManager:LoadFromSave(save_table) end

AddFunctionsInTableToPermanentsTables(Fable2Scripts, "F2S")
AddFunctionsInTableToPermanentsTables(BaseObjects, "BO")