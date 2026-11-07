local _, ZR = ...

-- The Forever Auction House category tree, plus Enchants.
local Cat = {}
ZR.ItemCategories = Cat

Cat.ENCHANT = "enchant"
local ENCHANT_SLOTS = { "Chest", "Bracer", "Boots", "Gloves", "Cloak", "Shield", "Weapon", "2H Weapon" }

local roots

local function F(c, s, i)
  return { c = c, s = s, i = i }
end

local function Add(parent, name, filter)
  if not name or name == "" then return nil end
  local n = { name = name, parent = parent, filters = {}, children = {} }
  if filter then n.filters[1] = filter end
  table.insert(parent and parent.children or roots, n)
  return n
end

local function SubName(c, s)
  return (C_Item.GetItemSubClassInfo(c, s))
end

local function SlotName(i)
  return (C_Item.GetItemInventorySlotInfo(i))
end

local function SubClasses(c)
  local list = C_AuctionHouse and C_AuctionHouse.GetAuctionItemSubClasses and C_AuctionHouse.GetAuctionItemSubClasses(c)
  if list and #list > 0 then return list end
  list = {}
  for s = 0, 20 do
    local name = SubName(c, s)
    if name and name ~= "" then list[#list + 1] = s end
  end
  return list
end

local function Group(parent, name, c, subs)
  local g = Add(parent, name)
  if g then
    for _, s in ipairs(subs) do Add(g, SubName(c, s), F(c, s)) end
  end
  return g
end

local function Pairs(parent, name, list)
  local g = Add(parent, name)
  if g then
    for _, p in ipairs(list) do Add(g, SubName(p[1], p[2]), F(p[1], p[2])) end
  end
  return g
end

local function AllSubClasses(parent, c, skip)
  for _, s in ipairs(SubClasses(c)) do
    if not (skip and skip[s]) then Add(parent, SubName(c, s), F(c, s)) end
  end
end

-- A node matches its own filters and every filter below it.
local function Collect(n)
  local all = {}
  for _, f in ipairs(n.filters) do all[#all + 1] = f end
  for _, child in ipairs(n.children) do
    for _, f in ipairs(Collect(child)) do all[#all + 1] = f end
  end
  n.all = all
  return all
end

local function Build()
  roots = {}
  local IC, W, A, INV = Enum.ItemClass, Enum.ItemWeaponSubclass, Enum.ItemArmorSubclass, Enum.InventoryType

  local weapons = Add(nil, AUCTION_CATEGORY_WEAPONS or "Weapons")
  Group(weapons, AUCTION_SUBCATEGORY_ONE_HANDED or "One-Handed", IC.Weapon, { W.Axe1H, W.Mace1H, W.Sword1H, W.Dagger, W.Unarmed, W.Wand })
  Group(weapons, AUCTION_SUBCATEGORY_TWO_HANDED or "Two-Handed", IC.Weapon, { W.Axe2H, W.Mace2H, W.Sword2H, W.Polearm, W.Staff })
  Group(weapons, AUCTION_SUBCATEGORY_RANGED or "Ranged", IC.Weapon, { W.Bows, W.Crossbow, W.Guns, W.Thrown })
  local wmisc = Group(weapons, AUCTION_SUBCATEGORY_MISCELLANEOUS or "Miscellaneous", IC.Weapon, { W.Fishingpole })
  Add(wmisc, AUCTION_SUBCATEGORY_OTHER or "Other", F(IC.Weapon, W.Generic))

  local armor = Add(nil, AUCTION_CATEGORY_ARMOR or "Armor")
  local slots = { INV.IndexHeadType, INV.IndexShoulderType, INV.IndexChestType, INV.IndexWaistType,
    INV.IndexLegsType, INV.IndexFeetType, INV.IndexWristType, INV.IndexHandType }
  for _, s in ipairs({ A.Plate, A.Mail, A.Leather, A.Cloth }) do
    local g = Add(armor, SubName(IC.Armor, s), F(IC.Armor, s))
    if g then
      for _, i in ipairs(slots) do Add(g, SlotName(i), F(IC.Armor, s, i)) end
    end
  end
  Group(armor, AUCTION_SUBCATEGORY_RELIC or "Relic", IC.Armor, { A.Idol, A.Libram, A.Totem })
  local amisc = Add(armor, SubName(IC.Armor, A.Generic), F(IC.Armor, A.Generic))
  if amisc then
    Add(amisc, SlotName(INV.IndexNeckType), F(IC.Armor, A.Generic, INV.IndexNeckType))
    Add(amisc, AUCTION_SUBCATEGORY_CLOAK or "Cloak", F(IC.Armor, A.Cloth, INV.IndexCloakType))
    Add(amisc, SlotName(INV.IndexFingerType), F(IC.Armor, A.Generic, INV.IndexFingerType))
    Add(amisc, SlotName(INV.IndexTrinketType), F(IC.Armor, A.Generic, INV.IndexTrinketType))
    Add(amisc, SlotName(INV.IndexHoldableType), F(IC.Armor, A.Generic, INV.IndexHoldableType))
    Add(amisc, SubName(IC.Armor, A.Shield), F(IC.Armor, A.Shield))
    Add(amisc, SlotName(INV.IndexBodyType), F(IC.Armor, A.Generic, INV.IndexBodyType))
  end

  local CS, QS = Enum.ItemContainerSubclass, Enum.ItemQuiverSubclass
  local containers = Add(nil, AUCTION_CATEGORY_CONTAINERS or "Containers")
  Pairs(containers, AUCTION_SUBCATEGORY_STANDARD_CONTAINER or "Bags", { { IC.Container, CS.Bag }, { IC.Container, CS.Soul } })
  Pairs(containers, AUCTION_SUBCATEGORY_AMMO_CONTAINER or "Ammo", { { IC.Quiver, QS.Quiver }, { IC.Quiver, QS.Ammopouch } })
  Pairs(containers, AUCTION_SUBCATEGORY_REAGENT_CONTAINER or "Trade Bags", {
    { IC.Container, CS.Herb }, { IC.Container, CS.Enchanting }, { IC.Container, CS.Engineering },
    { IC.Container, CS.Mining }, { IC.Container, CS.Leatherworking }, { IC.Container, CS.Tacklebox },
    { IC.Container, CS.Cooking }, { IC.Container, CS.Reagent },
  })

  local CO = Enum.ItemConsumableSubclass
  local consumables = Add(nil, AUCTION_CATEGORY_CONSUMABLES or "Consumables")
  for _, s in ipairs(SubClasses(IC.Consumable)) do
    if s ~= CO.Itemenhancement and s ~= CO.ItemenhancementTemporary then
      Add(consumables, SubName(IC.Consumable, s), F(IC.Consumable, s))
    end
    if s == CO.Bandage then
      Group(consumables, AUCTION_SUBCATEGORY_ITEM_ENHANCEMENT or "Item Enhancement", IC.Consumable,
        { CO.Itemenhancement, CO.ItemenhancementTemporary })
    end
  end

  local enchants = Add(nil, "Enchants", F(Cat.ENCHANT))
  for _, slot in ipairs(ENCHANT_SLOTS) do Add(enchants, slot, F(Cat.ENCHANT, slot)) end
  Add(enchants, AUCTION_SUBCATEGORY_OTHER or "Other", F(Cat.ENCHANT, "Other"))

  AllSubClasses(Add(nil, AUCTION_CATEGORY_TRADE_GOODS or "Trade Goods"), IC.Tradegoods)
  AllSubClasses(Add(nil, AUCTION_CATEGORY_PROJECTILE or "Ammo"), IC.Projectile)
  AllSubClasses(Add(nil, AUCTION_CATEGORY_RECIPES or "Recipes"), IC.Recipe)
  Add(nil, AUCTION_CATEGORY_QUEST_ITEMS or "Quest Items", F(IC.Questitem))
  local misc = Add(nil, AUCTION_CATEGORY_MISCELLANEOUS or "Miscellaneous", F(IC.Miscellaneous))
  AllSubClasses(misc, IC.Miscellaneous)

  for _, n in ipairs(roots) do Collect(n) end
end

function Cat.Roots()
  if not roots then Build() end
  return roots
end

-- Enchant spells carry their slot in the name, like "Enchant Chest - Minor Health".
function Cat.EnchantSlot(name)
  local slot = name and name:match("^Enchant (.-) %- ")
  for _, s in ipairs(ENCHANT_SLOTS) do
    if s == slot then return s end
  end
  return "Other"
end

function Cat.Matches(node, e)
  if not node then return true end
  for _, f in ipairs(node.all or node.filters) do
    if f.c == e.c and (f.s == nil or f.s == e.s) and (f.i == nil or f.i == e.i) then return true end
  end
  return false
end
