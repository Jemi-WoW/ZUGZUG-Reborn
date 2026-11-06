local _, ZR = ...

local Who = {}
ZR.Who = Who

Who.COOLDOWN = 8
local TIMEOUT = 10
local CAP = 50

Who.queue = {}
Who.results = {}
Who.guilded = {}
Who.stats = { queries = 0, guilded = 0, truncated = 0 }
Who.state = "idle"
Who.lastSend = 0
Who.lastQuery = nil
Who.params = nil

local pending

local function QueryText(q)
  local parts = {}
  if q.race then parts[#parts + 1] = ('r-"%s"'):format(q.race) end
  if q.class then parts[#parts + 1] = ('c-"%s"'):format(q.class) end
  parts[#parts + 1] = q.min .. "-" .. q.max
  return table.concat(parts, " ")
end
Who.QueryText = QueryText

function Who.Describe(q)
  if not q then return "" end
  local text = q.min == q.max and ("Level " .. q.min) or ("Level " .. q.min .. "-" .. q.max)
  if q.class then text = text .. " " .. q.class end
  if q.race then text = text .. " " .. q.race end
  return text
end

function Who.Reset()
  wipe(Who.queue)
  wipe(Who.results)
  wipe(Who.guilded)
  Who.stats.queries, Who.stats.guilded, Who.stats.truncated = 0, 0, 0
  Who.state = "idle"
  Who.lastQuery = nil
  Who.params = nil
  ZR.Fire("WhoChanged")
end

-- Seeds a fresh scan; className is localized or nil for all classes.
function Who.Start(minLevel, maxLevel, className)
  Who.Reset()
  Who.params = { min = minLevel, max = maxLevel, class = className }
  Who.queue[1] = { min = minLevel, max = maxLevel, class = className }
  Who.state = "ready"
  ZR.Fire("WhoChanged")
end

function Who.ReadyIn()
  return math.max(0, Who.lastSend + Who.COOLDOWN - GetTime())
end

function Who.Remaining()
  return #Who.queue
end

local function Restore()
  if LFGWhoListFrame then LFGWhoListFrame:RegisterEvent("WHO_LIST_UPDATE") end
  if not (LFGWhoListFrame and LFGWhoListFrame:IsShown()) then C_FriendList.SetWhoToUi(false) end
  pending = nil
end

-- Must run inside a click or key press.
function Who.Next()
  if pending then return false, "Waiting for the last /who" end
  if ZR.WhoDisabled() then return false, "/who is disabled here" end
  if Who.ReadyIn() > 0 then return false, "Cooldown" end
  local q = table.remove(Who.queue, 1)
  if not q then return false, "Nothing queued" end

  -- Forever's Group Finder pops open on every who result unless muted.
  if LFGWhoListFrame and not LFGWhoListFrame:IsShown() then
    LFGWhoListFrame:UnregisterEvent("WHO_LIST_UPDATE")
  end
  C_FriendList.SetWhoToUi(true)
  pending = q
  Who.lastQuery = q
  Who.lastSend = GetTime()
  Who.state = "waiting"
  C_FriendList.SendWho(QueryText(q), Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social or nil)
  ZR.Fire("WhoChanged")

  -- Throttled queries are dropped silently, so retry the same bucket.
  C_Timer.After(TIMEOUT, function()
    if pending == q then
      Restore()
      table.insert(Who.queue, 1, q)
      Who.state = "ready"
      Who.timedOut = true
      ZR.Fire("WhoChanged")
    end
  end)
  return true
end

local DEFAULT_SPLIT = 4

local function Split(q, num, total)
  local children = {}
  if q.max > q.min then
    local span = q.max - q.min + 1
    local k = total > num and math.ceil(total / 45) or DEFAULT_SPLIT
    k = math.min(span, math.max(2, k))
    local start = q.min
    for i = 1, k do
      local stop = (i == k) and q.max or (q.min + math.floor(span * i / k) - 1)
      if stop >= start then
        children[#children + 1] = { min = start, max = stop, class = q.class, race = q.race }
        start = stop + 1
      end
    end
  elseif not q.class then
    for _, c in ipairs(ZR.ClassList()) do
      children[#children + 1] = { min = q.min, max = q.max, class = c.name }
    end
  elseif not q.race then
    for _, race in ipairs(ZR.RaceList()) do
      children[#children + 1] = { min = q.min, max = q.max, class = q.class, race = race }
    end
  end
  for i = #children, 1, -1 do
    table.insert(Who.queue, 1, children[i])
  end
  return #children > 0
end

local function Collect()
  local me = ZR.PlayerName()
  local num, total = C_FriendList.GetNumWhoResults()
  num, total = num or 0, total or 0
  for i = 1, num do
    local w = C_FriendList.GetWhoInfo(i)
    local name = w and w.fullName
    if name and not ZR.IsSecret(name) and name ~= me then
      if (w.fullGuildName and w.fullGuildName ~= "") or ZR.IsGuildMember(name) then
        if not Who.guilded[name] then
          Who.guilded[name] = true
          Who.stats.guilded = Who.stats.guilded + 1
        end
        Who.results[name] = nil
      else
        Who.results[name] = {
          name = name,
          level = w.level or 0,
          class = w.classStr or "",
          classFile = w.filename,
          race = w.raceStr or "",
          zone = w.area or "",
          seen = ZR.Now(),
        }
      end
    end
  end
  return num, total
end

ZR.RegisterEvent("WHO_LIST_UPDATE", function()
  if not pending then return end
  local q = pending
  Restore()
  Who.timedOut = nil
  Who.stats.queries = Who.stats.queries + 1
  local num, total = Collect()
  -- Forever reports the total as the capped count, so a full page means more exist.
  if num >= CAP - 1 or total > num then
    if not Split(q, num, total) then
      Who.stats.truncated = Who.stats.truncated + 1
    end
  end
  Who.state = #Who.queue > 0 and "ready" or "done"
  ZR.Fire("WhoChanged")
end)

-- Players who joined since the scan drop out.
ZR.On("RosterChanged", function()
  local removed = false
  for name in pairs(Who.results) do
    if ZR.IsGuildMember(name) then
      Who.results[name] = nil
      removed = true
    end
  end
  if removed then ZR.Fire("WhoChanged") end
end)
