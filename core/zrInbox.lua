local _, ZR = ...

local Inbox = {}
ZR.Inbox = Inbox

local MAX_THREADS = 100
local MAX_LINES = 50

local function Threads()
  return ZR.CharDB().inbox
end

function Inbox.Get(name)
  return Threads()[name]
end

local function Prune(threads)
  local list = {}
  for name, t in pairs(threads) do list[#list + 1] = { name = name, last = t.last or 0 } end
  if #list <= MAX_THREADS then return end
  table.sort(list, function(a, b) return a.last > b.last end)
  for i = MAX_THREADS + 1, #list do threads[list[i].name] = nil end
end

local function Add(name, out, text)
  local threads = Threads()
  local t = threads[name]
  if not t then
    t = { msgs = {}, unread = 0, last = 0 }
    threads[name] = t
  end
  local now = ZR.Now()
  t.msgs[#t.msgs + 1] = { o = out or nil, t = now, m = text }
  while #t.msgs > MAX_LINES do table.remove(t.msgs, 1) end
  t.last = now
  if not out and not (Inbox.viewing and Inbox.openThread == name) then t.unread = (t.unread or 0) + 1 end
  Prune(threads)
  ZR.Fire("InboxChanged", name)
end

-- Newest conversation first.
function Inbox.Sorted()
  local list = {}
  for name, t in pairs(Threads()) do
    list[#list + 1] = { name = name, thread = t }
  end
  table.sort(list, function(a, b) return (a.thread.last or 0) > (b.thread.last or 0) end)
  return list
end

function Inbox.Unread()
  local n = 0
  for _, t in pairs(Threads()) do n = n + (t.unread or 0) end
  return n
end

function Inbox.MarkRead(name)
  local t = Threads()[name]
  if t and (t.unread or 0) > 0 then
    t.unread = 0
    ZR.Fire("InboxChanged", name)
  end
end

function Inbox.Delete(name)
  Threads()[name] = nil
  if Inbox.openThread == name then Inbox.openThread = nil end
  ZR.Fire("InboxChanged", name)
end

-- Click or Enter only; whispers need a hardware event on Forever.
function Inbox.Send(name, text)
  text = ZR.CleanChat(text)
  if text == "" then return false end
  ZR.Invite.Whisper(name, text:sub(1, 255))
  return true
end

ZR.RegisterEvent("CHAT_MSG_WHISPER", function(_, text, sender)
  if not text or not sender or ZR.IsSecret(text) or ZR.IsSecret(sender) then return end
  Add(ZR.StripRealm(sender), false, text)
end)

ZR.RegisterEvent("CHAT_MSG_WHISPER_INFORM", function(_, text, target)
  if not text or not target or ZR.IsSecret(text) or ZR.IsSecret(target) then return end
  Add(ZR.StripRealm(target), true, text)
end)
