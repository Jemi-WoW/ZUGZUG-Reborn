local _, ZR = ...

SLASH_ZUGZUGREBORN1 = "/zugzug"
SLASH_ZUGZUGREBORN2 = "/zr"

local function PrintHelp()
  ZR.Msg("Commands:")
  ZR.Msg("  |cffffd100/zr|r - open the Guild window page where you left off")
  ZR.Msg("  |cffffd100/zr recruit|r - open Recruitment")
  ZR.Msg("  |cffffd100/zr whispers|r - open the Whispers tab")
  ZR.Msg("  |cffffd100/zr craft <item>|r - find who in the guild can craft it")
  ZR.Msg("  |cffffd100/zr minimap|r - show or hide the minimap icon")
  ZR.Msg("  |cffffd100/zr invite chat|r or |cffffd100copy|r - how Invite hands you /ginvite")
  ZR.Msg("  |cffffd100/zr sync on|r or |cffffd100off|r - share contacts with other officers")
  ZR.Msg("  |cffffd100/zr days <n>|r - hide contacted players for n days (now " .. (ZR.DB().hideDays or 3) .. ")")
  ZR.Msg("  |cffffd100/zr resetcontacts|r - forget every whisper, invite and decline")
end

SlashCmdList["ZUGZUGREBORN"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")

  if cmd == "" then
    ZR.OpenPage()
    return
  end

  if cmd == "recruit" or cmd == "recruitment" then
    ZR.OpenPage("recruitment")
    return
  end

  if cmd == "craft" or cmd == "crafters" then
    ZR.OpenPage("crafters")
    if arg ~= "" then ZR.UI.CraftersSearch(arg) end
    return
  end

  if cmd == "help" or cmd == "?" then
    PrintHelp()
    return
  end

  if cmd == "whispers" then
    ZR.OpenPage("recruitment", ZR.TAB_WHISPERS)
    return
  end

  if cmd == "minimap" then
    local shown = ZR.ToggleMinimapButton()
    ZR.Msg("Minimap icon " .. (shown and "shown." or "hidden."))
    return
  end

  if cmd == "invite" then
    if arg == "chat" or arg == "copy" then
      ZR.DB().inviteMode = arg
      ZR.Msg(arg == "chat" and "Invite opens chat with /ginvite ready." or "Invite opens a copy box with /ginvite.")
    else
      ZR.Msg("Invite mode: " .. (ZR.DB().inviteMode or "copy") .. ". Use /zr invite chat or /zr invite copy.")
    end
    return
  end

  if cmd == "sync" then
    if arg == "on" or arg == "off" then
      ZR.DB().sync = arg == "on"
      if arg == "on" then ZR.Sync.Hello() end
    end
    ZR.Msg("Officer sync is " .. (ZR.DB().sync and "on." or "off."))
    return
  end

  if cmd == "days" then
    local n = tonumber(arg)
    if n and n >= 0 and n <= 60 then
      ZR.DB().hideDays = math.floor(n)
      ZR.Fire("ContactsChanged")
    end
    ZR.Msg("Contacted players stay hidden for " .. (ZR.DB().hideDays or 3) .. " days.")
    return
  end

  if cmd == "resetcontacts" then
    ZR.Contacts.ResetAll()
    ZR.Msg("Contact history cleared for this guild.")
    return
  end

  PrintHelp()
end
