-- Main window shell: frame, header, tabs, which auction house is viewed, and theme. The tabs live in ItemView,
-- MarketView, ArbitrageView, PortfolioView, Watchlists, SyncView and SettingsView.
local _, ns = ...
local L = ns.L

local W = ns.Widgets

local UI = {}
ns.UI = UI

-- the average period used everywhere (screener column, item card, tooltips): Settings, default 7 days
UI.WIDTH, UI.HEIGHT = 980, 500 -- design width the fixed-size pieces were laid out for; the window itself resizes
UI.MIN_W, UI.MIN_H = 760, 460 -- the smallest window every tab still works in
UI.COMPACT_W = 900 -- below this width tabs use their compact layout (UI.compact)
UI.FOOTER_SPACE = 90 -- width kept free for the version at the right end of the bottom row
UI.COLUMN2 = 490 -- x of the second column on the Sync and Settings tabs

function UI.AvgDays()
  return ns.Settings:Get("tooltipAvgDays") or 7
end

---------------------------------------------------------------------------------------------------------------------
-- window shell

local contentArea

-- The window is built in steps - the shell, then one tab per step, then the finishing touches - so it can be built
-- a step at a time in idle moments after login (UI:Prebuild) instead of all at once (a stutter) the first time you
-- open it. UI:Create() runs whatever is left; self.frame is only set once everything is there.
UI.BUILD_STEPS = {
  function(ui)
    ui:CreateShell()
  end,
  function(ui)
    ui.views.market = ui:CreateMarketView(ui.building)
  end,
  function(ui)
    ui.views.item = ui:CreateItemView(ui.building)
  end,
  function(ui)
    ui.views.arbitrage = ui:CreateArbitrageView(ui.building, contentArea)
  end,
  function(ui)
    ui.views.portfolio = ui:CreatePortfolioView(ui.building, contentArea)
  end,
  function(ui)
    ui.views.sync = ui:CreateSyncView(ui.building, contentArea)
  end,
  function(ui)
    ui.views.settings = ui:CreateSettingsView(ui.building, contentArea)
  end,
  function(ui)
    ui.views.guide = ns.Help.CreateGuide(ui.building, contentArea)
  end,
  function(ui)
    ui.frame = ui.building
    ui:RefreshViewOptions()
    ui:ApplyTheme()
  end,
}

-- build the next piece of the window; true once it's complete
function UI:BuildStep()
  self.built = self.built or 0
  local step = UI.BUILD_STEPS[self.built + 1]
  if step then
    self.built = self.built + 1
    step(self)
  end
  return self.built >= #UI.BUILD_STEPS
end

function UI:Create()
  while not self:BuildStep() do
  end
  return self.frame
end

-- Build the window a step at a time in the background (one step every few frames, never in combat), then load the
-- item facts the Market tab filters on. Started a few seconds after login.
function UI:Prebuild()
  local function step()
    if self.frame then
      return self:WarmItemFacts()
    end
    if InCombatLockdown and InCombatLockdown() then
      return C_Timer.After(2, step)
    end
    if self:BuildStep() then
      return self:WarmItemFacts()
    end
    C_Timer.After(0.1, step)
  end
  step()
end

-- ItemCache facts (class, name, quality) for every item in the index, a hundred per frame, so the first Market
-- refresh doesn't look them all up at once
function UI:WarmItemFacts()
  local index = ns.AME:CachedIndex(ns.AME:CurrentShard())
  if not index or self.factsWarmed == index then
    return
  end
  self.factsWarmed = index
  ns.AME.jobs:Add("item-facts", function(job)
    local n = 0
    for id in pairs(index.items) do
      ns.ItemCache.Get(id)
      n = n + 1
      if n % 100 == 0 then
        job:Checkpoint()
      end
    end
  end)
end

