-- The AME tab on the game's auction house window (only without Auctionator, whose Shopping tab AME uses instead):
-- your shopping lists, Search all (each item in turn, AHSearch), what each still needs and its cheapest listing, and
-- buying from the listings with the game's own purchase (a click to price it, a click to buy).
-- It's a display mode of the game's frame, like Buy, Sell and Auctions: those are left as they are.
local _, ns = ...
local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local T = {}
ns.AHShopping = T

T.ROWS = 12
T.LISTINGS = 5

local function shopping()
  return ns.AME.shopping
end

local function name(id)
  return ns.ItemCache.Name(id) or ("item:" .. tostring(id))
end

local function money(c)
  return c and W.Money(math.floor(c + 0.5)) or W.NONE
end

-- the list on screen: one of yours, or a recipe's reagents (Search AH from the profession window)
function T:Items()
  if self.temp then
    return self.temp.items, self.temp.name
  end
  local l = shopping():Lists()[self.list or 1]
  return l and l.items or {}, l and l.name
end

-- Pure: the tab's rows for a list: Shopping.Progress's rows, each with its cheapest listing and how many are on sale
-- at or under its top price (from AHSearch's results)
function T.Rows(items, holdings, market, results)
  local rows, totals = ns.Shopping.Progress(items, holdings, market)
  local left = 0
  for _, r in ipairs(rows) do
    local book = results[r.itemID]
    local first = book and book.rows[1]
    r.cheapest = first and first.price
    r.searched = book ~= nil
    if book and r.max then
      local n = 0
      for _, l in ipairs(book.rows) do
        if l.price <= r.max then
          n = n + l.qty
        end
      end
      r.underTop = n
    end
    if r.missing > 0 and r.cheapest then
      -- what the rest costs at the cheapest listings (climbing the book)
      local need, cost = r.missing, 0
      for _, l in ipairs(book.rows) do
        local take = math.min(need, l.qty)
        cost, need = cost + take * l.price, need - take
        if need <= 0 then
          break
        end
      end
      r.buyCost = cost
      left = left + cost
    end
  end
  totals.left = left
  return rows, totals
end

---------------------------------------------------------------------------------------------------------------------
-- the panel

local function cell(parent, width, justify)
  local fs = W.Text(parent, "GameFontHighlightSmall", justify or "RIGHT")
  fs:SetWidth(width)
  fs:SetWordWrap(false)
  return fs
end

function T:Create(ah)
  local p = CreateFrame("Frame", nil, ah, "BackdropTemplate")
  W.Skin(p, W.COLORS.bg) -- the main window's discreet border
  p:SetPoint("TOPLEFT", ah, "TOPLEFT", 8, -60)
  p:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -8, 28)
  p:Hide()

  -- the lists
  p.lists = {}
  local side = CreateFrame("Frame", nil, p)
  side:SetPoint("TOPLEFT", 8, -8)
  side:SetPoint("BOTTOMLEFT", 8, 8)
  side:SetWidth(190)
  p.side = side
  local head = W.Text(side, "GameFontNormalSmall")
  head:SetPoint("TOPLEFT", 0, 0)
  head:SetText(L["Shopping lists"])

  -- the table
  local main = CreateFrame("Frame", nil, p)
  main:SetPoint("TOPLEFT", side, "TOPRIGHT", 10, 0)
  main:SetPoint("BOTTOMRIGHT", -8, 8)
  p.main = main
  p.title = W.Text(main, "GameFontNormal")
  p.title:SetPoint("TOPLEFT", 0, 0)
  p.status = W.Text(main, "GameFontDisableSmall", "RIGHT")
  p.status:SetPoint("TOPRIGHT", -110, -2)
  p.searchAll = W.Button(main, L["Search all"], 100, 20, function()
    T:SearchAll()
  end)
  p.searchAll:SetPoint("TOPRIGHT", 0, 2)
  local header = CreateFrame("Frame", nil, main)
  header:SetPoint("TOPLEFT", 0, -24)
  header:SetPoint("RIGHT", 0, 0)
  header:SetHeight(16)
  local cols = {
    { L["need"], 50 },
    { L["have"], 50 },
    { L["cheapest"], 90 },
    { L["at or under top"], 100 },
    { L["vs market"], 70 },
  }
  local x = 0
  for k = #cols, 1, -1 do
    local fs = cell(header, cols[k][2])
    fs:SetPoint("RIGHT", -x, 0)
    fs:SetText(W.Dim(cols[k][1]))
    x = x + cols[k][2] + 8
  end
  p.rows = {}
  for i = 1, T.ROWS do
    local r = CreateFrame("Button", nil, main)
    r:SetHeight(18)
    r:SetPoint("TOPLEFT", 0, -42 - (i - 1) * 18)
    r:SetPoint("RIGHT", 0, 0)
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints()
    W.Fill(r.sel, W.COLORS.rowSelected)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    W.Fill(r.hl, W.COLORS.rowHover)
    r.name = W.Text(r, "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", 4, 0)
    r.name:SetPoint("RIGHT", -(x + 4), 0)
    r.name:SetWordWrap(false)
    r.cells = {}
    local cx = 0
    for k = #cols, 1, -1 do
      local fs = cell(r, cols[k][2])
      fs:SetPoint("RIGHT", -cx, 0)
      r.cells[k] = fs
      cx = cx + cols[k][2] + 8
    end
    r:SetScript("OnClick", function(self)
      T.selected = self.itemID
      T:Render()
    end)
    r:Hide() -- until Render fills it
    p.rows[i] = r
  end

  -- the selected item's listings, and buying
  local detail = CreateFrame("Frame", nil, main)
  detail:SetPoint("BOTTOMLEFT", 0, 0)
  detail:SetPoint("RIGHT", 0, 0)
  detail:SetHeight(T.LISTINGS * 16 + 52)
  detail:Hide()
  p.detail = detail
  p.detailTitle = W.Text(detail, "GameFontNormalSmall")
  p.detailTitle:SetPoint("TOPLEFT", 0, 0)
  p.listings = {}
  for i = 1, T.LISTINGS do
    local l = CreateFrame("Frame", nil, detail)
    l:SetHeight(16)
    l:SetPoint("TOPLEFT", 0, -16 - (i - 1) * 16)
    l:SetPoint("RIGHT", 0, 0)
    l.price = cell(l, 110)
    l.price:SetPoint("LEFT", 0, 0)
    l.qty = cell(l, 70)
    l.qty:SetPoint("LEFT", l.price, "RIGHT", 8, 0)
    l.buy = W.Button(l, L["Buy"], 50, 16)
    l.buy:SetPoint("LEFT", l.qty, "RIGHT", 12, 0)
    p.listings[i] = l
  end
  local buyLabel = W.Text(detail, "GameFontDisableSmall")
  buyLabel:SetPoint("BOTTOMLEFT", 0, 6)
  buyLabel:SetText(L["Buy"])
  p.qty = W.Input(detail, { numeric = true, width = 50 })
  p.qty:SetPoint("LEFT", buyLabel, "RIGHT", 6, 0)
  p.buyText = W.Text(detail, "GameFontHighlightSmall")
  p.buyText:SetPoint("LEFT", p.qty, "RIGHT", 8, 0)
  p.buy = W.Button(detail, L["Buy"], 90, 20, function()
    local pending = ns.AHSearch.pending
    if pending and not pending.sent then
      ns.AHSearch:Confirm()
    else
      ns.AHSearch:Buy(T.selected, math.max(1, tonumber(p.qty:GetText()) or 1))
    end
  end)
  p.buy:SetPoint("BOTTOMRIGHT", 0, 2)
  p.note = W.Text(detail, "GameFontDisableSmall")
  p.note:SetPoint("RIGHT", p.buy, "LEFT", -10, 0)

  self.panel = p
  return p
