-- The notification center: a bell left of the tabs, with how many notices you haven't seen, and a panel under it
-- listing them (Core/Notices.lua) - alerts that fired, players asking to share. Clicking one goes to it: an alert
-- opens its item, a request opens Settings, Sharing. Opening the panel marks everything read.
local _, ns = ...
local L = ns.L

local UI = ns.UI
local W = ns.Widgets

local BELL = "Interface\\Icons\\INV_Misc_Bell_01"
local ROWS, ROW_H, WIDTH = 10, 34, 360

local function notices()
  return ns.AME and ns.AME.notices
end

-- what a notice says, in one line, and its icon
function UI.NoticeLine(e)
  if e.kind == "alert" then
    local link = e.itemID and ns.ItemCache.Link(e.itemID)
    local icon = e.itemID and select(4, W.ItemInfo(e.itemID))
    return (link or ("item:" .. tostring(e.itemID))) .. " " .. (e.text or ""), icon or BELL
  elseif e.kind == "request" then
    return L["%s wants to share auction prices with you"]:format(e.who or "?"), "Interface\\Icons\\INV_Letter_15"
  end
  return e.text or "", BELL
end

function UI:CreateNotices(f)
  local bell = CreateFrame("Button", nil, f, "BackdropTemplate")
  bell:SetSize(24, 20)
  W.Skin(bell, W.COLORS.panel)
  bell.icon = bell:CreateTexture(nil, "ARTWORK")
  bell.icon:SetSize(16, 16)
  bell.icon:SetPoint("CENTER")
  bell.icon:SetTexture(BELL)
  bell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- unread count: a small filled badge on the corner
  bell.badge = CreateFrame("Frame", nil, bell, "BackdropTemplate")
  bell.badge:SetSize(14, 12)
  bell.badge:SetPoint("TOPRIGHT", 6, 5)
  bell.badge:SetFrameLevel(bell:GetFrameLevel() + 2)
  W.Skin(bell.badge, { 0.8, 0.2, 0.15, 1 }, { 0.8, 0.2, 0.15, 1 })
  bell.count = W.Text(bell.badge, "GameFontHighlightSmall", "CENTER")
  bell.count:SetPoint("CENTER", 0, 0)
  bell:SetScript("OnEnter", function(self)
    local c = W.COLORS.panelHover
    self:SetBackdropColor(c[1], c[2], c[3], c[4])
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(L["Notifications"], 1, 1, 1)
    GameTooltip:AddLine(
      L["Alerts that fired and players asking to share, kept here after chat scrolls on."],
      nil,
      nil,
      nil,
      true
    )
    GameTooltip:Show()
  end)
  bell:SetScript("OnLeave", function(self)
    local c = W.COLORS.panel
    self:SetBackdropColor(c[1], c[2], c[3], c[4])
    GameTooltip:Hide()
  end)
  bell:SetScript("OnClick", function()
    UI:ToggleNotices()
  end)
  self.bell = bell
  if notices() then
    notices():OnChange(function()
      UI:UpdateBell()
      if UI.noticePanel and UI.noticePanel:IsShown() then
        UI:RenderNotices()
      end
    end)
  end
  self:UpdateBell()
  return bell
end

function UI:UpdateBell()
  local bell, n = self.bell, notices()
  if not bell then
    return
  end
  local unread = n and n:Unread() or 0
  bell.badge:SetShown(unread > 0)
  bell.count:SetText(unread > 9 and "9+" or tostring(unread))
  bell.badge:SetWidth(unread > 9 and 20 or 14)
  bell.icon:SetDesaturated(unread == 0)
  bell.icon:SetAlpha(unread > 0 and 1 or 0.7)
end

