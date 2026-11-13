local _, ZR = ...

local Crafts = {}
ZR.Crafts = Crafts

local MINING = 186
local SMELTING_SPELL = 2656
-- Gathering and secondary skills have a level but no recipes we share.
local NO_RECIPES = { [182] = true, [393] = true, [356] = true, [185] = true, [129] = true }

Crafts.PROFESSIONS = {
  { id = 171, name = "Alchemy", icon = "Interface\\Icons\\Trade_Alchemy" },
  { id = 164, name = "Blacksmithing", icon = "Interface\\Icons\\Trade_BlackSmithing" },
  { id = 333, name = "Enchanting", icon = "Interface\\Icons\\Trade_Engraving" },
  { id = 202, name = "Engineering", icon = "Interface\\Icons\\Trade_Engineering" },
  { id = 165, name = "Leatherworking", icon = "Interface\\Icons\\INV_Misc_ArmorKit_17" },
  { id = 197, name = "Tailoring", icon = "Interface\\Icons\\Trade_Tailoring" },
  { id = MINING, name = "Mining", icon = "Interface\\Icons\\Trade_Mining" },
  { id = 182, name = "Herbalism", icon = "Interface\\Icons\\Spell_Nature_NatureTouchGrow" },
  { id = 393, name = "Skinning", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
}

Crafts.SECONDARY = {
  { id = 356, name = "Fishing", icon = "Interface\\Icons\\Trade_Fishing" },
  { id = 185, name = "Cooking", icon = "Interface\\Icons\\INV_Misc_Food_15" },
  { id = 129, name = "First Aid", icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
}

local profById, secondaryById = {}, {}
for _, p in ipairs(Crafts.PROFESSIONS) do profById[p.id] = p end
for _, p in ipairs(Crafts.SECONDARY) do
  profById[p.id] = p
  secondaryById[p.id] = p
end

local displayNames = {}

function Crafts.ProfName(id)
  if displayNames[id] then return displayNames[id] end
  local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, id)
  if not ok or not name or name == "" then
    name = profById[id] and profById[id].name or ("Profession " .. tostring(id))
  end
  displayNames[id] = name
  return name
end

function Crafts.HasRecipes(id)
  return not NO_RECIPES[id]
end

function Crafts.Store()
  local g = ZR.GDB()
  if not g then return nil end
  g.crafters = g.crafters or {}
  return g.crafters
end

function Crafts.Get(name)
  local s = Crafts.Store()
  return s and s[name]
end

function Crafts.GetProf(name, skill)
  local r = Crafts.Get(name)
  return r and r.p and r.p[skill]
end

function Crafts.Ensure(name)
  local s = Crafts.Store()
  if not s or not name or name == "" then return nil end
  local r = s[name]
  if not r then
    r = { p = {} }
    s[name] = r
  end
  r.p = r.p or {}
  return r
end

local index

function Crafts.Changed()
  index = nil
  ZR.Fire("CraftsChanged")
end

-- People who left are hidden once the full roster is known.
function Crafts.Visible(name)
  return name == ZR.PlayerName() or not ZR.RosterComplete() or ZR.IsGuildMember(name)
end

function Crafts.Count(p)
  local n = 0
  for _ in pairs(p and p.l or {}) do n = n + 1 end
  return n
end

-- Sync data only ever raises skill; a full list replaces an older one.
function Crafts.SetProf(name, skill, t, r, m, list)
  local rec = Crafts.Ensure(name)
  if not rec then return end
  local p = rec.p[skill] or { t = 0, l = {} }
  rec.p[skill] = p
  if list and t > (p.t or 0) then p.t, p.l = t, list end
  p.r = math.max(p.r or 0, r or 0)
  p.m = math.max(p.m or 0, m or 0)
  Crafts.Changed()
end

-- Primary professions only, so Cooking, Fishing and First Aid never count.
local function OwnProfessions()
  local out = {}
  local p1, p2 = GetProfessions()
  for _, idx in pairs({ p1, p2 }) do
    local name, _, rank, max, _, _, skillLine = GetProfessionInfo(idx)
    if skillLine then out[skillLine] = { name = name, rank = rank or 0, max = max or 0 } end
  end
  return out
end

-- Classified by skill line, since the slot order differs between game versions.
local function OwnSecondary()
  local out = {}
  local _, _, a, b, c, d = GetProfessions()
  for _, idx in pairs({ a, b, c, d }) do
    local _, _, rank, max, _, _, skillLine = GetProfessionInfo(idx)
    if secondaryById[skillLine] then out[skillLine] = { rank = rank or 0, max = max or 0 } end
  end
  return out
end

function Crafts.UpdateOwn()
  local rec = Crafts.Ensure(ZR.PlayerName())
  if not rec then return end
  local own, changed = OwnProfessions(), false
  local second = OwnSecondary()
  -- Unlearned ones go out as 0/0, so others can tell them from not shared yet.
  if next(own) or next(second) then
    for id in pairs(secondaryById) do own[id] = second[id] or { rank = 0, max = 0 } end
  end
  rec.c = select(2, UnitClass("player"))
  for skill, info in pairs(own) do
    local p = rec.p[skill]
    if not p then
      p = { t = 0, l = {} }
      rec.p[skill] = p
      changed = true
    end
    if p.r ~= info.rank or p.m ~= info.max then
      p.r, p.m = info.rank, info.max
      changed = true
    end
  end
  -- Skill data can be empty for a moment at login, so never wipe everything.
  if next(own) then
    for skill in pairs(rec.p) do
      if not own[skill] then
        rec.p[skill] = nil
        changed = true
      end
    end
  end
  if changed then
    Crafts.Changed()
    if ZR.CraftSync then ZR.CraftSync.QueueVersion() end
  end
end

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return (GetSpellInfo(id))
end

local function IsSmelting(name)
  return name ~= nil and (name == SpellName(SMELTING_SPELL) or name == "Smelting")
end

local function MatchOwn(own, ids, names)
  for _, id in ipairs(ids) do
    if own[id] then return id end
  end
  for skill, o in pairs(own) do
    for _, n in ipairs(names) do
      if o.name == n then return skill end
    end
  end
  for _, n in ipairs(names) do
    if own[MINING] and IsSmelting(n) then return MINING end
  end
end

local function OutputItem(id)
  local s = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(id, false)
  return s and s.outputItemID or 0
end

-- Linked, guild and NPC windows show someone else's recipes.
local function IsOwnWindow()
  local T = C_TradeSkillUI
  if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end
  if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return false end
  if T.IsNPCCrafting and T.IsNPCCrafting() then return false end
  return true
end

local function Same(a, b)
  for k, v in pairs(a) do
    if b[k] ~= v then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local tradeOpen, scanToken = false, 0

-- Returns the profession read, or nil if the window had nothing yet.
local function Scan(force)
  if not (tradeOpen or force) or not IsOwnWindow() or not C_TradeSkillUI.GetBaseProfessionInfo then return end
  local info = C_TradeSkillUI.GetBaseProfessionInfo()
  if not info then return end
  local skill = MatchOwn(OwnProfessions(), { info.professionID, info.parentProfessionID },
    { info.professionName, info.parentProfessionName })
  if not skill then return end
  Crafts.UpdateOwn()
  local me = ZR.PlayerName()
  local p = Crafts.GetProf(me, skill)
  if not p then return end

  local ids, complete
  if C_TradeSkillUI.GetAllRecipeIDs then
    ids, complete = C_TradeSkillUI.GetAllRecipeIDs(), true
  else
    -- The filtered list follows the window's search, so only ever add to it.
    ids, complete = C_TradeSkillUI.GetFilteredRecipeIDs and C_TradeSkillUI.GetFilteredRecipeIDs(), false
  end
  local list, found = complete and {} or CopyTable(p.l or {}), 0
  for _, id in ipairs(ids or {}) do
    local r = C_TradeSkillUI.GetRecipeInfo(id)
    if r and r.learned then
      list[id] = OutputItem(id)
      found = found + 1
    end
  end
  if found == 0 then return end
  if not Same(list, p.l or {}) then
    p.l, p.t = list, ZR.Now()
    Crafts.Changed()
    if ZR.CraftSync then ZR.CraftSync.SendProf(me, skill) end
  end
  return skill
end

local auto = { ok = {}, tries = {}, retryAt = {} }

local function ScheduleScan(delay)
  scanToken = scanToken + 1
  local token = scanToken
  C_Timer.After(delay, function()
    if token ~= scanToken then return end
    local skill = Scan()
    if skill then auto.ok[skill] = true end
  end)
end

-- Background scan: opens each profession hidden and muted, reads it, closes it.
local MAX_TRIES = 5
local WAIT = 6
local SMELT_COPPER = 2657
-- The professions window open and close sounds, so nothing else goes quiet.
local WINDOW_SOUNDS = { 567507, 567433 }
local AutoNext

local function PanelOpen()
  if not GetUIPanel then return false end
  return GetUIPanel("left") or GetUIPanel("center") or GetUIPanel("doublewide") or GetUIPanel("fullscreen")
end

-- Smelting may live on its own skill line, so Mining gets extra ids to try.
local function OpenIds(skill)
  local ids = { skill }
  if skill == MINING and C_TradeSkillUI.GetTradeSkillLineForRecipe then
    local ok, line, _, parent = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, SMELT_COPPER)
    if ok then
      for _, id in ipairs({ parent, line }) do
        if id and id ~= skill then ids[#ids + 1] = id end
      end
    end
  end
  return ids
end

local function MuteWindow(mute)
  local fn = mute and MuteSoundFile or UnmuteSoundFile
  if not fn then return end
  for _, id in ipairs(WINDOW_SOUNDS) do pcall(fn, id) end
end

local function AutoFinish(got)
  if auto.timer then
    auto.timer:Cancel()
    auto.timer = nil
  end
  local job = auto.job
  if not job then return end
  auto.job = nil
  pcall(C_TradeSkillUI.CloseTradeSkill)
  tradeOpen = false
  if got then
    auto.ok[job.skill] = true
    auto.read = true
  elseif job.at < #job.ids then
    job.at = job.at + 1
    table.insert(auto.queue, 1, job)
  else
    -- Data can lag right after login; back off and try again.
    local n = (auto.tries[job.skill] or 0) + 1
    auto.tries[job.skill] = n
    auto.retryAt[job.skill] = GetTime() + 30 * n
    C_Timer.After(30 * n + 1, Crafts.AutoScan)
  end
  C_Timer.After(0.5, function()
    local f = _G.ProfessionsFrame
    if f and auto.hidden then f:SetAlpha(1) end
    auto.hidden = nil
    MuteWindow(false)
    AutoNext()
  end)
end

AutoNext = function()
  if not auto.queue or #auto.queue == 0 then
    auto.queue = nil
    if auto.read and ZR.CraftSync then ZR.CraftSync.QueueVersion() end
    auto.read = nil
    return
  end
  -- Never interrupt the player; try again a bit later.
  if InCombatLockdown() or tradeOpen or PanelOpen() or UnitCastingInfo("player") then
    C_Timer.After(15, AutoNext)
    return
  end
  local job = table.remove(auto.queue, 1)
  if ProfessionsFrame_LoadUI and not _G.ProfessionsFrame then pcall(ProfessionsFrame_LoadUI) end
  local f = _G.ProfessionsFrame
  if f then
    f:SetAlpha(0)
    auto.hidden = true
  end
  MuteWindow(true)
  auto.job = job
  auto.timer = C_Timer.NewTimer(WAIT, function()
    auto.timer = nil
    AutoFinish(Scan(true) == job.skill)
  end)
  local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, job.ids[job.at])
  if not ok or opened == false then AutoFinish(false) end