function UI:CreateShell()
  local f = CreateFrame("Frame", "AMEMainWindow", UIParent, "BackdropTemplate")
  self.building = f
  self.views = {}
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  local maxW, maxH = UIParent:GetWidth(), UIParent:GetHeight()
  if f.SetResizeBounds then
    f:SetResizeBounds(UI.MIN_W, UI.MIN_H, maxW, maxH)
  elseif f.SetMinResize then
    f:SetMinResize(UI.MIN_W, UI.MIN_H)
    f:SetMaxResize(maxW, maxH)
  end
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    UI:SavePlacement()
  end)
  f:SetScript("OnSizeChanged", function(_, w)
    UI:OnResize(w)
    if UI.sizing then
      UI:SavePlacement() -- while you drag the grip: even a missed mouse-up keeps the new size
    end
  end)

  -- resize grip, bottom right
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function()
    UI.sizing = true
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    UI.sizing = false
    UI:SavePlacement()
  end)
  self.grip = grip
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

  self.tabBar = W.Segmented(f, {
    { "market", L["Market"] },
    { "arbitrage", L["Arbitrage"] },
    { "portfolio", L["Portfolio"] },
    { "item", L["Item"] },
    { "sync", L["Sync"] },
    { "settings", L["Settings"] },
    { "guide", L["Guide"] },
  }, {
    minWidth = 66,
    onSelect = function(name)
      UI:ShowTab(name)
    end,
  })
  self.tabBar:SetPoint("TOPRIGHT", -34, -8) -- right-aligned: long labels push the row left

  -- the version, bottom right, on the same row as each tab's status line (credits are on the Guide tab)
  local footer = W.Text(f, "GameFontDisableSmall", "RIGHT")
  footer:SetPoint("BOTTOMRIGHT", -22, 10) -- left of the resize grip
  footer:SetText("v" .. ns.VERSION)
  footer:SetAlpha(0.7)
  self.footer = footer
  -- while a market index is rebuilt, the (older) data on screen is marked as updating
  local elapsed = 0
  f:HookScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.5 then
      return
    end
    elapsed = 0
    footer:SetText(UI:FooterText())
  end)

  f:SetScript("OnShow", function()
    UI:ApplyPlacement()
    UI:ViewChanged()
    UI:ApplyTheme()
  end)
  self:ApplyPlacement()
end

---------------------------------------------------------------------------------------------------------------------
-- size, position, docking

-- the window's status row (bottom right): a scan being read with its real progress, market data being updated,
-- and the version
function UI:FooterText()
  local ingest, busy = ns.AME.ingest, nil
  local p = ingest and ingest.reading and ingest.progress
  if p and p.total > 0 then
    busy = L["reading scan %s / %s"]:format(W.Thousands(p.done), W.Thousands(p.total))
  elseif ns.AME:IndexBusy() then
    busy = L["updating market data..."]
  end
  return (busy and (busy .. "   ") or "") .. "v" .. ns.VERSION
end

local function clamp(x, lo, hi)
  return math.max(lo, math.min(hi, x))
end

