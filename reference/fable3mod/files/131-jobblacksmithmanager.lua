QuestManager.NewJobManagerThread("JobBlacksmithManager")

function JobBlacksmithManager:Init()
	self.Type = "STATIC"
	self.Duration = 20
	self.JobInstanceName = "JobBlacksmithInstance"
	
	self.JobData = {}
	
	if not IsDemoModeActive(EDemoMode.DEMO_2010_E3_BRIGHTWALL) then
		
		self.JobData[1] = {}
		self.JobData[1].Layer = "BS01_ActiveLayer"
		self.JobData[1].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[2] = {}
		self.JobData[2].Layer = "BS02_ActiveLayer"
		self.JobData[2].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[3] = {}
		self.JobData[3].Layer = "BS03_ActiveLayer"
		self.JobData[3].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[4] = {}
		self.JobData[4].Layer = "BS01_ActiveLayer"
		self.JobData[4].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[5] = {}
		self.JobData[5].Layer = "BS02_ActiveLayer"
		self.JobData[5].AvailableFromChapter = Chapters.BrightwallHeroTest
		
		self.JobData[6] = {}
		self.JobData[6].Layer = "BS03_ActiveLayer"
		self.JobData[6].AvailableFromChapter = Chapters.BrightwallHeroTest
		
	end

end

function JobBlacksmithManager:Update()
	while true do
		self:WaitUntilNextCheck()
		
		local job_to_start = self:GetRunnableJobKey()
		if job_to_start then
			self:StartJobInstance(job_to_start)
		end
	end
end

JobCoordinator.JobManagerThreads.JobBlacksmithManager = JobBlacksmithManager:new()
QuestManager.AddQuestThread(JobCoordinator.JobManagerThreads.JobBlacksmithManager)

function HeroJobController:SetupBlacksmith() 

	local job_description = "QJ002_Anvil" -- This seems pointless when they didn't use locals for any other JobData stuff
	local dog_marker_description = "QJ002_DogHammeringMarker" -- [Keshire] so where does this get used??
	
	--Grab some globals
	self.Anvil = ScriptFunction.GetEntityWithName(job_description .. self.JobData.Location, "object")
	self.BlacksmithVoiceMarker = ScriptFunction.GetEntityWithName("QJ002_BlacksmithVoiceMarker" .. self.JobData.Location, "marker")
	
	self:SetupCommon({
		JobCode = "QJ002",
		AnimInto =       "BlacksmithInto",
		AnimIdle =       "BlacksmithLoop",
		AnimOutOf =      "BlacksmithOutOf",
		AnimHitFail =    "BlacksmithOutOfFailure",
		AnimHitSuccess = "BlacksmithOutOfSuccess",
		AnimHitNoLook =  "BlacksmithOutOfNoLook"
	})
	
	Sound.SetSoundVariableValue("SV_BLACKSMITH_ANVIL_GAIN", 0)
	self.BlacksmithMusic = SoundTools.PlayMusic("MUSIC_QJ001_BLACKSMITH_JOB")
	self.EventsUntilTalk = 1
	
	self.HitWindowTimer = QuestManager.NewTimer(0)
	Gameflow.HitWindow = 1
	self.HammerBlows = 0
	
	Gameflow.HitAnim = "BlacksmithHitFast" -- Is this even used??
	self.InIdleAnim = false
	
	self.Ingot = ScriptFunction.GetEntityWithName("BlacksmithIngot" .. self.JobData.Location, "object")
	
	if GraphicAppearance.HasDummyObject(self.Anvil, DummyObjects.PROP_POINT) then
		--[Keshire] This is where the sparks show up 
		self.AnvilFXPoint = GraphicAppearance.GetDummyObjectPosition(self.Anvil, DummyObjects.PROP_POINT, 0)
	end
	
	--Animation Handling
	self:SetUpJobStartAnimationBlacksmith()
	
	--I have no idea what this is used for...
	Stats.SetRichPresenceText(self.EntityUsingItem, "RichPresenceBlacksmith")

end

function HeroJobController:SetUpJobStartAnimationBlacksmith() 
	self:IntoAndIdleAnimBlacksmith()
end

function HeroJobController:AddHelperGuiBlacksmith() 
	TutorialManager.DisplayTutorial(ETutorialType.TUTORIAL_JOB_INSTRUCTIONS_BLACKSMITH)
end

function HeroJobController:HideHelperGuiBlacksmith(set_as_complete) 
	if TutorialManager.IsTutorialBeingDisplayed(ETutorialType.TUTORIAL_JOB_INSTRUCTIONS_BLACKSMITH) then
		TutorialManager.StopTutorial(ETutorialType.TUTORIAL_JOB_INSTRUCTIONS_BLACKSMITH, set_as_complete)
	end
end

