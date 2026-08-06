QuestManager.NewJobManagerThread("JobLuteHeroManager")

function JobLuteHeroManager:Init()
	self.Type = "STATIC"
	self.Duration = 20
	self.JobInstanceName = "JobLuteHeroInstance"
	
	self.JobData = {}
	
	if not IsDemoModeActive(EDemoMode.DEMO_2010_E3_BRIGHTWALL) then
		
		self.JobData[1] = {}
		self.JobData[1].Layer = "LH01_ActiveLayer"
		self.JobData[1].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[2] = {}
		self.JobData[2].Layer = "LH02_ActiveLayer"
		self.JobData[2].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[3] = {}
		self.JobData[3].Layer = "LH03_ActiveLayer"
		self.JobData[3].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[4] = {}
		self.JobData[4].Layer = "LH04_ActiveLayer"
		self.JobData[4].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[5] = {}
		self.JobData[5].Layer = "LH01_ActiveLayer"
		self.JobData[5].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[6] = {}
		self.JobData[6].Layer = "LH02_ActiveLayer"
		self.JobData[6].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[7] = {}
		self.JobData[7].Layer = "LH03_ActiveLayer"
		self.JobData[7].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[8] = {}
		self.JobData[8].Layer = "LH04_ActiveLayer"
		self.JobData[8].AvailableFromChapter = Chapters.BrightwallHeroTest
		
	end

end

function JobLuteHeroManager:Update()
	while true do
		self:WaitUntilNextCheck()
		
		local job_to_start = self:GetRunnableJobKey()
		if job_to_start then
			self:StartJobInstance(job_to_start)
		end
	end
end

LuteHeroCrowdBalance = {}
LuteHeroCrowdBalance.CROWD_EMOTION_MAX = 200
LuteHeroCrowdBalance.CROWD_EMOTION_MIN = -100
LuteHeroCrowdBalance.CROWD_CHEER_THRESH = 150
LuteHeroCrowdBalance.CROWD_IDLE_THRESH = -50
LuteHeroCrowdBalance.GOOD_STRUM_DELTA = 5
LuteHeroCrowdBalance.BAD_STRUM_DELTA = -50
LuteHeroCrowdBalance.GOOD_ROUND_DELTA = 10
LuteHeroCrowdBalance.BAD_ROUND_DELTA = -100
LuteHeroCrowdBalance.GOOD_STREAK_THRESH = 4
LuteHeroCrowdBalance.BAD_STREAK_THRESH = 3
LuteHeroCrowdBalance.GOOD_STREAK_DELTA = 5
LuteHeroCrowdBalance.BAD_STREAK_DELTA = -30
LuteHeroCrowdBalance.MULTIPLIER_DOWN_DELTA = -150

JobCoordinator.JobManagerThreads.JobLuteHeroManager = JobLuteHeroManager:new()
QuestManager.AddQuestThread(JobCoordinator.JobManagerThreads.JobLuteHeroManager)

function HeroJobController:SetupLuteHero() 
	self:SetupCommon({
		JobCode = "QJ003",
		FOV = 24
	})
	
	self:SetupLuteMusic()
	SoundTools.StopMainMusic()
	
	self.AnimIdle = "LuteHeroIdle"
	self.AnimSheathe = "LuteHeroSheathe"
	self.AnimStrum = "LuteHeroStrum"
	self.AnimStrumDoNothing = "LuteHeroStrumDoNothing"
	self.AnimStrumFail = "LuteHeroStrumFail"
	self.AnimStrumSuccess = "LuteHeroStrumSuccess"
    self.AnimStrumWrongNote = "LuteHeroStrumWrongNote"
    self.AnimUnsheathe = "LuteHeroUnsheathe"
	
	ScriptFunction.WaitForFrames(1)
	
	self.PlayedNoteOnHero = false
	
	self:UnsheatheLuteHero()
	
	Stats.SetRichPresenceText(self.EntityUsingItem, "RichPresenceLuteHero")
	
	if Gameflow.JobLuteAchievementTotal == nil then
		Gameflow.JobLuteAchievementTotal = 0
	end
