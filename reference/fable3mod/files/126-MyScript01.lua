local mostLegendaryWeapons = {
	'ObjectInventoryLegendaryHammerAnwarGlory',
	'ObjectInventoryLegendaryHammerAuroraShield',
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
	'ObjectInventoryLegendaryPistolFullMonty',
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
	'ObjectInventoryLegendaryRifleMolynator',
	'ObjectInventoryLegendaryRifleSakerFlintlock',
	'ObjectInventoryLegendaryRifleScattershot',
	'ObjectInventoryLegendaryRifleSimmonsShotgun',
	'ObjectInventoryLegendaryRifleSkormJustice',
	'ObjectInventoryLegendaryRifleSwiftIrregular',
	'ObjectInventoryLegendarySwordAvoLamentation',
	'ObjectInventoryLegendarySwordBeadleCutlass',
	'ObjectInventoryLegendarySwordCasanova',
	'ObjectInventoryLegendarySwordDonorKebab',
	'ObjectInventoryLegendarySwordFishknife',
	'ObjectInventoryLegendarySwordMerchantsBodyguard',
	'ObjectInventoryLegendarySwordMogoShafter',
	'ObjectInventoryLegendarySwordMrStabby',
	'ObjectInventoryLegendarySwordPorkSword',
	'ObjectInventoryLegendarySwordSlimquick',
	'ObjectInventoryLegendarySwordSouldrinker',
	'ObjectInventoryLegendarySwordSwingingSword',
	'ObjectInventoryLegendarySwordThundaraga',
	'ObjectInventoryLegendarySwordThunderblade'
	}

for key,value in pairs(mostLegendaryWeapons) do
	if Inventory.GetNumberOfItemsOfType(GetLocalHero(), value) == 0 then
		Inventory.AddItemOfType(GetLocalHero(), value)
		GUI.DisplayReceivedItem(value)
	end
	
for key,value in pairs(mostLegendaryWeapons) do
	if Inventory.GetNumberOfItemsOfType(GetLocalHero(), value) > 1 then
		Inventory.RemoveItemOfType(GetLocalHero(), value)
	end
end