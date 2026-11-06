local _, ZR = ...
local UI = ZR.UI
local Inbox = ZR.Inbox

local view

local function ClassFileOf(name)
  local r = ZR.Who.results[name]
  return r and r.classFile
end

local function Color(chatType)
  local info = ChatTypeInfo and ChatTypeInfo[chatType]
  if info then return info.r, info.g, info.b end
  return 1, 0.5, 1
end

local function ShowThread()
  local name = Inbox.openThread
  local t = name and Inbox.Get(name)
  view.History:Clear()
  view.ThreadBox.Title:SetText(t and ZR.ColorName(name, ClassFileOf(name)) or "Conversation")
  view.Reply:SetEnabled(t ~= nil)
  view.SendButton:SetEnabled(t ~= nil)
  view.InviteButton:SetEnabled(t ~= nil and ZR.CanInvite())
  view.DeleteButton:SetEnabled(t ~= nil)
  view.Pick:SetShown(t == nil)
  if not t then return end
  for _, m in ipairs(t.msgs) do
    local stamp = "|cff888888" .. date("%H:%M", m.t) .. "|r "
    if m.o then
      view.History:AddMessage(stamp .. "To [" .. name .. "]: " .. m.m, Color("WHISPER_INFORM"))
    else
      view.History:AddMessage(stamp .. "[" .. name .. "]: " .. m.m, Color("WHISPER"))
    end
  end
  view.History:ScrollToBottom()
end

local function Select(name)
  Inbox.openThread = name
  Inbox.MarkRead(name)
  ShowThread()
  view.List:Refresh()
end

local function InitRow(row, data)
  if not row.Name then
    UI.StyleRow(row)
    row.Unread = row:CreateTexture(nil, "OVERLAY")
    row.Unread:SetAtlas("communities-icon-notification")
    row.Unread:SetSize(14, 14)
    row.Unread:SetPoint("TOPLEFT", 2, -3)
    row.Name = UI.CreateCell(row, "GameFontNormal")
    row.Name:SetPoint("TOPLEFT", 18, -4)
    row.Name:SetPoint("TOPRIGHT", -60, -4)
    row.Time = UI.CreateCell(row, "GameFontDisableSmall", "RIGHT")
    row.Time:SetPoint("TOPRIGHT", -6, -5)
    row.Last = UI.CreateCell(row, "GameFontDisableSmall")
    row.Last:SetPoint("BOTTOMLEFT", 18, 4)
    row.Last:SetPoint("BOTTOMRIGHT", -6, 4)
    row.Selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.Selected:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar")
    row.Selected:SetBlendMode("ADD")
    row.Selected:SetAllPoints()
    row:SetScript("OnClick", function(self)
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      Select(self.data.name)
    end)
  end
  row.data = data
  local t = data.thread
  row.Name:SetText(ZR.ColorName(data.name, ClassFileOf(data.name)))
  row.Time:SetText(ZR.TimeAgo(t.last))
  local last = t.msgs[#t.msgs]
  row.Last:SetText(last and ((last.o and "You: " or "") .. last.m) or "")
  row.Unread:SetShown((t.unread or 0) > 0)
  row.Selected:SetShown(Inbox.openThread == data.name)
end

local function UpdateList()
  if not view or not view:IsShown() then return end
  local list = Inbox.Sorted()
  view.List:SetRows(list)
  view.NoThreads:SetShown(#list == 0)
end

local function SendReply()
  local name = Inbox.openThread
  if not name then return end
  if Inbox.Send(name, view.Reply:GetText()) then view.Reply:SetText("") end
end

function UI.BuildWhispers(parent, inset)
  view = CreateFrame("Frame", nil, parent)
  view:SetAllPoints(parent)

  local listBox = UI.CreateBox(view, "Conversations")
  listBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -26)
  listBox:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 14, 12)
  listBox:SetWidth(250)

  view.List = UI.CreateTable(listBox, { { title = "", width = 0 } }, nil, 38, InitRow)
  view.List:SetPoint("TOPLEFT", 6, -6)
  view.List:SetPoint("BOTTOMRIGHT", -6, 6)
  view.List.Header:Hide()
  view.List.ScrollBox:SetPoint("TOPLEFT", view.List, "TOPLEFT", 0, 0)

  view.NoThreads = UI.Text(listBox, "GameFontDisable", "No whispers yet.")
  view.NoThreads:SetPoint("CENTER")

  view.ThreadBox = UI.CreateBox(view, "Conversation")
  view.ThreadBox:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 14, 0)
  view.ThreadBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -14, 44)
  view.ThreadBox:SetBackdropColor(0, 0, 0, 0.85)

  view.History = CreateFrame("ScrollingMessageFrame", nil, view.ThreadBox)
  view.History:SetPoint("TOPLEFT", 10, -8)
  view.History:SetPoint("BOTTOMRIGHT", -10, 8)
  view.History:SetFontObject(ChatFontNormal)
  view.History:SetJustifyH("LEFT")
  view.History:SetFading(false)
  view.History:SetMaxLines(200)
  view.History:EnableMouseWheel(true)
  view.History:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)

  view.Pick = UI.Text(view.ThreadBox, "GameFontDisable", "Pick a conversation on the left.")
  view.Pick:SetPoint("CENTER")

  view.DeleteButton = UI.CreateButton(view, DELETE or "Delete", 80, 20)
  view.DeleteButton:SetPoint("BOTTOMRIGHT", view.ThreadBox, "TOPRIGHT", 0, 1)
  view.DeleteButton:SetScript("OnClick", function()
    if Inbox.openThread then Inbox.Delete(Inbox.openThread) end
    ShowThread()
  end)

  view.InviteButton = UI.CreateButton(view, INVITE or "Invite", 80, 20)
  view.InviteButton:SetPoint("RIGHT", view.DeleteButton, "LEFT", -2, 0)
  view.InviteButton:SetScript("OnClick", function()
    if Inbox.openThread then ZR.Invite.Start(Inbox.openThread) end
  end)

  view.SendButton = UI.CreateButton(view, SEND_LABEL or "Send", 80, 22)
  view.SendButton:SetPoint("TOPRIGHT", view.ThreadBox, "BOTTOMRIGHT", 0, -10)
  view.SendButton:SetScript("OnClick", SendReply)

  view.Reply = UI.CreateInput(view, 100, 22)
  view.Reply:SetPoint("TOPLEFT", view.ThreadBox, "BOTTOMLEFT", 6, -10)
  view.Reply:SetPoint("RIGHT", view.SendButton, "LEFT", -8, 0)
  view.Reply:SetMaxBytes(256)
  view.Reply:SetScript("OnEnterPressed", SendReply)

  view:SetScript("OnShow", function()
    Inbox.viewing = true
    UpdateList()
    ShowThread()
    if Inbox.openThread then Inbox.MarkRead(Inbox.openThread) end
  end)
  view:SetScript("OnHide", function()
    Inbox.viewing = false
    view.Reply:ClearFocus()
  end)

  ZR.On("InboxChanged", function(name)
    if not view:IsShown() then return end
    if name and name == Inbox.openThread then
      Inbox.MarkRead(name)
      ShowThread()
    end
    UpdateList()
  end)
  view:Hide()
  return view
end