-- default size from the screen: full on big screens, compact on small ones (UIParent units, before AME's scale)
function UI:DefaultSize()
  local scale = ns.Settings:Get("windowScale") or 1
  local sw, sh = (UIParent:GetWidth() or 1365) / scale, (UIParent:GetHeight() or 768) / scale
  local w = math.min(clamp(math.floor(sw * 0.6), 900, 1100), sw)
  local h = math.min(clamp(math.floor(sh * 0.75), 520, 640), sh)
  return math.max(w, UI.MIN_W), math.max(h, UI.MIN_H)
end

-- Placement per character, saved across sessions (AME_DB.window): one size - whatever you last resized it to - and
-- two positions, with the auction house open ("ah") and without ("free").
function UI:Placements()
  AME_DB.window = AME_DB.window or {}
  local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
  local p = AME_DB.window[key] or {}
  AME_DB.window[key] = p
  if not p.w then -- older saves kept a size per position: take the one without the auction house
    local old = (p.free and p.free.w and p.free) or (p.ah and p.ah.w and p.ah)
    if old then
      p.w, p.h = old.w, old.h
    end
  end
  return p
end

function UI:PlacementMode()
  return ns.AME.ahOpen and "ah" or "free"
end

function UI:SavePlacement()
  local f = self.frame or self.building
  if not f or self.applying then
    return
  end
  local left, top = f:GetLeft(), f:GetTop()
  if not (left and top) then
    return
  end
  local p = self:Placements()
  p.w, p.h = f:GetWidth(), f:GetHeight()
  p[self:PlacementMode()] = { x = left, y = top }
  -- AME places the window itself: the client's own layout cache must not move it back at the next login
  if f.SetUserPlaced then
    f:SetUserPlaced(false)
  end
end

-- the auction house window on screen (the game's or the old one)
local function ahFrame()
  local ah = AuctionHouseFrame or AuctionFrame
  return ah and ah:IsShown() and ah or nil
end

-- is there room for a window this wide (in AME's scale) to the right of the auction house?
function UI:FitsBeside(ah, w)
  local right, screen = ah:GetRight(), UIParent:GetRight()
  if not (right and screen) then
    return false
  end
  local ui = UIParent:GetEffectiveScale()
  local mine = (self.frame or self.building):GetEffectiveScale()
  return right * ah:GetEffectiveScale() / ui + 6 + w * mine / ui <= screen
end

-- Size and position for now: beside the auction house when docking and there's room, else where you last put it
-- (separately with and without the auction house), else centred at the default size.
function UI:ApplyPlacement()
  local f = self.frame or self.building
  if not f then
    return
  end
  self.applying = true -- our own moves aren't the user's: don't save them
  f:SetScale(ns.Settings:Get("windowScale") or 1)
  local saved = self:Placements()
  local p = saved[self:PlacementMode()]
  local w, h = self:DefaultSize()
  if saved.w then
    w, h = math.max(saved.w, UI.MIN_W), math.max(saved.h, UI.MIN_H)
  end
  f:SetSize(w, h)
  f:ClearAllPoints()
  local ah = ns.AME.ahOpen and ahFrame()
  if ah and ns.Settings:Get("dockToAH") and self:FitsBeside(ah, w) then
    f:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0)
  elseif p and p.x then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
  else
    f:SetPoint("CENTER")
  end
  self.applying = false
  self:OnResize(w)
end

-- below UI.COMPACT_W the tabs use their compact layout; the title shortens to "AME"
function UI:OnResize(w)
  local compact = (w or UI.WIDTH) < UI.COMPACT_W
  if compact == self.compact then
    return
  end
  self.compact = compact
  if self.frame then
    self:ApplyTheme()
  end
  for _, view in pairs(self.views or {}) do
    if view.SetCompact then
      view:SetCompact(compact)
    end
  end
end

-- A market index was built or restored: refresh the open tab (the data on it may have been stale meanwhile).
function UI:OnIndexReady(shard)
  if not self.frame then
    return
  end
  self:WarmItemFacts()
  if not self.frame:IsShown() then
    return
  end
  self:RefreshViewOptions()
  if self.current == "market" and shard == self:ViewShard() then
    self:RefreshMarket(true)
  elseif self.current == "arbitrage" then
    self:RefreshArbitrage(true)
  elseif self.current == "portfolio" then
    self:RefreshPortfolio()
  end
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
      self.viewLoading = nil -- UI:OnIndexReady refreshes the tab
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
  W.ApplyPalette()
  local preferred = ns.Settings:Get("theme")
  W.SetTheme(preferred ~= "auto" and preferred or self:ViewHouse())
  local a = W.COLORS.accent
  if self.compact then
    self.title:SetText(("|c%sAME|r"):format(W.Hex(a)))
  else
    self.title:SetText(("|c%sAzeroth|r Mercantile Exchange"):format(W.Hex(a)))
  end
  if self.chartHolder then
    self.chartHolder:SetBackdropBorderColor(a[1], a[2], a[3], 0.22)
    W.TintInnerGlow(self.chartHolder)
  end
  local mv = self.marketView
  if mv then
    for _, line in ipairs(mv.side.lines) do
      W.Fill(line.sel, W.COLORS.rowSelected)
    end
    self:RenderMarket()
  end
end

-- the Guide tab at a term's glossary entry
function UI:ShowGuide(key)
  self:Create()
  self.frame:Show()
  self:ShowTab("guide")
  local guide = self.views.guide
  if guide and guide.ShowTerm then
    guide:ShowTerm(key)
  end
end

function UI:ShowTab(name)
  self:Create()
  for n, v in pairs(self.views) do
    v:SetShown(n == name)
  end
  self.tabBar:Select(name, true)
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
  v:SetPoint("BOTTOMRIGHT", -10, 10)
  v:Hide()
  return v
end
UI.ContentArea = contentArea
