local _, ZR = ...

local roster = {}
local lastOfficer

function ZR.IsOfficer()
  if not IsInGuild() then return false end
  if IsGuildLeader() then return true end
  return C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() or false
end

-- The user's own /ginvite fails without the rank's invite right.
function ZR.CanInvite()
  return ZR.IsOfficer() and (CanGuildInvite == nil or CanGuildInvite()) or false
end

-- Roster names may carry a realm suffix.
local function StripRealm(name)
  return name and (name:gsub("%-[^%s%-]+$", "")) or nil
end
ZR.StripRealm = StripRealm

function ZR.IsGuildMember(name)
  if not name then return false end
  if roster[name] then return true end
  if C_GuildInfo.MemberExistsByName and C_GuildInfo.MemberExistsByName(name) then return true end
  return false
end

-- Legacy roster globals are not in Blizzard's own code on this client.
function ZR.RefreshRoster()
  wipe(roster)
  if not GetNumGuildMembers or not GetGuildRosterInfo then return end
  for i = 1, (GetNumGuildMembers() or 0) do
    local name = GetGuildRosterInfo(i)
    if name and not ZR.IsSecret(name) then
      roster[name] = true
      roster[StripRealm(name)] = true
    end
  end
end

function ZR.RequestRoster()
  if IsInGuild() and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end

local function CheckOfficer()
  local now = ZR.IsOfficer()
  if now ~= lastOfficer then
    lastOfficer = now
    ZR.Fire("OfficerChanged", now)
  end
end
ZR.CheckOfficer = CheckOfficer

ZR.RegisterEvent("GUILD_ROSTER_UPDATE", function()
  ZR.RefreshRoster()
  CheckOfficer()
  ZR.Fire("RosterChanged")
end)

ZR.RegisterEvent("PLAYER_GUILD_UPDATE", function(_, unit)
  if unit and unit ~= "player" then return end
  ZR.RequestRoster()
  CheckOfficer()
end)

ZR.RegisterEvent("GUILD_RANKS_UPDATE", CheckOfficer)
ZR.RegisterEvent("PLAYER_ENTERING_WORLD", CheckOfficer)
