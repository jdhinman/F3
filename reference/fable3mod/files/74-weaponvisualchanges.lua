VisualChangeScripts = {}
VisualChangeScripts.SetVisualChangeIfPresent = function(visual_changes, effects_record, visual_change_name)
	if effects_record:Exists(visual_change_name) then
		visual_changes[FNVHash(visual_change_name)] = FNVHash(effects_record:GetString(visual_change_name))
	end
end
VisualChangeScripts.DefaultVisualChangeScript = function(applied_augments, weapon_entity)

	local visual_changes = {}
	local WeaponSize = "SMALL"
	local PrimaryMesh = "BASE"
	local SecondaryMesh = "BASE"
	local ParticleEffect = "NONE"
	local WeaponSizes = {}
		WeaponSizes.SizeSmall = "SMALL"
		WeaponSizes.SizeMedium = "MEDIUM"
		WeaponSizes.SizeLarge = "LARGE"
	local WeaponTypes = {}
		WeaponTypes[3] = "SE_HAMMER"
		WeaponTypes[2] = "SE_SWORD"
		WeaponTypes[6] = "SE_RIFLE"
		WeaponTypes[7] = "SE_PISTOL"
	local PrimaryMeshes = {}
		PrimaryMeshes.PrimaryMeshBase = "BASE"
		PrimaryMeshes.PrimaryMeshEvil1 = "EVIL1"
		PrimaryMeshes.PrimaryMeshGood1 = "GOOD1"
		PrimaryMeshes.PrimaryMeshAuroran = "AURORAN"
		PrimaryMeshes.PrimaryMeshIntricate = "INTRICATE"
		PrimaryMeshes.PrimaryMeshReaver = "REAVER"
		PrimaryMeshes.PrimaryMeshEvil2 = "EVIL2"
		PrimaryMeshes.PrimaryMeshOrganic = "ORGANIC"
		PrimaryMeshes.PrimaryMeshGood2 = "GOOD2"
		PrimaryMeshes.PrimaryMeshCrystal = "CRYSTAL"
	local SecondaryMeshes = {}
		SecondaryMeshes.SecondaryMeshBase = "BASE"
		SecondaryMeshes.SecondaryMeshSpell = "SPELL"
		SecondaryMeshes.SecondaryMeshBone = "BONE"
		SecondaryMeshes.SecondaryMeshAuroran = "AURORAN"
		SecondaryMeshes.SecondaryMeshRoyal = "ROYAL"
	local WeaponParticles = {}
		WeaponParticles.ParticleEffectLightning = "LIGHTNING"
		WeaponParticles.ParticleEffectFire = "FIRE"
		WeaponParticles.ParticleEffectShadow = "SHADOW"
		WeaponParticles.ParticleEffectSparkles = "HOLY"
		WeaponParticles.ParticleEffectBlood = "BLOOD"
		WeaponParticles.ParticleEffectEthereal = "ETHEREAL"
		WeaponParticles.ParticleEffectInk = "GOLDEN"
		WeaponParticles.ParticleEffectPoison = "POISON"
	local WeaponParticleEffectName = {}
		WeaponParticleEffectName.LIGHTNING = {}
		WeaponParticleEffectName.FIRE = {}
		WeaponParticleEffectName.SHADOW = {}
		WeaponParticleEffectName.HOLY = {}
		WeaponParticleEffectName.BLOOD = {}
		WeaponParticleEffectName.ETHEREAL = {}
		WeaponParticleEffectName.GOLDEN = {}
		WeaponParticleEffectName.POISON = {}
	
	WeaponParticleEffectName.LIGHTNING["SE_HAMMER"] = "fxaug_lightning_hammer"
	WeaponParticleEffectName.LIGHTNING["SE_SWORD"] = "fxaug_lightning_blade"
	WeaponParticleEffectName.LIGHTNING["SE_CURVEDSWORD"] = "fxaug_lightning_blade_curve"
	WeaponParticleEffectName.LIGHTNING["SE_PISTOL"] = "fxaug_lightning_pistol"
	WeaponParticleEffectName.LIGHTNING["SE_RIFLE"] = "fxaug_lightning_rifle"
	WeaponParticleEffectName.FIRE["SE_HAMMER"] = "fxaug_fire_hammer"
	WeaponParticleEffectName.FIRE["SE_SWORD"] = "fxaug_fire_blade"
	WeaponParticleEffectName.FIRE["SE_CURVEDSWORD"] = "fxaug_fire_blade_curve"
	WeaponParticleEffectName.FIRE["SE_PISTOL"] = "fxaug_fire_pistol"
	WeaponParticleEffectName.FIRE["SE_RIFLE"] = "fxaug_fire_rifle"
	WeaponParticleEffectName.SHADOW["SE_HAMMER"] = "fxaug_shadow_hammer"
	WeaponParticleEffectName.SHADOW["SE_SWORD"] = "fxaug_shadow_blade"
	WeaponParticleEffectName.SHADOW["SE_CURVEDSWORD"] = "fxaug_shadow_blade_curve"
	WeaponParticleEffectName.SHADOW["SE_PISTOL"] = "fxaug_shadow_pistol"
	WeaponParticleEffectName.SHADOW["SE_RIFLE"] = "fxaug_shadow_rifle"
	WeaponParticleEffectName.HOLY["SE_HAMMER"] = "fxaug_holy_hammer"
	WeaponParticleEffectName.HOLY["SE_SWORD"] = "fxaug_holy_blade"
	WeaponParticleEffectName.HOLY["SE_CURVEDSWORD"] = "fxaug_holy_blade_curve"
	WeaponParticleEffectName.HOLY["SE_PISTOL"] = "fxaug_holy_pistol"
	WeaponParticleEffectName.HOLY["SE_RIFLE"] = "fxaug_holy_rifle"
	WeaponParticleEffectName.BLOOD["SE_HAMMER"] = "fxaug_blood_hammer"
	WeaponParticleEffectName.BLOOD["SE_SWORD"] = "fxaug_blood_blade"
	WeaponParticleEffectName.BLOOD["SE_CURVEDSWORD"] = "fxaug_blood_blade_curve"
	WeaponParticleEffectName.BLOOD["SE_PISTOL"] = "fxaug_blood_pistol"
	WeaponParticleEffectName.BLOOD["SE_RIFLE"] = "fxaug_blood_rifle"
	WeaponParticleEffectName.ETHEREAL["SE_HAMMER"] = "fxaug_ethereal_hammer"
	WeaponParticleEffectName.ETHEREAL["SE_SWORD"] = "fxaug_ethereal_blade"
	WeaponParticleEffectName.ETHEREAL["SE_CURVEDSWORD"] = "fxaug_ethereal_blade_curve"
	WeaponParticleEffectName.ETHEREAL["SE_PISTOL"] = "fxaug_ethereal_pistol"
	WeaponParticleEffectName.ETHEREAL["SE_RIFLE"] = "fxaug_ethereal_rifle"
	WeaponParticleEffectName.GOLDEN["SE_HAMMER"] = "fxaug_golden_hammer"
	WeaponParticleEffectName.GOLDEN["SE_SWORD"] = "fxaug_golden_blade"
	WeaponParticleEffectName.GOLDEN["SE_CURVEDSWORD"] = "fxaug_golden_blade_curve"
	WeaponParticleEffectName.GOLDEN["SE_PISTOL"] = "fxaug_golden_pistol"
	WeaponParticleEffectName.GOLDEN["SE_RIFLE"] = "fxaug_golden_rifle"
	WeaponParticleEffectName.POISON["SE_HAMMER"] = "fxaug_poison_hammer"
	WeaponParticleEffectName.POISON["SE_SWORD"] = "fxaug_poison_blade"
	WeaponParticleEffectName.POISON["SE_CURVEDSWORD"] = "fxaug_poison_blade_curve"
	WeaponParticleEffectName.POISON["SE_PISTOL"] = "fxaug_poison_pistol"
	WeaponParticleEffectName.POISON["SE_RIFLE"] = "fxaug_poison_rifle"
	--So much typing....
	
	local WeaponAttachmentName = {}
		WeaponAttachmentName.SE_SWORD = "Weapon.Weapon.Top"
		WeaponAttachmentName.SE_HAMMER = "Weapon.Weapon.TrailBase"
		WeaponAttachmentName.SE_PISTOL = "Weapon.Weapon.ProjectileEmitter"
		WeaponAttachmentName.SE_RIFLE = "Weapon.Weapon.ProjectileEmitter"
		
	local WeaponType = WeaponTypes[Weapon.GetWeaponType(weapon_entity)]
	
	for i,v in ipairs(applied_augments) do
		local augment_record = GDB.GetRecord(v)
		local effects_record = augment_record:GetRecord("VisualChangeEffects")
		if effects_record:Exists("VisualChangePrimaryColourForeground") then
			visual_changes[FNVHash("VisualChangePrimaryColourForeground")] = FNVHash(effects_record:GetString("VisualChangePrimaryColourForeground"))
		end
		if effects_record:Exists("VisualChangePrimaryColourBackground") then
			visual_changes[FNVHash("VisualChangePrimaryColourBackground")] = FNVHash(effects_record:GetString("VisualChangePrimaryColourBackground"))
		end
		if effects_record:Exists("VisualChangeSecondaryMesh") then
			visual_changes[FNVHash("VisualChangeSecondaryMesh")] = FNVHash(effects_record:GetString("VisualChangeSecondaryMesh"))
			if WeaponType == "SE_HAMMER" then
				local MeshString = effects_record:GetString("VisualChangeSecondaryMesh")
				SecondaryMesh = SecondaryMeshes[effects_record:GetString("VisualChangeSecondaryMesh")]
			end
		end
		if effects_record:Exists("VisualChangePrimaryMesh") then
			visual_changes[FNVHash("VisualChangePrimaryMesh")] = FNVHash(effects_record:GetString("VisualChangePrimaryMesh"))
			PrimaryMesh = PrimaryMeshes[effects_record:GetString("VisualChangePrimaryMesh")]
		end
		if effects_record:Exists("VisualChangeSize") then
			if WeaponSize == "SMALL" then
				WeaponSize = "MEDIUM"
			elseif WeaponSize == "MEDIUM" then
				WeaponSize = "LARGE"
			end
		end
	end
	for i,v in ipairs(applied_augments) do
		local augment_record = GDB.GetRecord(v)
		local effects_record = augment_record:GetRecord("VisualChangeEffects")
		if effects_record:Exists("VisualChangeParticleEffect") then
			local ParticleString = effects_record:GetString("VisualChangeParticleEffect")
			ParticleEffect = WeaponParticles[ParticleString]
			
			if ParticleEffect and WeaponType and WeaponType=="SE_SWORD" 
			and PrimaryMesh ~= "EVIL1" and PrimaryMesh ~= "GOOD1" and PrimaryMesh ~= "GOOD2" 
			and PrimaryMesh == "AURORAN" then
				if WeaponParticleEffectName[ParticleEffect].SE_CURVEDSWORD then
					if WeaponAttachmentName[WeaponType] then
						CustomisableWeapon.AddWeaponParticleEffect(weapon_entity, WeaponParticleEffectName[ParticleEffect].SE_CURVEDSWORD, WeaponAttachmentName[WeaponType], 1)
					end
				end
			else
				if WeaponParticleEffectName[ParticleEffect][WeaponType] and WeaponAttachmentName[WeaponType] then
						CustomisableWeapon.AddWeaponParticleEffect(weapon_entity, WeaponParticleEffectName[ParticleEffect][WeaponType], WeaponAttachmentName[WeaponType], 1)
				end
			end
		end
	end
	
	if WeaponSize == "LARGE" then
		visual_changes[FNVHash("VisualChangeSize")] = FNVHash("SizeLarge")
	elseif WeaponSize == "MEDIUM" then
		visual_changes[FNVHash("VisualChangeSize")] = FNVHash("SizeMedium")
	else
		visual_changes[FNVHash("VisualChangeSize")] = FNVHash("SizeSmall")
		WeaponSize = "SMALL"
	end
		
	local WeaponNumber = Weapon.GetWeaponType(weapon_entity)
	local FullString = WeaponTypes[Weapon.GetWeaponType(weapon_entity)]..";"..WeaponSize..";"..PrimaryMesh..";"..ParticleEffect
	Weapon.SetSoundEventTag(weapon_entity, FullString)
	if WeaponType == "SE_HAMMER" then
		FullString = WeaponTypes[Weapon.GetWeaponType(weapon_entity)]..";"..WeaponSize..";"..SecondaryMesh..";"..ParticleEffect
		Weapon.SetSoundEventBlockOverrideTag(weapon_entity, FullString)
	end
	
	if Gameflow.WeaponMeshOverride then
	
		local HackedPrimaryMesh = "PrimaryMeshBase"
		if Gameflow.PrimaryMeshOverride then
			HackedPrimaryMesh = Gameflow.PrimaryMeshOverride
		end
		visual_changes[FNVHash("VisualChangePrimaryMesh")] = FNVHash(HackedPrimaryMesh)
	
		local HackedSecondaryMesh = "SecondaryMeshBase"
		if Gameflow.SecondaryMeshOverride then
			HackedSecondaryMesh = Gameflow.SecondaryMeshOverride
		end
		visual_changes[FNVHash("VisualChangeSecondaryMesh")] = FNVHash(HackedSecondaryMesh)
	
		local HackedMeshSize = "SizeSmall"
		if Gameflow.PrimaryMeshSize then
			HackedMeshSize = Gameflow.PrimaryMeshSize
		end
		visual_changes[FNVHash("VisualChangeSize")] = FNVHash(HackedMeshSize)
	
		if Gameflow.PrimaryColour then
			visual_changes[FNVHash("VisualChangePrimaryColourBackground")] = FNVHash(Gameflow.PrimaryColour)
		end
		if Gameflow.ForegroundColour then
			visual_changes[FNVHash("VisualChangePrimaryColourForeground")] = FNVHash(Gameflow.ForegroundColour)
		end
		if Gameflow.ParticleEffect and ParticleEffect == Gameflow.ParticleEffect and WeaponType then
			if WeaponType == "SE_SWORD" and
				(PrimaryMeshes[HackedPrimaryMesh] == "EVIL1" or
				PrimaryMeshes[HackedPrimaryMesh] == "GOOD1" or
				PrimaryMeshes[HackedPrimaryMesh] == "GOOD2" or
				PrimaryMeshes[HackedPrimaryMesh] == "AURORAN") then
						if WeaponParticleEffectName[ParticleEffect].SE_CURVEDSWORD then
							if WeaponAttachmentName[WeaponType] then
								CustomisableWeapon.AddWeaponParticleEffect(weapon_entity, WeaponParticleEffectName[ParticleEffect].SE_CURVEDSWORD, WeaponAttachmentName[WeaponType], 1)
							end
						end
			elseif WeaponParticleEffectName[ParticleEffect][WeaponType] and WeaponAttachmentName[WeaponType] then
				CustomisableWeapon.AddWeaponParticleEffect(weapon_entity, WeaponParticleEffectName[ParticleEffect][WeaponType], WeaponAttachmentName[WeaponType], 1)
			end
		end
		
		FullString = WeaponTypes[Weapon.GetWeaponType(weapon_entity)]..";"..WeaponSizes[HackedMeshSize]..";"..PrimaryMeshes[HackedPrimaryMesh]..";"..ParticleEffect
		Weapon.SetSoundEventTag(weapon_entity, FullString)
		if WeaponType == "SE_HAMMER" then
			FullString = WeaponTypes[Weapon.GetWeaponType(weapon_entity)]..";"..WeaponSizes[HackedMeshSize]..";"..SecondaryMeshes[HackedSecondaryMesh]..";"..ParticleEffect
			Weapon.SetSoundEventBlockOverrideTag(weapon_entity, FullString)
		end
	end
	
	return visual_changes
	
end
VisualChangeScripts.GauntletVisualChangeScript = function(applied_augments, weapon_entity)
	local visual_changes = {}
	return visual_changes
end