function HeroJobController:SetUpDummiesAndTeleportBlacksmith() 

	--[Keshire] Is this even needed since it's defined in the main SetUp?
	if GraphicAppearance.HasDummyObject(self.Anvil, DummyObjects.PROP_POINT) then
		self.AnvilFXPoint = GraphicAppearance.GetDummyObjectPosition(self.Anvil, DummyObjects.PROP_POINT, 0)
	end
	
	--[Keshire] Teleport
	if GraphicAppearance.HasDummyObject(self.Anvil, DummyObjects.ACTION_GENERIC) then
		local dummy_pos = GraphicAppearance.GetDummyObjectPosition(self.Anvil, DummyObjects.ACTION_GENERIC, 0)
		local dummy_facing = GraphicAppearance.GetDummyObjectFacingDirection(self.Anvil, DummyObjects.ACTION_GENERIC, 0)
		
		Physics.TeleportToPosition(self.EntityUsingItem, dummy_pos)
		ScriptFunction.SetFacingVector(self.EntityUsingItem, dummy_facing)
	end
	
	--[Keshire] Attach a hammer
	local hammer = Debug.CreateEntityAt("ObjectSmithHammer", "BlacksmithHammer" .. self.JobData.Location, self.EntityUsingItem:GetPosition())
	Carrying.PutEntityInSlot(self.EntityUsingItem, DummyObjects.HAND_RIGHT, hammer)
	
	--[Keshire] Attach an Ingot
	self.Ingot = Debug.CreateEntityAt("MetalWork_Minigame_Stage1","BlacksmithIngot" .. self.JobData.Location, self.EntityUsingItem:GetPosition())
	ObjectAttachment.AddEntity(self.EntityUsingItem, self.Ingot, DummyObjects.HAND_LEFT, 0)
	
	--[Keshire] Move the dog...
	if self.Dog:IsAlive() then
		local dogmarker = ScriptFunction.GetEntityWithName("QJ002_DogHammeringMarker" .. self.JobData.Location, "marker")
		Physics.TeleportToPosition(self.Dog, dogmarker:GetPosition())
		ScriptFunction.SetFacingVector(self.Dog, Physics.GetFacingVector(dogmarker))
		ScriptFunction.DogLieAtPosition(self.Dog, dogmarker:GetPosition(), {wait = false, speed = ENavigationSpeed.NAV_SPEED_RUN})
	end
	
	--[Keshire] Is this the blacksmith's sign?? Or actual Hammer?
	Layers.DeactivateLayer("QJ002_JobBlacksmith_Hammer")

end

function HeroJobController:ReactToMessagesBlacksmith() 
	
	if self.MissDetected or self.BlockMissDetected or self.SuccessfulHitDetected > 0 then
		self:ReactToMessagesCommon()
	elseif not self.InIdleAnim then
		self:CallJobDependentFunction("SetIdleAnim")
		self.InIdleAnim = true
	end
	
end

function HeroJobController:RespondToHitBlacksmith() 
	self:RespondToHitCommon()
	
	Debug.CreateEntityAtPosition("FX_Smith_Hit_Ingot", "effect", self.AnvilFXPoint)

	self.HammerBlows = self.HammerBlows+1

	if self.HammerBlows == 3 and ObjectAttachment.IsEntityAttached(self.EntityUsingItem, self.Ingot) then
	
		self.Ingot:Destroy()
		self.Ingot = Debug.CreateEntityAt("MetalWork_Minigame_Stage2", "BlacksmithIngot" .. self.JobData.Location, self.EntityUsingItem:GetPosition())
		ObjectAttachment.AddEntity(self.EntityUsingItem, self.Ingot, DummyObjects.HAND_LEFT, 0)
		
	end
end

function HeroJobController:PlayAnimHitBlacksmith() 
	self:HitSuccessAndIdleAnimBlacksmith()
end

function HeroJobController:RespondToMissBlacksmith() 
	self:RespondToMissCommon()
end

function HeroJobController:PlayAnimMissBlacksmith() 
	self:HitFailAndIdleAnimBlacksmith()
end

function HeroJobController:RespondToBlockMissBlacksmith() 
	self:RespondToBlockMissCommon()
end

function HeroJobController:JobEndGoodCommentBlacksmith() 
	local text_group = "TEXT_QUEST_QJ002_GOOD_BLADE"
	if IsLevelLoaded("Aurora\\BloodWeShare") then
		text_group = "TEXT_QUEST_QJ002_AURORA_GOOD_BLADE"
	end	
	self:JobEndComment(text_group, "TEXT_QUEST_QJ002_NARRATOR_NAME")
end

function HeroJobController:JobEndBadCommentBlacksmith() 
	local text_group = "TEXT_QUEST_QJ002_BAD_BLADE"
	if IsLevelLoaded("Aurora\\BloodWeShare") then
		text_group = "TEXT_QUEST_QJ002_AURORA_BAD_BLADE"
	end	
	self:JobEndComment(text_group, "TEXT_QUEST_QJ002_NARRATOR_NAME")
