local _, ZR = ...
local UI = ZR.UI

local GF = {}
UI.GuildFrame = GF
UI.features = {}

local BLIZZ_TABS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"

local cf, under, page, sideTab
local currentKey
local openAfterCombat

function UI.RegisterFeature(f)
  table.insert(UI.features, f)
end

local function Feature(key)
  for _, f in ipairs(UI.features) do
    if f.key == key then return f end
  end
  return UI.features[1]
end

local function IsGuildClub(clubId)
  return clubId ~= nil and clubId == C_Club.GetGuildClubId()
end

-- Re-check the Blizzard tab that matches the mode left underneath.
local function CheckBlizzardTab()
  local M, mode = COMMUNITIES_FRAME_DISPLAY_MODES, cf:GetDisplayMode()
  local key = (mode == M.CHAT and "ChatTab")
    or ((mode == M.ROSTER or (cf.IsShowingApplicantList and cf:IsShowingApplicantList())) and "RosterTab")
    or (mode == M.GUILD_BENEFITS and "GuildBenefitsTab")
    or (mode == M.GUILD_INFO and "GuildInfoTab")
    or (mode == M.GUILD_PREFERRED_PLAY_SETTINGS and "GuildPreferredPlaySettingsTab")
  if key and cf[key] then cf[key]:SetChecked(true) end
end

local function UncheckBlizzardTabs()
  for _, key in ipairs(BLIZZ_TABS) do
    if cf[key] then cf[key]:SetChecked(false) end
  end
end

local function Swallow() end

local function TiledRock(frame, layer, sub)
  local t = frame:CreateTexture(nil, layer, nil, sub)
  t:SetTexture(ROCK, "REPEAT", "REPEAT")
  t:SetHorizTile(true)
  t:SetVertTile(true)
  return t
end

-- Under the portrait: hides Blizzard content while the portrait stays on top.
local function BuildUnder()
  under = CreateFrame("Frame", nil, cf)
  under:SetPoint("TOPLEFT", cf, "TOPLEFT", 2, -21)
  under:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -2, 2)
  under:SetFrameLevel(math.max(1, (cf.PortraitOverlay and cf.PortraitOverlay:GetFrameLevel() or 300) - 1))
  under:EnableMouse(true)
  under:EnableMouseWheel(true)
  under:SetScript("OnMouseWheel", Swallow)
  TiledRock(under, "BACKGROUND", -6):SetAllPoints()
  local streaks = under:CreateTexture(nil, "BORDER", "_UI-Frame-TopTileStreaks")
  streaks:SetPoint("TOPLEFT")
  streaks:SetPoint("TOPRIGHT")
  under:Hide()
end

local function BuildLock()
  local lock = CreateFrame("Frame", nil, page)
  lock:SetAllPoints(page.Inset)
  lock:SetFrameLevel(page.Inset:GetFrameLevel() + 5)
  lock.Icon = lock:CreateTexture(nil, "ARTWORK")
  lock.Icon:SetAtlas("communities-icon-lock")
  lock.Icon:SetSize(36, 45)
  lock.Icon:SetPoint("CENTER", 0, 40)
  lock.Text = UI.Text(lock, "GameFontNormalLarge", "Only officers can view this page.")
  lock.Text:SetPoint("TOP", lock.Icon, "BOTTOM", 0, -12)
  lock.Sub = UI.Text(lock, "GameFontHighlight", "Ask an officer if you want to help with recruiting.")
  lock.Sub:SetPoint("TOP", lock.Text, "BOTTOM", 0, -8)
  lock:Hide()
  page.Lock = lock
end

local function BuildTopTabs()
  local prev
  for _, f in ipairs(UI.features) do
    local b = UI.CreateIconTab(page, f.icon, f.title)
    if prev then
      b:SetPoint("LEFT", prev, "RIGHT", 1, 0)
    else
      b:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", 64, -60)
    end
    b:SetScript("OnClick", function()
      PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
      GF.SelectFeature(f.key)
    end)
    f.iconTab = b
    prev = b
  end
  page.Title = UI.Text(page, "GameFontNormalLarge")
  page.Title:SetPoint("LEFT", prev, "RIGHT", 12, -2)
end

