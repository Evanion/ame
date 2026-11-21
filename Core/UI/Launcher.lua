-- The minimap / broker button, and AME's page in the game's Options > AddOns: a short intro and a button to AME's
-- own Settings tab, where every setting lives (one place to keep them).
local ADDON, ns = ...
local L = ns.L

local W = ns.Widgets

local Launcher = {}
ns.Launcher = Launcher

local TITLE = W.Color("brand", "Azeroth") .. " Mercantile Exchange"

function Launcher:Init()
  self:RegisterOptionsPage()
  self:CreateLauncher()
  self:CreateNoticeFeed()
end

function Launcher:RegisterOptionsPage()
  local page = CreateFrame("Frame")
  page.name = "Azeroth Mercantile Exchange"
  local title = W.Text(page, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(TITLE)
  local intro = W.Text(page, "GameFontHighlight")
  intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  intro:SetWidth(560)
  intro:SetJustifyH("LEFT")
  intro:SetText(
    L["Records auction house prices from every scan and search you run (native APIs; works with any scanning addon), per realm and auction house."]
      .. "\n\n"
      .. L["All of AME's settings are in its own window: %s, Settings tab."]:format(W.Color("brand", "/ame"))
  )
  local open = W.Button(page, L["Open AME settings"], 200, 24, function()
    -- close the game's options first (both the current and the older options window)
    local panel = SettingsPanel or InterfaceOptionsFrame
    if panel and panel:IsShown() then
      pcall(HideUIPanel, panel)
    end
    ns.Settings:Open()
  end)
  open:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)
  self.page = page

  local Blizzard = _G.Settings -- the game's options API (not ns.Settings)
  if Blizzard and Blizzard.RegisterCanvasLayoutCategory and Blizzard.RegisterAddOnCategory then
    Blizzard.RegisterAddOnCategory(Blizzard.RegisterCanvasLayoutCategory(page, page.name))
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(page)
  end
end

function Launcher:SetMinimap(show)
  AME_DB.settings.minimap.hide = not show
  local icon = LibStub("LibDBIcon-1.0", true)
  if icon then
    if show then
      icon:Show(ADDON)
    else
      icon:Hide(ADDON)
    end
  end
end

function Launcher:HasMinimapLibrary()
  return LibStub("LibDBIcon-1.0", true) ~= nil
end

-- LibDataBroker launcher (+ LibDBIcon minimap button when that library is available)
function Launcher:CreateLauncher()
  local LDB = LibStub("LibDataBroker-1.1", true)
  if not LDB then
    return
  end
  local launcher = LDB:NewDataObject(ADDON, {
    type = "launcher",
    label = "AME",
    icon = ns.ICON,
    OnClick = function(_, button)
      if button == "RightButton" then
        ns.Settings:Open()
      else
        ns.UI:Toggle()
      end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine(TITLE)
      tt:AddLine(ns.ShardLabel(ns.AME:CurrentShard()), 0.7, 0.7, 0.7)
      local last = AME_DB.stats.lastFull
      if last then
        W.TipPair(tt, L["Last full scan"], date("%b %d %H:%M", last.at))
      end
      local index = ns.AME.index
      if index then
        W.TipPair(tt, L["Items tracked"], tostring(index.count))
        local hidden = ns.AME.watch and ns.AME.watch:Hidden() or {}
        local top = ns.MarketIndex.Rank(index, "score", function(s)
          return s.signal == "buy" and not hidden[s.itemID]
        end)
        if #top > 0 then
          tt:AddLine(" ")
          tt:AddLine(L["Top buy signals"])
          for i = 1, math.min(3, #top) do
            local s = top[i]
            local name = W.ItemInfo(s.itemID) or ("item:" .. s.itemID)
            W.TipPair(tt, name, W.Money(s.market) .. "  " .. W.Percent(s.change7))
          end
        end
      end
      tt:AddLine(" ")
      tt:AddLine(W.Dim(L["Left-click: window   Right-click: settings"]))
    end,
  })
  local icon = LibStub("LibDBIcon-1.0", true)
  if icon and launcher then
    icon:Register(ADDON, launcher, AME_DB.settings.minimap)
  end
end

-- Notifications on info bars (Titan Panel, ChocolateBar, Bazooka...): a LibDataBroker data source, "AME
-- Notifications", whose text says how many notices you haven't seen ("2 new"; nothing new: no text, just the bell).
-- Hover: the newest few. Click: AME's window with the notification center open.
Launcher.FEED = ADDON .. "_Notifications"
Launcher.FEED_TIP = 5

function Launcher.FeedText(unread)
  return unread > 0 and W.Color("bad", L["%d new"]:format(unread)) or ""
end

function Launcher:CreateNoticeFeed()
  local LDB = LibStub("LibDataBroker-1.1", true)
  local notices = ns.AME and ns.AME.notices
  if not (LDB and notices) then
    return
  end
  local feed = LDB:NewDataObject(Launcher.FEED, {
    type = "data source",
    label = L["AME notifications"],
    text = "",
    icon = "Interface\\Icons\\INV_Misc_Bell_01",
    OnClick = function()
      ns.UI:Create()
      ns.UI.frame:Show()
      if not (ns.UI.noticePanel and ns.UI.noticePanel:IsShown()) then
        ns.UI:ToggleNotices()
      end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine(TITLE)
      local list, now = notices:List(), GetServerTime()
      if #list == 0 then
        tt:AddLine(L["No notifications."], 0.7, 0.7, 0.7)
      end
      for i = 1, math.min(Launcher.FEED_TIP, #list) do
        local e = list[i]
        local line = ns.UI.NoticeLine(e)
        tt:AddDoubleLine(line, W.Ago(e.at, now), 1, 1, 1, 0.6, 0.6, 0.6)
      end
      if #list > Launcher.FEED_TIP then
        tt:AddLine(L["+ %d older"]:format(#list - Launcher.FEED_TIP), 0.6, 0.6, 0.6)
      end
      tt:AddLine(" ")
      tt:AddLine(W.Dim(L["Click: open the notifications"]))
    end,
  })
  if not feed then
    return
  end
  self.feed = feed
  local function update()
    feed.text = Launcher.FeedText(notices:Unread())
  end
  notices:OnChange(update)
  update()
end
