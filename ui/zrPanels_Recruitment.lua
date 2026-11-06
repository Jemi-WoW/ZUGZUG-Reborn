local _, ZR = ...
local UI = ZR.UI

local TAB_MESSAGE, TAB_INVITE, TAB_WHISPERS = 1, 2, 3
ZR.TAB_WHISPERS = TAB_WHISPERS

local views = {}

UI.RegisterFeature({
  key = "recruitment",
  title = "Recruitment",
  icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
  officerOnly = true,
  tabs = { "Recruit Message", "Fast Invite", "Whispers" },

  tabLabel = function(index)
    if index ~= TAB_WHISPERS then return nil end
    local n = ZR.Inbox.Unread()
    return n > 0 and ("Whispers (%d)"):format(n) or "Whispers"
  end,

  build = function(frame, inset)
    views[TAB_MESSAGE] = UI.BuildRecruitMessage(frame, inset)
    views[TAB_INVITE] = UI.BuildFastInvite(frame, inset)
    views[TAB_WHISPERS] = UI.BuildWhispers(frame, inset)
  end,

  selectTab = function(index)
    for i, v in ipairs(views) do v:SetShown(i == index) end
  end,
})