local function BuildBottomTabs(f)
  local holder = CreateFrame("Frame", nil, cf)
  holder:SetSize(1, 1)
  holder:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", 12, 2)
  holder:SetFrameLevel(math.max(1, cf.NineSlice:GetFrameLevel() - 10))
  holder.tabPadding, holder.minTabWidth = 20, 70
  holder:Hide()
  for i, label in ipairs(f.tabs) do
    local t = CreateFrame("Button", nil, holder, "PanelTabButtonTemplate")
    t:SetID(i)
    t:SetText(label)
    t:SetScript("OnClick", function(self)
      PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
      GF.SelectSubTab(f, self:GetID())
    end)
    if i == 1 then
      t:SetPoint("TOPLEFT", holder, "TOPLEFT")
    else
      t:SetPoint("TOPLEFT", holder.Tabs[i - 1], "TOPRIGHT", 3, 0)
    end
  end
  PanelTemplates_SetNumTabs(holder, #holder.Tabs)
  f.holder = holder
end

local function BuildPage()
  if page then return true end
  BuildUnder()

  page = CreateFrame("Frame", "ZUGZUGRebornPage", cf)
  page:SetPoint("TOPLEFT", cf, "TOPLEFT", 2, -21)
  page:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -2, 2)
  page:SetFrameLevel(cf.ChatEditBox:GetFrameLevel() + 10)
  page:EnableMouse(true)
  page:Hide()

  -- The chat edit box sits above the portrait level, so this strip covers it.
  local strip = TiledRock(page, "BACKGROUND", -6)
  strip:SetPoint("BOTTOMLEFT")
  strip:SetPoint("BOTTOMRIGHT")
  strip:SetHeight(26)

  page.Inset = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
  page.Inset:SetPoint("TOPLEFT", cf, "TOPLEFT", 4, -60)
  page.Inset:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -6, 26)
  page.Inset:SetFrameLevel(page:GetFrameLevel() + 1)

  BuildTopTabs()
  BuildLock()
  for _, f in ipairs(UI.features) do
    if f.tabs then BuildBottomTabs(f) end
  end
  return true
end

local function BuildFeature(f)
  if f.frame then return end
  f.frame = CreateFrame("Frame", nil, page)
  f.frame:SetAllPoints(page)
  f.frame:SetFrameLevel(page.Inset:GetFrameLevel() + 2)
  f.build(f.frame, page.Inset)
end

function GF.RefreshTabLabels()
  for _, f in ipairs(UI.features) do
    if f.holder and f.tabLabel then
      for i, t in ipairs(f.holder.Tabs) do
        local label = f.tabLabel(i)
        if label and label ~= t:GetText() then
          t:SetText(label)
          PanelTemplates_TabResize(t, f.holder.tabPadding, nil, f.holder.minTabWidth)
        end
      end
    end
  end
  if sideTab then
    sideTab.Unread:SetShown(ZR.IsOfficer() and ZR.Inbox.Unread() > 0)
  end
end

function GF.SelectSubTab(f, index)
  f.lastTab = index
  PanelTemplates_SetTab(f.holder, index)
  if f.selectTab then f.selectTab(index) end
end

function GF.SelectFeature(key)
  local f = Feature(key)
  if not f then return end
  currentKey = f.key
  local allowed = not f.officerOnly or ZR.IsOfficer()
  for _, other in ipairs(UI.features) do
    UI.SetIconTabSelected(other.iconTab, other == f)
    if other ~= f then
      if other.frame then other.frame:Hide() end
      if other.holder then other.holder:Hide() end
    end
  end
  page.Title:SetText(f.title)
  page.Lock:SetShown(not allowed)
  if allowed then
    BuildFeature(f)
    f.frame:Show()
    if f.holder then
      f.holder:Show()
      GF.RefreshTabLabels()
      GF.SelectSubTab(f, f.lastTab or 1)
    end
  else
    if f.frame then f.frame:Hide() end
    if f.holder then f.holder:Hide() end
  end
end

function GF.IsShown()
  return page ~= nil and page:IsShown()
end

-- tabIndex optionally picks a bottom tab.
function GF.ShowPage(key, tabIndex)
  if not cf or not BuildPage() then return end
  if tabIndex then Feature(key or currentKey).lastTab = tabIndex end
  under:Show()
  page:Show()
  local bar = cf.Chat and cf.Chat.ScrollBar
  if bar and bar:GetFrameStrata() == "HIGH" then
    bar:SetFrameStrata("MEDIUM")
    GF.loweredBar = bar
  end
  sideTab:SetChecked(true)
  UncheckBlizzardTabs()
  GF.SelectFeature(key or currentKey)
  ZR.RequestRoster()
end

