local _, ZR = ...

local Channels = {}
ZR.Channels = Channels

Channels.MAX_BYTES = 255

-- Channels already posted to in the current Post round.
local round = {}

-- "Trade - Orgrimmar" and "Trade" share one saved checkbox.
local function BaseName(name)
  return (name or ""):gsub("%s+%-%s+.*$", "")
end
Channels.BaseName = BaseName

function Channels.List()
  local out = {}
  local list = { GetChannelList() }
  for i = 1, #list, 3 do
    local id, name, disabled = list[i], list[i + 1], list[i + 2]
    if id and name then
      local _, fullName = GetChannelName(id)
      out[#out + 1] = {
        id = id,
        name = fullName or name,
        key = BaseName(name),
        disabled = disabled and true or false,
      }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function Channels.IsChecked(key)
  local g = ZR.GDB()
  return g and g.channels[key] and true or false
end

function Channels.SetChecked(key, checked)
  local g = ZR.GDB()
  if not g then return end
  g.channels[key] = checked and true or nil
  round[key] = nil
  ZR.Fire("ChannelsChanged")
end

function Channels.LastPosted(key)
  local g = ZR.GDB()
  return g and g.lastPosted[key]
end

function Channels.Message()
  local g = ZR.GDB()
  return ZR.CleanChat(g and g.message or "")
end

function Channels.Targets()
  local out = {}
  for _, ch in ipairs(Channels.List()) do
    if not ch.disabled and Channels.IsChecked(ch.key) then out[#out + 1] = ch end
  end
  return out
end

-- Next checked channel this round, its position and the round size.
function Channels.Next()
  local targets = Channels.Targets()
  if #targets == 0 then return nil, 0, 0 end
  local done = 0
  for _, ch in ipairs(targets) do
    if round[ch.key] then done = done + 1 end
  end
  if done >= #targets then
    wipe(round)
    done = 0
  end
  for _, ch in ipairs(targets) do
    if not round[ch.key] then return ch, done + 1, #targets end
  end
end

function Channels.ResetRound()
  wipe(round)
  ZR.Fire("ChannelsChanged")
end

-- Why Post is unavailable, or nil when it can post.
function Channels.Blocker()
  local msg = Channels.Message()
  if msg == "" then return "Write a message first" end
  if #msg > Channels.MAX_BYTES then return "Message is too long" end
  if ZR.ChatLocked() then return "Chat is locked right now" end
  if not Channels.Next() then return "Pick a channel" end
end

-- One channel per click; the game needs a hardware event for each.
function Channels.PostNext()
  local reason = Channels.Blocker()
  if reason then return false, reason end
  local ch = Channels.Next()
  ZR.SendChat(Channels.Message(), "CHANNEL", nil, ch.id)
  round[ch.key] = true
  ZR.Fire("ChannelsChanged")
  return true, ch
end

-- Our own echo confirms the post went out.
ZR.RegisterEvent("CHAT_MSG_CHANNEL", function(_, text, _, _, channelName, _, _, _, _, channelBaseName, _, _, guid)
  if ZR.IsSecret(guid) or guid ~= UnitGUID("player") then return end
  if ZR.IsSecret(channelBaseName) or ZR.IsSecret(channelName) then return end
  local g = ZR.GDB()
  if not g then return end
  local key = BaseName((channelBaseName and channelBaseName ~= "") and channelBaseName or channelName)
  if g.channels[key] then
    g.lastPosted[key] = ZR.Now()
    ZR.Fire("ChannelsChanged")
  end
end)

local function ChannelsMoved()
  ZR.Fire("ChannelsChanged")
end
ZR.RegisterEvent("CHANNEL_UI_UPDATE", ChannelsMoved)
ZR.RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", ChannelsMoved)
ZR.RegisterEvent("UPDATE_CHAT_COLOR", ChannelsMoved)
