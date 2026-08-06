Hero_AbilityPowerUpTracker = {}

function Hero_AbilityPowerUpTracker:Update()
	while true do
		local is_posted, message = MessageEvents.IsMessageSentBy(EMessageEventType.MESSAGE_EVENT_ABILITY_LEVEL_INCREASED, QuestManager.HeroEntity, self.LastMessageID_PoweredUp)
		if is_posted then
			self.LastMessageID_PoweredUp = message:GetID()

--		local action =
--		{
--			Type = EScriptableAction.KNOCK_ON_DOOR,
--			IntoAction = {Type = EScriptableAction.PLAY_ANIMATION, Anim = "PowerUpInto", OverrideLooking = true},
--			LoopAction = {Type = EScriptableAction.PLAY_ANIMATION, Anim = "PowerUpLoop", OverrideLooking = true},
--			OutOfAction = {Type = EScriptableAction.PLAY_ANIMATION, Anim = "PowerUpOutof", OverrideLooking = true},
--			NumLoops = 1
--		}
--		Action.SetCurrentAction(QuestManager.HeroEntity, action)

			local xp_type = message:GetExtraDataAsNumber()

			if xp_type == EExperienceType.EXPERIENCE_STRENGTH then
				Debug.CreateEntityAt("FX_PotionEffect_Experience_Strength", "FX", QuestManager.HeroEntity:GetPosition())
			elseif xp_type == EExperienceType.EXPERIENCE_SKILL then
				Debug.CreateEntityAt("FX_PotionEffect_Experience_Skill", "FX", QuestManager.HeroEntity:GetPosition())
			elseif xp_type == EExperienceType.EXPERIENCE_WILL then
				Debug.CreateEntityAt("FX_PotionEffect_Experience_Will", "FX", QuestManager.HeroEntity:GetPosition())
			end

--		while Action.IsPerformingAnyAction(QuestManager.HeroEntity) do
--			coroutine.yield()
--		end
		end

		coroutine.yield()
	end
end

Hero_SuckExperienceTracker = {}

