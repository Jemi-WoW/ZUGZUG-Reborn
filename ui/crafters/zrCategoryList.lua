local _, ZR = ...
local UI = ZR.UI

local BG_ATLAS = "auctionhouse-background-categories"

-- Same art per depth as the Auction House category buttons.
local STYLE = {
  { normal = "auctionhouse-nav-button", nw = 136, nx = -2, sel = "auctionhouse-nav-button-select",
    hi = "auctionhouse-nav-button-highlight", w = 132, h = 21, point = "LEFT", x = 0, y = 0, text = 8, font = "GameFontNormalSmall" },
  { normal = "auctionhouse-nav-button-secondary", nw = 133, nx = 1, sel = "auctionhouse-nav-button-secondary-select",
    hi = "auctionhouse-nav-button-secondary-highlight", w = 122, h = 21, point = "TOPLEFT", x = 10, y = 0, text = 18, font = "GameFontHighlightSmall" },
  { sel = "auctionhouse-ui-row-select", hi = "auctionhouse-ui-row-highlight",
    w = 116, h = 18, point = "TOPRIGHT", x = 0, y = -2, text = 26, font = "GameFontHighlightSmall", lines = true },
}

local function Place(tex, st, atlas)
  tex:SetAtlas(atlas, false)
  tex:SetSize(st.w, st.h)
  tex:ClearAllPoints()
  tex:SetPoint(st.point, st.x, st.y)
end

local function InitButton(b, data)
  if not b.Label then
    b:SetSize(132, 21)
    b.Lines = b:CreateTexture(nil, "BACKGROUND")
    b.Lines:SetAtlas("auctionhouse-nav-button-tertiary-filterline", true)
    b.Lines:SetPoint("LEFT", 18, 3)
    b.Normal = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.Highlight = b:CreateTexture(nil, "BORDER")
    b.Highlight:Hide()
    b.Selected = b:CreateTexture(nil, "ARTWORK")
    b.Selected:SetBlendMode("ADD")
    b.Label = b:CreateFontString(nil, "OVERLAY")
    b.Label:SetJustifyH("LEFT")
    b.Label:SetWordWrap(false)
    b.Label:SetPoint("RIGHT", -4, 0)
    b:SetScript("OnEnter", function(self) self.Highlight:Show() end)
    b:SetScript("OnLeave", function(self) self.Highlight:Hide() end)
    b:SetScript("OnClick", function(self)
      PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
      self.list:Click(self.node)
    end)
  end
  local st = STYLE[math.min(data.depth, 3)]
  b.list, b.node = data.list, data.node
  if st.normal then
    b.Normal:SetAtlas(st.normal, false)
    b.Normal:SetSize(st.nw, 32)
    b.Normal:ClearAllPoints()
    b.Normal:SetPoint("TOPLEFT", st.nx, 0)
    b.Normal:SetAlpha(1)
  else
    b.Normal:SetAlpha(0)
  end
  Place(b.Selected, st, st.sel)
  Place(b.Highlight, st, st.hi)
  b.Selected:SetShown(data.selected)
  b.Lines:SetShown(st.lines == true)
  b.Label:SetFontObject(st.font)
  b.Label:SetPoint("LEFT", st.text, 0)
  b.Label:SetText(data.node.name)
end

-- Shows the bottom of the background art, cropped to the list height.
local function FitBackground(bg, height)
  local a = C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BG_ATLAS)
  local file = a and (a.file or a.filename)
  if not file or not a.height or a.height <= 0 then
    bg:Hide()
    return
  end
  local frac = math.min(1, height / a.height)
  bg:SetTexture(file)
  bg:SetTexCoord(a.leftTexCoord, a.rightTexCoord,
    a.bottomTexCoord - (a.bottomTexCoord - a.topTexCoord) * frac, a.bottomTexCoord)
  bg:SetSize(a.width, a.height * frac)
end

local function Flatten(list)
  local open = {}
  local n = list.selected
  while n do
    open[n] = true
    n = n.parent
  end
  local out = {}
  local function Add(nodes, depth)
    for _, node in ipairs(nodes) do
      out[#out + 1] = { list = list, node = node, depth = depth, selected = node == list.selected }
      if open[node] and #node.children > 0 then Add(node.children, depth + 1) end
    end
  end
  Add(list.roots, 1)
  return out
end

function UI.CreateCategoryList(parent, onSelect)
  local list = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
  list:SetWidth(168)

  list.Background = list:CreateTexture(nil, "BACKGROUND", nil, 1)
  list.Background:SetPoint("BOTTOMLEFT", 3, 3)
  list:SetScript("OnSizeChanged", function(self, _, h) FitBackground(self.Background, h - 6) end)

  list.ScrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
  list.ScrollBox:SetPoint("TOPLEFT", 3, -6)
  list.ScrollBox:SetPoint("BOTTOMRIGHT", -25, 2)
  list.ScrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
  list.ScrollBar:SetPoint("TOPLEFT", list.ScrollBox, "TOPRIGHT", 6, 0)
  list.ScrollBar:SetPoint("BOTTOMLEFT", list.ScrollBox, "BOTTOMRIGHT", 6, 4)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(21)
  view:SetElementInitializer("Button", InitButton)
  ScrollUtil.InitScrollBoxListWithScrollBar(list.ScrollBox, list.ScrollBar, view)

  list.roots = ZR.ItemCategories.Roots()

  function list:Refresh()
    self.ScrollBox:SetDataProvider(CreateDataProvider(Flatten(self)), ScrollBoxConstants.RetainScrollPosition)
  end

  -- Clicking the open category closes it, like the Auction House.
  function list:Click(node)
    if node == self.selected then node = node.parent end
    self.selected = node
    self:Refresh()
    onSelect(node)
  end

  list:Refresh()
  return list
end
