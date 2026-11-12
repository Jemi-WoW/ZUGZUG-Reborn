local _, ZR = ...
local UI = ZR.UI
local Crafts = ZR.Crafts
local Cat = ZR.ItemCategories

-- The friends list dots, so online looks the same everywhere.
local DOT_ON = "Interface\\FriendsFrame\\StatusIcon-Online"
local DOT_OFF = "Interface\\FriendsFrame\\StatusIcon-Offline"
local QUESTION_MARK = 134400
local SEP = "  |cff888888>|r  "

local view, items, members, recipes, roster
local state = { search = "", cat = nil, prof = nil, item = nil, member = nil, memberSkill = nil, roster = true }
local dirty = true
local pendingSearch
local Update, Back

-- The mouse side button steps back, like a browser.
local function MouseBack(button)
  if button ~= "Button4" then return false end
  Back()
  return true
end

local itemSort = { key = "name", asc = true }
local memberSort = { key = "online", asc = true }
local recipeSort = { key = "name", asc = true }
local rosterSort = { key = "online", asc = true }

local ITEM_COLUMNS = {
  { title = "Item", width = 270, key = "name" },
  { title = "Profession", width = 110, key = "prof" },
  { title = "Crafters", width = 0, key = "count" },
}
local MEMBER_COLUMNS = {
  { title = NAME or "Name", width = 170, key = "name" },
  { title = "Skill", width = 70, key = "skill" },
  { title = "Recipes", width = 64, key = "recipes" },
  { title = "Last online", width = 96, key = "online" },
  { title = "Updated", width = 0, key = "updated" },
}
local PROF_SLOTS, SLOT_WIDTH = 3, 80
local ROSTER_COLUMNS = {
  { title = NAME or "Name", width = 170, key = "name" },
  { title = "Professions", width = PROF_SLOTS * SLOT_WIDTH + 10, key = "profs" },
  { title = "Last online", width = 0, key = "online" },
}
local RECIPE_COLUMNS = {
  { title = "Item", width = 300, key = "name" },
  { title = TYPE or "Type", width = 0, key = "type" },
}

local function ColumnX(columns, index)
  local x = 0
  for i = 1, index - 1 do x = x + columns[i].width - 2 end
  return x
end

local function Presence(name)
  if name == ZR.PlayerName() then return true, "Online" end
  local info = ZR.RosterInfo(name)
  if info and info.online then return true, "Online" end
  if info and info.away then return false, ZR.TimeAgo(ZR.Now() - info.away) end
  return false, ""
end

local function Dot(on)
  return "|T" .. (on and DOT_ON or DOT_OFF) .. ":14:14|t"
end

local function ClassOf(name)
  local info = ZR.RosterInfo(name)
  local rec = Crafts.Get(name)
  return (info and info.classFile) or (rec and rec.c)
end

local function SkillText(p)
  if not p or not p.m or p.m <= 0 then return "-" end
  return p.r .. "/" .. p.m
end

local function ClassIcon(name)
  local class = ClassOf(name)
  return class and ("|A:classicon-%s:14:14|a "):format(class:lower()) or ""
end