function GF.HidePage(recheck)
  if not page or not page:IsShown() then return end
  page:Hide()
  under:Hide()
  if GF.loweredBar then
    GF.loweredBar:SetFrameStrata("HIGH")
    GF.loweredBar = nil
  end
  for _, f in ipairs(UI.features) do
    if f.holder then f.holder:Hide() end
  end
  sideTab:SetChecked(false)
  if recheck then CheckBlizzardTab() end
end

local function BuildSideTab()
  sideTab = CreateFrame("CheckButton", "ZUGZUGRebornCommunitiesTab", cf, "RightSideTabTemplate")
  sideTab:SetFrameLevel(cf.ChatTab:GetFrameLevel())
  sideTab:SetPoint("BOTTOMLEFT", cf, "BOTTOMRIGHT", 0, 40)
  sideTab.Icon:SetTexture(ZR.ICON_TEXTURE)
  sideTab.Icon:SetTexCoord(0, 1, 0, 1)
  sideTab.tooltip = ZR.TITLE
  sideTab.Unread = sideTab:CreateTexture(nil, "OVERLAY")
  sideTab.Unread:SetAtlas("communities-icon-notification")
  sideTab.Unread:SetSize(16, 16)
  sideTab.Unread:SetPoint("CENTER", sideTab, "TOPRIGHT", -3, -3)
  sideTab.Unread:Hide()
  sideTab:SetScript("OnClick", function(self)
    RightSideTabMixin.OnClick(self)
    GF.ShowPage()
  end)
  sideTab:Hide()
end

local function Setup()
  if cf then return end
  cf = CommunitiesFrame
  if not cf then return end
  BuildSideTab()

  hooksecurefunc(cf, "UpdateCommunitiesTabs", function(self)
    local show = self.ChatTab:IsShown() and IsGuildClub(self:GetSelectedClubId())
    sideTab:SetShown(show)
    if not show then
      GF.HidePage(false)
    elseif GF.IsShown() then
      UncheckBlizzardTabs()
    end
  end)
  for _, key in ipairs(BLIZZ_TABS) do
    if cf[key] then cf[key]:HookScript("OnClick", function() GF.HidePage(true) end) end
  end
  cf:RegisterCallback(CommunitiesFrameMixin.Event.DisplayModeChanged, function() GF.HidePage(false) end, GF)
  cf:RegisterCallback(CommunitiesFrameMixin.Event.ClubSelected, function(_, clubId)
    if not IsGuildClub(clubId) then GF.HidePage(true) end
  end, GF)
  cf:HookScript("OnHide", function() GF.HidePage(false) end)
  GF.RefreshTabLabels()
end

-- Opens Guild & Communities on our page without calling Communities methods.
function ZR.OpenPage(key, tabIndex)
  if InCombatLockdown() then
    openAfterCombat = { key, tabIndex }
    UIErrorsFrame:AddExternalErrorMessage(ERR_NOT_IN_COMBAT)
    return
  end
  if not IsInGuild() then
    UIErrorsFrame:AddExternalErrorMessage("You are not in a guild.")
    return
  end
  if not C_AddOns.IsAddOnLoaded("Blizzard_Communities") then C_AddOns.LoadAddOn("Blizzard_Communities") end
  Setup()
  if not cf then return end
  local guildClubId = C_Club.GetGuildClubId()
  if cf:IsShown() and (cf:GetSelectedClubId() ~= guildClubId or cf.MaximizeMinimizeFrame:IsMinimized()) then
    HideUIPanel(cf)
  end
  if not cf:IsShown() then
    if guildClubId then SetCVar("lastSelectedClubId", guildClubId) end
    SetCVar("miniCommunitiesFrame", "0")
    ToggleGuildFrame()
  end
  if cf:IsShown() and IsGuildClub(cf:GetSelectedClubId()) and sideTab:IsShown() then
    GF.ShowPage(key, tabIndex)
  end
end

function ZR.TogglePage()
  if GF.IsShown() and cf:IsShown() then
    HideUIPanel(cf)
  else
    ZR.OpenPage("recruitment")
  end
end

ZR.RegisterEvent("PLAYER_REGEN_ENABLED", function()
  if openAfterCombat then
    local args = openAfterCombat
    openAfterCombat = nil
    ZR.OpenPage(args[1], args[2])
  end
end)

ZR.On("InboxChanged", GF.RefreshTabLabels)
ZR.On("OfficerChanged", function()
  GF.RefreshTabLabels()
  if GF.IsShown() then GF.SelectFeature(currentKey) end
end)

function GF.Init()
  EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", Setup)
end