end

function HeroJobController:AddHelperGuiLuteHero() 
	TutorialManager.DisplayTutorial(ETutorialType.TUTORIAL_JOB_INSTRUCTIONS_LUTEHERO)
end

function HeroJobController:HideHelperGuiLuteHero(set_as_complete) 
	if TutorialManager.IsTutorialBeingDisplayed(ETutorialType.TUTORIAL_JOB_INSTRUCTIONS_LUTEHERO) then
		TutorialManager.StopTutorial(ETutorialType.TUTORIAL_JOB_INSTRUCTIONS_LUTEHERO, set_as_complete)
	end
end

function HeroJobController:SetupLuteMusic() 
	LuteSong1 = { 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12}
	LuteSong2 = { 2, 2, 2, 4, 6, 6, 1, 8, 4, 3, 7, 5}
	LuteSong3 = {12, 4, 6, 2, 7, 3, 1, 5, 9,10,11,12}
	LuteSong4 = { 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12}
	LuteSong5 = { 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12}
	-- [Keshire] um... Why did they create empty tables first?
	self.LuteSongBookLevel1 = {}
	self.LuteSongBookLevel1 = {LuteSong1,LuteSong2,LuteSong3}
	self.LuteSongBookLevel2 = {}
	self.LuteSongBookLevel2 = {LuteSong2,LuteSong2,LuteSong2}
	self.LuteSongBookLevel3 = {}
	self.LuteSongBookLevel3 = {LuteSong3,LuteSong3,LuteSong3}
	self.LuteSongBookLevel4 = {}
	self.LuteSongBookLevel4 = {LuteSong4,LuteSong4,LuteSong4}
	self.LuteSongBookLevel5 = {}
	self.LuteSongBookLevel5 = {LuteSong5,LuteSong5,LuteSong5}
	self.LuteSongBooks = {
		self.LuteSongBookLevel1,
		self.LuteSongBookLevel2,
		self.LuteSongBookLevel3,
		self.LuteSongBookLevel4,
		self.LuteSongBookLevel5
	}
end

