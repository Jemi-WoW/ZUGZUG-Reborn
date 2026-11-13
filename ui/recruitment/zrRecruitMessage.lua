local _, ZR = ...
local UI = ZR.UI
local Channels = ZR.Channels

local SAMPLE_NAME = "Firstname Lastname"
local ROW_HEIGHT = 24

local view

local function PreviewLine(ch, msg)
  local info = (ch and ChatTypeInfo["CHANNEL" .. ch.id]) or ChatTypeInfo.CHANNEL or { r = 1, g = 0.75, b = 0.75 }
  local name = ZR.PlayerName()
  local _, classFile = UnitClass("player")
  if ChatFrameUtil and ChatFrameUtil.ShouldColorChatByClass and ChatFrameUtil.ShouldColorChatByClass(info) then
    name = ZR.ColorName(name, classFile)
  end
  if C_ChatInfo.ReplaceIconAndGroupExpressions then
    local ok, out = pcall(C_ChatInfo.ReplaceIconAndGroupExpressions, msg)
    if ok and out then msg = out end
  end
  local label = ch and (ch.id .. ". " .. ch.name) or "2. Trade"
  return ("[%s] [%s]: %s"):format(label, name, msg), info.r or 1, info.g or 1, info.b or 1
end

-- Someone from the last scan reads more real than a placeholder.
local function SampleName()
  for name in pairs(ZR.Who and ZR.Who.results or {}) do return name end
  return SAMPLE_NAME
end

local function WhisperLine(tpl)
  local info = ChatTypeInfo.WHISPER_INFORM or { r = 1, g = 0.5, b = 1 }
  local name = SampleName()
  local msg = ZR.CleanChat(ZR.FillTemplate(tpl, name))
  return ("To [%s]: %s"):format(name, msg ~= "" and msg or "..."), info.r or 1, info.g or 0.5, info.b or 1
end

local function CountText(bytes)
  local color = bytes > Channels.MAX_BYTES and "|cffff4040" or "|cffbbbbbb"
  return color .. bytes .. "/" .. Channels.MAX_BYTES .. "|r"
end

