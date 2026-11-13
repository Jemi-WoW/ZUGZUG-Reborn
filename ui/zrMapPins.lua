local _, ZR = ...
local UI = ZR.UI
local Map = ZR.Map

local SIZE = 18
local RING = 1.5
local FONT_SIZE = 10
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TAXI = { Horde = 132268, Alliance = 132239 }
local FALLBACK = { r = 0.2, g = 1, b = 0.4 }
local CLUSTER = { r = 1, g = 0.82, b = 0 }

local pins, rects = {}, {}
local dirty = true
local seen = {}
local setUp, wasShowing

-- MapUtils skips drawing its guild dots while a hook says hidden, but keeps sharing.
local hooks = _G.D4GuildMapHooks or {}
_G.D4GuildMapHooks = hooks
hooks.ZUGZUGReborn = { isHidden = function() return Map.Showing() end }

-- Only on a toggle, so MapUtils redraws once instead of on every position.
local function RefreshMapUtils()
  local showing = Map.Showing()
  if showing == wasShowing then return end
  wasShowing = showing
  for _, guild in pairs(_G.D4GuildMapInstances or {}) do guild.dirty = true end
end

local function Rect(from, to)
  local key = from * 100000 + to
  if rects[key] == nil then
    local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(from, to)
    rects[key] = (minX and maxX and minY and maxY and minX < maxX and minY < maxY) and { minX, maxX, minY, maxY } or false
  end
  return rects[key] or nil
end

-- A position on one map, placed on another: directly, or by walking up parent maps.
local function Project(from, to, x, y)
  local visited = {}
  while from ~= to do
    if visited[from] then return nil end
    visited[from] = true
    local r = Rect(from, to)
    if r then return r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3]) end
    r = Rect(to, from)
    if r then return (x - r[1]) / (r[2] - r[1]), (y - r[3]) / (r[4] - r[3]) end
    local info = C_Map.GetMapInfo(from)
    local parent = info and info.parentMapID
    if not parent or parent == 0 then return nil end
    r = Rect(from, parent)
    if not r then return nil end
    x, y = r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3])
    from = parent
  end
  return x, y
end

local function ClassOf(m)
  local info = ZR.RosterInfo(m.name)
  return (info and info.classFile) or m.class
end

local function Waypoint(m)
  local can = C_Map.CanSetUserWaypointOnMap and UiMapPoint and C_Map.SetUserWaypoint
  if not can or not C_Map.CanSetUserWaypointOnMap(m.mapID) then
    ZR.Msg("A waypoint can't be placed on that map.")
    return
  end
  C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(m.mapID, m.x, m.y))
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
end

local function AddProfessions(name)
  local Crafts = ZR.Crafts
  for _, prof in ipairs(Crafts.PROFESSIONS) do
    local p = Crafts.GetProf(name, prof.id)
    if p and (p.m or 0) > 0 then
      GameTooltip:AddDoubleLine("|T" .. prof.icon .. ":14:14|t " .. Crafts.ProfName(prof.id), p.r .. "/" .. p.m,
        1, 0.82, 0, 1, 1, 1)
    end
  end
end