end

function HeroJobController:ActivateGossipBlacksmith() 
	self:ActivateGossipCommon("Blacksmith")
end

function HeroJobController:ReactToRoundEndBlacksmith() 
	local round_success = false
	
	if self.CorrectButtonsPressedThisRound == self.ButtonsPressedThisRound then
		round_success = true
	end
	
	self:ReactToRoundEndCommon(round_success)

	self:OutOfAndIdleAnimBlacksmith()
	
	self:CompleteBladeBlacksmith()

	self:PickUpIngotBlacksmith()
	
end

function HeroJobController:RespondToSuccessBlacksmith() 
	self:RespondToSuccessCommon()
end

function HeroJobController:RespondToFailBlacksmith() 
	self:RespondToFailCommon()
end

function HeroJobController:UpdateMoneyBlacksmith() 
	self:UpdateMoneyCommon()
end

function HeroJobController:SetIdleAnimBlacksmith() 
	
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
	Action.SetCurrentAction(self.EntityUsingItem, idle_loop)
	
end

function HeroJobController:IntoAndIdleAnimBlacksmith() 
	
	local into = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimInto,
		Priority = EActionPriority.PRIORITY_IDLE,
		OverrideLooking = true
	}

	local loop = {
		Type = EScriptableAction.LOOP,
		OverrideLooking = true,
		Priority = EActionPriority.PRIORITY_IDLE,
		CanBeOverridenBySamePriority = true,
		LoopAction = {Type = EScriptableAction.PLAY_ANIMATION,Anim = self.AnimIdle},
		NumLoops = 0
	}
		
	local into_to_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {into,loop}
	}
		
	Action.ReplaceCurrentAction(self.EntityUsingItem,into_to_loop_batch)

end

function HeroJobController:OutOfAndIdleAnimBlacksmith() 
	
	local out_of = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimOutOf,
		Priority = EActionPriority.PRIORITY_IDLE,
		OverrideLooking = true
		}
	
	
	local into = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimInto,
		Priority = EActionPriority.PRIORITY_IDLE,
		OverrideLooking = true
		}

	
	local loop = {
		Type = EScriptableAction.LOOP,
		OverrideLooking = true,
		Priority = EActionPriority.PRIORITY_IDLE,
		CanBeOverridenBySamePriority = true,
		LoopAction = { Type = EScriptableAction.PLAY_ANIMATION, Anim = self.AnimIdle },
		NumLoops = 0
	}
		
	local out_of_to_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {
			out_of, 
			into, 
			loop
			}
		}
		
	Action.ReplaceCurrentAction(self.EntityUsingItem, out_of_to_loop_batch)
	
end

function HeroJobController:HitFailAndIdleAnimBlacksmith() 
	
	local hit_fail = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimHitFail,
		Priority = EActionPriority.PRIORITY_IDLE,
		OverrideLooking = true
	}

	
	local loop = {
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
		
	
	local hit_fail_to_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {
			hit_fail, 
			loop
		}
	}
		
	Action.ReplaceCurrentAction(self.EntityUsingItem, hit_fail_to_loop_batch)
	
end

function HeroJobController:HitSuccessAndIdleAnimBlacksmith() 
	
	local hit_success = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimHitSuccess,
		Priority = EActionPriority.PRIORITY_IDLE,
		OverrideLooking = true
	}

	
	local loop = {
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
		
	
	local hit_success_to_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {hit_success,loop}
	}
		
	Action.ReplaceCurrentAction(self.EntityUsingItem, hit_success_to_loop_batch)
	
end

function HeroJobController:HitSuccessNoLookAndIdleAnimBlacksmith() 
	
	local hit_success_no_look = {
		Type = EScriptableAction.PLAY_ANIMATION,
		Anim = self.AnimHitNoLook,
		Priority = EActionPriority.PRIORITY_IDLE,
		OverrideLooking = true
	}

	
	local loop = {
		Type = EScriptableAction.LOOP,
		OverrideLooking = true,
		Priority = EActionPriority.PRIORITY_IDLE,
		CanBeOverridenBySamePriority = true,
		LoopAction = {Type = EScriptableAction.PLAY_ANIMATION, Anim = self.AnimIdle},
		NumLoops = 0
	}
		
	
	local hit_success_no_look_to_loop_batch = {
		Type = EScriptableAction.BATCH,
		Actions = {hit_success_no_look,loop}
	}
		
	Action.ReplaceCurrentAction(self.EntityUsingItem, hit_success_no_look_to_loop_batch)
	
end