local function createPanel()
  local p = CreateFrame("Frame", nil, UI.bell:GetParent(), "BackdropTemplate")
  W.Skin(p, W.COLORS.bg)
  p:SetFrameStrata("DIALOG")
  p:SetWidth(WIDTH)
  p:SetPoint("TOPRIGHT", UI.bell, "BOTTOMRIGHT", 0, -4)
  p:EnableMouse(true)
  p:Hide() -- a new frame shows: the first click opens it
  local head = W.Text(p, "GameFontNormal")
  head:SetPoint("TOPLEFT", 10, -9)
  head:SetText(L["Notifications"])
  p.clear = W.Button(p, L["Clear all"], 70, 18, function()
    notices():Clear()
  end)
  p.clear:SetPoint("TOPRIGHT", -8, -6)
  p.empty = W.Text(p, "GameFontDisableSmall")
  p.empty:SetPoint("TOPLEFT", 10, -36)
  p.empty:SetPoint("RIGHT", -10, 0)
  p.empty:SetWordWrap(true)
  p.empty:SetText(L["Nothing yet. Alerts you set on an item's page show up here when they fire."])
  p.more = W.Text(p, "GameFontDisableSmall")
  p.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, p)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 4, -30 - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", -4, 0)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    W.Fill(r.hl, W.COLORS.rowHover)
    r.dot = r:CreateTexture(nil, "OVERLAY") -- unread
    r.dot:SetSize(4, 4)
    r.dot:SetPoint("LEFT", 2, 0)
    r.dot:SetColorTexture(0.9, 0.3, 0.2, 1)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", 10, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = W.Text(r, "GameFontHighlightSmall")
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 0)
    r.text:SetPoint("RIGHT", -6, 0)
    r.text:SetWordWrap(false)
    r.when = W.Text(r, "GameFontDisableSmall")
    r.when:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, 0)
    -- the whole line on hover (a long item name cuts it short); the row takes the click
    r:SetScript("OnEnter", function(self)
      if self.notice then
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(UI.NoticeLine(self.notice), 1, 1, 1, 1, true)
        GameTooltip:AddLine(self.notice.kind == "alert" and L["Click to open the item."] or L["Click to open Sharing."])
        GameTooltip:Show()
      end
    end)
    r:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self)
      UI:OpenNotice(self.notice)
    end)
    p.rows[i] = r
  end
  -- closes on a click elsewhere, like a menu
  p:SetScript("OnShow", function(self)
    pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
  end)
  p:SetScript("OnHide", function(self)
    pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
  end)
  p:SetScript("OnEvent", function(self)
    if not self:IsMouseOver() and not UI.bell:IsMouseOver() then
      self:Hide()
    end
  end)
  return p
end

function UI:ToggleNotices()
  if not notices() then
    return
  end
  self.noticePanel = self.noticePanel or createPanel()
  local p = self.noticePanel
  if p:IsShown() then
    p:Hide()
    return
  end
  W.HideMenu()
  -- what's new is marked while the panel shows (the dots), and counts as read from now on
  self.noticesSeenBefore = notices().db.readAt
  self:RenderNotices()
  p:Show()
  notices():MarkRead(GetServerTime())
end

function UI:RenderNotices()
  local p, n = self.noticePanel, notices()
  local list, now = n:List(), GetServerTime()
  local seen = self.noticesSeenBefore or n.db.readAt
  local shown = math.min(#list, ROWS)
  for i, r in ipairs(p.rows) do
    local e = list[i]
    r.notice = e
    if e then
      local text, icon = UI.NoticeLine(e)
      r.text:SetText(text)
      r.icon:SetTexture(icon)
      r.when:SetText(W.Ago(e.at, now))
      r.dot:SetShown(e.at > seen)
      r:Show()
    else
      r:Hide()
    end
  end
  p.empty:SetShown(#list == 0)
  p.clear:SetShown(#list > 0)
  p.more:ClearAllPoints()
  p.more:SetPoint("TOPLEFT", 10, -34 - shown * ROW_H)
  p.more:SetText(#list > ROWS and L["+ %d older"]:format(#list - ROWS) or "")
  p:SetHeight(#list == 0 and 70 or (36 + shown * ROW_H + (#list > ROWS and 16 or 4)))
end

function UI:OpenNotice(e)
  if not e then
    return
  end
  if self.noticePanel then
    self.noticePanel:Hide()
  end
  if e.kind == "alert" and e.itemID then
    self:ShowItem(e.itemID)
  elseif e.kind == "request" then
    self:ShowTab("sync")
  end
end
