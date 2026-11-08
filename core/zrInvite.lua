local _, ZR = ...

local Invite = {}
ZR.Invite = Invite

local PENDING_SECONDS = 60

-- Names whose /ginvite is sitting in the chat box.
local pending = {}
local lastPending
-- Names we whispered through the addon, waiting for the echo.
local whisperSent = {}

function Invite.PendingAt(name)
  local t = pending[name]
  if t and GetTime() - t < PENDING_SECONDS then return t end
  pending[name] = nil
end

local copyBox

local function CopyBox()
  if copyBox then return copyBox end
  local f = CreateFrame("Frame", "ZUGZUGRebornCopyBox", UIParent, "BackdropTemplate")
  f:SetSize(340, 120)
  f:SetPoint("CENTER", 0, 120)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  f.Title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  f.Title:SetPoint("TOP", 0, -18)
  f.Hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.Hint:SetPoint("TOP", f.Title, "BOTTOM", 0, -6)
  f.Edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  f.Edit:SetSize(280, 22)
  f.Edit:SetPoint("TOP", f.Hint, "BOTTOM", 0, -8)
  f.Edit:SetAutoFocus(false)
  f.Edit:SetScript("OnEscapePressed", function() f:Hide() end)
  f.Edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  f.Edit:SetScript("OnTextChanged", function(self, user)
    if user then
      self:SetText(f.command or "")
      self:HighlightText()
    end
  end)
  f.Edit:SetScript("OnKeyDown", function(_, key)
    if key == "C" and IsControlKeyDown() then C_Timer.After(0.1, function() f:Hide() end) end
  end)
  f.Close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.Close:SetPoint("TOPRIGHT", -6, -6)
  f:Hide()
  copyBox = f
  return f
end

function ZR.ShowCopyBox(title, hint, text)
  local f = CopyBox()
  f.Title:SetText(title)
  f.Hint:SetText(hint)
  f.command = text
  f.Edit:SetText(text)
  f:Show()
  f.Edit:SetFocus()
  f.Edit:HighlightText()
end

function Invite.ShowCopyBox(name)
  ZR.ShowCopyBox("Guild invite", "Ctrl+C, then Enter, Ctrl+V, Enter", "/ginvite " .. name)
end

-- Addons cannot invite on Forever, so the user sends the command themselves.
function Invite.Start(name)
  if not name or name == "" then return end
  if not ZR.CanInvite() then
    ZR.Msg("Your rank cannot invite to the guild.")
    return
  end
  pending[name] = GetTime()
  lastPending = name
  if ZR.DB().inviteMode == "copy" then
    Invite.ShowCopyBox(name)
  else
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    open("/ginvite " .. name)
  end
  ZR.Fire("ContactsChanged", name)
end

-- Sends the saved whisper template; click only.
function Invite.WhisperTemplate(name)
  local g = ZR.GDB()
  if not g then return end
  local text = ZR.CleanChat(ZR.FillTemplate(g.template, name))
  if text == "" then
    ZR.Msg("Write a whisper template on the Recruit Message tab first.")
    return
  end
  Invite.Whisper(name, text:sub(1, 255), true)
end

-- track counts it as a recruiting whisper once the echo arrives.
function Invite.Whisper(name, text, track)
  if ZR.ChatLocked() then
    ZR.Msg("Chat is locked right now.")
    return
  end
  if track then whisperSent[name] = GetTime() end
  ZR.SendChat(text, "WHISPER", nil, name)
end

function Invite.ExpectWhisper(name)
  whisperSent[name] = GetTime()
end

local function ToPattern(fmt)
  if not fmt then return nil end
  local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  return "^" .. p .. "$"
end

local rules

local function Rules()
  if rules then return rules end
  rules = {}
  local list = {
    { ERR_GUILD_INVITE_S, "invited" },
    { ERR_GUILD_DECLINE_S, "declined" },
    { ERR_GUILD_DECLINE_AUTO_S, "autodecline" },
    { ERR_GUILD_JOIN_S, "joined" },
    { ERR_ALREADY_IN_GUILD_S, "inguild" },
    { ERR_ALREADY_INVITED_TO_GUILD_S, "pending" },
    { ERR_GUILD_PLAYER_NOT_FOUND_S, "notfound" },
    { ERR_CHAT_PLAYER_NOT_FOUND_S, "whispernotfound" },
  }
  for _, r in ipairs(list) do
    local p = ToPattern(r[1])
    if p then rules[#rules + 1] = { p, r[2] } end
  end
  return rules
end

local function Known(name)
  return pending[name] or whisperSent[name] or ZR.Contacts.Get(name) or (ZR.Who and ZR.Who.results[name])
end

local NAMELESS = {
  { "ERR_GUILD_TRIAL_ACCOUNT_TRIAL", "trial" },
  { "ERR_GUILD_TRIAL_ACCOUNT_VETERAN", "trial" },
  { "ERR_GUILD_INVITE_BAD_SUPER_DISTRICT", "ruleset" },
  { "ERR_GUILD_NOT_ALLIED", "faction" },
}

ZR.RegisterEvent("CHAT_MSG_SYSTEM", function(_, text)
  if not text or ZR.IsSecret(text) then return end
  if lastPending and Invite.PendingAt(lastPending) then
    for _, r in ipairs(NAMELESS) do
      if _G[r[1]] and text == _G[r[1]] then
        pending[lastPending] = nil
        ZR.Contacts.Mark(lastPending, r[2])
        lastPending = nil
        return
      end
    end
  end
  text = text:gsub("|Hplayer:[^|]*|h%[?(.-)%]?|h", "%1")
  for _, r in ipairs(Rules()) do
    local name = text:match(r[1])
    if name then
      name = ZR.StripRealm(name)
      local status = r[2]
      if status == "whispernotfound" then
        if whisperSent[name] then
          whisperSent[name] = nil
          ZR.Contacts.Mark(name, "notfound")
        end
      elseif status == "joined" or status == "invited" or Known(name) then
        pending[name] = nil
        ZR.Contacts.Mark(name, status)
      end
      return
    end
  end
end)

-- Our whisper echo marks the contact only for recruits.
ZR.RegisterEvent("CHAT_MSG_WHISPER_INFORM", function(_, _, target)
  if not target or ZR.IsSecret(target) then return end
  local name = ZR.StripRealm(target)
  local sentAt = whisperSent[name]
  if sentAt and GetTime() - sentAt < 120 and Known(name) then
    whisperSent[name] = nil
    ZR.Contacts.Mark(name, "whispered")
  end
end)

-- If the game blocks the chat prefill, fall back to the copy box.
local function OnBlocked(_, addon, func)
  if addon ~= ZR.ADDON or type(func) ~= "string" or not func:find("Invite") then return end
  if ZR.DB().inviteMode ~= "copy" then
    ZR.DB().inviteMode = "copy"
    ZR.Msg("WoW blocked the /ginvite chat shortcut. Invite now opens a copy box. /reload to clean the chat box. /zr invite chat to try again.")
  end
end
ZR.RegisterEvent("ADDON_ACTION_FORBIDDEN", OnBlocked)
ZR.RegisterEvent("ADDON_ACTION_BLOCKED", OnBlocked)