function HeroJobController:CompleteBladeBlacksmith() 
	
	print("BLACKSMITH - PUT DOWN SWORD")
	--[Keshire] reset hammer blows
	self.HammerBlows = 0
	ScriptFunction.WaitForTimeInSecondsUntilCondition(0.10000000149012, function() return self.HenchmanWentAWOL end)
	if not self.HenchmanWentAWOL then
	
		if ObjectAttachment.IsEntityAttached(self.EntityUsingItem, self.Ingot) then
	
			self.Ingot:Destroy()
			self.Ingot = Debug.CreateEntityAt("MetalWork_Minigame_Stage3", "BlacksmithIngot" .. self.JobData.Location, self.EntityUsingItem:GetPosition())
			ObjectAttachment.AddEntity(self.EntityUsingItem, self.Ingot, DummyObjects.HAND_LEFT, 0)
		
		end
	
		ScriptFunction.WaitForTimeInSecondsUntilCondition(1.8999999761581, function() return self.HenchmanWentAWOL end)
	end
	
	--[Keshire] Why again??
	if not self.HenchmanWentAWOL then
	
		Debug.CreateEntityAt("FX_Smith_Steam_Ingot", "effect", self.Ingot:GetPosition())
		if ObjectAttachment.IsEntityAttached(self.EntityUsingItem, self.Ingot) then 
	
			ObjectAttachment.RemoveEntity(self.EntityUsingItem, self.Ingot)
		
			self.Ingot:Destroy()
			self.Ingot = Debug.CreateEntityAt("MetalWork_Minigame_Stage1", "BlacksmithIngot" .. self.JobData.Location, self.EntityUsingItem:GetPosition())
			ObjectAttachment.AddEntity(self.EntityUsingItem, self.Ingot, DummyObjects.HAND_LEFT, 0)
		end
		
	else
	
		self.Ingot:Destroy()
		self.Ingot = nil
		
	end
end

function HeroJobController:PickUpIngotBlacksmith() 

	if not self.JobActive then
		return
	end
	print("BLACKSMITH - PICK UP INGOT")

	ScriptFunction.WaitForTimeInSecondsUntilCondition(1.2999999523163, function() return self.HenchmanWentAWOL end)

	if not self.HenchmanWentAWOL then
	
		Debug.CreateEntityAtPosition("FX_Smith_Spark_Ingot", "effect", self.Ingot:GetPosition())
		
	elseif self.Ingot then
	
		self.Ingot:Destroy()
		self.Ingot = nil
		
	end
end

function HeroJobController:RemoveIngotBlacksmith() 

	if not self.HenchmanWentAWOL and ObjectAttachment.IsEntityAttached(self.EntityUsingItem, self.Ingot) then
		ObjectAttachment.RemoveEntity(self.EntityUsingItem, self.Ingot)
	end
	if self.Ingot then
		self.Ingot:Destroy()
		self.Ingot = nil
	end

end

--[Keshire] This Clearup/ClearUp isn't a typo...
function HeroJobController:ClearupBlacksmith() 
	self:ClearUpCommon()
end

function HeroJobController:DestroyDummiesAndTeleportBlacksmith() 

	self:RemoveIngotBlacksmith()
	local job_finished_marker_description = "QJ002_FinishedMarker"
	ScriptFunction.TeleportPlayerTo(ScriptFunction.GetEntityWithName(job_finished_marker_description .. self.JobData.Location, "marker"):GetPosition(), true, true, true)
	
	local dog_finished_marker_description = "QJ002_DogFinishedMarker"
	if self.Dog:IsAlive() then
		Physics.TeleportToPosition(self.Dog, ScriptFunction.GetEntityWithName(dog_finished_marker_description .. self.JobData.Location, "marker"):GetPosition())
	end
	
	self:ClearUpCouchSpectator(job_finished_marker_description, dog_finished_marker_description)
	ScriptFunction.SetExclusionZoneAsActive("QJ002_Camera_ExclusionZone" .. self.JobData.Location, false)
	
	if not self.HenchmanWentAWOL then
		local hammer = Carrying.RemoveEntityFromSlot(self.EntityUsingItem, DummyObjects.HAND_RIGHT)
		if hammer:IsAlive() then
			hammer:Destroy()
		end
		
		ScriptFunction.MoveAndRotateEntityToMarkerNamed(self.EntityUsingItem, "QJ002_FinishedMarker" .. self.JobData.Location, true, true, true)
		
		if self.Dog:IsAlive() then
			local dogmarker = ScriptFunction.GetEntityWithName("QJ002_DogFinishedMarker" .. self.JobData.Location, "marker")
			Physics.TeleportToPosition(self.Dog, dogmarker:GetPosition())
			ScriptFunction.SetFacingVector(self.Dog, Physics.GetFacingVector(dogmarker))
			ScriptFunction.DogStopLying(self.Dog)
		end

	end
	Layers.ActivateLayer("QJ002_JobBlacksmith_Hammer")
	
end