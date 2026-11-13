local _, ZR = ...

local readyGuild

-- Guild data arrives a little after login.
local function CheckGuildReady()
  local g, name = ZR.GDB()
  if not g or readyGuild == name then return end
  readyGuild = name
  ZR.Contacts.Prune()
  ZR.Fire("GuildReady")
end

ZR.RegisterEvent("ADDON_LOADED", function(_, name)
  if name ~= ZR.ADDON then return end
  ZR.InitDB()
end)

ZR.RegisterEvent("PLAYER_LOGIN", function()
  ZR.CharDB()
  ZR.UI.GuildFrame.Init()
  ZR.ApplyMinimapButton()
  ZR.Sync.Init()
  ZR.CraftSync.Init()
  ZR.Map.Init()
  ZR.RequestRoster()
  ZR.CheckOfficer()
  CheckGuildReady()
end)

ZR.RegisterEvent("GUILD_ROSTER_UPDATE", CheckGuildReady)
ZR.RegisterEvent("PLAYER_GUILD_UPDATE", CheckGuildReady)
