local allLegendaryWeapons = {
	'ObjectInventoryLegendaryHammerAbsolver',
	'ObjectInventoryLegendaryHammerAnwarGlory',
	'ObjectInventoryLegendaryHammerAuroraShield',
	'ObjectInventoryLegendaryHammerChampion',
	'ObjectInventoryLegendaryHammerDragonboneHammer',
	'ObjectInventoryLegendaryHammerFaerie',
	'ObjectInventoryLegendaryHammerHammerOfTheWhale',
	'ObjectInventoryLegendaryHammerJackHammer',
	'ObjectInventoryLegendaryHammerLunariumPounder',
	'ObjectInventoryLegendaryHammerMalletsMallet',
	'ObjectInventoryLegendaryHammerScytheHammer',
	'ObjectInventoryLegendaryHammerSorrowsFist',
	'ObjectInventoryLegendaryHammerTenderiser',
	'ObjectInventoryLegendaryHammerTrollblight',
	'ObjectInventoryLegendaryHammerTwatter',
	'ObjectInventoryLegendaryHammerWillmageddon',
	'ObjectInventoryLegendaryPistolBarnumificator',
	'ObjectInventoryLegendaryPistolBloodcraver',
	'ObjectInventoryLegendaryPistolBriarsBlaster',
	'ObjectInventoryLegendaryPistolChickenbane',
	'ObjectInventoryLegendaryPistolDesertFury',
	'ObjectInventoryLegendaryPistolDragonstomper',
	'ObjectInventoryLegendaryPistolFullMonty',
	'ObjectInventoryLegendaryPistolGnomewrecker',
	'ObjectInventoryLegendaryPistolHolyVengeance',
	'ObjectInventoryLegendaryPistolIceMaiden',
	'ObjectInventoryLegendaryPistolMiriansMutilator',
	'ObjectInventoryLegendaryPistolPerforator',
	'ObjectInventoryLegendaryPistolSailorGeriShooter',
	'ObjectInventoryLegendaryRifleArkwrightFlintlock',
	'ObjectInventoryLegendaryRifleDefender',
	'ObjectInventoryLegendaryRifleEqualiser',
	'ObjectInventoryLegendaryRifleEthelbertBoner',
	'ObjectInventoryLegendaryRifleFacemelter',
	'ObjectInventoryLegendaryRifleHeroCompanion',
	'ObjectInventoryLegendaryRifleMarksman',
	'ObjectInventoryLegendaryRifleMolynator',
	'ObjectInventoryLegendaryRifleSakerFlintlock',
	'ObjectInventoryLegendaryRifleScattershot',
	'ObjectInventoryLegendaryRifleSimmonsShotgun',
	'ObjectInventoryLegendaryRifleSkormJustice',
	'ObjectInventoryLegendaryRifleSwiftIrregular',
	'ObjectInventoryLegendarySwordAvoLamentation',
	'ObjectInventoryLegendarySwordBeadleCutlass',
	'ObjectInventoryLegendarySwordCasanova',
	'ObjectInventoryLegendarySwordChanneler',
	'ObjectInventoryLegendarySwordDonorKebab',
	'ObjectInventoryLegendarySwordFishknife',
	'ObjectInventoryLegendarySwordInquisitor',
	'ObjectInventoryLegendarySwordMerchantsBodyguard',
	'ObjectInventoryLegendarySwordMogoShafter',
	'ObjectInventoryLegendarySwordMrStabby',
	'ObjectInventoryLegendarySwordPorkSword',
	'ObjectInventoryLegendarySwordShardborne',
	'ObjectInventoryLegendarySwordSlimquick',
	'ObjectInventoryLegendarySwordSouldrinker',
	'ObjectInventoryLegendarySwordSwingingSword',
	'ObjectInventoryLegendarySwordThundaraga',
	'ObjectInventoryLegendarySwordThunderblade'
	}

for key,value in pairs(allLegendaryWeapons) do
	if Inventory.GetNumberOfItemsOfType(GetLocalHero(), value) == 0 then
		Inventory.AddItemOfType(GetLocalHero(), value)
		GUI.DisplayReceivedItem(value)
	end
end

if Inventory.GetNumberOfItemsOfType(QuestManager.HeroEntity, 'ObjectInventoryPotionDogStatsLevel5') > 0 then
	Inventory.RemoveItemOfType(QuestManager.HeroEntity, 'ObjectInventoryPotionDogStatsLevel5')
	DogStats.SetTrainingLevel(GetDog(GetLocalHero()), EDogTrainingType.DOG_TRAINING_TYPE_COMBAT, - DogStats.GetTrainingLevel(GetDog(GetLocalHero()), EDogTrainingType.DOG_TRAINING_TYPE_COMBAT))
	DogStats.SetTrainingLevel(GetDog(GetLocalHero()), EDogTrainingType.DOG_TRAINING_TYPE_TREASURE_HUNTING, - DogStats.GetTrainingLevel(GetDog(GetLocalHero()), EDogTrainingType.DOG_TRAINING_TYPE_TREASURE_HUNTING))
	DogStats.SetTrainingLevel(GetDog(GetLocalHero()), EDogTrainingType.DOG_TRAINING_TYPE_CHARISMA, - DogStats.GetTrainingLevel(GetDog(GetLocalHero()), EDogTrainingType.DOG_TRAINING_TYPE_CHARISMA))
end