function HeroJobController:SetUpDummiesAndTeleportLuteHero() 
	ScriptFunction.SetExclusionZoneAsActive("QJ003_Camera_ExclusionZone",true)
	
	local weapon = Carrying.GetEntityInSlot(self.EntityUsingItem,DummyObjects.SHEATHE_BACK)
	self.StoredWeapon = InventoryItem.GetItem(weapon)
	self.LuteEntity = Debug.CreateEntityByHero("ObjectInventoryLute")
	Carrying.PutEntityInSlot(self.EntityUsingItem,DummyObjects.SHEATHE_BACK,self.LuteEntity)
	
	local job_marker_description = "QJ003_PlayerMarker"
	local player_marker = ScriptFunction.GetEntityWithName(job_marker_description .. self.JobData.Location,"marker")
	Physics.TeleportToPosition(self.EntityUsingItem,player_marker:GetPosition())
	ScriptFunction.SetFacingVector(self.EntityUsingItem,Physics.GetFacingVector(player_marker))
	
	local dog_marker_description = "QJ003_DogMarker"
	if self.Dog:IsAlive() then
		local dogmarker = ScriptFunction.GetEntityWithName(dog_marker_description .. self.JobData.Location,"marker")
		Physics.TeleportToPosition(self.Dog,dogmarker:GetPosition())
		ScriptFunction.SetFacingVector(self.Dog,Physics.GetFacingVector(dogmarker))
		
		ScriptFunction.DogLieAtPosition(self.Dog,dogmarker:GetPosition(),{wait = false, speed = ENavigationSpeed.NAV_SPEED_RUN})
	end
	
	if Network.IsServer() then
		self.Simulants = {}
		self.Simulants[1] = ScriptFunction.GrabSimulant({
			age_group = EAgeGroup.EAGE_GROUP_ADULT,
			jobs_multiple = {EJobType.JOB_NONE,EJobType.JOB_GYPSY},
			gender = EGender.EG_MALE
		})
		ScriptFunction.SetEntityName(self.Simulants[1], "QJ003_CrowdMember" .. self.JobData.Location .. "_1")
		
		self.Simulants[2] = ScriptFunction.GrabSimulant({
			age_group = EAgeGroup.EAGE_GROUP_ADULT,
			jobs_multiple = {EJobType.JOB_NONE,EJobType.JOB_GYPSY},
			gender = EGender.EG_MALE
		})
		ScriptFunction.SetEntityName(self.Simulants[2], "QJ003_CrowdMember" .. self.JobData.Location .. "_2")
		
		self.Simulants[3] = ScriptFunction.GrabSimulant({
			age_group = EAgeGroup.EAGE_GROUP_ADULT,
			jobs_multiple = {EJobType.JOB_NONE,EJobType.JOB_GYPSY},
			gender = EGender.EG_FEMALE
		})
		ScriptFunction.SetEntityName(self.Simulants[3], "QJ003_CrowdMember" .. self.JobData.Location .. "_3")
		
		self.Simulants[4] = ScriptFunction.GrabSimulant({
			age_group = EAgeGroup.EAGE_GROUP_ADULT,
			jobs_multiple = {EJobType.JOB_NONE,EJobType.JOB_GYPSY},
			gender = EGender.EG_MALE
		})
		ScriptFunction.SetEntityName(self.Simulants[4], "QJ003_CrowdMember" .. self.JobData.Location .. "_4")

		self.Simulants[5] = ScriptFunction.GrabSimulant({
			age_group = EAgeGroup.EAGE_GROUP_ADULT,
			jobs_multiple = {EJobType.JOB_NONE,EJobType.JOB_GYPSY},
			gender = EGender.EG_FEMALE
		})
		ScriptFunction.SetEntityName(self.Simulants[5], "QJ003_CrowdMember" .. self.JobData.Location .. "_5")
		
		GroupEvent.CreateCrowdControl("LuteHeroJobCrowd")
		GroupEvent.SetCrowdRadius("LuteHeroJobCrowd",2)
		GroupEvent.SetMaxCrowdMembers("LuteHeroJobCrowd",10)
		GroupEvent.SetCrowdFocalEntity("LuteHeroJobCrowd",self.EntityUsingItem)
		
		local marker = nil
		for i,entity in pairs(self.Simulants) do
			marker = ScriptFunction.GetEntityWithName("QJ003_CrowdMarker" .. self.JobData.Location .. "_" .. i,"marker")
			Creature.PlaceNear(self.Simulants[i],marker,0)
			AIManager:TerminateAndExitBehaviours(self.Simulants[i])
			ScriptFunction.SetFacingEntity(self.Simulants[i],self.EntityUsingItem)
			Navigation.SetMovementPaused(self.Simulants[i],true)
		end
	end
end

function HeroJobController:IntoAndIdleAnimLuteHero() 
	local idle = {
		Type = EScriptableAction.LOOP,
		OverrideLooking = true,
		Priority = EActionPriority.PRIORITY_IDLE,
		LoopAction = {
			Type = EScriptableAction.PLAY_ANIMATION, 
			Anim = self.AnimIdle
		},
		NumLoops = 0
	}
	
	local strum = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimStrum,
		OverrideLooking = true,
		Priority = EActionPriority.PRIORITY_IDLE
	}
	
	local strum_to_idle_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {strum,idle}
	}
	
	Action.ReplaceCurrentAction(self.EntityUsingItem, strum_to_idle_loop_batch)
end

