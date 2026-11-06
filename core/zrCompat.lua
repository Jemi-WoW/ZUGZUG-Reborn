local _, ZR = ...

-- Chat payloads can arrive as secret values during lockdown.
function ZR.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

function ZR.Now()
  return GetServerTime and GetServerTime() or time()
end

-- The global SendChatMessage is only a deprecation shim on this client.
function ZR.SendChat(msg, chatType, languageID, target)
  if C_ChatInfo and C_ChatInfo.SendChatMessage then
    return C_ChatInfo.SendChatMessage(msg, chatType, languageID, target)
  end
  return SendChatMessage(msg, chatType, languageID, target)
end

function ZR.ChatLocked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
    return true
  end
  if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and Enum.AddOnRestrictionType then
    return C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Chat) and true or false
  end
  return false
end

function ZR.WhoDisabled()
  if C_GameRules and C_GameRules.IsGameRuleActive and Enum.GameRule and Enum.GameRule.IngameWhoListDisabled then
    return C_GameRules.IsGameRuleActive(Enum.GameRule.IngameWhoListDisabled) and true or false
  end
  return false
end

local classList

-- Localized class names, sorted like Blizzard's who filter.
function ZR.ClassList()
  if classList then return classList end
  classList = {}
  local ids = C_SpecializationInfo and C_SpecializationInfo.GetAllClassIDs and C_SpecializationInfo.GetAllClassIDs()
  if not ids then
    ids = {}
    for i = 1, (GetNumClasses and GetNumClasses() or 0) do ids[#ids + 1] = i end
  end
  for _, id in ipairs(ids) do
    local name, file = GetClassInfo(id)
    if name and file then
      classList[#classList + 1] = { id = id, name = name, file = file }
    end
  end
  table.sort(classList, function(a, b) return a.name < b.name end)
  return classList
end

function ZR.ClassByFile(file)
  for _, c in ipairs(ZR.ClassList()) do
    if c.file == file then return c end
  end
end

function ZR.RaceList()
  local out = {}
  local filters = C_FriendList.GetWhoRaceFilters and C_FriendList.GetWhoRaceFilters()
  for _, r in ipairs(filters or {}) do
    if r.name then out[#out + 1] = r.name end
  end
  return out
end

function ZR.MaxLevel()
  return GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
end