end

function T:RenderLists()
  local p = self.panel
  local entries = {}
  if self.temp then
    entries[#entries + 1] = { name = self.temp.name, temp = true }
  end
  for i, l in ipairs(shopping():Lists()) do
    entries[#entries + 1] = { name = l.name, index = i }
  end
  for i, e in ipairs(entries) do
    local b = p.lists[i]
    if not b then
      b = W.Button(p.side, "", 186, 20)
      b:SetPoint("TOPLEFT", 0, -16 - (i - 1) * 22)
      p.lists[i] = b
    end
    b:SetText(e.name)
    b:SetSelected((e.temp and self.temp ~= nil) or (not self.temp and e.index == (self.list or 1)))
    b:SetScript("OnClick", function()
      if not e.temp then
        T.temp, T.list = nil, e.index
      end
      T.selected = nil
      T:Render()
    end)
    b:Show()
  end
  for i = #entries + 1, #p.lists do
    p.lists[i]:Hide()
  end
end

function T:Render()
  local p = self.panel
  if not (p and p:IsShown()) then
    return
  end
  self:RenderLists()
  local items, title = self:Items()
  p.title:SetText(title or L["no shopping lists yet"])
  local index = ns.AME:FactionIndex()
  local rows, totals = T.Rows(items, AME_DB.holdings, index and index.items, ns.AHSearch.results)
  self.rowsShown = rows
  local S = ns.AHSearch
  if S:Busy() then
    p.status:SetText(L["searching %d of %d"]:format(math.min(S.done + 1, S.total), S.total))
  else
    p.status:SetText(W.Dim(L["left to buy"] .. " ") .. money(totals.left))
  end
  for i, r in ipairs(p.rows) do
    local row = rows[i]
    r.itemID = row and row.itemID
    if row then
      r.name:SetText(name(row.itemID) .. (row.missing == 0 and W.Dim("  " .. L["(enough)"]) or ""))
      r.cells[1]:SetText(W.Count(row.need))
      r.cells[2]:SetText(W.Count(row.held))
      r.cells[3]:SetText(row.cheapest and money(row.cheapest) or W.Dim(row.searched and L["none"] or "·"))
      r.cells[4]:SetText(row.underTop and W.Count(row.underTop) or W.Dim("·"))
      r.cells[5]:SetText(row.cheapest and row.market and W.Percent(row.cheapest / row.market - 1, 0) or W.Dim("·"))
      r.sel:SetShown(row.itemID == self.selected)
      r:Show()
    else
      r:Hide()
    end
  end
  self:RenderDetail()
end

function T:RenderDetail()
  local p = self.panel
  local key = self.selected
  local book = key and ns.AHSearch.results[key]
  p.detail:SetShown(key ~= nil)
  if not key then
    return
  end
  p.detailTitle:SetText(name(key) .. W.Dim("  ·  " .. L["cheapest first"]))
  for i, l in ipairs(p.listings) do
    local row = book and book.rows[i]
    if row then
      l.price:SetText(money(row.price))
      l.qty:SetText(W.Count(row.qty))
      l.buy:SetShown(not book.commodity)
      l.buy:SetScript("OnClick", function()
        ns.AHSearch:Buy(key, row.qty, row)
      end)
      l:Show()
    else
      l:Hide()
    end
  end
  local pending = ns.AHSearch.pending
  local commodity = book and book.commodity
  p.qty:SetShown(commodity or false)
  if pending and pending.key == key and not pending.sent then
    p.buy:SetText(L["Confirm"])
    p.buyText:SetText(
      pending.total and (L["%s for %s"]:format(W.Count(pending.qty), money(pending.total))) or L["asking the price..."]
    )
    p.note:SetText(W.Dim(L["click Confirm to buy"]))
  else
    p.buy:SetText(L["Buy"])
    local missing
    for _, r in ipairs(self.rowsShown or {}) do
      if r.itemID == key then
        missing = r.missing
      end
    end
    if commodity and p.qty:GetText() == "" and missing and missing > 0 then
      p.qty:SetText(tostring(missing))
    end
    p.buyText:SetText("")
    local last = ns.AHSearch.last
    p.note:SetText(
      last and last.key == key and (last.ok and L["bought"] or W.Color("bad", L["the purchase failed"])) or ""
    )
  end
  p.buy:SetShown(commodity or (pending and pending.key == key and not pending.sent) or false)
end

function T:SearchAll()
  local keys = {}
  for _, r in ipairs(self.rowsShown or {}) do
    if r.missing > 0 then
      keys[#keys + 1] = r.itemID
    end
  end
  ns.AHSearch:Start(keys, function()
    T:Render()
  end)
  self:Render()
end

-- Search AH from the profession window: the recipe's item and reagents as a list of their own, searched right away
function T:ShowKeys(keys, title)
  local items = {}
  for _, k in ipairs(keys) do
    items[k] = { need = 1 }
  end
  self.temp = { name = title or L["Search"], items = items }
  self.selected = nil
  self:Open()
  ns.AHSearch:Start(keys, function()
    T:Render()
  end)
end

function UI:SearchItems(keys, title)
  if not T.tab then
    return ns.AME:SearchAuctionHouse(keys[1])
  end
  T:ShowKeys(keys, title)
end

function T:Open()
  local ah = _G.AuctionHouseFrame
  if ah and self.mode and ah.SetDisplayMode then
    ah:SetDisplayMode(self.mode)
  end
  self:Render()
end

-- the tab, added to the game's auction house window once (without Auctionator)
function T:Attach()
  local ah = _G.AuctionHouseFrame
  local modes = _G.AuctionHouseFrameDisplayMode
  if self.attached or not (ah and modes and rawget(ah, "Tabs")) or _G.Auctionator then
    return
  end
  self.attached = true -- once, whatever happens below: never a second panel or tab
  local panel = self:Create(ah)
  rawset(ah, "AMEShopping", panel)
  self.mode = { "AMEShopping" }
  modes.AMEShopping = self.mode
  local last = ah.Tabs[#ah.Tabs]
  local ok, tab = pcall(CreateFrame, "Button", "AuctionHouseFrameAMETab", ah, "AuctionHouseFrameDisplayModeTabTemplate")
  if not ok or not tab then
    tab = W.Button(ah, "AME", 80, 24, function()
      T:Open()
    end)
  end
  self.tab = tab
  tab.displayMode = self.mode
  tab:SetText(L["Shopping"])
  tab:SetPoint("LEFT", last, "RIGHT", -15, 0)
  -- the game's tab template puts itself in the frame's Tabs already (a second entry anchors the tab to itself)
  local index
  for i, t in ipairs(ah.Tabs) do
    if t == tab then
      index = i
    end
  end
  if not index then
    ah.Tabs[#ah.Tabs + 1] = tab
    index = #ah.Tabs
  end
  local setNum = _G.PanelTemplates_SetNumTabs
  if setNum then
    pcall(setNum, ah, #ah.Tabs)
  end
  if rawget(ah, "tabsForDisplayMode") then
    ah.tabsForDisplayMode[self.mode] = index
  end
  -- the window's title for the tab, as the game's own tabs have theirs
  if ah.SetDisplayMode and hooksecurefunc then
    hooksecurefunc(ah, "SetDisplayMode", function(frame, mode)
      if mode == T.mode and frame.SetTitle then
        frame:SetTitle(L["Shopping"])
      end
    end)
  end
  panel:HookScript("OnShow", function()
    T:Render()
  end)
end
