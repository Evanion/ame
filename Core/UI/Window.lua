-- Main window shell: frame, header, tabs, which auction house is viewed, and theme. The tabs live in ItemView,
-- MarketView, ArbitrageView, PortfolioView, Watchlists, SyncView and SettingsView.
local _, ns = ...
local L = ns.L

local W = ns.Widgets

local UI = {}
ns.UI = UI

-- the average period used everywhere (screener column, item card, tooltips): Settings, default 7 days
UI.WIDTH, UI.HEIGHT = 980, 500 -- the main window; content is inset 10 px on each side
UI.COLUMN2 = 490 -- x of the second column on the Sync and Settings tabs

function UI.AvgDays()
  return ns.Settings:Get("tooltipAvgDays") or 7
end

---------------------------------------------------------------------------------------------------------------------
-- window shell

local contentArea

function UI:Create()
  if self.frame then
    return self.frame
  end
  local f = CreateFrame("Frame", "AMEMainWindow", UIParent, "BackdropTemplate")
  self.frame = f
  f:SetSize(UI.WIDTH, UI.HEIGHT)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  W.Skin(f)
  f:Hide()
  tinsert(UISpecialFrames, "AMEMainWindow") -- Escape closes

  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(ns.ICON)
  logo:SetSize(18, 18)
  logo:SetPoint("TOPLEFT", 10, -8)
  local title = W.Text(f, "GameFontNormal")
  title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
  self.title = title
  self.shardText = W.Text(f, "GameFontDisableSmall")
  self.shardText:SetPoint("LEFT", title, "RIGHT", 10, 0)
  local houses = { { "Horde", L["Horde AH"] }, { "Alliance", L["Alliance AH"] }, { "Neutral", L["Goblin AH"] } }
  self.viewSelect = W.Dropdown(f, 110, houses, function(value)
    UI.viewHouse = value
    UI:ViewChanged()
  end, { neutral = true })
  self.viewSelect:SetPoint("LEFT", self.shardText, "RIGHT", 8, 0)

  local close = W.CloseButton(f)
  close:SetPoint("TOPRIGHT", -6, -7)
  self.closeButton = close

  self.tabs = {}
  local function tab(name, label, x)
    local b = W.Button(f, label, 66, 20, function()
      UI:ShowTab(name)
    end)
    b:SetPoint("TOPRIGHT", -(34 + x), -8)
    self.tabs[name] = b
  end
  tab("market", L["Market"], 420)
  tab("arbitrage", L["Arbitrage"], 350)
  tab("portfolio", L["Portfolio"], 280)
  tab("item", L["Item"], 210)
  tab("sync", L["Sync"], 140)
  tab("settings", L["Settings"], 70)
  tab("guide", L["Guide"], 0)

  self.views = {
    item = self:CreateItemView(f),
    market = self:CreateMarketView(f),
    guide = ns.Help.CreateGuide(f, contentArea),
    sync = self:CreateSyncView(f, contentArea),
    arbitrage = self:CreateArbitrageView(f, contentArea),
    portfolio = self:CreatePortfolioView(f, contentArea),
    settings = self:CreateSettingsView(f, contentArea),
  }
  local footer = W.Text(f, "GameFontDisableSmall", "RIGHT")
  footer:SetPoint("BOTTOMRIGHT", -12, 7)
  footer:SetText(
    "Azeroth Mercantile Exchange " .. L["%s  -  created by Tyken Evanion  -  PvP Horde, WoW Forever"]:format(ns.VERSION)
  )
  footer:SetAlpha(0.7)
  self.footer = footer

  f:SetScript("OnShow", function()
    UI:ViewChanged()
    UI:ApplyTheme()
  end)
  self:RefreshViewOptions()
  self:ApplyTheme()
  return f
end

-- Which auction house the Market and Item tabs show: the one you're at, unless picked in the title bar.
function UI:ViewHouse()
  return self.viewHouse or ns.AME:CurrentHouse()
end