local function MemberTooltip(pin, m)
  local info = ZR.RosterInfo(m.name)
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  GameTooltip_SetTitle(GameTooltip, ZR.ColorName(m.name, ClassOf(m)))
  local bits = {}
  if info and info.rank then bits[#bits + 1] = info.rank end
  local level = (info and info.level) or m.level
  if level and level > 0 then bits[#bits + 1] = (LEVEL or "Level") .. " " .. level end
  if #bits > 0 then GameTooltip:AddLine(table.concat(bits, ", "), 1, 1, 1) end
  local mapInfo = C_Map.GetMapInfo(m.mapID)
  if mapInfo and mapInfo.name then GameTooltip:AddLine(mapInfo.name, 0.7, 0.7, 0.7) end
  if m.taxi then GameTooltip:AddLine("On a flight path", 1, 0.82, 0) end
  AddProfessions(m.name)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("Updated %ds ago%s"):format(math.max(0, math.floor(GetTime() - m.at)),
    m.source == "MapUtils" and ", shared by MapUtils" or ""), 0.5, 0.5, 0.5)
  GameTooltip:AddLine("Click to whisper, Shift-click for a waypoint, right-click for more.", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

local function ClusterTooltip(pin, list)
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  GameTooltip_SetTitle(GameTooltip, #list .. " guild members")
  for _, m in ipairs(list) do
    local mapInfo = C_Map.GetMapInfo(m.mapID)
    GameTooltip:AddDoubleLine(ZR.ColorName(m.name, ClassOf(m)), mapInfo and mapInfo.name or "", 1, 1, 1, 0.7, 0.7, 0.7)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click to pick who to whisper.", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function PinEnter(pin)
  if #pin.list == 1 then MemberTooltip(pin, pin.list[1]) else ClusterTooltip(pin, pin.list) end
end

local function ClusterMenu(pin)
  if not MenuUtil or not MenuUtil.CreateContextMenu then return end
  MenuUtil.CreateContextMenu(pin, function(_, root)
    root:CreateTitle(WHISPER or "Whisper")
    for _, m in ipairs(pin.list) do
      root:CreateButton(ZR.ColorName(m.name, ClassOf(m)), function() UI.Whisper(m.name) end)
    end
  end)
end

local function PinClick(pin, button)
  if #pin.list > 1 then return ClusterMenu(pin) end
  local m = pin.list[1]
  if button == "RightButton" then
    UI.NameMenu(pin, m.name, ClassOf(m))
  elseif IsShiftKeyDown() then
    Waypoint(m)
  else
    UI.Whisper(m.name)
  end
end

local function CreatePin(canvas)
  local pin = CreateFrame("Button", nil, canvas)
  pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  pin.Shadow = pin:CreateTexture(nil, "BACKGROUND", nil, -1)
  pin.Shadow:SetTexture(MASK)
  pin.Shadow:SetVertexColor(0, 0, 0, 0.85)
  pin.Ring = pin:CreateTexture(nil, "BACKGROUND")
  pin.Ring:SetAllPoints()
  pin.Ring:SetTexture(MASK)
  pin.Icon = pin:CreateTexture(nil, "ARTWORK")
  pin.Mask = pin:CreateMaskTexture()
  pin.Mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  pin.Mask:SetAllPoints(pin.Icon)
  pin.Icon:AddMaskTexture(pin.Mask)
  pin.Count = pin:CreateFontString(nil, "OVERLAY")
  pin.Count:SetPoint("CENTER")
  pin:SetScript("OnEnter", PinEnter)
  pin:SetScript("OnLeave", GameTooltip_Hide)
  pin:SetScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
  pin:SetScript("OnClick", PinClick)
  return pin
end

-- Sized against the canvas scale so pins look the same at every zoom.
local function SetupPin(pin, list, scale)
  pin.list = list
  local size, ring = SIZE / scale, RING / scale
  pin:SetSize(size, size)
  -- A dark edge keeps yellow and white class colors visible on the map.
  pin.Shadow:ClearAllPoints()
  pin.Shadow:SetPoint("TOPLEFT", -1 / scale, 1 / scale)
  pin.Shadow:SetPoint("BOTTOMRIGHT", 1 / scale, -1 / scale)
  pin.Icon:ClearAllPoints()
  pin.Icon:SetPoint("TOPLEFT", ring, -ring)
  pin.Icon:SetPoint("BOTTOMRIGHT", -ring, ring)
  pin.Count:SetFont(STANDARD_TEXT_FONT, FONT_SIZE / scale, "OUTLINE")
  if #list > 1 then
    pin.Ring:SetVertexColor(CLUSTER.r, CLUSTER.g, CLUSTER.b)
    pin.Icon:SetColorTexture(0.08, 0.08, 0.08)
    pin.Count:SetText(#list)
    pin.Count:Show()
    return
  end
  pin.Count:Hide()
  local m = list[1]
  local class = ClassOf(m)
  local color = (class and RAID_CLASS_COLORS[class]) or FALLBACK
  pin.Ring:SetVertexColor(color.r, color.g, color.b)
  local taxi = m.taxi and TAXI[UnitFactionGroup("player") or ""]
  if taxi then
    pin.Icon:SetTexture(taxi)
    pin.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  elseif class then
    pin.Icon:SetAtlas("classicon-" .. class:lower())
  else
    pin.Icon:SetColorTexture(color.r, color.g, color.b)
  end
end

local function PinLevel(canvas)
  if not InCombatLockdown() and WorldMapFrame.GetPinFrameLevelsManager then
    local manager = WorldMapFrame:GetPinFrameLevelsManager()
    if manager and manager.GetValidFrameLevel then
      local ok, level = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_GROUP_MEMBER")
      if ok and level then return level end
    end
  end
  return canvas:GetFrameLevel() + 30
end

-- Nearby members share one pin, so a busy town stays readable.
local function Cluster(points, size)
  table.sort(points, function(a, b) return a.m.name < b.m.name end)
  local groups = {}
  for _, p in ipairs(points) do
    local hit
    for _, g in ipairs(groups) do
      local dx, dy = g.x - p.x, g.y - p.y
      if dx * dx + dy * dy < size * size then
        hit = g
        break
      end
    end
    if hit then
      hit.list[#hit.list + 1] = p.m
    else
      groups[#groups + 1] = { x = p.x, y = p.y, list = { p.m } }
    end
  end
  return groups
end

local function Draw()
  dirty = false
  local canvas = WorldMapFrame:GetCanvas()
  local mapID = WorldMapFrame:GetMapID()
  local count = 0
  local scale = canvas and canvas:GetScale()
  local width, height = canvas and canvas:GetWidth() or 0, canvas and canvas:GetHeight() or 0
  if mapID and Map.Showing() and scale and scale > 0 and width > 0 and height > 0 then
    local points = {}
    for name, m in pairs(Map.Active()) do
      -- Blizzard already draws party and raid members.
      if not UnitInParty(name) and not UnitInRaid(name) then
        local x, y = Project(m.mapID, mapID, m.x, m.y)
        if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
          points[#points + 1] = { m = m, x = width * x, y = height * y }
        end
      end
    end
    local level = PinLevel(canvas)
    for _, g in ipairs(Cluster(points, SIZE / scale)) do
      count = count + 1
      local pin = pins[count]
      if not pin then
        pin = CreatePin(canvas)
        pins[count] = pin
      end
      if pin:GetFrameLevel() ~= level then pin:SetFrameLevel(level) end
      SetupPin(pin, g.list, scale)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", canvas, "TOPLEFT", g.x, -g.y)
      pin:Show()
    end
  end
  for i = count + 1, #pins do pins[i]:Hide() end
end

local function OnUpdate(self, elapsed)
  self.elapsed = (self.elapsed or 0) + elapsed
  if self.elapsed < 0.1 then return end
  self.elapsed = 0
  local canvas = WorldMapFrame:GetCanvas()
  local mapID, scale, width = WorldMapFrame:GetMapID(), canvas:GetScale(), canvas:GetWidth()
  if not dirty and seen.mapID == mapID and seen.scale == scale and seen.width == width then return end
  seen.mapID, seen.scale, seen.width = mapID, scale, width
  Draw()
end

local function Setup()
  if setUp or not WorldMapFrame or not WorldMapFrame.GetCanvas or not C_Map.GetMapRectOnMap then return end
  setUp = true
  local updater = CreateFrame("Frame", nil, WorldMapFrame)
  updater:SetScript("OnUpdate", OnUpdate)
  WorldMapFrame:HookScript("OnShow", function() dirty = true end)
end

ZR.On("MapChanged", function()
  dirty = true
  RefreshMapUtils()
end)
ZR.On("RosterChanged", function() dirty = true end)
ZR.RegisterEvent("GROUP_ROSTER_UPDATE", function() dirty = true end)
EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Setup)
-- Some clients build the world map at startup instead of as its own addon.
ZR.RegisterEvent("PLAYER_LOGIN", Setup)
