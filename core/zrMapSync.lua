local _, ZR = ...

-- Shares where guild members are, for the world map pins.
local Map = {}
ZR.Map = Map

local PREFIX = "ZUGZUGMap"
local MAPUTILS = "MapUtils"
local PROTO = "1"
local SCALE = 10000
local SEND_EVERY = 5
local HEARTBEAT = 30
local MOVED = 0.0015
local EXPIRE = 75

Map.members = {}
local last = {}

function Map.Showing()
  return ZR.DB().mapPins ~= false
end

function Map.Sharing()
  return ZR.DB().mapShare ~= false
end

local function Changed()
  ZR.Fire("MapChanged")
end

local function Send(msg)
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
end

local function CanSend()
  if not Map.Sharing() or not IsInGuild() then return false end
  if C_GuildInfo.CanSpeakInGuildChat and not C_GuildInfo.CanSpeakInGuildChat() then return false end
  local _, kind = IsInInstance()
  return kind ~= "pvp" and kind ~= "arena"
end

local function OwnPosition()
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID or ZR.IsSecret(mapID) then return end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  if ZR.IsSecret(x) or ZR.IsSecret(y) or not x or not y or (x == 0 and y == 0) then return end
  return mapID, x, y
end

-- Sends only after moving, plus a heartbeat so pins never expire while standing still.
local function Broadcast()
  if not CanSend() then return end
  local mapID, x, y = OwnPosition()
  if not mapID then return end
  local onTaxi = UnitOnTaxi("player")
  local taxi = (not ZR.IsSecret(onTaxi) and onTaxi) and "1" or "0"
  local now = GetTime()
  local moved = last.mapID ~= mapID or last.taxi ~= taxi
    or math.abs(x - last.x) > MOVED or math.abs(y - last.y) > MOVED
  if not moved and now - last.at < HEARTBEAT then return end
  local _, class = UnitClass("player")
  Send(table.concat({ PROTO, "P", mapID, math.floor(x * SCALE + 0.5), math.floor(y * SCALE + 0.5),
    UnitLevel("player") or 0, class or "", taxi }, "|"))
  last.mapID, last.x, last.y, last.taxi, last.at = mapID, x, y, taxi, now
end

local function Store(name, source, mapID, x, y, level, class, taxi)
  if not name or name == "" or name == ZR.PlayerName() then return end
  if not mapID or mapID <= 0 or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return end
  local now = GetTime()
  local m = Map.members[name]
  -- Ours carries more, so a MapUtils copy of the same player never replaces a fresh one.
  if m and m.source == "zz" and source ~= "zz" and now - m.at < EXPIRE then return end
  m = m or { name = name }
  Map.members[name] = m
  m.source, m.mapID, m.x, m.y, m.taxi, m.at = source, mapID, x, y, taxi, now
  if level and level > 0 then m.level = level end
  if class and RAID_CLASS_COLORS[class] then m.class = class end
  Changed()
end

local function Remove(name)
  if Map.members[name] then
    Map.members[name] = nil
    Changed()
  end
end

-- Members seen recently enough to draw.
function Map.Active()
  local out, now = {}, GetTime()
  for name, m in pairs(Map.members) do
    if now - m.at < EXPIRE then out[name] = m end
  end
  return out
end

local function Prune()
  local now, removed = GetTime(), false
  for name, m in pairs(Map.members) do
    if now - m.at >= EXPIRE then
      Map.members[name] = nil
      removed = true
    end
  end
  if removed then Changed() end
end

-- Only right after a roster update, since the cached roster goes stale between updates.
local function DropOffline()
  local now, removed = GetTime(), false
  for name, m in pairs(Map.members) do
    local info = ZR.RosterInfo(name)
    if info and not info.online and now - m.at > 10 then
      Map.members[name] = nil
      removed = true
    end
  end
  if removed then Changed() end
end

local function OnMessage(_, prefix, text, channel, sender)
  if channel ~= "GUILD" or (prefix ~= PREFIX and prefix ~= MAPUTILS) then return end
  if ZR.IsSecret(text) or ZR.IsSecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  local name = ZR.StripRealm(sender)
  if prefix == MAPUTILS then
    if text:sub(1, 1) ~= "G" then return end
    local mapID, x, y, class, level, _, taxi = strsplit(":", text:sub(2))
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end
    Store(name, "MapUtils", tonumber(mapID), x / SCALE, y / SCALE, tonumber(level), class, taxi == "1")
    return
  end
  local proto, kind, mapID, x, y, level, class, taxi = strsplit("|", text)
  if proto ~= PROTO then return end
  if kind == "X" then
    Remove(name)
  elseif kind == "P" then
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return end
    Store(name, "zz", tonumber(mapID), x / SCALE, y / SCALE, tonumber(level), class, taxi == "1")
  end
end

function Map.SetSharing(on)
  ZR.DB().mapShare = on
  wipe(last)
  -- Turning it off clears our pin for everyone right away.
  if not on and IsInGuild() then Send(PROTO .. "|X") end
end

function Map.SetShowing(on)
  ZR.DB().mapPins = on
  Changed()
end

function Map.Init()
  if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
  if C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    -- Members who only run MapUtils still show up.
    C_ChatInfo.RegisterAddonMessagePrefix(MAPUTILS)
  end
  ZR.RegisterEvent("CHAT_MSG_ADDON", OnMessage)
  C_Timer.NewTicker(SEND_EVERY, function()
    Broadcast()
    Prune()
  end)
  C_Timer.After(2, Broadcast)
end

ZR.On("RosterChanged", DropOffline)
ZR.RegisterEvent("PLAYER_GUILD_UPDATE", function()
  wipe(Map.members)
  Changed()
end)