end

function Crafts.AutoScan()
  if auto.queue or not C_TradeSkillUI.OpenTradeSkill or not Crafts.Store() then return end
  local rec = Crafts.Get(ZR.PlayerName())
  local list, now = {}, GetTime()
  for skill in pairs(rec and rec.p or {}) do
    if Crafts.HasRecipes(skill) and not auto.ok[skill] and (auto.tries[skill] or 0) < MAX_TRIES
      and (auto.retryAt[skill] or 0) <= now then
      list[#list + 1] = { skill = skill, ids = OpenIds(skill), at = 1 }
    end
  end
  if #list == 0 then return end
  auto.queue = list
  AutoNext()
end

ZR.RegisterEvent("TRADE_SKILL_SHOW", function()
  tradeOpen = true
  if auto.job then return end
  if auto.hidden and _G.ProfessionsFrame then _G.ProfessionsFrame:SetAlpha(1) end
  ScheduleScan(1)
end)
ZR.RegisterEvent("TRADE_SKILL_CLOSE", function() tradeOpen = false end)
ZR.RegisterEvent("TRADE_SKILL_LIST_UPDATE", function()
  if auto.job then
    if C_TradeSkillUI.IsDataSourceChanging and C_TradeSkillUI.IsDataSourceChanging() then return end
    -- Keep waiting until the list really holds this profession.
    if Scan(true) == auto.job.skill then AutoFinish(true) end
  elseif tradeOpen then
    ScheduleScan(0.5)
  end
end)

ZR.RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", function()
  if tradeOpen then ScheduleScan(0.5) end
end)

