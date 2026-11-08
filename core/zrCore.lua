local ADDON, ZR = ...
_G.ZUGZUGReborn = ZR

ZUGZUGRebornDB = ZUGZUGRebornDB or {}

ZR.ADDON = ADDON
ZR.TITLE = "ZUGZUG Reborn"
ZR.ICON_TEXTURE = "Interface\\AddOns\\ZUGZUG-Reborn\\externals\\img\\ZUGZUGRebornIcon.tga"
ZR.SYNC_PREFIX = "ZUGZUGReborn"
ZR.DISCORD_URL = "https://discord.gg/Vg7npmWaxf"

BINDING_HEADER_ZUGZUGREBORN = "ZUGZUG Reborn"
BINDING_NAME_ZUGZUGREBORN_SCAN = "Fast Invite: scan next"
BINDING_NAME_ZUGZUGREBORN_POST = "Recruit Message: post to next channel"

local DEFAULTS = {
  hideDays = 3,
  inviteTimeout = 300,
  inviteMode = "copy",
  sync = true,
}

local DEFAULT_MESSAGE = "<%s> is recruiting! Friendly guild for leveling, dungeons and raids. Whisper me for an invite!"
local DEFAULT_TEMPLATE = "Hey {name}! <{guild}> is recruiting, want an invite?"

function ZR.Msg(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cffd4af37[ZUGZUG Reborn]|r " .. tostring(text))
end

function ZR.InitDB()
  local db = ZUGZUGRebornDB
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then db[k] = v end
  end
  db.minimap = db.minimap or {}
  db.guilds = db.guilds or {}
  db.chars = db.chars or {}
  db.version = 1
end

function ZR.DB()
  return ZUGZUGRebornDB
end

function ZR.PlayerName()
  return GetUnitName("player", false) or UnitName("player")
end

function ZR.CharDB()
  local key = UnitGUID("player") or "UNKNOWN"
  local c = ZUGZUGRebornDB.chars[key]
  if not c then
    c = { inbox = {} }
    ZUGZUGRebornDB.chars[key] = c
  end
  c.name = ZR.PlayerName()
  c.inbox = c.inbox or {}
  return c
end

-- Per-guild data; nil until guild info has arrived.
function ZR.GDB()
  local guild = GetGuildInfo("player")
  if not guild or guild == "" then return nil end
  local g = ZUGZUGRebornDB.guilds[guild]
  if not g then
    g = {
      message = DEFAULT_MESSAGE:format(guild),
      template = DEFAULT_TEMPLATE,
      channels = {},
      lastPosted = {},
      contacts = {},
      syncTs = 0,
    }
    ZUGZUGRebornDB.guilds[guild] = g
  end
  return g, guild
end

-- Tiny internal message bus between core and UI.
local listeners = {}

function ZR.On(name, fn)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], fn)
end

function ZR.Fire(name, ...)
  for _, fn in ipairs(listeners[name] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()(err) end
  end
end

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ZR.RegisterEvent(event, fn)
  if not handlers[event] then
    -- Unknown events error on register, so one missing event cannot break the file.
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return end
    handlers[event] = {}
  end
  table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event]) do
    local ok, err = pcall(fn, event, ...)
    if not ok then geterrorhandler()(err) end
  end
end)

function ZR.TimeAgo(ts)
  if not ts or ts <= 0 then return "never" end
  local d = ZR.Now() - ts
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

-- Fills {name} and {guild} in a template.
function ZR.FillTemplate(template, name)
  local guild = GetGuildInfo("player") or ""
  local out = (template or ""):gsub("{name}", function() return name or "" end)
  out = out:gsub("{guild}", function() return guild end)
  return out
end

-- Chat lines are single-line and pipes must be escaped.
function ZR.CleanChat(text)
  text = (text or ""):gsub("[\r\n]+", " ")
  text = text:gsub("||", "\001"):gsub("|", "||"):gsub("\001", "||")
  return strtrim(text)
end

function ZR.ClassColor(classFile)
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  return c
end

function ZR.ColorName(name, classFile)
  local c = ZR.ClassColor(classFile)
  if c then return c:WrapTextInColorCode(name) end
  return name
end