local function SortedCrafters(e)
  local list = {}
  for _, n in ipairs(e.crafters or {}) do
    local p = Crafts.GetProf(n, e.by[n])
    list[#list + 1] = { name = n, on = (Presence(n)), r = p and p.r or 0 }
  end
  table.sort(list, function(a, b)
    if a.on ~= b.on then return a.on end
    if a.r ~= b.r then return a.r > b.r end
    return a.name < b.name
  end)
  return list
end

local function CraftersText(e)
  local list, parts = SortedCrafters(e), {}
  for i = 1, math.min(3, #list) do
    parts[i] = ClassIcon(list[i].name) .. (list[i].on and "|cff40ff40" or "|cff9d9d9d") .. list[i].name .. "|r"
  end
  local text = table.concat(parts, ", ")
  if #list > 3 then text = text .. ("  |cffffd100+%d|r"):format(#list - 3) end
  return text
end

local function TypeText(e)
  if e.typeText then return e.typeText end
  local t = ""
  if e.c == Cat.ENCHANT then
    t = "Enchant " .. (e.s or "")
  elseif e.c and e.s then
    t = C_Item.GetItemSubClassInfo(e.c, e.s) or ""
    local slot = e.i and e.i > 0 and C_Item.GetItemInventorySlotInfo(e.i)
    if slot and slot ~= "" and slot ~= t then t = t .. " - " .. slot end
  end
  e.typeText = t
  return t
end

local function SetQualityColor(fs, e)
  if e.quality and C_Item.GetItemQualityColor then
    local r, g, b = C_Item.GetItemQualityColor(e.quality)
    if r then
      fs:SetTextColor(r, g, b)
      return
    end
  end
  fs:SetTextColor(1, 1, 1)
end

local function LinkOf(e)
  if e.item then return select(2, C_Item.GetItemInfo(e.item)) end
  return C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(e.recipe) or nil
end

local function InsertLink(link)
  local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
  if link and insert then insert(link) end
end

local function Whisper(name, e)
  local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
  if tell then tell(name) end
  if e then InsertLink(LinkOf(e)) end
end

local function EntryTooltip(owner, e)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if e.item then GameTooltip:SetItemByID(e.item) else GameTooltip:SetSpellByID(e.recipe) end
end

local function ItemTooltip(row)
  local e = row.data
  if not e then return end
  EntryTooltip(row, e)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Crafted by", 1, 0.82, 0)
  for _, c in ipairs(SortedCrafters(e)) do
    local p = Crafts.GetProf(c.name, e.by[c.name])
    GameTooltip:AddDoubleLine(Dot(c.on) .. " " .. ZR.ColorName(c.name, ClassOf(c.name)), SkillText(p),
      1, 1, 1, 0.7, 0.7, 0.7)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click to see the crafters. Shift-click to link it.", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function RecipeTooltip(row)
  if not row.data then return end
  EntryTooltip(row, row.data)
  GameTooltip:Show()
end

local function Matches(e, skill)
  if skill and not e.skills[skill] then return false end
  if not Cat.Matches(state.cat, e) then return false end
  if state.search ~= "" then
    local name = Crafts.Name(e)
    return name ~= nil and name:lower():find(state.search, 1, true) ~= nil
  end
  return true
end

local function Sort(list, s, value, tiebreak)
  table.sort(list, function(a, b)
    local va, vb = value(a, s.key), value(b, s.key)
    if va ~= vb then
      if s.asc then return va < vb end
      return va > vb
    end
    return tiebreak(a) < tiebreak(b)
  end)
end

local function EntryName(e)
  return (Crafts.Name(e) or "~"):lower()
end

local function EntryKey(e)
  return e.key
end

local function ItemValue(e, key)
  if key == "prof" then return Crafts.ProfName(e.skill) end
  if key == "count" then return -#e.crafters end
  return EntryName(e)
end

local function RecipeValue(e, key)
  if key == "type" then return TypeText(e) end
  return EntryName(e)
end

local function MemberValue(d, key)
  if key == "skill" then return -(d.p.r or 0) end
  if key == "recipes" then return -Crafts.Count(d.p) end
  if key == "updated" then return -(d.p.t or 0) end
  if key == "online" then return d.on and -1 or (d.away or 1e12) end
  return d.name:lower()
end

local function RosterValue(d, key)
  if key == "profs" then return d.profText end
  return MemberValue(d, key)
end

local function MemberData(name, skill)
  local on, seen = Presence(name)
  local info = ZR.RosterInfo(name)
  return {
    name = name, skill = skill, p = Crafts.GetProf(name, skill) or { t = 0 },
    on = on, seen = seen, away = info and info.away, class = ClassOf(name),
  }
end

local function Mode()
  if state.member then return "recipes" end
  if state.item then return "crafters" end
  if state.roster then return "roster" end
  if state.prof and state.search == "" and not state.cat then return "members" end
  return "items"
end

local function OpenMember(d)
  state.member, state.memberSkill = d.name, d.skill
  Update()
end

local function InitItemRow(row, e)
  if not row.Name then
    UI.StyleRow(row)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT", 4, 0)
    row.Name = UI.CreateCell(row)
    row.Name:SetPoint("LEFT", 24, 0)
    row.Name:SetWidth(ITEM_COLUMNS[1].width - 28)
    row.Prof = UI.CreateCell(row)
    row.Prof:SetPoint("LEFT", ColumnX(ITEM_COLUMNS, 2) + 6, 0)
    row.Prof:SetWidth(ITEM_COLUMNS[2].width - 10)
    row.Crafters = UI.CreateCell(row)
    row.Crafters:SetPoint("LEFT", ColumnX(ITEM_COLUMNS, 3) + 6, 0)
    row.Crafters:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnEnter", ItemTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:RegisterForClicks("LeftButtonUp", "Button4Up")
    row:SetScript("OnClick", function(self, button)
      if MouseBack(button) then return end
      if IsModifiedClick("CHATLINK") then
        InsertLink(LinkOf(self.data))
        return
      end
      state.item = self.data
      Update()
    end)
  end
  row.data = e
  row.Icon:SetTexture(e.icon or QUESTION_MARK)
  row.Name:SetText(Crafts.Name(e) or (RETRIEVING_ITEM_INFO or "Loading..."))
  SetQualityColor(row.Name, e)
  row.Prof:SetText(Crafts.ProfName(e.skill))
  row.Crafters:SetText(CraftersText(e))
end

local function ShowMemberTooltip(owner, d)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip_SetTitle(GameTooltip, Dot(d.on) .. " " .. ZR.ColorName(d.name, d.class))
  GameTooltip:AddDoubleLine(Crafts.ProfName(d.skill), SkillText(d.p), 1, 0.82, 0, 1, 1, 1)
  if Crafts.HasRecipes(d.skill) then
    if (d.p.t or 0) > 0 then
      GameTooltip:AddDoubleLine("Recipes", Crafts.Count(d.p), 1, 0.82, 0, 1, 1, 1)
      GameTooltip:AddDoubleLine("Updated", ZR.TimeAgo(d.p.t), 1, 0.82, 0, 1, 1, 1)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Click to see everything they can make.", 0.6, 0.6, 0.6)
    else
      GameTooltip:AddLine("Not shared yet. It shares automatically once they log in with ZUGZUG Reborn.", 0.6, 0.6, 0.6, true)
    end
  end
  GameTooltip:Show()
end

local function MemberTooltip(row)
  if row.data then ShowMemberTooltip(row, row.data) end
end

local function InitMemberRow(row, d)
  if not row.Name then
    UI.StyleRow(row)
    row.Dot = row:CreateTexture(nil, "ARTWORK")
    row.Dot:SetSize(14, 14)
    row.Dot:SetPoint("LEFT", 4, 0)
    row.Class = row:CreateTexture(nil, "ARTWORK")
    row.Class:SetSize(16, 16)
    row.Class:SetPoint("LEFT", 20, 0)
    row.Name = UI.CreateCell(row)
    row.Name:SetPoint("LEFT", 40, 0)
    row.Name:SetWidth(MEMBER_COLUMNS[1].width - 44)
    row.Skill = UI.CreateCell(row, "GameFontHighlightSmall", "CENTER")
    row.Skill:SetPoint("LEFT", ColumnX(MEMBER_COLUMNS, 2), 0)
    row.Skill:SetWidth(MEMBER_COLUMNS[2].width - 4)
    row.Recipes = UI.CreateCell(row, "GameFontHighlightSmall", "CENTER")
    row.Recipes:SetPoint("LEFT", ColumnX(MEMBER_COLUMNS, 3), 0)
    row.Recipes:SetWidth(MEMBER_COLUMNS[3].width - 4)
    row.Seen = UI.CreateCell(row)
    row.Seen:SetPoint("LEFT", ColumnX(MEMBER_COLUMNS, 4) + 6, 0)
    row.Seen:SetWidth(MEMBER_COLUMNS[4].width - 10)

    row.Whisper = UI.CreateButton(row, WHISPER or "Whisper", 72, 18)
    row.Whisper:SetPoint("RIGHT", -2, 0)
    row.Whisper:SetScript("OnClick", function(self) Whisper(self:GetParent().data.name, state.item) end)
    UI.SetButtonTooltip(row.Whisper, function()
      if state.item then return "Whisper", "Opens a whisper with the item linked." end
      return "Whisper", "Opens a whisper to them."
    end)

    row.Updated = UI.CreateCell(row)
    row.Updated:SetPoint("LEFT", ColumnX(MEMBER_COLUMNS, 5) + 6, 0)
    row.Updated:SetPoint("RIGHT", row.Whisper, "LEFT", -6, 0)
    row:SetScript("OnEnter", MemberTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:RegisterForClicks("LeftButtonUp", "Button4Up")
    row:SetScript("OnClick", function(self, button)
      if MouseBack(button) then return end
      if Crafts.HasRecipes(self.data.skill) then OpenMember(self.data) end
    end)
  end
  row.data = d
  row.Dot:SetTexture(d.on and DOT_ON or DOT_OFF)
  if d.class then
    row.Class:SetAtlas("classicon-" .. d.class:lower())
    row.Class:Show()
  else
    row.Class:Hide()
  end
  row.Name:SetText(ZR.ColorName(d.name, d.class))
  row.Skill:SetText(SkillText(d.p))
  local shared = (d.p.t or 0) > 0
  if not Crafts.HasRecipes(d.skill) then
    row.Recipes:SetText("")
    row.Updated:SetText("")
  elseif shared then
    row.Recipes:SetText(Crafts.Count(d.p))
    row.Updated:SetText(ZR.TimeAgo(d.p.t))
  else
    row.Recipes:SetText("-")
    row.Updated:SetText("|cff888888Not shared yet|r")
  end
  row.Seen:SetText(d.seen)
  if d.on then row.Seen:SetTextColor(0.25, 1, 0.25) else row.Seen:SetTextColor(0.7, 0.7, 0.7) end
  row.Whisper:SetEnabled(d.name ~= ZR.PlayerName())
end

local function RosterTooltip(row)
  local d = row.data
  if not d then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip_SetTitle(GameTooltip, Dot(d.on) .. " " .. ZR.ColorName(d.name, d.class))
  for _, prof in ipairs(d.profs) do
    GameTooltip:AddDoubleLine(Crafts.ProfName(prof.id), SkillText(Crafts.GetProf(d.name, prof.id)), 1, 0.82, 0, 1, 1, 1)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click a profession to see everything they can make.", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function OpenSlot(self, button)
  if MouseBack(button) then return end
  local d = self:GetParent().data
  if Crafts.HasRecipes(self.prof.id) then OpenMember(MemberData(d.name, self.prof.id)) end
end

local function SlotTooltip(self)
  ShowMemberTooltip(self, MemberData(self:GetParent().data.name, self.prof.id))
end

local function CreateSlot(row, i)
  local s = CreateFrame("Button", nil, row)
  s:SetSize(SLOT_WIDTH - 4, 18)
  s:SetPoint("LEFT", ColumnX(ROSTER_COLUMNS, 2) + 4 + (i - 1) * SLOT_WIDTH, 0)
  s:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar", "ADD")
  s.Icon = s:CreateTexture(nil, "ARTWORK")
  s.Icon:SetSize(16, 16)
  s.Icon:SetPoint("LEFT", 2, 0)
  s.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  s.Text = UI.CreateCell(s)
  s.Text:SetPoint("LEFT", s.Icon, "RIGHT", 4, 0)
  s.Text:SetPoint("RIGHT", -2, 0)
  s:RegisterForClicks("LeftButtonUp", "Button4Up")
  s:SetScript("OnClick", OpenSlot)
  s:SetScript("OnEnter", SlotTooltip)
  s:SetScript("OnLeave", GameTooltip_Hide)
  return s
end

local function InitRosterRow(row, d)
  if not row.Name then
    UI.StyleRow(row)
    row.Dot = row:CreateTexture(nil, "ARTWORK")
    row.Dot:SetSize(14, 14)
    row.Dot:SetPoint("LEFT", 4, 0)
    row.Class = row:CreateTexture(nil, "ARTWORK")
    row.Class:SetSize(16, 16)
    row.Class:SetPoint("LEFT", 20, 0)
    row.Name = UI.CreateCell(row)
    row.Name:SetPoint("LEFT", 40, 0)
    row.Name:SetWidth(ROSTER_COLUMNS[1].width - 44)
    row.Slots = {}
    for i = 1, PROF_SLOTS do row.Slots[i] = CreateSlot(row, i) end
    row.Whisper = UI.CreateButton(row, WHISPER or "Whisper", 72, 18)
    row.Whisper:SetPoint("RIGHT", -2, 0)
    row.Whisper:SetScript("OnClick", function(self) Whisper(self:GetParent().data.name) end)
    UI.SetButtonTooltip(row.Whisper, function() return "Whisper", "Opens a whisper to them." end)
    row.Seen = UI.CreateCell(row)
    row.Seen:SetPoint("LEFT", ColumnX(ROSTER_COLUMNS, 3) + 6, 0)
    row.Seen:SetPoint("RIGHT", row.Whisper, "LEFT", -6, 0)
    row:SetScript("OnEnter", RosterTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:RegisterForClicks("LeftButtonUp", "Button4Up")
    row:SetScript("OnClick", function(self, button)
      if MouseBack(button) then return end
      for _, prof in ipairs(self.data.profs) do
        if Crafts.HasRecipes(prof.id) then return OpenMember(MemberData(self.data.name, prof.id)) end
      end
    end)
  end
  row.data = d
  row.Dot:SetTexture(d.on and DOT_ON or DOT_OFF)
  if d.class then
    row.Class:SetAtlas("classicon-" .. d.class:lower())
    row.Class:Show()
  else
    row.Class:Hide()
  end
  row.Name:SetText(ZR.ColorName(d.name, d.class))
  for i, s in ipairs(row.Slots) do
    local prof = d.profs[i]
    s.prof = prof
    s:SetShown(prof ~= nil)
    if prof then
      s.Icon:SetTexture(prof.icon)
      s.Text:SetText(SkillText(Crafts.GetProf(d.name, prof.id)))
    end
  end
  row.Seen:SetText(d.seen)
  if d.on then row.Seen:SetTextColor(0.25, 1, 0.25) else row.Seen:SetTextColor(0.7, 0.7, 0.7) end
  row.Whisper:SetEnabled(d.name ~= ZR.PlayerName())
end

local function InitRecipeRow(row, e)
  if not row.Name then
    UI.StyleRow(row)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT", 4, 0)
    row.Name = UI.CreateCell(row)
    row.Name:SetPoint("LEFT", 24, 0)
    row.Name:SetWidth(RECIPE_COLUMNS[1].width - 28)
    row.Whisper = UI.CreateButton(row, WHISPER or "Whisper", 72, 18)
    row.Whisper:SetPoint("RIGHT", -2, 0)
    row.Whisper:SetScript("OnClick", function(self) Whisper(state.member, self:GetParent().data) end)
    UI.SetButtonTooltip(row.Whisper, function() return "Whisper", "Opens a whisper with the item linked." end)
    row.Type = UI.CreateCell(row)
    row.Type:SetPoint("LEFT", ColumnX(RECIPE_COLUMNS, 2) + 6, 0)
    row.Type:SetPoint("RIGHT", row.Whisper, "LEFT", -6, 0)
    row:SetScript("OnEnter", RecipeTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:RegisterForClicks("LeftButtonUp", "Button4Up")
    row:SetScript("OnClick", function(self, button)
      if MouseBack(button) then return end
      if IsModifiedClick("CHATLINK") then InsertLink(LinkOf(self.data)) end
    end)
  end
  row.data = e
  row.Icon:SetTexture(e.icon or QUESTION_MARK)
  row.Name:SetText(Crafts.Name(e) or (RETRIEVING_ITEM_INFO or "Loading..."))
  SetQualityColor(row.Name, e)
  row.Type:SetText(TypeText(e))
  row.Whisper:SetEnabled(state.member ~= ZR.PlayerName())
end

local function ItemRows()
  local rows = {}
  for _, e in pairs(Crafts.Index()) do
    if Matches(e, state.prof) then rows[#rows + 1] = e end
  end
  Sort(rows, itemSort, ItemValue, EntryKey)
  return rows
end

local function MemberRows()
  local rows = {}
  if state.item then
    for _, n in ipairs(state.item.crafters or {}) do rows[#rows + 1] = MemberData(n, state.item.by[n]) end
  else
    for _, n in ipairs(Crafts.Members(state.prof)) do rows[#rows + 1] = MemberData(n, state.prof) end
  end
  Sort(rows, memberSort, MemberValue, function(d) return d.name end)
  return rows
end

local function RosterRows()
  local rows = {}
  for name, rec in pairs(Crafts.Store() or {}) do
    if Crafts.Visible(name) and name:lower():find(state.search, 1, true) then
      local profs, names = {}, {}
      for _, prof in ipairs(Crafts.PROFESSIONS) do
        if rec.p and rec.p[prof.id] then
          profs[#profs + 1] = prof
          names[#names + 1] = Crafts.ProfName(prof.id)
        end
      end
      if #profs > 0 then
        local d = MemberData(name)
        d.profs, d.profText = profs, table.concat(names, " ")
        rows[#rows + 1] = d
      end
    end
  end
  Sort(rows, rosterSort, RosterValue, function(d) return d.name end)
  return rows
end

local function RecipeRows()
  local rows = {}
  for _, e in ipairs(Crafts.RecipesOf(state.member, state.memberSkill)) do
    if Matches(e) then rows[#rows + 1] = e end
  end
  Sort(rows, recipeSort, RecipeValue, EntryKey)
  return rows
end

local function RefreshProfButtons()
  for _, b in ipairs(view.ProfButtons) do
    b.count = #Crafts.Members(b.prof.id)
    b.Selected:SetShown(state.prof == b.prof.id)
    b.Icon:SetDesaturated(b.count == 0)
    b.Icon:SetAlpha(b.count == 0 and 0.5 or 1)
  end
end

local function Plural(n, word)
  return n .. " " .. word .. (n == 1 and "" or "s")
end

local function Filtering()
  return state.search ~= "" or state.cat ~= nil
end

Update = function()
  dirty = false
  if not view or not view:IsVisible() then return end
  RefreshProfButtons()
  local mode = Mode()
  items:SetShown(mode == "items")
  members:SetShown(mode == "members" or mode == "crafters")
  recipes:SetShown(mode == "recipes")
  roster:SetShown(mode == "roster")
  view.Members:SetText(state.roster and "All Items" or "Members")
  if view.Search.Instructions then view.Search.Instructions:SetText(state.roster and "Search members" or "Search items") end
  local onItem = mode == "crafters" and state.item ~= nil
  view.ItemBar:SetShown(onItem)
  members:SetPoint("TOPLEFT", view.Categories, "TOPRIGHT", 6, onItem and -34 or -2)
  if onItem then
    local e = state.item
    view.ItemBar.Icon:SetTexture(e.icon or QUESTION_MARK)
    view.ItemBar.Name:SetText(Crafts.Name(e) or (RETRIEVING_ITEM_INFO or "Loading..."))
    SetQualityColor(view.ItemBar.Name, e)
    view.ItemBar.Prof:SetText(Crafts.ProfName(e.skill))
  end

  local rows, crumb, count, empty = {}, "", nil, nil
  if not Crafts.Store() then
    items:SetRows(rows)
    empty = "Loading guild data..."
  elseif mode == "recipes" then
    rows = RecipeRows()
    recipes:SetRows(rows)
    crumb = Crafts.ProfName(state.memberSkill) .. SEP .. ZR.ColorName(state.member, ClassOf(state.member))
    count = Plural(#rows, "recipe")
    empty = Filtering() and "Nothing matches your search." or "They have not shared any recipes yet."
  elseif mode == "crafters" then
    rows = MemberRows()
    members:SetRows(rows)
    crumb = (state.prof and (Crafts.ProfName(state.prof) .. SEP) or "") .. (Crafts.Name(state.item) or "")
    count = Plural(#rows, "crafter")
  elseif mode == "roster" then
    rows = RosterRows()
    roster:SetRows(rows)
    crumb = "Guild members"
    count = Plural(#rows, "member")
    empty = state.search ~= "" and "Nobody matches your search." or "Nobody in your guild has shared a profession yet."
  elseif mode == "members" then
    rows = MemberRows()
    members:SetRows(rows)
    crumb = Crafts.ProfName(state.prof)
    count = Plural(#rows, "member")
    empty = ("Nobody in your guild has shared %s yet."):format(Crafts.ProfName(state.prof))
  else
    rows = ItemRows()
    items:SetRows(rows)
    crumb = state.prof and Crafts.ProfName(state.prof) or "All professions"
    if state.cat then crumb = crumb .. SEP .. state.cat.name end
    count = Plural(#rows, "item")
    if next(Crafts.Index()) == nil then
      empty = "No recipes shared yet.\nGuild members with ZUGZUG Reborn share theirs automatically when they log in."
    else
      empty = "Nothing matches your search."
    end
  end

  view.Empty:SetText(empty or "")
  view.Empty:SetShown(#rows == 0 and empty ~= nil)
  view.Crumb:SetText(crumb .. (count and ("  |cff888888-  " .. count .. "|r") or ""))
  view.Back:SetEnabled(state.member ~= nil or state.item ~= nil or state.prof ~= nil or not state.roster)
  local canWhisper = mode == "recipes" and state.member ~= ZR.PlayerName()
  view.Whisper:SetShown(canWhisper)
  view.Status:SetPoint("RIGHT", canWhisper and view.Whisper or view.Back, "LEFT", -10, 0)
  if ZR.CraftSync.Busy() then
    view.Status:SetText("|cffffd100Syncing guild recipes...|r")
  else
    view.Status:SetText(Crafts.OwnHint() or "")
  end
end

local function MarkDirty()
  dirty = true
end

Back = function()
  if state.member then
    state.member, state.memberSkill = nil, nil
  elseif state.item then
    state.item = nil
  else
    -- The members list is home, everything else steps back to it.
    state.prof, state.roster = nil, true
  end
  Update()
end

local function SetSearch(text)
  state.search = strtrim(text or ""):lower()
  state.item = nil
  Update()
end

function UI.CraftersSearch(text)
  state.roster = nil
  if view then
    view.Search:SetText(text or "")
    SetSearch(text)
  else
    pendingSearch = text
  end
end

local function BuildProfButtons(anchor)
  view.ProfButtons = {}
  local prev = anchor
  for i, prof in ipairs(Crafts.PROFESSIONS) do
    local b = CreateFrame("Button", nil, view)
    b:SetSize(24, 24)
    b:SetPoint("LEFT", prev, "RIGHT", i == 1 and 14 or 5, 0)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetAllPoints()
    b.Icon:SetTexture(prof.icon)
    b.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    -- Own texture, since a checked texture ignores ADD and covers the icon in black.
    b.Selected = b:CreateTexture(nil, "OVERLAY")
    b.Selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.Selected:SetBlendMode("ADD")
    b.Selected:SetAllPoints()
    b.Selected:Hide()
    b.prof = prof
    b:SetScript("OnClick", function(self)
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      state.prof = state.prof ~= self.prof.id and self.prof.id or nil
      state.item, state.member, state.memberSkill = nil, nil, nil
      state.roster = state.prof == nil or nil
      Update()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip_SetTitle(GameTooltip, Crafts.ProfName(self.prof.id))
      GameTooltip_AddNormalLine(GameTooltip, Plural(self.count or 0, "guild member") .. " shared")
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    view.ProfButtons[i] = b
    prev = b
  end
end

local function Sorter(s, columns)
  return function(_, index)
    local key = columns[index] and columns[index].key
    if not key then return end
    if s.key == key then s.asc = not s.asc else s.key, s.asc = key, true end
    Update()
  end
end

function UI.BuildCrafters(parent, inset)
  view = CreateFrame("Frame", nil, parent)
  view:SetAllPoints(parent)

  -- Only the content area, so the feature tabs above stay clickable.
  local catcher = CreateFrame("Frame", nil, view)
  catcher:SetAllPoints(inset)
  catcher:SetFrameLevel(view:GetFrameLevel())
  catcher:EnableMouse(true)
  catcher:SetScript("OnMouseUp", function(_, button) MouseBack(button) end)

  view.Search = CreateFrame("EditBox", nil, view, "SearchBoxTemplate")
  view.Search:SetSize(180, 20)
  view.Search:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -8)
  view.Search:SetAutoFocus(false)
  if view.Search.Instructions then view.Search.Instructions:SetText("Search items") end
  view.Search:HookScript("OnTextChanged", function(self) SetSearch(self:GetText()) end)

  BuildProfButtons(view.Search)

  view.Members = UI.CreateButton(view, "Members", 100, 22)
  view.Members:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -8, -7)
  view.Members:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    state.roster = not state.roster or nil
    state.prof, state.item, state.member, state.memberSkill = nil, nil, nil, nil
    -- Item names would hide everyone, and member names would hide every item.
    view.Search:SetText("")
    Update()
  end)
  UI.SetButtonTooltip(view.Members, function()
    if state.roster then return "All Items", "Back to every item the guild can craft." end
    return "Members", "Everyone in the guild with a profession, and which ones they have."
  end)

  view.Categories = UI.CreateCategoryList(view, function(node)
    state.cat = node
    state.item, state.roster = nil, nil
    Update()
  end)
  view.Categories:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -34)
  view.Categories:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 4, 4)

  items = UI.CreateTable(view, ITEM_COLUMNS, nil, 20, InitItemRow)
  members = UI.CreateTable(view, MEMBER_COLUMNS, { title = "", width = 80 }, 20, InitMemberRow)
  recipes = UI.CreateTable(view, RECIPE_COLUMNS, { title = "", width = 80 }, 20, InitRecipeRow)
  roster = UI.CreateTable(view, ROSTER_COLUMNS, { title = "", width = 80 }, 20, InitRosterRow)
  for _, t in ipairs({ items, members, recipes, roster }) do
    t:SetPoint("TOPLEFT", view.Categories, "TOPRIGHT", 6, -2)
    t:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -6, 6)
  end
  local bar = CreateFrame("Button", nil, view)
  bar:SetPoint("TOPLEFT", view.Categories, "TOPRIGHT", 8, -4)
  bar:SetPoint("RIGHT", inset, "RIGHT", -8, 0)
  bar:SetHeight(24)
  bar.Icon = bar:CreateTexture(nil, "ARTWORK")
  bar.Icon:SetSize(24, 24)
  bar.Icon:SetPoint("LEFT")
  bar.Name = UI.Text(bar, "GameFontNormalLarge")
  bar.Name:SetPoint("LEFT", bar.Icon, "RIGHT", 8, 0)
  bar.Prof = UI.Text(bar, "GameFontDisableSmall")
  bar.Prof:SetPoint("LEFT", bar.Name, "RIGHT", 10, -1)
  bar:SetScript("OnEnter", function(self)
    if not state.item then return end
    EntryTooltip(self, state.item)
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", GameTooltip_Hide)
  bar:SetScript("OnClick", function()
    if state.item and IsModifiedClick("CHATLINK") then InsertLink(LinkOf(state.item)) end
  end)
  bar:Hide()
  view.ItemBar = bar

  items.Header.sortingFunction = Sorter(itemSort, ITEM_COLUMNS)
  members.Header.sortingFunction = Sorter(memberSort, MEMBER_COLUMNS)
  recipes.Header.sortingFunction = Sorter(recipeSort, RECIPE_COLUMNS)
  roster.Header.sortingFunction = Sorter(rosterSort, ROSTER_COLUMNS)

  view.Empty = UI.Text(view, "GameFontDisable")
  view.Empty:SetPoint("CENTER", items, "CENTER", 0, -10)
  view.Empty:SetWidth(420)
  view.Empty:SetJustifyH("CENTER")

  view.Back = UI.CreateButton(view, BACK or "Back", 90, 20)
  view.Back:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -3, 3)
  view.Back:SetScript("OnClick", Back)

  view.Whisper = UI.CreateButton(view, WHISPER or "Whisper", 90, 20)
  view.Whisper:SetPoint("RIGHT", view.Back, "LEFT", -4, 0)
  view.Whisper:SetScript("OnClick", function() Whisper(state.member) end)
  UI.SetButtonTooltip(view.Whisper, function() return "Whisper", "Opens a whisper to " .. (state.member or "them") .. "." end)

  view.Crumb = UI.Text(view, "GameFontHighlightSmall")
  view.Crumb:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 7)
  view.Crumb:SetJustifyH("LEFT")
  view.Crumb:SetWordWrap(false)

  view.Status = UI.Text(view, "GameFontHighlightSmall")
  view.Status:SetPoint("RIGHT", view.Whisper, "LEFT", -10, 0)
  view.Status:SetPoint("LEFT", view.Crumb, "RIGHT", 16, 0)
  view.Status:SetJustifyH("RIGHT")
  view.Status:SetWordWrap(false)

  view:SetScript("OnShow", function()
    Crafts.LoadNames()
    Update()
  end)
  view.elapsed = 0
  view:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed > 0.3 then
      self.elapsed = 0
      if dirty then Update() end
    end
  end)

  ZR.On("CraftsChanged", MarkDirty)
  ZR.On("CraftNamesLoaded", MarkDirty)
  ZR.On("RosterChanged", MarkDirty)
  ZR.On("GuildReady", MarkDirty)

  if pendingSearch then
    view.Search:SetText(pendingSearch)
    pendingSearch = nil
  end
  return view
end