function UI:ViewShard()
  return ns.ShardKey(ns.AME:MarketRealmName(), self:ViewHouse())
end

-- market index for the viewed house: nil + "loading" (built in the background, refreshes when ready) or "empty"
function UI:ViewIndex()
  local AME, shard = ns.AME, self:ViewShard()
  local cached = AME:CachedIndex(shard)
  if cached then
    return cached
  end
  if AME:HistoryLoaded() and not AME:HasData(shard) then
    return nil, "empty"
  end
  if AME:HistoryLoaded() and self.viewLoading ~= shard then
    self.viewLoading = shard
    AME:IndexFor(shard, function()
      self.viewLoading = nil
      self:RefreshMarket(true)
    end)
  end
  return nil, "loading"
end

-- The title-bar selector lists only auction houses with history (plus the one you're at); with just one it's
-- plain text.
function UI:RefreshViewOptions()
  if not self.frame then
    return
  end
  local AME = ns.AME
  local realm, current = AME:MarketRealmName(), AME:CurrentHouse()
  local options = {}
  for _, house in ipairs({ "Horde", "Alliance", "Neutral" }) do
    local hasData = AME:HasData(ns.ShardKey(realm, house))
    if house == current or hasData then
      options[#options + 1] = { house, ns.HOUSE_LABEL[house] }
    end
  end
  if self.viewHouse then
    local listed = false
    for _, o in ipairs(options) do
      listed = listed or o[1] == self.viewHouse
    end
    if not listed then
      self.viewHouse = nil
    end
  end
  self.viewSelect:SetOptions(options)
  self.viewSelect:SetValue(self:ViewHouse())
  local several = #options > 1
  self.viewSelect:SetShown(several)
  self.shardText:SetText(several and realm or ns.ShardLabel(self:ViewShard()))
end

function UI:ViewChanged()
  if not self.frame then
    return
  end
  self:RefreshViewOptions()
  self:ApplyTheme()
  self.list = nil
  self:RefreshMarket(true)
  if self.current == "item" and self.itemID then
    self:ShowItem(self.itemID)
  end
end

-- Faction colours for the chrome, from the auction house being viewed (by default the one in use, or the character's
-- faction before the first visit).
function UI:ApplyTheme()
  if not self.frame then
    return
  end
  local preferred = ns.Settings:Get("theme")
  W.SetTheme(preferred ~= "auto" and preferred or self:ViewHouse())
  local a = W.COLORS.accent
  self.title:SetText(("|c%sAzeroth|r Mercantile Exchange"):format(W.Hex(a)))
  for n, b in pairs(self.tabs) do
    b:SetSelected(n == self.current)
  end
  if self.chartHolder then
    self.chartHolder:SetBackdropBorderColor(a[1], a[2], a[3], 0.22)
    W.TintInnerGlow(self.chartHolder)
  end
  local iv = self.itemView
  if iv then
    for _, b in ipairs(iv.rangeButtons) do
      b:SetSelected(b.key == self.rangeKey)
    end
  end
  local mv = self.marketView
  if mv then
    for _, line in ipairs(mv.side.lines) do
      W.Fill(line.sel, W.COLORS.rowSelected)
    end
    self:RenderMarket()
  end
end

function UI:ShowTab(name)
  self:Create()
  for n, v in pairs(self.views) do
    v:SetShown(n == name)
    self.tabs[n]:SetSelected(n == name)
  end
  self.current = name
  if name == "market" then
    self:RefreshMarket()
  end
end

function UI:Toggle(itemID)
  self:Create()
  if itemID then
    self.frame:Show()
    self:ShowItem(itemID)
  elseif self.frame:IsShown() then
    self.frame:Hide()
  else
    self.frame:Show()
    self:ShowTab(self.current or "market")
  end
end

function contentArea(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetPoint("TOPLEFT", 10, -36)
  v:SetPoint("BOTTOMRIGHT", -10, 24) -- room for the footer
  v:Hide()
  return v
end
UI.ContentArea = contentArea
