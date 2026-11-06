local _, ZR = ...
local UI = ZR.UI
local Who = ZR.Who
local Contacts = ZR.Contacts

local view, tbl
local sortKey, sortAsc = "level", true

local COLUMNS = {
  { title = "Lvl", width = 38, key = "level" },
  { title = CLASS or "Class", width = 44, key = "class" },
  { title = NAME or "Name", width = 140, key = "name" },
  { title = RACE or "Race", width = 84, key = "race" },
  { title = ZONE or "Zone", width = 120, key = "zone" },
  { title = "Status", width = 0, key = "status" },
}
local ACTIONS_WIDTH = 150

local function ScanSettings()
  local db = ZR.DB()
  db.scan = db.scan or { min = 10, max = ZR.MaxLevel() }
  return db.scan
end

local function ReadParams()
  local s = ScanSettings()
  local minL, maxL = s.min or 1, s.max or ZR.MaxLevel()
  if view then
    local a, b = view.Levels:GetLevelRange()
    if a and a > 0 then minL = a end
    if b and b > 0 then maxL = b end
  end
  minL = math.max(1, math.min(minL, ZR.MaxLevel()))
  maxL = math.max(minL, math.min(maxL, ZR.MaxLevel()))
  s.min, s.max = minL, maxL
  local class = s.class and ZR.ClassByFile(s.class)
  return minL, maxL, class and class.name or nil
end

local function ParamsChanged(minL, maxL, className)
  local p = Who.params
  return not p or p.min ~= minL or p.max ~= maxL or p.class ~= className
end

-- One /who per click; key bindings count as clicks too.
local function Scan()
  if not ZR.IsOfficer() then return end
  local minL, maxL, className = ReadParams()
  if Who.state == "idle" or Who.state == "done" or ParamsChanged(minL, maxL, className) then
    if Who.state == "waiting" then return end
    Who.Start(minL, maxL, className)
  end
  local ok, reason = Who.Next()
  if not ok then UIErrorsFrame:AddExternalErrorMessage(reason) end
end
ZR.BindingScan = Scan

local function SortValue(row, key)
  if key == "status" then return Contacts.Describe(row.name) end
  return row[key]
end