function HeroJobController:ClearupLuteHero() 
	if not self.HenchmanWentAWOL then
		ScriptFunction.WaitForFrames(1)
		self:SheatheLuteHero()
		ScriptFunction.WaitForFrames(2)
	end
	if Network.IsServer() then
		GroupEvent.EndCrowdControl("LuteHeroJobCrowd")
	end
	self:ClearUpCommon()
end

function HeroJobController:DestroyDummiesAndTeleportLuteHero() 
	ScriptFunction.SetExclusionZoneAsActive("QJ003_Camera_ExclusionZone" .. self.JobData.Location,false)
	
	if not self.HenchmanWentAWOL then
		local lute = Carrying.RemoveEntityFromSlot(self.EntityUsingItem,DummyObjects.HAND_RIGHT)
		if lute:IsAlive() then
			lute:Destroy()
		end
		local new_weapon = Inventory.InstantiateItem(self.EntityUsingItem,self.StoredWeapon,"No_Name_Needed")
		Carrying.PutWeaponInSheatheSlot(self.EntityUsingItem,new_weapon)
	end
	self.LuteEntity = nil
	
	if self.Dog:IsAlive() then
		ScriptFunction.DogStopLying(self.Dog)
	end
	self:ClearUpCouchSpectator(nil,nil)
	
	if Network.IsServer() then
		for i,entity in pairs(self.Simulants) do
			Navigation.SetMovementPaused(self.Simulants[i], false)
			-- [Keshire] why is this twice??
			Navigation.SetMovementPaused(self.Simulants[i], false)
		end
	end
	SoundTools.RestartMainMusic()
end

function HeroJobController:ReactToMessagesLuteHero() 
	self:ReactToMessagesCommon()
end

function HeroJobController:StrumSuccessLuteHero() 
	
	local idle = {
		Type = EScriptableAction.LOOP, 
		OverrideLooking = true, 
		Priority = EActionPriority.PRIORITY_IDLE,
		LoopAction = {
			Type = EScriptableAction.PLAY_ANIMATION,
			Anim = self.AnimIdle
		},
		NumLoops = 0
	}
	
	local strum_success = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimStrumSuccess,
		Priority = EActionPriority.PRIORITY_IDLE,
		OverrideLooking = true
	}
	
	local strum_success_to_idle_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {
			strum_success,
			idle
		}
	}
	
	Action.ReplaceCurrentAction(self.EntityUsingItem,strum_success_to_idle_loop_batch)
	
end

function HeroJobController:UnsheatheLuteHero()

	local idle = {
		Type = EScriptableAction.LOOP, 
		OverrideLooking = true, 
		Priority = EActionPriority.PRIORITY_IDLE,
		Anim = self.AnimIdle, --[Keshire] why is this declared outside of the loop action??
		LoopAction = {
			Type = EScriptableAction.PLAY_ANIMATION,
			Anim = self.AnimIdle
		},
		NumLoops = 0
	}
	
	local unsheathe = {
		Type = EScriptableAction.MOVE_TO_CARRY_SLOT,
		Anim = self.AnimUnsheathe,
		Priority = EActionPriority.PRIORITY_IDLE,
		SourceSlot = DummyObjects.SHEATHE_BACK,
		DestSlot = DummyObjects.HAND_RIGHT,
		OverrideLooking = true
	}
	
	local unsheathe_to_idle_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {
			unsheathe,
			idle
		}
	}	
	
	Action.ReplaceCurrentAction(self.EntityUsingItem,unsheathe_to_idle_loop_batch)
	
	while not self.HenchmanWentAWOL and not ScriptFunction.IsCurrentAnimNearEnd(self.EntityUsingItem) do
		coroutine.yield()
	end
end

