local _, ZR = ...

local Contacts = {}
ZR.Contacts = Contacts

local DAY = 86400
local PRUNE_DAYS = 90

-- Status keys; counters track how often each happened.
local COUNTERS = { whispered = "w", invited = "i", declined = "d" }
local TOUCHES = { whispered = true, invited = true, pending = true }

local BLOCKERS = {
  autodecline = "They decline all guild invites. Whisper them instead.",
  joined = "Already in your guild.",
  inguild = "Already in another guild. Whisper them instead.",
  pending = "They already have a guild invite waiting.",
  trial = "Free trial accounts cannot join guilds.",
  ruleset = "They play under different game rules.",
  faction = "They are the other faction.",
}

local COLORS = {
  new = { 0.25, 1, 0.25 },
  wait = { 1, 0.82, 0 },
  bad = { 1, 0.35, 0.35 },
  good = { 0.25, 1, 0.25 },
  grey = { 0.6, 0.6, 0.6 },
}

local function Store()
  local g = ZR.GDB()
  return g and g.contacts
end

function Contacts.Get(name)
  local c = Store()
  return c and c[name]
end

local function NewRecord()
  return { s = "new", t = 0, by = "", d = 0, w = 0, i = 0, lc = 0 }
end

function Contacts.Mark(name, status)
  local c = Store()
  if not c or not name or name == "" then return end
  local r = c[name] or NewRecord()
  local now = ZR.Now()
  r.s, r.t, r.by = status, now, ZR.PlayerName()
  local k = COUNTERS[status]
  if k then r[k] = (r[k] or 0) + 1 end
  if TOUCHES[status] then r.lc = now end
  c[name] = r
  ZR.Fire("ContactsChanged", name)
  if ZR.Sync then ZR.Sync.Push(name) end
end

-- Last write wins on the status; counters keep the highest seen.
function Contacts.Merge(name, inc)
  local c = Store()
  if not c or not name or name == "" then return false end
  local r = c[name]
  if not r then
    r = NewRecord()
    c[name] = r
  end
  local changed = false
  if (inc.t or 0) > (r.t or 0) then
    r.s, r.t, r.by = inc.s, inc.t, inc.by
    changed = true
  end
  for _, k in ipairs({ "d", "w", "i", "lc" }) do
    if (inc[k] or 0) > (r[k] or 0) then
      r[k] = inc[k]
      changed = true
    end
  end
  if changed then ZR.Fire("ContactsChanged", name) end
  return changed
end

-- Declined players stay visible so officers can see the count before trying again.
function Contacts.IsHidden(name)
  local r = Contacts.Get(name)
  if not r then return false end
  if r.s == "joined" then return true end
  if (r.d or 0) > 0 or BLOCKERS[r.s] or r.s == "notfound" then return false end
  local days = ZR.DB().hideDays or 3
  return (r.lc or 0) > 0 and (ZR.Now() - r.lc) < days * DAY
end

-- Why /ginvite would fail for this player, or nil.
function Contacts.InviteBlocker(name)
  local r = Contacts.Get(name)
  if not r then return nil end
  if r.s == "pending" and ZR.Now() - (r.t or 0) > (ZR.DB().inviteTimeout or 300) then return nil end
  return BLOCKERS[r.s]
end

function Contacts.CanInvite(name)
  return Contacts.InviteBlocker(name) == nil
end

local function Times(n)
  return n and n > 1 and (" " .. n .. "x") or ""
end

-- Text and color for the Status column.
function Contacts.Describe(name)
  local r = Contacts.Get(name)
  local pendingAt = ZR.Invite and ZR.Invite.PendingAt(name)
  if pendingAt then
    return ZR.DB().inviteMode == "copy" and "Paste /ginvite in chat" or "Press Enter in chat", COLORS.wait
  end
  if not r or r.s == "new" then
    return "New", COLORS.new
  end

  local s, text, color = r.s, nil, nil
  if s == "whispered" then
    text, color = "Whispered" .. Times(r.w), COLORS.wait
  elseif s == "invited" then
    local timeout = ZR.DB().inviteTimeout or 300
    if ZR.Now() - (r.t or 0) > timeout then
      text, color = "No answer", COLORS.grey
    else
      text, color = "Invited", COLORS.wait
    end
  elseif s == "declined" then
    text, color = "Declined " .. (r.d or 1) .. "x", COLORS.bad
  elseif s == "autodecline" then
    text, color = "Declines all invites", COLORS.bad
  elseif s == "joined" then
    text, color = "Joined", COLORS.good
  elseif s == "inguild" then
    text, color = "In a guild", COLORS.grey
  elseif s == "pending" then
    text, color = "Invited elsewhere", COLORS.wait
  elseif s == "trial" then
    text, color = "Trial account", COLORS.bad
  elseif s == "ruleset" then
    text, color = "Other game rules", COLORS.bad
  elseif s == "faction" then
    text, color = "Other faction", COLORS.bad
  elseif s == "notfound" then
    text, color = "Offline", COLORS.grey
  else
    text, color = s, COLORS.grey
  end

  if s ~= "declined" and (r.d or 0) > 0 then
    text = text .. ", declined " .. r.d .. "x"
  end
  text = text .. " (" .. ZR.TimeAgo(r.t) .. ")"
  return text, color
end

-- Tooltip lines with the full history.
function Contacts.Tooltip(tt, name)
  local r = Contacts.Get(name)
  if not r then
    tt:AddLine("Not contacted yet", 0.6, 0.6, 0.6)
    return
  end
  tt:AddDoubleLine("Whispered", tostring(r.w or 0), 1, 0.82, 0, 1, 1, 1)
  tt:AddDoubleLine("Invited", tostring(r.i or 0), 1, 0.82, 0, 1, 1, 1)
  tt:AddDoubleLine("Declined", tostring(r.d or 0), 1, 0.82, 0, 1, 1, 1)
  if r.by and r.by ~= "" then
    tt:AddDoubleLine("Last action by", r.by, 1, 0.82, 0, 1, 1, 1)
  end
  tt:AddDoubleLine("Last update", ZR.TimeAgo(r.t), 1, 0.82, 0, 1, 1, 1)
end

function Contacts.Prune()
  local c = Store()
  if not c then return end
  local cutoff = ZR.Now() - PRUNE_DAYS * DAY
  for name, r in pairs(c) do
    if (r.t or 0) < cutoff and (r.d or 0) == 0 then c[name] = nil end
  end
end

function Contacts.ResetAll()
  local c = Store()
  if c then wipe(c) end
  ZR.Fire("ContactsChanged")
end