local function BuildRows()
  local rows, hiddenContacted = {}, 0
  local showAll = ZR.DB().showContacted
  for name, r in pairs(Who.results) do
    if not showAll and Contacts.IsHidden(name) then
      hiddenContacted = hiddenContacted + 1
    else
      rows[#rows + 1] = r
    end
  end
  table.sort(rows, function(a, b)
    local va, vb = SortValue(a, sortKey), SortValue(b, sortKey)
    if va == vb then return a.name < b.name end
    if sortAsc then return va < vb end
    return va > vb
  end)
  return rows, hiddenContacted
end

local function ColumnX(index)
  local x = 0
  for i = 1, index - 1 do x = x + COLUMNS[i].width - 2 end
  return x
end

local function RowTooltip(row)
  local d = row.data
  if not d then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip_SetTitle(GameTooltip, ZR.ColorName(d.name, d.classFile))
  GameTooltip:AddLine(("Level %d %s %s"):format(d.level, d.race, d.class), 1, 1, 1)
  if d.zone ~= "" then GameTooltip:AddLine(d.zone, 0.7, 0.7, 0.7) end
  GameTooltip:AddLine(" ")
  Contacts.Tooltip(GameTooltip, d.name)
  GameTooltip:Show()
end

local function InitRow(row, data)
  if not row.Level then
    UI.StyleRow(row)
    row.Level = UI.CreateCell(row, "GameFontHighlightSmall", "CENTER")
    row.Level:SetPoint("LEFT", ColumnX(1), 0)
    row.Level:SetWidth(COLUMNS[1].width - 4)
    row.ClassIcon = row:CreateTexture(nil, "ARTWORK")
    row.ClassIcon:SetSize(16, 16)
    row.ClassIcon:SetPoint("LEFT", ColumnX(2) + (COLUMNS[2].width - 16) / 2 - 1, 0)
    row.Name = UI.CreateCell(row)
    row.Name:SetPoint("LEFT", ColumnX(3) + 6, 0)
    row.Name:SetWidth(COLUMNS[3].width - 10)
    row.Race = UI.CreateCell(row)
    row.Race:SetPoint("LEFT", ColumnX(4) + 6, 0)
    row.Race:SetWidth(COLUMNS[4].width - 10)
    row.Zone = UI.CreateCell(row)
    row.Zone:SetPoint("LEFT", ColumnX(5) + 6, 0)
    row.Zone:SetWidth(COLUMNS[5].width - 10)

    row.Whisper = UI.CreateButton(row, WHISPER or "Whisper", 72, 18)
    row.Whisper:SetPoint("RIGHT", -2, 0)
    row.Whisper:SetScript("OnClick", function(self)
      local name = self:GetParent().data.name
      if IsShiftKeyDown() then
        ZR.Invite.ExpectWhisper(name)
        ChatFrameUtil.SendTell(name)
      else
        ZR.Invite.WhisperTemplate(name)
      end
    end)
    UI.SetButtonTooltip(row.Whisper, function()
      return "Whisper", "Sends your whisper template. Shift-click to type your own."
    end)

    row.Invite = UI.CreateButton(row, INVITE or "Invite", 72, 18)
    row.Invite:SetPoint("RIGHT", row.Whisper, "LEFT", -2, 0)
    row.Invite:SetScript("OnClick", function(self)
      ZR.Invite.Start(self:GetParent().data.name)
    end)
    UI.SetButtonTooltip(row.Invite, function(self)
      if not ZR.CanInvite() then return "Can't invite", "Your guild rank cannot invite." end
      local reason = Contacts.InviteBlocker(self:GetParent().data.name)
      if reason then return "Can't invite", reason end
      if ZR.DB().inviteMode == "copy" then
        return "Guild invite", "Opens a box with /ginvite ready to copy."
      end
      return "Guild invite", "Opens chat with /ginvite ready. Press Enter to send it."
    end)

    row.Status = UI.CreateCell(row)
    row.Status:SetPoint("LEFT", ColumnX(6) + 6, 0)
    row.Status:SetPoint("RIGHT", row.Invite, "LEFT", -6, 0)

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end

  row.data = data
  row.Level:SetText(data.level)
  if data.classFile then
    row.ClassIcon:SetAtlas("classicon-" .. data.classFile:lower())
    row.ClassIcon:Show()
  else
    row.ClassIcon:Hide()
  end
  row.Name:SetText(ZR.ColorName(data.name, data.classFile))
  row.Race:SetText(data.race)
  row.Zone:SetText(data.zone)
  local text, color = Contacts.Describe(data.name)
  row.Status:SetText(text)
  row.Status:SetTextColor(color[1], color[2], color[3])
  row.Invite:SetEnabled(ZR.CanInvite() and Contacts.CanInvite(data.name))
end

local function UpdateRows()
  if not view or not view:IsShown() then return end
  local rows, hidden = BuildRows()
  tbl:SetRows(rows)
  local parts = { #rows .. " found" }
  if Who.stats.guilded > 0 then parts[#parts + 1] = Who.stats.guilded .. " in a guild skipped" end
  if hidden > 0 then parts[#parts + 1] = hidden .. " contacted hidden" end
  view.Summary:SetText(table.concat(parts, "  |cff666666-|r  "))
  view.Empty:SetShown(#rows == 0)
end

local function UpdateScanState()
  if not view or not view:IsShown() then return end
  local ready = Who.ReadyIn()
  local b, text = view.ScanButton, nil
  if ZR.WhoDisabled() then
    b:SetText("Scan")
    b:SetEnabled(false)
    view.Progress:SetText("|cffff4040/who is disabled here.|r")
    return
  end
  if Who.state == "waiting" then
    b:SetText("Searching...")
    b:SetEnabled(false)
    text = "Searching " .. Who.Describe(Who.lastQuery)
  else
    local label
    if Who.state == "ready" and #Who.queue > 0 then
      label = ("Scan next (%d left)"):format(#Who.queue)
      text = "Next: " .. Who.Describe(Who.queue[1])
      if Who.timedOut then text = "|cffffd100No answer from /who, click again.|r" end
    elseif Who.state == "done" then
      label = "New scan"
      text = "Scan complete after " .. Who.stats.queries .. " searches."
      if Who.stats.truncated > 0 then
        text = text .. " " .. Who.stats.truncated .. " capped at 50."
      end
    else
      label = "Scan"
      text = "Pick levels and a class, then click Scan."
    end
    if ready > 0 then
      b:SetText(("%s (%d)"):format(label, math.ceil(ready)))
      b:SetEnabled(false)
    else
      b:SetText(label)
      b:SetEnabled(true)
    end
  end
  view.Progress:SetText(text)
end

local function SetupClassDropdown(dd)
  local s = ScanSettings()
  dd:SetupMenu(function(_, root)
    root:CreateRadio("All classes", function() return s.class == nil end, function()
      s.class = nil
    end)
    for _, c in ipairs(ZR.ClassList()) do
      local label = UI.ClassIcon(c.file, 14) .. " " .. ZR.ColorName(c.name, c.file)
      root:CreateRadio(label, function() return s.class == c.file end, function()
        s.class = c.file
      end)
    end
  end)
end

function UI.BuildFastInvite(parent, inset)
  view = CreateFrame("Frame", nil, parent)
  view:SetAllPoints(parent)

  local levelLabel = UI.Text(view, "GameFontNormalSmall", LEVEL_RANGE or "Level range")
  levelLabel:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -14)
  view.Levels = CreateFrame("Frame", nil, view, "LevelRangeFrameTemplate")
  view.Levels:SetPoint("LEFT", levelLabel, "RIGHT", 8, 0)
  local s = ScanSettings()
  view.Levels:SetMinLevel(s.min or 10)
  view.Levels:SetMaxLevel(s.max or ZR.MaxLevel())
  view.Levels:SetLevelRangeChangedCallback(function() ReadParams() end)

  local classLabel = UI.Text(view, "GameFontNormalSmall", CLASS or "Class")
  classLabel:SetPoint("LEFT", view.Levels, "RIGHT", 18, 0)
  view.Class = CreateFrame("DropdownButton", nil, view, "WowStyle1DropdownTemplate")
  view.Class:SetWidth(160)
  view.Class:SetPoint("LEFT", classLabel, "RIGHT", 8, 0)
  SetupClassDropdown(view.Class)

  view.ShowContacted = UI.CreateCheck(view, "Show contacted")
  view.ShowContacted:SetPoint("LEFT", view.Class, "RIGHT", 14, 0)
  view.ShowContacted:SetChecked(ZR.DB().showContacted and true or false)
  view.ShowContacted:SetScript("OnClick", function(self)
    ZR.DB().showContacted = self:GetChecked() and true or nil
    UpdateRows()
  end)
  UI.SetButtonTooltip(view.ShowContacted, function()
    return "Show contacted", ("Players whispered or invited in the last %d days are hidden. Players who declined always show."):format(ZR.DB().hideDays or 3)
  end)

  tbl = UI.CreateTable(view, COLUMNS, { title = "", width = ACTIONS_WIDTH }, 20, InitRow)
  tbl:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -42)
  tbl:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -6, 6)
  tbl.Header.sortingFunction = function(_, index)
    local key = COLUMNS[index] and COLUMNS[index].key
    if not key then return end
    if sortKey == key then sortAsc = not sortAsc else sortKey, sortAsc = key, true end
    UpdateRows()
  end

  view.Empty = UI.Text(view, "GameFontDisable", "No players yet. Click Scan to search with /who.")
  view.Empty:SetPoint("CENTER", tbl, "CENTER", 0, -10)

  view.ScanButton = UI.CreateButton(view, "Scan", 170, 20)
  view.ScanButton:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -3, 3)
  view.ScanButton:SetScript("OnClick", Scan)
  UI.SetButtonTooltip(view.ScanButton, function()
    return "Scan", "Each click sends one /who. Big ranges split into more searches so nobody is lost to the 50 player cap."
  end)

  view.ClearButton = UI.CreateButton(view, "Clear", 90, 20)
  view.ClearButton:SetPoint("RIGHT", view.ScanButton, "LEFT", -2, 0)
  view.ClearButton:SetScript("OnClick", function()
    if Who.state ~= "waiting" then Who.Reset() end
  end)

  view.Summary = UI.Text(view, "GameFontHighlightSmall")
  view.Summary:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 7)

  view.Progress = UI.Text(view, "GameFontHighlightSmall")
  view.Progress:SetPoint("LEFT", view.ShowContacted.Text or view.ShowContacted, "RIGHT", 16, 0)
  view.Progress:SetPoint("RIGHT", inset, "TOPRIGHT", -12, -19)
  view.Progress:SetJustifyH("RIGHT")
  view.Progress:SetWordWrap(false)

  view:SetScript("OnShow", function()
    UpdateRows()
    UpdateScanState()
  end)
  view.elapsed = 0
  view:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed > 0.25 then
      self.elapsed = 0
      UpdateScanState()
      self.tick = (self.tick or 0) + 1
      if self.tick % 4 == 0 then tbl:Refresh() end
    end
  end)

  ZR.On("WhoChanged", function()
    UpdateRows()
    UpdateScanState()
  end)
  ZR.On("ContactsChanged", UpdateRows)
  ZR.On("OfficerChanged", function() tbl:Refresh() end)
  view:Hide()
  return view
end