function HeroJobController:SheatheLuteHero()
	
	local idle = {
		Type = EScriptableAction.LOOP, 
		OverrideLooking = true, 
		Priority = EActionPriority.PRIORITY_IDLE,
		LoopAction = {
			Type = EScriptableAction.PLAY_ANIMATION,
			Anim = self.AnimIdle
		},
		NumLoops = 0
	}
	
	local sheathe = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimSheathe,
		Priority = EActionPriority.PRIORITY_IDLE,
		OverrideLooking = true
	}
	
	local sheathe_to_idle_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {
			sheathe,
			idle
		}
	}	
	
	Action.ReplaceCurrentAction(self.EntityUsingItem,sheathe_to_idle_loop_batch)
	
end

function HeroJobController:StrumFailLuteHero()
	
	local idle = {
		Type = EScriptableAction.LOOP, 
		OverrideLooking = true, 
		Priority = EActionPriority.PRIORITY_IDLE,
		LoopAction = {
			Type = EScriptableAction.PLAY_ANIMATION,
			Anim = self.AnimIdle
		},
		NumLoops = 0
	}
	
	local strum_fail = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimStrumFail,
		Priority = EActionPriority.PRIORITY_IDLE,
		OverrideLooking = true
	}
	
	local strum_fail_to_idle_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {
			strum_fail,
			idle
		}
	}	
	
	Action.ReplaceCurrentAction(self.EntityUsingItem,strum_fail_to_idle_loop_batch)
	
end

function HeroJobController:ReactToRoundStartLuteHero()

	local current_lute_song_book = self.LuteSongBooks[self.JobData.CurrentLuteHeroLevel]
	local current_song_number = math.random(#current_lute_song_book)
	self.SongPlaying = current_lute_song_book[current_song_number]
	
end

function HeroJobController:PlayAnimHitLuteHero()

	local idle = {
		Type = EScriptableAction.LOOP, 
		OverrideLooking = true, 
		Priority = EActionPriority.PRIORITY_IDLE,
		LoopAction = {
			Type = EScriptableAction.PLAY_ANIMATION,
			Anim = self.AnimIdle
		},
		NumLoops = 0
	}
	
	local strum = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimStrum,
		Priority = EActionPriority.PRIORITY_IDLE,
		OverrideLooking = true
	}
	
	local strum_to_idle_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {
			strum,
			idle
		}
	}	
	
	Action.ReplaceCurrentAction(self.EntityUsingItem,strum_to_idle_loop_batch)
	
end

function HeroJobController:RespondToHitLuteHero()

	self:RespondToHitCommon()
	
	local chord_to_play = self.SongPlaying[self.SegmentsPassedThisRound]
	if chord_to_play then
		if chord_to_play < 10 then
			chord_to_play = "0"..tostring(chord_to_play)
		else
			chord_to_play = tostring(chord_to_play)
		end
		
		local entity_to_play_on = self.EntityUsingItem
		if self.PlayedNoteOnHero then
			entity_to_play_on = self.LuteEntity
		end

		Sound.PlayEvent(entity_to_play_on,"LUTE_CHORD_"..chord_to_play,"")
		self.PlayedNoteOnHero = not self.PlayedNoteOnHero -- [Keshire] First time I've ever seen a not gate used in code
		
	end
	self:CallJobDependentFunction("AdjustCrowdStrumSuccess")
	self:CallJobDependentFunction("CrowdResponse")
	
end

function HeroJobController:ReactToRoundEndLuteHero()
	local round_success
	round_success = nil
	if self.CorrectButtonsPressedThisRound/self.ButtonsPressedThisRound > 0.5 then
		round_success = true
	else
		round_success = false
	end
	
	self:ReactToRoundEndCommon(round_success)
	
	if Gameflow.JobLute5SBWV == nil then
		Gameflow.JobLute5SBWV = false
	end
	if Gameflow.JobLute5SSS == nil then
		Gameflow.JobLute5SSS = false
	end
	if Gameflow.JobLute5SBWSM == nil then
		Gameflow.JobLute5SBWSM = false
	end
	if Gameflow.JobLute5SMGC == nil then
		Gameflow.JobLute5SMGC = false
	end 
	
