local _, ZR = ...

-- Shares profession data with every guild member running the addon.
local CS = {}
ZR.CraftSync = CS

local PREFIX = "ZUGZUGCraft"
local PROTO = "1"
local BURST = 6
local MAX_QUEUE = 800
local CHUNK = 190
local ASK_AGAIN = 60

local queue, tokens = {}, BURST
local asked, receiving, responding, partial = {}, {}, {}, {}
local indexHeardAt, indexTimer, versionTimer = 0, nil, nil
-- Index entries heard since the last query, so later answers only fill gaps.
local heard

local function Crafts() return ZR.Crafts end

local function Join(...)
  return table.concat({ PROTO, ... }, "|")
end

local function Queue(msg)
  if msg and #queue < MAX_QUEUE then queue[#queue + 1] = msg end
end

local function Send(msg)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  if not ok then return true end
  -- 3 and 8 are throttles; anything else will not succeed on retry.
  return result ~= 3 and result ~= 8
end

local function Pump()
  tokens = math.min(BURST, tokens + 1)
  while tokens >= 1 and #queue > 0 do
    if not IsInGuild() then
      wipe(queue)
      break
    end
    if not Send(queue[1]) then break end
    table.remove(queue, 1)
    tokens = tokens - 1
  end
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function B36(n)
  n = math.floor(n or 0)
  if n <= 0 then return "0" end
  local s = ""
  while n > 0 do
    local r = n % 36
    s = DIGITS:sub(r + 1, r + 1) .. s
    n = math.floor(n / 36)
  end
  return s
end

local function MyChars()
  local set = {}
  for _, c in pairs(ZR.DB().chars or {}) do
    if c.name then set[c.name] = true end
  end
  return set
end