local function UpdateChannelRows()
  local list = Channels.List()
  view.rows = view.rows or {}
  for i, ch in ipairs(list) do
    local row = view.rows[i]
    if not row then
      row = CreateFrame("Frame", nil, view.ChannelBox)
      row:SetHeight(ROW_HEIGHT)
      row:SetPoint("TOPLEFT", 8, -8 - (i - 1) * ROW_HEIGHT)
      row:SetPoint("TOPRIGHT", -8, -8 - (i - 1) * ROW_HEIGHT)
      row.Check = UI.CreateCheck(row, "")
      row.Check:SetPoint("LEFT")
      row.Check:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        Channels.SetChecked(self.key, self:GetChecked())
      end)
      row.Name = UI.Text(row, "GameFontHighlight")
      row.Name:SetPoint("LEFT", row.Check, "RIGHT", 2, 0)
      row.Name:SetPoint("RIGHT", -70, 0)
      row.Name:SetJustifyH("LEFT")
      row.Name:SetWordWrap(false)
      row.Time = UI.Text(row, "GameFontDisableSmall")
      row.Time:SetPoint("RIGHT")
      view.rows[i] = row
    end
    row.Check.key = ch.key
    row.Check:SetChecked(Channels.IsChecked(ch.key))
    row.Check:SetEnabled(not ch.disabled)
    row.Name:SetText(ch.id .. ". " .. ch.name)
    row.Name:SetTextColor(ch.disabled and 0.5 or 1, ch.disabled and 0.5 or 1, ch.disabled and 0.5 or 1)
    local last = Channels.LastPosted(ch.key)
    row.Time:SetText(last and ZR.TimeAgo(last) or "")
    row:Show()
  end
  for i = #list + 1, #view.rows do view.rows[i]:Hide() end
  view.NoChannels:SetShown(#list == 0)
end

local function Update()
  if not view or not view:IsShown() then return end
  local g = ZR.GDB()
  view.Loading:SetShown(not g)
  if not g then return end

  if not view.MessageEdit:HasFocus() and view.MessageEdit:GetText() ~= g.message then
    view.MessageEdit:SetText(g.message or "")
  end
  if not view.TemplateEdit:HasFocus() and view.TemplateEdit:GetText() ~= g.template then
    view.TemplateEdit:SetText(g.template or "")
  end

  local msg = Channels.Message()
  view.MessageCount:SetText(CountText(#msg))
  local tpl = ZR.CleanChat(ZR.FillTemplate(g.template, SAMPLE_NAME))
  view.TemplateCount:SetText(CountText(#tpl))

  local nextCh, index, total = Channels.Next()
  local line, r, gg, b
  if view.previewMode == "whisper" then
    line, r, gg, b = WhisperLine(g.template)
  else
    line, r, gg, b = PreviewLine(nextCh or Channels.List()[1], msg ~= "" and msg or "...")
  end
  view.Preview:SetText(line)
  view.Preview:SetTextColor(r, gg, b)
  for mode, tab in pairs(view.PreviewTabs) do
    local on = mode == view.previewMode
    tab:GetFontString():SetTextColor(on and 1 or 0.5, on and 0.82 or 0.5, on and 0 or 0.5)
  end

  local blocker = Channels.Blocker()
  view.PostButton.blocker = blocker
  if nextCh then
    view.PostButton:SetText(("Post to %d. %s (%d/%d)"):format(nextCh.id, nextCh.key, index, total))
  else
    view.PostButton:SetText("Post")
  end
  view.PostButton:SetEnabled(blocker == nil)

  UpdateChannelRows()
end

local function SetPreview(mode)
  if view.previewMode == mode then return end
  view.previewMode = mode
  Update()
end

local function PreviewTab(parent, text, mode)
  local b = CreateFrame("Button", nil, parent)
  b:SetNormalFontObject("GameFontNormalSmall")
  b:SetText(text)
  b:SetSize(b:GetFontString():GetStringWidth() + 4, 16)
  b:SetScript("OnClick", function() SetPreview(mode) end)
  return b
end

-- A multi-line box like the message one, so long text stays readable.
local function TextBox(parent, title, height, onChange)
  local box = UI.CreateBox(parent, title)
  box:SetSize(512, height)
  local edit = CreateFrame("EditBox", nil, box)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("GameFontHighlight")
  edit:SetPoint("TOPLEFT", 10, -9)
  edit:SetPoint("BOTTOMRIGHT", -10, 9)
  edit:SetScript("OnEscapePressed", edit.ClearFocus)
  -- Chat is single-line, so Enter finishes instead of adding a line.
  edit:SetScript("OnEnterPressed", edit.ClearFocus)
  edit:SetScript("OnTextChanged", function(self, user)
    if user then onChange(self:GetText()) end
  end)
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() edit:SetFocus() end)
  return box, edit
end

local function Post()
  local ok, result = Channels.PostNext()
  if ok then
    view.Status:SetText(("Posted to %d. %s"):format(result.id, result.name))
  else
    UIErrorsFrame:AddExternalErrorMessage(result)
  end
end

function ZR.BindingPost()
  if ZR.IsOfficer() then Post() end
end

function UI.BuildRecruitMessage(parent, inset)
  view = CreateFrame("Frame", nil, parent)
  view:SetAllPoints(parent)

  local msgBox, edit = TextBox(view, "Recruitment message", 76, function(text)
    local g = ZR.GDB()
    if g then
      g.message = text
      Channels.ResetRound()
    end
  end)
  msgBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -26)
  view.MessageCount = UI.Text(view, "GameFontHighlightSmall")
  view.MessageCount:SetPoint("BOTTOMRIGHT", msgBox, "TOPRIGHT", -4, 3)
  edit:HookScript("OnEditFocusGained", function() SetPreview("channel") end)
  view.MessageEdit = edit

  local prevBox = UI.CreateBox(view, "Chat preview")
  prevBox:SetPoint("TOPLEFT", msgBox, "BOTTOMLEFT", 0, -24)
  prevBox:SetSize(512, 66)
  view.previewMode = "channel"
  view.PreviewTabs = {
    whisper = PreviewTab(prevBox, "Whisper", "whisper"),
    channel = PreviewTab(prevBox, "Channel post", "channel"),
  }
  view.PreviewTabs.whisper:SetPoint("BOTTOMRIGHT", prevBox, "TOPRIGHT", -4, 1)
  view.PreviewTabs.channel:SetPoint("RIGHT", view.PreviewTabs.whisper, "LEFT", -10, 0)
  prevBox:SetBackdropColor(0, 0, 0, 0.85)
  view.Preview = prevBox:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
  local font, size, flags = DEFAULT_CHAT_FRAME:GetFont()
  if font then view.Preview:SetFont(font, size, flags) end
  view.Preview:SetPoint("TOPLEFT", 10, -9)
  view.Preview:SetPoint("BOTTOMRIGHT", -10, 9)
  view.Preview:SetJustifyH("LEFT")
  view.Preview:SetJustifyV("TOP")

  local tplBox, tpl = TextBox(view, "Whisper template", 76, function(text)
    local g = ZR.GDB()
    if g then
      g.template = text
      Update()
    end
  end)
  tplBox:SetPoint("TOPLEFT", prevBox, "BOTTOMLEFT", 0, -24)
  tpl:SetMaxBytes(512)
  tpl:HookScript("OnEditFocusGained", function() SetPreview("whisper") end)
  local tplHint = UI.Text(view, "GameFontDisableSmall", "{name} = their name, {guild} = your guild")
  tplHint:SetPoint("LEFT", tplBox.Title, "RIGHT", 8, 0)
  view.TemplateCount = UI.Text(view, "GameFontHighlightSmall")
  view.TemplateCount:SetPoint("BOTTOMRIGHT", tplBox, "TOPRIGHT", -4, 3)
  view.TemplateEdit = tpl

  local tplNote = UI.Text(view, "GameFontDisableSmall", "Sent by Whisper and Whisper next on Fast Invite. Shift-click Whisper to type your own.")
  tplNote:SetPoint("TOPLEFT", tplBox, "BOTTOMLEFT", 2, -5)

  view.ChannelBox = UI.CreateBox(view, "Channels")
  view.ChannelBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 548, -26)
  view.ChannelBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -14, 12)
  view.NoChannels = UI.Text(view.ChannelBox, "GameFontDisable", "Join a channel to post here.")
  view.NoChannels:SetPoint("CENTER")

  view.PostButton = UI.CreateButton(view, "Post", 240, 20)
  view.PostButton:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -3, 3)
  view.PostButton:SetScript("OnClick", Post)
  UI.SetButtonTooltip(view.PostButton, function(self)
    if self.blocker then return self.blocker end
    return "Post to the next channel", "Blizzard allows one channel post per click."
  end)

  view.Status = UI.Text(view, "GameFontHighlightSmall")
  view.Status:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 7)

  view.Loading = UI.Text(view, "GameFontDisable", "Loading guild data...")
  view.Loading:SetPoint("CENTER", inset)

  view:SetScript("OnShow", Update)
  view.elapsed = 0
  view:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed > 10 then
      self.elapsed = 0
      Update()
    end
  end)
  ZR.On("ChannelsChanged", Update)
  ZR.On("GuildReady", Update)
  view:Hide()
  return view
end