function Hero_SuckExperienceTracker:Update()
	while true do
		local is_posted, message = MessageEvents.IsMessageSentBy(EMessageEventType.MESSAGE_EVENT_SUCK_EXPERIENCE_PERFORMED, QuestManager.HeroEntity, self.LastMessageID_SuckExperience)
		if is_posted then
			self.LastMessageID_SuckExperience = message:GetID()

			Orchestra:EndAllFlourishes()
			Orchestra.DisableListeningForMessages	=	true

			Orchestra:StartFlourishFromTable(QuestManager.HeroEntity, nil, {Delay = 0.5, FlourishName = 'SuckXP', ForceOpen = true})
			Sound.PlayEvent(QuestManager.HeroEntity, "SE_HERO_XP_SUCK", "SUCK_XP")

			local xp_value_at_which_env_theme_is_full = ExperienceOrb.GetExperienceOnCurrentLevel(EExperienceType.EXPERIENCE_TYPE_COUNT)

			local xp_gen = EExperienceType.EXPERIENCE_GENERAL
			local xp_str = EExperienceType.EXPERIENCE_STRENGTH
			local xp_ski = EExperienceType.EXPERIENCE_SKILL
			local xp_wil = EExperienceType.EXPERIENCE_WILL

			local initial_xp = {}
			initial_xp[xp_gen] = Experience.Get(QuestManager.HeroEntity, xp_gen)
			initial_xp[xp_str] = Experience.Get(QuestManager.HeroEntity, xp_str)
			initial_xp[xp_ski] = Experience.Get(QuestManager.HeroEntity, xp_ski)
			initial_xp[xp_wil] = Experience.Get(QuestManager.HeroEntity, xp_wil)
			local initial_xp_total = initial_xp[xp_gen] + initial_xp[xp_str] + initial_xp[xp_ski] + initial_xp[xp_wil]

			Experience.ResetEffeciencyCacluation(QuestManager.HeroEntity)

			local current_num_affordable_abilities = Stats.GetNumAffordableHeroAbilities(QuestManager.HeroEntity)
			local sound_pitch = 1.0

			-- [Keshire] while ExpressionPerformer.IsPerformingExpression(QuestManager.HeroEntity) do
			while ExperienceOrb.GetSuckMode() do -- [Keshire] This is different from Fable 2 --
				local current_xp = {}
				current_xp[xp_gen] = Experience.Get(QuestManager.HeroEntity, xp_gen)
				current_xp[xp_str] = Experience.Get(QuestManager.HeroEntity, xp_str)
				current_xp[xp_ski] = Experience.Get(QuestManager.HeroEntity, xp_ski)
				current_xp[xp_wil] = Experience.Get(QuestManager.HeroEntity, xp_wil)
				local current_xp_total = current_xp[xp_gen] + current_xp[xp_str] + current_xp[xp_ski] + current_xp[xp_wil]

				local gained_xp = current_xp_total - initial_xp_total
				local env_theme_weight = gained_xp / xp_value_at_which_env_theme_is_full
				EnvironmentTheme.BlendToEnvironmentTheme("EnvThemeXP", env_theme_weight, 1 / Timing.GetTickRate())
				
				sound_pitch = 1.0 + env_theme_weight
				Sound.SetPitchForSoundCategory(QuestManager.HeroEntity, "SUCK_XP", sound_pitch, 300)

				local new_num_affordable_abilities = Stats.GetNumAffordableHeroAbilities(QuestManager.HeroEntity)
				if new_num_affordable_abilities > current_num_affordable_abilities then
					Player.StartRumbleEvent(QuestManager.HeroEntity, ERumbleEvents.RUMBLE_EVENT_ORB_SUCK_POWER_UP)
					MessageEvents.PostMessage({type = EMessageEventType.MESSAGE_EVENT_SUCK_EXPERIENCE_SHUDDER, from = QuestManager.HeroEntity, to = QuestManager.HeroEntity})
					local powerup_fx = Debug.CreateEntityAtEntitysPosition("FX_XP_Powerup_Effects", "FX", QuestManager.HeroEntity)
					ParticleEmitter.AttachToEntity(powerup_fx, QuestManager.HeroEntity, "", 0)

					current_num_affordable_abilities = new_num_affordable_abilities
				end

				--if not Sound.IsSoundCategoryPlaying(QuestManager.HeroEntity, "SUCK_XP") then
				--	Sound.PlayEvent(QuestManager.HeroEntity, "SE_HERO_XP_SUCK", "SUCK_XP")
				--end

				--[Keshire] if ExperienceOrb.GetNumberOfOrbsOnCurrentLevel() == 0 then
				--[Keshire] 	Action.FinishAllActions(QuestManager.HeroEntity)
				--[Keshire] else
					coroutine.yield()
				--[Keshire] end
			end

			--Sound.ReleaseAllLoopingSounds(QuestManager.HeroEntity)
			Sound.PlayEventAtPitch(QuestManager.HeroEntity, "SE_HERO_XP_SUCK_RELEASE", "SUCK_XP", sound_pitch)

			Orchestra.DisableListeningForMessages	=	false
			Orchestra:EndTopOpenFlourish()

			EnvironmentTheme.BlendToEnvironmentTheme("EnvThemeXP", 0.0, 1.0)

			if Experience.EffeciencyScoreAvailable(QuestManager.HeroEntity) then
				-- We're interested in how much of a *bonus* this is
				local score = (Experience.GetEffeciencyScore(QuestManager.HeroEntity) - 1.0) * 100
				if score < 0 then
					if TutorialManager.HasDisplayedTutorial(ETutorialType.TUTORIAL_COMBAT_EXPERIENCE) then
						Experience.DoEfficiencyTopBox(score)
					else
						TutorialManager.DisplayTutorial(ETutorialType.TUTORIAL_COMBAT_EXPERIENCE)
					end
				else
					Experience.DoEfficiencyTopBox(score)
				end
			end
		end

		coroutine.yield()
	end
end

Henchman_SuckExperienceTracker = {}