end

function HeroJobController:ActivateGossipLuteHero() 
	self:ActivateGossipCommon("Bard")
end

function HeroJobController:RespondToSuccessLuteHero() 
	self:RespondToSuccessCommon()
	self:CallJobDependentFunction("StrumSuccess")
	self:CallJobDependentFunction("AdjustCrowdRoundSuccess")
	self:CallJobDependentFunction("CrowdResponse")
	
	if self.JobData.CurrentLuteHeroLevel == 5 
		and self.CorrectButtonsPressedThisRound == self.ButtonsPressedThisRound
		and Stats.IsAvailable(self.EntityUsingItem) 
		and not Stats.HasUnlockedAchievement(self.EntityUsingItem,"ACH_LUTE_SOCIAL") then
	
		if IsHeroGameOwner(self.EntityUsingItem) then
			self.FixupAchievementProgress(self.EntityUsingItem)
		end
		
		Stats.AddSuccessForLuteHeroAchievement(self.EntityUsingItem)
	end
end

function HeroJobController:RespondToFailLuteHero()

	self:RespondToFailCommon()
	self:CallJobDependentFunction("StrumFail")
	self:CallJobDependentFunction("AdjustCrowdRoundFail")
	self:CallJobDependentFunction("CrowdResponse")

end

function HeroJobController:PlayAnimMissLuteHero() 

	local idle = {
		Type = EScriptableAction.LOOP, 
		OverrideLooking = true, 
		Priority = EActionPriority.PRIORITY_IDLE,
		LoopAction = {
			Type = EScriptableAction.PLAY_ANIMATION,
			Anim = self.AnimIdle
		},
		NumLoops = 0
	}
	
	local strum_wrong_note = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimStrumWrongNote,
		Priority = EActionPriority.PRIORITY_IDLE,
		SpeedMultiplier = 2,
		OverrideLooking = true
	}
	
	local strum_wrong_note_to_idle_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {
			strum_wrong_note,
			idle
		}
	}	
	
	Action.ReplaceCurrentAction(self.EntityUsingItem,strum_wrong_note_to_idle_loop_batch)

end

function HeroJobController:RespondToMissLuteHero()
	
	self:RespondToMissCommon()
	local entity_to_play_on = self.EntityUsingItem
	
	if self.PlayedNoteOnHero then
		entity_to_play_on = self.LuteEntity
	end
	
	Sound.PlayEvent(entity_to_play_on,"LUTE_WRONG_CHORD","")
	self.PlayedNoteOnHero = not self.PlayedNoteOnHero
	self:CallJobDependentFunction("AdjustCrowdStrumFail")
	self:CallJobDependentFunction("CrowdResponse")
	
end

function HeroJobController:RespondToMultiplierDownLuteHero()
	
	self:CallJobDependentFunction("AdjustCrowdMultiplierDown")
	
end

function HeroJobController:RespondToBlockMissLuteHero() 

	self:RespondToBlockMissCommon()
	self:CallJobDependentFunction("CrowdResponse")
	
end

function HeroJobController:CrowdResponseLuteHero()

	if Network.IsServer() then
		self.CrowdEmotionController = math.min(self.CrowdEmotionController,LuteHeroCrowdBalance.CROWD_EMOTION_MAX)
		self.CrowdEmotionController = math.max(self.CrowdEmotionController,LuteHeroCrowdBalance.CROWD_EMOTION_MIN)
		
		if self.CrowdEmotionController >= LuteHeroCrowdBalance.CROWD_CHEER_THRESH then
			GroupEvent.SetCrowdState("LuteHeroJobCrowd",ECrowdControlState.ECCS_CHEER)
			
		elseif self.CrowdEmotionController >= LuteHeroCrowdBalance.CROWD_IDLE_THRESH then
			GroupEvent.SetCrowdState("LuteHeroJobCrowd",ECrowdControlState.ECCS_IDLE)
		
		else
			GroupEvent.SetCrowdState("LuteHeroJobCrowd",ECrowdControlState.ECCS_BOO)
		end
	end
	