local skillTimer
ZR.RegisterEvent("SKILL_LINES_CHANGED", function()
  if skillTimer then skillTimer:Cancel() end
  skillTimer = C_Timer.NewTimer(2, function()
    Crafts.UpdateOwn()
    Crafts.AutoScan()
  end)
end)

-- Recipe scrolls and trainers both land here, no window needed.
ZR.RegisterEvent("NEW_RECIPE_LEARNED", function(_, recipeID)
  if not recipeID or not C_TradeSkillUI.GetTradeSkillLineForRecipe then return end
  local skillLine, lineName, parent = C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID)
  local skill = MatchOwn(OwnProfessions(), { skillLine, parent }, { lineName })
  if not skill then return end
  local me = ZR.PlayerName()
  local p = Crafts.GetProf(me, skill)
  if not p then
    Crafts.UpdateOwn()
    p = Crafts.GetProf(me, skill)
  end
  if not p or (p.l and p.l[recipeID]) then return end
  local prev = p.t or 0
  p.l = p.l or {}
  p.l[recipeID] = OutputItem(recipeID)
  p.t = ZR.Now()
  Crafts.Changed()
  if ZR.CraftSync then ZR.CraftSync.SendAdd(me, skill, prev, p.t, recipeID, p.l[recipeID]) end