function Henchman_SuckExperienceTracker:Update()
	while true do
		--[Keshire] local henchman = GetPlayerHenchman()
		local henchman = GetRemoteHero()
		if henchman ~= nil and henchman:IsAlive() then
			local is_posted, message = MessageEvents.IsMessageSentBy(EMessageEventType.MESSAGE_EVENT_SUCK_EXPERIENCE_PERFORMED, henchman, self.LastMessageID_SuckExperience)
			if is_posted then
				self.LastMessageID_SuckExperience = message:GetID()

				Orchestra:EndAllFlourishes()
				Orchestra.DisableListeningForMessages	=	true

				Orchestra:StartFlourishFromTable(henchman, nil, {Delay = 0.5, FlourishName = 'SuckXP', ForceOpen = true})
				Sound.PlayEvent(henchman, "SE_HERO_XP_SUCK", "SUCK_XP")

				local xp_value_at_which_env_theme_is_full = ExperienceOrb.GetExperienceOnCurrentLevel(EExperienceType.EXPERIENCE_TYPE_COUNT)

				local xp_gen = EExperienceType.EXPERIENCE_GENERAL
				local xp_str = EExperienceType.EXPERIENCE_STRENGTH
				local xp_ski = EExperienceType.EXPERIENCE_SKILL
				local xp_wil = EExperienceType.EXPERIENCE_WILL
				
				local initial_xp = {}
				initial_xp[xp_gen] = Experience.Get(QuestManager.HeroEntity, xp_gen)
				initial_xp[xp_str] = Experience.Get(QuestManager.HeroEntity, xp_str)
				initial_xp[xp_ski] = Experience.Get(QuestManager.HeroEntity, xp_ski)
				initial_xp[xp_wil] = Experience.Get(QuestManager.HeroEntity, xp_wil)
				local initial_xp_total = initial_xp[xp_gen] + initial_xp[xp_str] + initial_xp[xp_ski] + initial_xp[xp_wil]

				Experience.ResetEffeciencyCacluation(QuestManager.HeroEntity)
				
				local sound_pitch = 1.0

				--[Keshire] while ExpressionPerformer.IsPerformingExpression(henchman) do
				while ExperienceOrb.GetSuckMode() do -- [Keshire] This is different from Fable 2 --
					local current_xp = {}
					current_xp[xp_gen] = Experience.Get(QuestManager.HeroEntity, xp_gen)
					current_xp[xp_str] = Experience.Get(QuestManager.HeroEntity, xp_str)
					current_xp[xp_ski] = Experience.Get(QuestManager.HeroEntity, xp_ski)
					current_xp[xp_wil] = Experience.Get(QuestManager.HeroEntity, xp_wil)
					local current_xp_total = current_xp[xp_gen] + current_xp[xp_str] + current_xp[xp_ski] + current_xp[xp_wil]

					local gained_xp = current_xp_total - initial_xp_total
					local env_theme_weight = gained_xp / xp_value_at_which_env_theme_is_full
					EnvironmentTheme.BlendToEnvironmentTheme("EnvThemeXP", env_theme_weight, 1 / Timing.GetTickRate())
					
					sound_pitch = 1.0 + env_theme_weight
					Sound.SetPitchForSoundCategory(henchman, "SUCK_XP", sound_pitch, 300)

					--if not Sound.IsSoundCategoryPlaying(henchman, "SUCK_XP") then
					--	Sound.PlayEvent(henchman, "SE_HERO_XP_SUCK", "SUCK_XP")
					--end

					--[Keshire] if ExperienceOrb.GetNumberOfOrbsOnCurrentLevel() == 0 then
					--[Keshire] 	Action.FinishAllActions(henchman)
					--[Keshire] else
						coroutine.yield()
					--[Keshire] end
				end

				--Sound.ReleaseAllLoopingSounds(henchman)
				Sound.PlayEventAtPitch(henchman, "SE_HERO_XP_SUCK_RELEASE", "SUCK_XP", sound_pitch)

				Orchestra.DisableListeningForMessages	=	false
				Orchestra:EndTopOpenFlourish()

				EnvironmentTheme.BlendToEnvironmentTheme("EnvThemeXP", 0.0, 1.0)
				
				if Experience.EffeciencyScoreAvailable(QuestManager.HeroEntity) then
					-- We're interested in how much of a *bonus* this is
					local score = (Experience.GetEffeciencyScore(QuestManager.HeroEntity) - 1.0) * 100
			
					if score < 0 then
						if TutorialManager.HasDisplayedTutorial(ETutorialType.TUTORIAL_COMBAT_EXPERIENCE) then
							Experience.DoEfficiencyTopBox(score)
						else
							TutorialManager.DisplayTutorial(ETutorialType.TUTORIAL_COMBAT_EXPERIENCE)
						end
					else			
						Experience.DoEfficiencyTopBox(score)
					end
				end
			end
		end

		coroutine.yield()
	end
end