end

function HeroJobController:AdjustCrowdStrumSuccessLuteHero()

	self.CrowdEmotionController = self.CrowdEmotionController + LuteHeroCrowdBalance.GOOD_STRUM_DELTA
	self:CallJobDependentFunction("AdjustCrowdStreak")
	
end

function HeroJobController:AdjustCrowdStrumFailLuteHero()

	self.CrowdEmotionController = self.CrowdEmotionController + LuteHeroCrowdBalance.BAD_STRUM_DELTA
	self:CallJobDependentFunction("AdjustCrowdStreak")

end

function HeroJobController:AdjustCrowdRoundSuccessLuteHero()

	self.CrowdEmotionController = self.CrowdEmotionController + LuteHeroCrowdBalance.GOOD_ROUND_DELTA

end

function HeroJobController:AdjustCrowdRoundFailLuteHero() 

	self.CrowdEmotionController = self.CrowdEmotionController + LuteHeroCrowdBalance.BAD_ROUND_DELTA
	
end

function HeroJobController:AdjustCrowdStreakLuteHero() 

	if self.CorrectButtonsPressedInSequence >= LuteHeroCrowdBalance.GOOD_STREAK_THRESH then
		self.CrowdEmotionController = self.CrowdEmotionController + LuteHeroCrowdBalance.GOOD_STREAK_DELTA
	end
	
	if self.IncorrectButtonsPressedInSequence >= LuteHeroCrowdBalance.BAD_STREAK_THRESH then
		self.CrowdEmotionController = self.CrowdEmotionController + LuteHeroCrowdBalance.BAD_STREAK_DELTA
	end

end

function HeroJobController:AdjustCrowdMultiplierDownLuteHero()

	self.CrowdEmotionController = self.CrowdEmotionController + LuteHeroCrowdBalance.MULTIPLIER_DOWN_DELTA

end

function HeroJobController:SetIdleAnimLuteHero()

	local idle_loop = {
		Type = EScriptableAction.LOOP, 
		OverrideLooking = true, 
		Priority = EActionPriority.PRIORITY_IDLE,
		CanBeOverridenBySamePriority = true,
		LoopAction = {
			Type = EScriptableAction.PLAY_ANIMATION,
			Anim = self.AnimIdle
		},
		NumLoops = 0
	}
	
	Action.SetCurrentAction(self.EntityUsingItem,idle_loop)

end

function HeroJobController:UpdateMoneyLuteHero()

	self:UpdateMoneyCommon()

end

--function HeroJobController.FixupAchievementProgress()
HeroJobController.FixupAchievementProgress = function(player) -- [Keshire] they didn't want to use the default self parameter...
	if player and player:IsAlive() and Stats.IsAvailable(player) and not Stats.HasFixedUpLuteHero(player) then

		Stats.SetFixedUpLuteHero(player,true)
		
		if Gameflow.JobLute5SBWV == true then
			Stats.AddSuccessForLuteHeroLocationForAchievementFixup(player,"fable3","albion\\brightwallvillage")
		end
		if Gameflow.JobLute5SSS == true then
			Stats.AddSuccessForLuteHeroLocationForAchievementFixup(player,"fable3","aurora\\bloodweshare")
		end
		if Gameflow.JobLute5SBWSM == true then
			Stats.AddSuccessForLuteHeroLocationForAchievementFixup(player,"fable3","albion\\bwsmarket")
		end
		if Gameflow.JobLute5SMGC == true then
			Stats.AddSuccessForLuteHeroLocationForAchievementFixup(player,"fable3","albion\\mistpeak_gypsycamp")
		end
	end
end