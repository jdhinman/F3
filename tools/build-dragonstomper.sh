#!/usr/bin/env bash
# Build "F3Dragonstomper", an original overpowered ranged weapon, into all three copies of
# globals.gdb, and install them.
#
# This is the first piece of NEW CONTENT the toolchain has produced: an item record that did
# not ship with the game, assembled from cloned component records so nothing existing is
# modified. It exists to prove the writable GDB end to end, and it is the template for any
# future item.
#
#   bash tools/build-dragonstomper.sh          build and install
#   bash tools/build-dragonstomper.sh revert   put all three banks back
#
# A Fable III item is not one record. It is a small graph:
#
#   ObjectInventoryLegendaryRifleMarksman   the item, 6 component fields
#     |- WeaponComponent          DamageMultiplier
#     |- InventoryItemComponent   NameTag, DescriptionTag
#     |- ShopItemComponent        BasePrice
#     `- parent -> a base rifle   which itself carries FirearmComponent (capacity, spread,
#                                 range, knockdown) and everything not overridden
#
# Cloning reuses the source's template, so a clone has exactly the source's field set and no
# more. That is why the firearm stats need the BASE cloned as well: the item's own template
# has no FirearmComponent field to override, so the override has to happen one level up.
#
# Object hashes are chosen explicitly with --hash so each record can be pointed at before the
# next one is written. 0xF3D0xxxx is not a hash of anything; it is just a private range that
# collides with nothing in the file, and gdbwrite errors if it ever does.
set -euo pipefail
cd "$(dirname "$0")/.."

GW=./target/release/gdbwrite.exe
BANKS=(
  'C:\Games\Fable 3\data\levels.bnk'
  'C:\Games\Fable 3\DLC\traitors_keep\Content\dlc2free.bnk'
  'C:\Games\Fable 3\DLC\understone_quest\Content\dlc_freeforall.bnk'
)
NAMES=(levels dlc2free dlc_freeforall)

if [ "${1:-}" = "revert" ]; then
  for b in "${BANKS[@]}"; do python tools/bnk-replace.py revert "$b"; done
  exit 0
fi

# Source records, all from the Marksman legendary rifle line.
SRC_ITEM=0x9BB71C7C     # ObjectInventoryLegendaryRifleMarksman
SRC_WEAPON=0xC2841501   #   its WeaponComponent      (DamageMultiplier 24.0)
SRC_INV=0xEFAF4991      #   its InventoryItemComponent (NameTag/DescriptionTag)
SRC_SHOP=0x4299E3F2     #   its ShopItemComponent    (BasePrice 8300)
SRC_BASE=0xD4C81984     #   its parent, the base rifle
SRC_FIREARM=0x6E3BAF8A  #     the base's FirearmComponent

# New object hashes.
N_WEAPON=0xF3D00001
N_FIREARM=0xF3D00002
N_BASE=0xF3D00003
N_INV=0xF3D00004
N_SHOP=0xF3D00005
N_ITEM=0xF3D00006

for i in "${!BANKS[@]}"; do
  n="${NAMES[$i]}"
  bank="${BANKS[$i]}"
  echo "===================== $n"
  python tools/bnk-extract.py "$bank" 'globals\globals.gdb' "work/ds-$n-0.gdb"
  $GW "work/ds-$n-0.gdb" --verify

  # 1. Damage. The Marksman's 24.0 is the highest in the base game.
  $GW "work/ds-$n-0.gdb" --clone $SRC_WEAPON --hash $N_WEAPON \
      --set DamageMultiplier=900.0 --out "work/ds-$n-1.gdb"

  # 2. Firearm handling: a 60-round magazine, four times the range, and knockdown that
  #    throws everything in a wide radius. SpreadAngle 0.25 rather than 0.0 - it is pinpoint
  #    either way, and a zero has no business going into an angle calculation we have not read.
  $GW "work/ds-$n-1.gdb" --clone $SRC_FIREARM --hash $N_FIREARM \
      --set BulletCapacity=60 --set BulletsPerReload=60 --set SpreadAngle=0.25 \
      --set Range=240.0 --set CloseDamageMultiplier=4.0 \
      --set KnockDownRange=18.0 --set KnockDownDamageMultiplier=30.0 \
      --set CursorSpeedMultiplier=3.0 --out "work/ds-$n-2.gdb"

  # 3. A private base rifle carrying that firearm component, so the real one is untouched.
  $GW "work/ds-$n-2.gdb" --clone $SRC_BASE --hash $N_BASE \
      --set FirearmComponent=$N_FIREARM --set WeaponComponent=$N_WEAPON \
      --out "work/ds-$n-3.gdb"

  # 4. Display name and description. These are BABEL localisation ids, not text, so a new
  #    label here would render blank - the ids are borrowed from the Dragonstomper .48,
  #    which is exactly the open question this build also answers. -> [[Formats]]
  $GW "work/ds-$n-3.gdb" --clone $SRC_INV --hash $N_INV \
      --set 'NameTag="INV_ITEM_WEAPON_DRAGONSTOMPER_NAME"' \
      --set 'DescriptionTag="INV_ITEM_WEAPON_DRAGONSTOMPER_DESC"' --out "work/ds-$n-4.gdb"

  # 5. Price, so it behaves if it ever reaches a shop.
  $GW "work/ds-$n-4.gdb" --clone $SRC_SHOP --hash $N_SHOP \
      --set BasePrice=1000000 --out "work/ds-$n-5.gdb"

  # 6. The item itself. This is the only record that needs a NAME, because it is the only
  #    one a script asks for: Inventory.AddItemOfType(hero, "F3Dragonstomper").
  $GW "work/ds-$n-5.gdb" --clone $SRC_ITEM --hash $N_ITEM --name F3Dragonstomper \
      --set parent=$N_BASE --set WeaponComponent=$N_WEAPON \
      --set InventoryItemComponent=$N_INV --set ShopItemComponent=$N_SHOP \
      --out "work/ds-$n.gdb"

  python tools/bnk-replace.py apply "$bank" 'globals\globals.gdb' "work/ds-$n.gdb"
  $GW --verify-all --bank "$bank"
done
echo
echo "F3Dragonstomper installed in all three globals.gdb copies. Restart the game."
