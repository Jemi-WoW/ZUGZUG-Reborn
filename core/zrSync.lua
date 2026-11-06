local _, ZR = ...

local Sync = {}
ZR.Sync = Sync

local PROTO = "1"
local BURST = 8
local MAX_REPLY = 150
local MAX_QUEUE = 400

local queue, queued = {}, {}
local tokens = BURST
local ticker
local replyTimer

local function Enabled()
  return ZR.DB().sync and ZR.IsOfficer() and IsInGuild()
end

local function Send(msg)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, ZR.SYNC_PREFIX, msg, "OFFICER")
  if not ok then return true end
  -- 3 and 8 are throttles; anything else will not succeed on retry.
  return result ~= 3 and result ~= 8
end

local function Encode(name, r)
  return table.concat({ PROTO, "C", name, r.s or "", r.t or 0, r.by or "", r.d or 0, r.w or 0, r.i or 0, r.lc or 0 }, "|")
end

local function Pump()
  tokens = math.min(BURST, tokens + 1)
  while tokens >= 1 and #queue > 0 do
    if not Enabled() then
      wipe(queue)
      wipe(queued)
      break
    end
    local name = queue[1]
    local r = ZR.Contacts.Get(name)
    if r and not Send(Encode(name, r)) then break end
    table.remove(queue, 1)
    queued[name] = nil
    tokens = tokens - 1
  end
end

function Sync.Push(name)
  if not Enabled() or queued[name] or #queue >= MAX_QUEUE then return end
  queued[name] = true
  queue[#queue + 1] = name
end

function Sync.Hello()
  if not Enabled() then return end
  local g = ZR.GDB()
  Send(table.concat({ PROTO, "H", g and g.syncTs or 0 }, "|"))
end

-- Answer a hello with what changed since that officer last synced.
local function Reply(since)
  local g = ZR.GDB()
  if not g then return end
  local list = {}
  for name, r in pairs(g.contacts) do
    if (r.t or 0) > since then list[#list + 1] = { name = name, t = r.t } end
  end
  table.sort(list, function(a, b) return a.t > b.t end)
  for i = 1, math.min(#list, MAX_REPLY) do Sync.Push(list[i].name) end
end

local function OnMessage(_, prefix, text, channel, sender)
  if prefix ~= ZR.SYNC_PREFIX or channel ~= "OFFICER" then return end
  if ZR.IsSecret(text) or ZR.IsSecret(sender) or not Enabled() then return end
  sender = ZR.StripRealm(sender)
  if sender == ZR.PlayerName() then return end

  local parts = { strsplit("|", text) }
  if parts[1] ~= PROTO then return end
  if parts[2] == "H" then
    local since = tonumber(parts[3]) or 0
    if replyTimer then replyTimer:Cancel() end
    replyTimer = C_Timer.NewTimer(2 + math.random() * 6, function() Reply(since) end)
  elseif parts[2] == "C" and parts[3] and parts[3] ~= "" then
    local rec = {
      s = parts[4], t = tonumber(parts[5]) or 0, by = parts[6] or sender,
      d = tonumber(parts[7]) or 0, w = tonumber(parts[8]) or 0,
      i = tonumber(parts[9]) or 0, lc = tonumber(parts[10]) or 0,
    }
    ZR.Contacts.Merge(parts[3], rec)
    local g = ZR.GDB()
    if g and rec.t > (g.syncTs or 0) then g.syncTs = rec.t end
  end
end

function Sync.Init()
  if C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ZR.SYNC_PREFIX)
  end
  ZR.RegisterEvent("CHAT_MSG_ADDON", OnMessage)
  ticker = ticker or C_Timer.NewTicker(1, Pump)
  C_Timer.After(15, Sync.Hello)
end