end)

ZR.RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
  ZR.Fire("CraftNamesLoaded")
end)

-- Static item info is kept across rebuilds so names load only once.
local entries = {}

local function NewEntry(item, recipe)
  local e = { item = item > 0 and item or nil, recipe = recipe }
  if e.item then
    local _, _, _, _, icon, classID, subClassID = C_Item.GetItemInfoInstant(e.item)
    e.icon, e.c, e.s = icon, classID, subClassID
    local inv = C_Item.GetItemInventoryTypeByID and C_Item.GetItemInventoryTypeByID(e.item)
    if inv == Enum.InventoryType.IndexRobeType then inv = Enum.InventoryType.IndexChestType end
    e.i = inv
  else
    e.name = SpellName(recipe)
    e.icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(recipe)
    e.c, e.s = ZR.ItemCategories.ENCHANT, ZR.ItemCategories.EnchantSlot(e.name)
  end
  return e
end

-- Everything the guild can craft, keyed by item, or by negative spell for enchants.
function Crafts.Index()
  if index then return index end
  index = {}
  for name, rec in pairs(Crafts.Store() or {}) do
    if Crafts.Visible(name) then
      for skill, p in pairs(rec.p or {}) do
        for recipe, item in pairs(p.l or {}) do
          local key = item > 0 and item or -recipe
          local e = entries[key]
          if not e then
            e = NewEntry(item, recipe)
            e.key = key
            entries[key] = e
          end
          if not index[key] then
            index[key] = e
            e.crafters, e.by, e.skills, e.skill = {}, {}, {}, skill
          end
          if not e.by[name] then
            e.crafters[#e.crafters + 1] = name
            e.by[name] = skill
          end
          e.skills[skill] = true
        end
      end
    end
  end
  return index
end

function Crafts.Name(e)
  if e.name or not e.item then return e.name end
  local name = C_Item.GetItemNameByID(e.item)
  if name then
    e.name, e.quality = name, C_Item.GetItemQualityByID(e.item)
  elseif not e.requested then
    e.requested = true
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(e.item) end
  end
  return e.name
end

function Crafts.LoadNames()
  for _, e in pairs(Crafts.Index()) do Crafts.Name(e) end
end

function Crafts.Members(skill)
  local out = {}
  for name, rec in pairs(Crafts.Store() or {}) do
    if rec.p and rec.p[skill] and Crafts.Visible(name) then out[#out + 1] = name end
  end
  return out
end

function Crafts.RecipesOf(name, skill)
  local p = Crafts.GetProf(name, skill)
  local idx, out = Crafts.Index(), {}
  for recipe, item in pairs(p and p.l or {}) do
    local e = idx[item > 0 and item or -recipe]
    if e then out[#out + 1] = e end
  end
  return out
end

function Crafts.OwnHint()
  if auto.job then return "Reading your professions..." end
  -- Opening a profession now would shove the guild window aside.
  if auto.queue then return "Your professions are read once this window closes." end
  local rec = Crafts.Get(ZR.PlayerName())
  for skill, p in pairs(rec and rec.p or {}) do
    if (p.t or 0) == 0 and Crafts.HasRecipes(skill) then
      return ("Could not read %s yet. Opening it once fixes that."):format(Crafts.ProfName(skill))
    end
  end
end

function Crafts.Prune()
  local s = Crafts.Store()
  if not s or not ZR.RosterComplete() then return end
  local removed = false
  for name in pairs(s) do
    if not Crafts.Visible(name) then
      s[name] = nil
      removed = true
    end
  end
  if removed then Crafts.Changed() end
end

ZR.On("GuildReady", function()
  index = nil
  C_Timer.After(5, Crafts.UpdateOwn)
  C_Timer.After(8, Crafts.AutoScan)
  C_Timer.After(60, Crafts.Prune)
end)
ZR.On("RosterChanged", function() index = nil end)