local function VersionMsg(name)
  local rec = Crafts().Get(name)
  if not rec then return nil end
  local parts = {}
  for skill, p in pairs(rec.p or {}) do
    parts[#parts + 1] = table.concat({ skill, p.t or 0, p.r or 0, p.m or 0 }, ":")
  end
  return Join("PV", name, rec.c or "", table.concat(parts, ";"))
end

-- Full recipe list, split so each message stays under the 255 byte limit.
local function QueueData(name, skill)
  local p = Crafts().GetProf(name, skill)
  if not p or (p.t or 0) == 0 then return end
  local chunks, buf, len = {}, {}, 0
  for recipe, item in pairs(p.l or {}) do
    local pair = B36(recipe) .. ":" .. B36(item)
    if len + #pair + 1 > CHUNK then
      chunks[#chunks + 1] = table.concat(buf, ",")
      buf, len = {}, 0
    end
    buf[#buf + 1] = pair
    len = len + #pair + 1
  end
  chunks[#chunks + 1] = table.concat(buf, ",")
  for i, payload in ipairs(chunks) do
    Queue(Join("PD", name, skill, p.t, p.r or 0, p.m or 0, i, #chunks, payload))
  end
end

local function QueueIndex(skip)
  local store = Crafts().Store()
  if not store then return end
  local buf, len = {}, 0
  local function Flush()
    if #buf > 0 then Queue(Join("PI", table.concat(buf, ";"))) end
    buf, len = {}, 0
  end
  for name, rec in pairs(store) do
    if Crafts().Visible(name) then
      for skill, p in pairs(rec.p or {}) do
        local seen = skip and skip[name .. "|" .. skill]
        if not seen or seen < (p.t or 0) then
          local entry = table.concat({ name, skill, p.t or 0, p.r or 0, p.m or 0 }, ":")
          if len + #entry + 1 > 220 then Flush() end
          buf[#buf + 1] = entry
          len = len + #entry + 1
        end
      end
    end
  end
  Flush()
end

local function Key(name, skill)
  return name .. "|" .. skill
end

-- Waits a moment so a reply already on its way is not asked for twice.
local function Request(name, skill, t)
  local key = Key(name, skill)
  if asked[key] and GetTime() - asked[key] < ASK_AGAIN then return end
  local stamp = GetTime()
  asked[key] = stamp
  C_Timer.After(3 + math.random() * 3, function()
    -- Someone else asked meanwhile; their answer reaches us too.
    if asked[key] ~= stamp then return end
    local p = Crafts().GetProf(name, skill)
    if p and (p.t or 0) >= t then return end
    if receiving[key] and GetTime() - receiving[key] < 30 then return end
    Queue(Join("PR", name, skill, t))
  end)
end

-- One entry from an index or version list: raise skill, ask for newer recipes.
local function Learn(name, skill, t, r, m, mine)
  if not name or name == "" or not skill then return end
  local p = Crafts().GetProf(name, skill)
  if mine[name] then
    if p and (p.t or 0) > t then QueueData(name, skill) end
    return
  end
  if not Crafts().Visible(name) then return end
  if not p or (p.r or 0) < r or (p.m or 0) < m then Crafts().SetProf(name, skill, 0, r, m) end
  if t > ((p and p.t) or 0) then Request(name, skill, t) end
end

local function OnVersion(sender, name, class, list)
  local me = ZR.PlayerName()
  if not name or name == me then return end
  local rec = Crafts().Ensure(name)
  if not rec then return end
  if class and class ~= "" then rec.c = class end
  local listed, mine = {}, {}
  for entry in (list or ""):gmatch("[^;]+") do
    local skill, t, r, m = strsplit(":", entry)
    skill, t, r, m = tonumber(skill), tonumber(t) or 0, tonumber(r) or 0, tonumber(m) or 0
    if skill then
      listed[skill] = true
      local p = rec.p[skill]
      -- The owner's own word on skill wins, even if it went down.
      if sender == name and p then p.r, p.m = r, m end
      Learn(name, skill, t, r, m, mine)
    end
  end
  if sender == name then
    for skill in pairs(rec.p) do
      if not listed[skill] then rec.p[skill] = nil end
    end
  end
  Crafts().Changed()
end

local function OnIndex(list)
  indexHeardAt = GetTime()
  local mine = MyChars()
  mine[ZR.PlayerName()] = true
  for entry in (list or ""):gmatch("[^;]+") do
    local name, skill, t, r, m = strsplit(":", entry)
    t = tonumber(t) or 0
    if heard and name and skill then
      local key = name .. "|" .. skill
      heard[key] = math.max(heard[key] or -1, t)
    end
    Learn(name, tonumber(skill), t, tonumber(r) or 0, tonumber(m) or 0, mine)
  end
end

local function OnRequest(name, skill, t)
  local key = Key(name, skill)
  asked[key] = GetTime()
  local p = Crafts().GetProf(name, skill)
  if not p or (p.t or 0) == 0 or p.t < t or responding[key] then return end
  -- The owner answers first; anyone else only if nobody has after a few seconds.
  local delay = name == ZR.PlayerName() and 0.3 or (2 + math.random() * 5)
  responding[key] = C_Timer.NewTimer(delay, function()
    responding[key] = nil
    QueueData(name, skill)
  end)
end

local function OnData(name, skill, t, r, m, i, n, payload)
  if not name or name == ZR.PlayerName() or not skill or not t or not i or not n then return end
  local key = Key(name, skill)
  receiving[key] = GetTime()
  if responding[key] then
    responding[key]:Cancel()
    responding[key] = nil
  end
  local p = Crafts().GetProf(name, skill)
  if p and (p.t or 0) >= t then return end
  if not Crafts().Visible(name) then return end

  local now = GetTime()
  for k, part in pairs(partial) do
    if now - part.at > 120 then partial[k] = nil end
  end
  local pk = key .. "|" .. t
  local part = partial[pk]
  if not part then
    part = { n = n, got = 0, parts = {}, at = now }
    partial[pk] = part
  end
  if not part.parts[i] then
    part.parts[i] = payload or ""
    part.got = part.got + 1
  end
  if part.got < part.n then return end
  partial[pk] = nil
  local list = {}
  for k = 1, part.n do
    for rs, is in (part.parts[k] or ""):gmatch("(%w+):(%w+)") do
      local recipe = tonumber(rs, 36)
      if recipe then list[recipe] = tonumber(is, 36) or 0 end
    end
  end
  Crafts().SetProf(name, skill, t, r or 0, m or 0, list)
end

local function OnAdd(name, skill, prev, t, pair)
  if not name or name == ZR.PlayerName() or not skill or not t or not Crafts().Visible(name) then return end
  local p = Crafts().GetProf(name, skill)
  local rs, is = (pair or ""):match("(%w+):(%w+)")
  local recipe = rs and tonumber(rs, 36)
  if p and recipe and (p.t or 0) == prev then
    p.l = p.l or {}
    p.l[recipe] = tonumber(is, 36) or 0
    p.t = t
    Crafts().Changed()
  elseif not p or (p.t or 0) < t then
    Request(name, skill, t)
  end
end

local function OnQuery()
  -- Everyone online vouches for their own character; one member covers the rest.
  if not versionTimer then
    versionTimer = C_Timer.NewTimer(1 + math.random() * 4, function()
      versionTimer = nil
      Queue(VersionMsg(ZR.PlayerName()))
    end)
  end
  if indexTimer then return end
  heard = {}
  local heardBefore = indexHeardAt
  indexTimer = C_Timer.NewTimer(3 + math.random() * 7, function()
    indexTimer = nil
    -- If someone answered first, only add what their answer missed.
    QueueIndex(indexHeardAt ~= heardBefore and heard or nil)
    heard = nil
  end)
end

local function OnMessage(_, prefix, text, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" then return end
  if ZR.IsSecret(text) or ZR.IsSecret(sender) or not Crafts().Store() then return end
  sender = ZR.StripRealm(sender)
  if sender == ZR.PlayerName() then return end
  local f = { strsplit("|", text) }
  if f[1] ~= PROTO then return end
  local kind = f[2]
  if kind == "PV" then
    OnVersion(sender, f[3], f[4], f[5])
  elseif kind == "PQ" then
    OnQuery()
  elseif kind == "PI" then
    OnIndex(f[3])
  elseif kind == "PR" then
    OnRequest(f[3], tonumber(f[4]), tonumber(f[5]) or 0)
  elseif kind == "PD" then
    OnData(f[3], tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), tonumber(f[8]), tonumber(f[9]), f[10])
  elseif kind == "PA" then
    OnAdd(f[3], tonumber(f[4]), tonumber(f[5]) or 0, tonumber(f[6]), f[7])
  end
end

function CS.QueueVersion()
  if versionTimer then versionTimer:Cancel() end
  versionTimer = C_Timer.NewTimer(5, function()
    versionTimer = nil
    if IsInGuild() then Queue(VersionMsg(ZR.PlayerName())) end
  end)
end

function CS.SendProf(name, skill)
  if IsInGuild() then QueueData(name, skill) end
end

function CS.SendAdd(name, skill, prev, t, recipe, item)
  if IsInGuild() then Queue(Join("PA", name, skill, prev, t, B36(recipe) .. ":" .. B36(item))) end
end

-- Announce our characters, then ask the guild what it knows.
function CS.Hello()
  if not IsInGuild() or not Crafts().Store() then return end
  Crafts().UpdateOwn()
  local store = Crafts().Store()
  for name in pairs(MyChars()) do
    if store[name] then Queue(VersionMsg(name)) end
  end
  Queue(Join("PQ"))
end

function CS.Busy()
  return #queue + (next(partial) and 1 or 0) > 0
end

function CS.Init()
  if C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  end
  ZR.RegisterEvent("CHAT_MSG_ADDON", OnMessage)
  C_Timer.NewTicker(1, Pump)
end

ZR.On("GuildReady", function()
  C_Timer.After(20, CS.Hello)
end)
