local _, ZR = ...

local UI = {}
ZR.UI = UI

local GOLD = { 1, 0.82, 0 }
UI.GOLD = GOLD

-- Spellbook-style square icon tab, without TabSystemButtonMixin (it taints an upvalue).
function UI.CreateIconTab(parent, icon, tooltip)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(44, 32)
  b:SetMotionScriptsWhileDisabled(true)
  b.Icon = b:CreateTexture(nil, "ARTWORK")
  b.Icon:SetSize(36, 35)
  b.Icon:SetPoint("CENTER")
  b.Icon:SetTexture(icon)
  local mask = b:CreateMaskTexture()
  mask:SetAtlas("SquareMask")
  mask:SetPoint("TOPLEFT", b.Icon, "TOPLEFT", 0, -2)
  mask:SetPoint("BOTTOMRIGHT", b.Icon, "BOTTOMRIGHT", -2, 0)
  b.Icon:AddMaskTexture(mask)
  b.Frame = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.Frame:SetAtlas("spellbook-Tab-Frame-C60", true)
  b.Frame:SetPoint("BOTTOM", 0, 1)
  b.Active = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.Active:SetAtlas("spellbook-Tab-Frame-Glow-C60", true)
  b.Active:SetPoint("BOTTOM", 0, 1)
  b.Glow = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.Glow:SetAtlas("spellbook-Tab-Frame-glow-gradient-C60", true)
  b.Glow:SetPoint("BOTTOM")
  b.tooltipText = tooltip
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -12, -6)
    GameTooltip_AddNormalLine(GameTooltip, self.tooltipText)
    if self.tooltipNote then GameTooltip_AddErrorLine(GameTooltip, self.tooltipNote) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  UI.SetIconTabSelected(b, false)
  return b
end

function UI.SetIconTabSelected(b, selected)
  b.Frame:SetShown(not selected)
  b.Active:SetShown(selected)
  b.Glow:SetShown(selected)
  b:SetEnabled(not selected)
end

function UI.Text(parent, font, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
  if text then fs:SetText(text) end
  return fs
end

-- Gold label above a dark tooltip-bordered box, like the chat settings boxes.
function UI.CreateBox(parent, title)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  box:SetBackdropColor(0, 0, 0, 0.55)
  box:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
  if title then
    box.Title = UI.Text(box, "GameFontNormal", title)
    box.Title:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 4, 2)
  end
  return box
end

function UI.CreateButton(parent, text, width, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 130, height or 20)
  b:SetText(text or "")
  b:SetMotionScriptsWhileDisabled(true)
  return b
end

-- Shows a tooltip even while the button is disabled.
function UI.SetButtonTooltip(b, getText)
  b:SetScript("OnEnter", function(self)
    local title, note = getText(self)
    if not title then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, title)
    if note then GameTooltip_AddNormalLine(GameTooltip, note) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
end

function UI.CreateInput(parent, width, height)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width or 120, height or 22)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  return e
end

function UI.CreateCheck(parent, text)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  if c.Text then
    c.Text:SetFontObject("GameFontHighlightSmall")
    c.Text:SetText(text or "")
  end
  return c
end

function UI.ClassIcon(classFile, size)
  if not classFile then return "" end
  return CreateAtlasMarkup("classicon-" .. classFile:lower(), size or 14, size or 14)
end

-- Guild-frame header bar, as on the Guild Info page.
function UI.CreateHeaderBar(parent, text, width)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetSize(width or 280, 22)
  local tex = bar:CreateTexture(nil, "BACKGROUND")
  tex:SetTexture("Interface\\GuildFrame\\GuildFrame")
  tex:SetTexCoord(0.00097656, 0.31445313, 0.93164063, 0.97460938)
  tex:SetAllPoints()
  bar.Text = UI.Text(bar, "GameFontNormal", text)
  bar.Text:SetPoint("LEFT", 10, 0)
  return bar
end

-- Roster-style list: column headers over a ScrollBox with a minimal bar.
function UI.CreateTable(parent, columns, extraColumn, rowHeight, initRow)
  local t = CreateFrame("Frame", nil, parent)

  t.Header = CreateFrame("Frame", nil, t, "ColumnDisplayTemplate")
  t.Header:SetPoint("TOPLEFT", -2, 0)
  t.Header:SetPoint("TOPRIGHT", 0, 0)
  t.Header:SetHeight(22)
  if t.Header.Background then t.Header.Background:Hide() end
  if t.Header.TopTileStreaks then t.Header.TopTileStreaks:Hide() end
  t.Header:LayoutColumns(columns, extraColumn)

  t.ScrollBox = CreateFrame("Frame", nil, t, "WowScrollBoxList")
  t.ScrollBox:SetPoint("TOPLEFT", 0, -24)
  t.ScrollBox:SetPoint("BOTTOMRIGHT", -18, 0)

  t.ScrollBar = CreateFrame("EventFrame", nil, t, "MinimalScrollBar")
  t.ScrollBar:SetPoint("TOPLEFT", t.ScrollBox, "TOPRIGHT", 6, -2)
  t.ScrollBar:SetPoint("BOTTOMLEFT", t.ScrollBox, "BOTTOMRIGHT", 6, 2)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(rowHeight or 20)
  view:SetElementInitializer("Button", initRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(t.ScrollBox, t.ScrollBar, view)

  function t:SetRows(rows)
    self.ScrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
  end

  function t:Refresh()
    self.ScrollBox:ForEachFrame(function(row)
      local data = row.GetElementData and row:GetElementData()
      if data then initRow(row, data) end
    end)
  end

  return t
end

-- Native roster row art and highlight.
function UI.StyleRow(row)
  row:SetNormalTexture("Interface\\GuildFrame\\GuildFrame")
  row:GetNormalTexture():SetTexCoord(0.36230469, 0.38183594, 0.95898438, 0.99804688)
  row:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar", "ADD")
end

function UI.CreateCell(row, font, justify)
  local fs = row:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end
