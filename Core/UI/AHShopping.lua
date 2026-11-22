-- The Shopping tab on the game's auction house window (only without Auctionator, whose Shopping tab AME uses
-- instead): a search box with filters (AHBrowse), your recent searches and shopping lists. A search shows what's for
-- sale with AME's view of each (cheapest, against the market, the signal); a list shows what each item still needs
-- (Search all searches each in turn, AHSearch). Click an item for its listings, and buy with the game's own purchase
-- (a click to price it, a click to buy).
-- It's a display mode of the game's frame, like Buy, Sell and Auctions: those are left as they are. The Selling tab
-- (AHSelling) is added next to it the same way.
local _, ns = ...
local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local T = {}
ns.AHShopping = T

T.LISTINGS = 5
T.RECENT = 6 -- recent searches kept
T.SIDE_W = 200

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
-- vendorPrice(itemID) (optional): what a vendor charges, for items a vendor sells - those are bought there (the
-- vendor panel), so they're marked, not searched, and left out of what's left to buy here
function T.Rows(items, holdings, market, results, vendorPrice)
  local rows, totals = ns.Shopping.Progress(items, holdings, market)
  local left = 0
  for _, r in ipairs(rows) do
    r.vendor = vendorPrice and vendorPrice(r.itemID) or nil
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
    if r.missing > 0 and r.cheapest and not r.vendor then
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

-- Pure: buying qty of a commodity climbs its listings, cheapest first: how many each listing gives (taken[i]),
-- what it all costs, and how many the listings hold in all (when that's fewer than qty)
function T.Fill(rows, qty)
  local taken, cost, left = {}, 0, qty or 0
  for i, r in ipairs(rows or {}) do
    if left <= 0 then
      break
    end
    local n = math.min(left, r.qty)
    taken[i], cost, left = n, cost + n * r.price, left - n
  end
  return taken, cost, (qty or 0) - left
end

-- Pure: the game's price against the listings it was worked out from: the share it's higher by when that's over the
-- warning (Settings buyWarnPct), else nil
function T.PriceJump(total, expected, warnPct)
  if not (total and expected and expected > 0 and warnPct and warnPct > 0) then
    return nil
  end
  local up = total / expected - 1
  return up * 100 > warnPct and up or nil
end

-- Bought from the Shopping tab: the list on screen needs that many fewer (gone at none). What you buy goes to your
-- mailbox, and the lists count bags and bank, so without this the list still asked for all of it - and offered to
-- buy it again.
function T:Bought(key, qty)
  if not (key and qty and qty > 0) or self.mode ~= "list" then
    return
  end
  local items, i = self:Items(), (not self.temp) and (self.list or 1) or nil
  local e = items[key]
  if not e then
    return
  end
  local left = (e.need or 0) - qty
  if i then
    shopping():SetItem(i, key, left)
  elseif left > 0 then
    e.need = left
  else
    items[key] = nil
  end
  if left <= 0 and self.selected == key then
    self:Select(nil) -- nothing left to buy of it: no Buy button to click again
  else
    self.panel.qty:SetText(left > 0 and tostring(left) or "")
    self:Render()
  end
end

-- recent searches (AME_DB.recentSearches, newest first): the same text and filters again moves to the top
local function sameFilters(a, b)
  for _, k in ipairs({ "category", "minLevel", "maxLevel", "minItemLevel", "maxItemLevel", "quality", "maxPrice" }) do
    if (a[k] or false) ~= (b[k] or false) then
      return false
    end
  end
  return (a.exact or false) == (b.exact or false) and (a.usable or false) == (b.usable or false)
end

function T.Remember(list, text, f, max)
  for i = #list, 1, -1 do
    if list[i].text == text and sameFilters(list[i].f or {}, f or {}) then
      table.remove(list, i)
    end
  end
  local copy = {}
  for k, v in pairs(f or {}) do
    copy[k] = v
  end
  table.insert(list, 1, { text = text, f = copy })
  while #list > (max or T.RECENT) do
    table.remove(list)
  end
  return list
end

local function recent()
  AME_DB.recentSearches = AME_DB.recentSearches or {}
  return AME_DB.recentSearches
end

---------------------------------------------------------------------------------------------------------------------
-- the panel

local function cell(parent, width, justify)
  local fs = W.Text(parent, "GameFontHighlightSmall", justify or "RIGHT")
  fs:SetWidth(width)
  fs:SetWordWrap(false)
  return fs
end

-- a panel like the main window's (its colour, the discreet border) and the frame inside it, inset by pad
local function makePanel(parent, pad)
  local outer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Skin(outer, W.COLORS.panel)
  local inner = CreateFrame("Frame", nil, outer)
  inner:SetPoint("TOPLEFT", pad, -pad)
  inner:SetPoint("BOTTOMRIGHT", -pad, pad)
  return outer, inner
end
T.Panel = makePanel

-- a small labelled control in the filters (y: the row's top)
local function labeled(parent, text, control, x, y)
  local label = W.Text(parent, "GameFontDisableSmall")
  label:SetPoint("TOPLEFT", x, y or 0)
  label:SetText(text)
  control:SetPoint("TOPLEFT", x, (y or 0) - 13)
  return control
end

T.FILTERS_H = 92 -- two rows, in a panel

-- the subcategory choices under a top category ({ path, name })
local function subOptions(top)
  local out = { { false, L["Any"] } }
  local c = top and ns.AHBrowse.Category(_G.AuctionCategories, top)
  for j, sub in ipairs(c and c.subCategories or {}) do
    if sub.name then
      out[#out + 1] = { top .. "." .. j, sub.name }
    end
  end
  return out
end

-- Two rows: category, subcategory and quality; then required level, item level, the highest price each, exact
-- name and usable. (Two dropdowns for the category: the game's whole tree is too long for one menu.)
function T:CreateFilters(main)
  local p = self.panel
  local outer, box = makePanel(main, 8)
  outer:SetPoint("TOPLEFT", 0, -28)
  outer:SetPoint("RIGHT", 0, 0)
  outer:SetHeight(T.FILTERS_H)
  outer:Hide()
  p.filters = outer
  local f = self.filters
  local function changed()
    T:RenderFiltersButton()
  end
  local tops = { { false, L["Any category"] } }
  for i, c in ipairs(_G.AuctionCategories or {}) do
    if c.name then
      tops[#tops + 1] = { tostring(i), c.name }
    end
  end
  p.subcategory = labeled(
    box,
    L["Subcategory"],
    W.Dropdown(box, 150, subOptions(nil), function(v)
      f.category = v or p.category.value or nil
      changed()
    end),
    160
  )
  p.category = labeled(
    box,
    L["Category"],
    W.Dropdown(box, 150, tops, function(v)
      p.category.value = v or nil
      f.category = v or nil
      p.subcategory:SetOptions(subOptions(v or nil))
      p.subcategory:SetValue(false)
      changed()
    end),
    0
  )
  local qualities = { { 0, L["Any quality"] } }
  for q = 1, 5 do
    local label = _G["ITEM_QUALITY" .. q .. "_DESC"]
    qualities[#qualities + 1] = { q, type(label) == "string" and label or tostring(q) }
  end
  p.quality = labeled(
    box,
    L["Quality at least"],
    W.Dropdown(box, 110, qualities, function(v)
      f.quality = (v and v > 0) and v or nil
      changed()
    end),
    320
  )
  local row2 = -40
  local function level(key, x, tip)
    local input = W.Input(box, {
      width = 34,
      numeric = true,
      hint = tip,
      onChange = function(_, n)
        f[key] = n
        changed()
      end,
    })
    input:SetPoint("TOPLEFT", x, row2 - 13)
    return input
  end
  local req = W.Text(box, "GameFontDisableSmall")
  req:SetPoint("TOPLEFT", 0, row2)
  req:SetText(L["Required level"])
  p.minLevel, p.maxLevel = level("minLevel", 0, L["min"]), level("maxLevel", 40, L["max"])
  local il = W.Text(box, "GameFontDisableSmall")
  il:SetPoint("TOPLEFT", 92, row2)
  il:SetText(L["Item level"])
  p.minItemLevel, p.maxItemLevel = level("minItemLevel", 92, L["min"]), level("maxItemLevel", 132, L["max"])
  p.maxPrice = labeled(
    box,
    L["Each at most"],
    W.MoneyInput(box, L["any"], function(copper)
      f.maxPrice = copper
      changed()
    end),
    184,
    row2
  )
  p.exact = W.Check(box, L["Exact name"], function(on)
    f.exact = on or nil
    changed()
  end)
  p.exact:SetPoint("TOPLEFT", 270, row2 - 15)
  p.usable = W.Check(box, L["Usable by you"], function(on)
    f.usable = on or nil
    changed()
  end)
  p.usable:SetPoint("TOPLEFT", 380, row2 - 15)
end

-- the sidebar, styled like the Market tab's: plain lines on a panel, headings, the picked line filled, counts right
T.LINE_H = 20

local function sideLine(side, i)
  local b = CreateFrame("Button", nil, side)
  b:SetHeight(T.LINE_H)
  b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * T.LINE_H)
  b:SetPoint("RIGHT", -4, 0)
  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  W.Fill(b.sel, W.COLORS.rowSelected)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  W.Fill(b.hl, W.COLORS.rowHover)
  b.text = W.Text(b, "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", 6, 0)
  b.text:SetPoint("RIGHT", -40, 0)
  b.text:SetWordWrap(false)
  b.count = W.Text(b, "GameFontDisableSmall", "RIGHT")
  b.count:SetPoint("RIGHT", -4, 0)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, button)
    if self.entry and self.entry.click then
      self.entry.click(button)
    end
  end)
  return b
end

-- The tables are the AME window's own: search results are the Market screener's (UI.ScreenerOpts: its columns,
-- star, confidence, signal reasons), a list is the Market tab's shopping list (UI.SHOPPING_COLUMNS) with the
-- cheapest listing beside the market price. Only a click does something else here: the item's listings below.
local function pickRow(d)
  T:Select(d.itemID)
end
local function selected(d)
  return d.itemID == T.selected
end

-- a list's columns: the Market tab's, the cheapest listing after the market price, the cost at the listings;
-- narrower, for the auction house window (the market price goes first when it's too narrow)
local LIST_FIT = { name = 170, need = 44, have = 44, missing = 52, market = 76, cost = 76 }
local LIST_DROP = { market = 3 }
local function listColumns()
  local out = {}
  for _, original in ipairs(UI.SHOPPING_COLUMNS or {}) do
    local col = {}
    for k, v in pairs(original) do
      col[k] = v
    end
    col.width = LIST_FIT[col.key] or col.width
    col.drop = LIST_DROP[col.key] or col.drop
    if col.key == "cost" then
      out[#out + 1] = {
        key = "cost",
        label = col.label,
        width = col.width,
        text = function(r)
          if r.vendor then
            return "" -- bought from a vendor, not here
          end
          return r.missing > 0 and W.Money(math.floor((r.buyCost or r.cost or 0) + 0.5)) or ""
        end,
      }
    else
      out[#out + 1] = col
    end
    if col.key == "market" then
      out[#out + 1] = {
        key = "cheapest",
        label = L["Cheapest"],
        width = 76,
        text = function(r)
          if r.vendor then
            return W.Dim(L["vendor"] .. " ") .. W.Money(r.vendor)
          end
          return r.cheapest and W.Money(r.cheapest) or W.Dim(r.searched and L["none"] or "-")
        end,
      }
    end
  end
  return out
end

function T:Create(ah)
  local p = CreateFrame("Frame", nil, ah, "BackdropTemplate")
  W.Skin(p, W.COLORS.bg) -- the main window's discreet border
  p:SetPoint("TOPLEFT", ah, "TOPLEFT", 8, -60)
  p:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -8, 28)
  p:Hide()
  self.panel = p
  self.filters = self.filters or {}
  self.mode = self.mode or "list"
  self.sideOffset = 0

  -- the sidebar: recent searches, then the lists
  local side = CreateFrame("Frame", nil, p, "BackdropTemplate")
  W.Skin(side, W.COLORS.panel)
  side:SetPoint("TOPLEFT", 0, 0)
  side:SetPoint("BOTTOMLEFT", 0, 0)
  side:SetWidth(T.SIDE_W)
  side.lines = {}
  for i = 1, 24 do
    side.lines[i] = sideLine(side, i)
  end
  side:EnableMouseWheel(true)
  side:SetScript("OnMouseWheel", function(_, delta)
    T.sideOffset = math.max(0, (T.sideOffset or 0) - delta * 2)
    T:RenderSide()
  end)
  p.side = side

  -- search row, filters, the title row, then the table
  local main = CreateFrame("Frame", nil, p)
  main:SetPoint("TOPLEFT", side, "TOPRIGHT", 10, -8)
  main:SetPoint("BOTTOMRIGHT", -8, 8)
  p.main = main
  p.search = W.Input(main, {
    height = 22,
    hint = L["Search the auction house"],
    onEnter = function(self)
      self:ClearFocus()
      T:Search()
    end,
  })
  p.search:SetPoint("TOPLEFT", 0, 0)
  p.search:SetPoint("RIGHT", -196, 0)
  p.filterButton = W.Button(main, L["Filters"], 100, 22, function()
    p.filters:SetShown(not p.filters:IsShown())
    T:Layout()
  end)
  p.filterButton:SetPoint("LEFT", p.search, "RIGHT", 6, 0)
  p.go = W.Button(main, L["Search"], 84, 22, function()
    T:Search()
  end)
  p.go:SetPoint("LEFT", p.filterButton, "RIGHT", 6, 0)
  self:CreateFilters(main)

  local top = CreateFrame("Frame", nil, main)
  top:SetHeight(22)
  p.top = top
  p.title = W.Text(top, "GameFontNormal")
  p.title:SetPoint("LEFT", 0, 0)
  p.status = W.Text(top, "GameFontDisableSmall", "RIGHT")
  p.status:SetPoint("RIGHT", -110, 0)
  p.searchAll = W.Button(top, L["Search all"], 100, 20, function()
    T:SearchAll()
  end)
  p.searchAll:SetPoint("RIGHT", 0, 0)

  -- the table's panel: under the title row, down to the listings (or the bottom)
  local box, inner = makePanel(main, 4)
  p.tableBox = box
  p.listTable = ns.DataTable.New(inner, {
    columns = listColumns(),
    fill = true,
    rows = 8,
    itemID = function(r)
      return r.itemID
    end,
    sort = { key = "missing", ascending = false },
    onClick = pickRow,
    selected = selected,
    rowAlpha = function(r)
      return r.vendor and 0.55 or 1 -- a vendor sells it: bought there
    end,
  })
  p.searchTable = ns.DataTable.New(
    inner,
    UI.ScreenerOpts({
      fill = true,
      rows = 8,
      sort = { key = "min", ascending = true },
      onClick = pickRow,
      selected = selected,
    })
  )
  -- the screener's columns as you chose them for the Market tab, and the cheapest listing (what you'd pay now)
  local hidden = UI.MarketHiddenColumns and UI:MarketHiddenColumns() or {}
  hidden.min = nil
  p.searchTable:SetUserHidden(hidden)

  -- the selected item's listings, and buying
  local detailPanel, detail = makePanel(main, 8)
  detailPanel:SetPoint("BOTTOMLEFT", 0, 0)
  detailPanel:SetPoint("RIGHT", 0, 0)
  detailPanel:SetHeight(T.LISTINGS * 16 + 68)
  detailPanel:Hide()
  p.detail = detailPanel
  p.detailTitle = W.Text(detail, "GameFontNormalSmall")
  p.detailTitle:SetPoint("TOPLEFT", 0, 0)
  p.listings = {}
  for i = 1, T.LISTINGS do
    local l = CreateFrame("Frame", nil, detail)
    l:SetHeight(16)
    l:SetPoint("TOPLEFT", 0, -16 - (i - 1) * 16)
    l:SetPoint("RIGHT", 0, 0)
    l.bg = l:CreateTexture(nil, "BACKGROUND")
    l.bg:SetAllPoints()
    l.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
    l.fill = l:CreateTexture(nil, "BACKGROUND", nil, 1) -- a listing the order takes from
    l.fill:SetAllPoints()
    W.Fill(l.fill, W.COLORS.rowSelected)
    l.fill:Hide()
    l.price = cell(l, 110)
    l.price:SetPoint("LEFT", 0, 0)
    l.qty = cell(l, 70)
    l.qty:SetPoint("LEFT", l.price, "RIGHT", 8, 0)
    l.mine = W.Text(l, "GameFontHighlightSmall")
    l.mine:SetPoint("LEFT", l.qty, "RIGHT", 10, 0)
    l.buy = W.Button(l, L["Buy"], 50, 16)
    l.buy:SetPoint("RIGHT", 0, 0)
    p.listings[i] = l
  end
  local buyLabel = W.Text(detail, "GameFontDisableSmall")
  buyLabel:SetPoint("BOTTOMLEFT", 0, 6)
  buyLabel:SetText(L["Buy"])
  p.buyLabel = buyLabel
  p.qty = W.Input(detail, {
    numeric = true,
    width = 50,
    onChange = function(_, _, user)
      if user then
        T:RenderDetail() -- the listings it takes from, as you type
      end
    end,
  })
  p.qty:SetPoint("LEFT", buyLabel, "RIGHT", 6, 0)
  p.buyText = W.Text(detail, "GameFontHighlightSmall")
  p.buyText:SetPoint("LEFT", p.qty, "RIGHT", 8, 0)
  p.buy = W.Button(detail, L["Buy"], 90, 20, function()
    local pending = ns.AHSearch.pending
    if pending and not pending.sent then
      ns.AHSearch:Confirm()
    else
      local qty = math.max(1, tonumber(p.qty:GetText()) or 1)
      local book = ns.AHSearch.results[T.selected]
      local _, expected = T.Fill(book and book.rows, qty)
      if ns.AHSearch:Buy(T.selected, qty) and ns.AHSearch.pending then
        ns.AHSearch.pending.expected = expected -- what the listings shown added up to (the price warning)
      end
    end
  end)
  p.buy:SetPoint("BOTTOMRIGHT", 0, 2)
  W.Primary(p.buy)
  p.note = W.Text(detail, "GameFontDisableSmall")
  p.note:SetPoint("RIGHT", p.buy, "LEFT", -10, 0)

  ns.AHSearch.onBought = function(key, qty)
    T:Bought(key, qty)
  end
  -- a list added or changed anywhere (the craft queue, the AME window): shown at once, once per frame
  shopping().onChange = function()
    if T.renderPending or not C_Timer then
      return
    end
    T.renderPending = true
    C_Timer.After(0, function()
      T.renderPending = false
      T:Render()
    end)
  end
  self:Layout()
  return p
end

-- the title row under the search row (and under the filters when they're open); the table down to the listings
function T:Layout()
  local p = self.panel
  p.top:ClearAllPoints()
  p.top:SetPoint("TOPLEFT", p.main, "TOPLEFT", 0, p.filters:IsShown() and -(32 + T.FILTERS_H) or -30)
  p.top:SetPoint("RIGHT", p.main, "RIGHT", 0, 0)
  p.tableBox:ClearAllPoints()
  p.tableBox:SetPoint("TOPLEFT", p.top, "BOTTOMLEFT", 0, -4)
  p.tableBox:SetPoint("RIGHT", p.main, "RIGHT", 0, 0)
  if p.detail:IsShown() then
    p.tableBox:SetPoint("BOTTOM", p.detail, "TOP", 0, 8)
  else
    p.tableBox:SetPoint("BOTTOM", p.main, "BOTTOM", 0, 0)
  end
  self:RenderFiltersButton()
  self:Render()
end

function T:RenderFiltersButton()
  local p = self.panel
  local n = ns.AHBrowse.Count(self.filters)
  p.filterButton:SetText(n > 0 and L["Filters (%d)"]:format(n) or L["Filters"])
  p.filterButton:SetSelected(p.filters:IsShown())
end

-- an item clicked: its listings (searched when they aren't in yet), and the AME window beside the auction house
-- shows it, as it does for a search
function T:Select(key)
  self.selected = key
  if key and not ns.AHSearch.results[key] then
    ns.AHSearch:Start({ key }, function()
      T:Render()
    end)
  end
  if key and ns.UI.FollowAuctionItem then
    ns.UI:FollowAuctionItem(key)
  end
  local shown = self.panel.detail:IsShown()
  self.panel.detail:SetShown(key ~= nil)
  if shown ~= (key ~= nil) then
    self:Layout()
  else
    self:Render()
  end
end

-- search by the box and the filters; remembered among the recent searches
function T:Search(text, f)
  local p = self.panel
  if text then
    p.search:SetText(text)
  end
  text = p.search:GetText() or ""
  self.filters = f or self.filters
  if f then
    self:ShowFilters()
  end
  self.mode, self.temp = "search", nil
  T.Remember(recent(), text, self.filters)
  ns.AHBrowse:Search(text, self.filters, function()
    T:Render()
  end)
  self:Select(nil)
end

-- put a recent search's filters back in the controls
function T:ShowFilters()
  local p, f = self.panel, self.filters
  local top = f.category and f.category:match("^(%d+)")
  p.category:SetValue(top or false)
  p.category.value = top
  p.subcategory:SetOptions(subOptions(top))
  p.subcategory:SetValue(f.category and f.category:find("%.") and f.category or false)
  p.quality:SetValue(f.quality or 0)
  p.minLevel:SetText(f.minLevel and tostring(f.minLevel) or "")
  p.maxLevel:SetText(f.maxLevel and tostring(f.maxLevel) or "")
  p.minItemLevel:SetText(f.minItemLevel and tostring(f.minItemLevel) or "")
  p.maxItemLevel:SetText(f.maxItemLevel and tostring(f.maxItemLevel) or "")
  p.maxPrice:SetCopper(f.maxPrice)
  p.exact:SetChecked(f.exact or false)
  p.usable:SetChecked(f.usable or false)
  self:RenderFiltersButton()
end

-- the sidebar's lines: { header } or { label, count, selected, click(button) }
function T:SideEntries()
  local out = {}
  out[#out + 1] = { header = L["Recent searches"] }
  local searches = recent()
  for i, s in ipairs(searches) do
    local head, note = ns.AHBrowse.Label(s.text, s.f, _G.AuctionCategories)
    out[#out + 1] = {
      label = head .. (note ~= "" and W.Dim("  " .. note) or ""),
      selected = self.mode == "search" and i == 1,
      click = function(button)
        if button == "RightButton" then
          table.remove(searches, i)
          T:Render()
          return
        end
        local copy = {}
        for k, v in pairs(s.f or {}) do
          copy[k] = v
        end
        T:Search(s.text, copy)
      end,
    }
  end
  if #searches == 0 then
    out[#out + 1] = { label = W.Dim(L["none yet"]) }
  end
  out[#out + 1] = { header = L["Shopping lists"] }
  local function pick(index)
    return function()
      if index then
        T.temp, T.list = nil, index
      end
      T.mode = "list"
      ns.AHBrowse:Stop()
      T:Select(nil)
    end
  end
  if self.temp then
    out[#out + 1] = { label = self.temp.name, selected = self.mode == "list", click = pick(nil) }
  end
  for i, l in ipairs(shopping():Lists()) do
    out[#out + 1] = {
      label = l.name,
      count = shopping():Count(i),
      selected = self.mode == "list" and not self.temp and i == (self.list or 1),
      click = pick(i),
    }
  end
  if #shopping():Lists() == 0 and not self.temp then
    out[#out + 1] = { label = W.Dim(L["make one in the AME window or from the craft queue"]) }
  end
  return out
end

function T:RenderSide()
  local side = self.panel.side
  local entries = self:SideEntries()
  local h = side:GetHeight() or 0
  local rows = h > 0 and math.min(#side.lines, math.floor((h - 8) / T.LINE_H)) or #side.lines
  self.sideOffset = math.max(0, math.min(self.sideOffset or 0, #entries - rows))
  for i, b in ipairs(side.lines) do
    local e = i <= rows and entries[i + self.sideOffset]
    b.entry = e or nil
    if e then
      b.text:SetFontObject(e.header and "GameFontDisableSmall" or "GameFontNormalSmall")
      b.text:SetText(e.header or e.label)
      b.count:SetText(e.count and tostring(e.count) or "")
      b.sel:SetShown(e.selected or false)
      b.hl:SetShown(e.click ~= nil)
      b:Show()
    else
      b:Hide()
    end
  end
end

-- the table's rows for the mode, its title and status
function T:TableRows()
  local index = ns.AME:FactionIndex()
  if self.mode == "search" then
    local B = ns.AHBrowse
    local found = B.Rows(B.results, self.filters, index and index.items)
    -- the screener's rows: each item's summary, with what's on sale now (its cheapest listing and how many)
    local avgKey = "avg" .. (ns.Settings:Get("tooltipAvgDays") or 7)
    local rows = {}
    for i, r in ipairs(found) do
      local s = index and index.items[r.key] or {}
      local avg = s[avgKey] or s.avg7
      rows[i] = setmetatable({
        itemID = r.key,
        min = r.cheapest,
        qty = r.qty,
        vsAvg = s.market and avg and avg > 0 and s.market / avg - 1 or nil,
      }, { __index = s })
    end
    local head = B.Label(B.text or self.panel.search:GetText(), self.filters, _G.AuctionCategories)
    local status = B.active and L["searching..."] or L["%d found"]:format(#rows)
    return rows, head, status
  end
  local items, title = self:Items()
  local rows, totals = T.Rows(
    items,
    AME_DB.holdings,
    index and index.items,
    ns.AHSearch.results,
    ns.VendorPanel and ns.VendorPanel.PriceOf
  )
  self.rowsShown = rows
  local S = ns.AHSearch
  local status
  if S:Busy() then
    status = L["searching %d of %d"]:format(math.min(S.done + 1, S.total), S.total)
  else
    status = W.Dim(L["left to buy"] .. " ") .. money(totals.left)
  end
  return rows, title or L["no shopping lists yet"], status
end

function T:Render()
  local p = self.panel
  if not (p and p:IsShown()) then
    return
  end
  self:RenderSide()
  local rows, title, status = self:TableRows()
  p.title:SetText(title)
  p.status:SetText(status)
  p.searchAll:SetShown(self.mode == "list")
  local shown, other = p.listTable, p.searchTable
  if self.mode == "search" then
    shown, other = p.searchTable, p.listTable
  end
  other:SetShown(false)
  shown:SetShown(true)
  shown:SetData(rows)
  shown:Render()
  self:RenderDetail()
end

function T:RenderDetail()
  local p = self.panel
  local key = self.selected
  local book = key and ns.AHSearch.results[key]
  if not key then
    return
  end
  local note = book and (#book.rows > 0 and L["cheapest first"] or L["none listed"]) or L["searching..."]
  p.detailTitle:SetText(name(key) .. W.Dim("  ·  " .. note))
  -- a commodity: the listings the order takes from, highlighted; the last one partly ("20 of 555")
  local pending = ns.AHSearch.pending
  local want = book
    and book.commodity
    and (pending and pending.key == key and not pending.sent and pending.qty or tonumber(p.qty:GetText()))
  local taken, cost, covered = T.Fill(book and book.rows, want or 0)
  for i, l in ipairs(p.listings) do
    local row = book and book.rows[i]
    if row then
      l.price:SetText(money(row.price))
      local n = taken[i]
      l.qty:SetText(
        n and n < row.qty and (W.Count(n) .. W.Dim(" " .. L["of %s"]:format(W.Count(row.qty)))) or W.Count(row.qty)
      )
      l.fill:SetShown(n ~= nil)
      l.mine:SetText(row.mine and W.Color("brand", L["yours"]) or "")
      l.buy:SetShown(not book.commodity)
      l.buy:SetScript("OnClick", function()
        ns.AHSearch:Buy(key, row.qty, row)
      end)
      l:Show()
    else
      l:Hide()
    end
  end
  local commodity = book and book.commodity
  p.qty:SetShown(commodity or false)
  p.buyLabel:SetShown(commodity or false)
  if pending and pending.key == key and not pending.sent then
    p.buyText:SetText(
      pending.total and (L["%s for %s"]:format(W.Count(pending.qty), money(pending.total))) or L["asking the price..."]
    )
    -- the game's price against the listings it was worked out from: prices can move between the search and now
    local jump = T.PriceJump(pending.total, pending.expected, ns.Settings:Get("buyWarnPct"))
    if jump then
      p.buy:SetText(L["Confirm anyway"])
      p.note:SetText(
        W.Color(
          "bad",
          L["%d%% above the listings shown (%s)"]:format(math.floor(jump * 100 + 0.5), money(pending.expected))
        )
      )
    else
      p.buy:SetText(L["Confirm"])
      p.note:SetText(W.Dim(L["click Confirm to buy"]))
    end
  else
    p.buy:SetText(L["Buy"])
    local missing
    for _, r in ipairs(self.mode == "list" and self.rowsShown or {}) do
      if r.itemID == key then
        missing = r.missing
      end
    end
    if commodity and p.qty:GetText() == "" then
      p.qty:SetText(tostring(missing and missing > 0 and missing or 1))
      return self:RenderDetail() -- the listings it takes from, for that many
    end
    -- what the order should cost at the listings shown (the game says the real price when you click Buy)
    if commodity and want and want > 0 and covered > 0 then
      local short = covered < want and W.Color("bad", "  " .. L["only %s listed"]:format(W.Count(covered))) or ""
      p.buyText:SetText(W.Dim("~") .. money(cost) .. short)
    else
      p.buyText:SetText("")
    end
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
    if r.missing > 0 and not r.vendor then -- a vendor sells it: not searched here
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
  self.mode, self.selected = "list", nil
  self:Open()
  ns.AHSearch:Start(keys, function()
    T:Render()
  end)
end

-- one item, from anywhere (Search the AH on AME's pages, a Shift-click): the Shopping tab searches its name and
-- shows its listings
function T:SearchItem(key, text)
  self:Open()
  self:Search(text or ns.ItemCache.Name(key) or "")
  self:Select(key)
end

-- a Shift-clicked item (bags, chat, the AH) while the Shopping tab is up: search for it. Not while you're typing in
-- chat (that link is for the chat). Returns true when it was taken.
function T:OnItemLink(link)
  local p = self.panel
  if not (link and p and p:IsVisible()) then
    return false
  end
  local chat = _G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow()
  if chat and not p.search:HasFocus() then
    return false
  end
  local id = ns.ItemCache.Learn(link)
  if not id then
    return false
  end
  local now = GetTime and GetTime() or 0
  if self.lastLink == link and now - (self.lastLinkAt or 0) < 0.3 then -- several hooks report the same click
    return true
  end
  self.lastLink, self.lastLinkAt = link, now
  p.search:ClearFocus()
  self:SearchItem(id, ns.ItemCache.Name(id) or link:match("%[(.-)%]"))
  return true
end

function UI:SearchItems(keys, title)
  if not T.tab then
    return ns.AME:SearchAuctionHouse(keys[1])
  end
  T:ShowKeys(keys, title)
end

function T:Open()
  local ah = _G.AuctionHouseFrame
  if ah and self.displayMode and ah.SetDisplayMode then
    ah:SetDisplayMode(self.displayMode)
  end
  self:Render()
end

---------------------------------------------------------------------------------------------------------------------
-- the tabs, added to the game's auction house window once (without Auctionator)

-- one tab and its panel as a display mode of the game's window: key (the frame's key and the mode's), label
local function addTab(ah, key, label, panel)
  rawset(ah, key, panel)
  local mode = { key }
  _G.AuctionHouseFrameDisplayMode[key] = mode
  local last = ah.Tabs[#ah.Tabs]
  local ok, tab =
    pcall(CreateFrame, "Button", "AuctionHouseFrame" .. key .. "Tab", ah, "AuctionHouseFrameDisplayModeTabTemplate")
  if not ok or not tab then
    tab = W.Button(ah, label, 80, 24, function()
      ah:SetDisplayMode(mode)
    end)
  end
  tab.displayMode = mode
  tab:SetText(label)
  tab:SetPoint("LEFT", last, "RIGHT", -15, 0)
  -- the template sizes a tab when it shows; this one showed (with the window already open) before it had its label:
  -- sized now, and again next frame and whenever the window opens (the font may not measure until it's drawn)
  T.ownTabs = T.ownTabs or {}
  T.ownTabs[#T.ownTabs + 1] = tab
  if _G.PanelTemplates_TabResize and rawget(tab, "Text") then
    pcall(
      _G.PanelTemplates_TabResize,
      tab,
      rawget(ah, "tabPadding"),
      nil,
      rawget(ah, "minTabWidth"),
      rawget(ah, "maxTabWidth")
    )
  end
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
  if _G.PanelTemplates_SetNumTabs then
    pcall(_G.PanelTemplates_SetNumTabs, ah, #ah.Tabs)
  end
  if rawget(ah, "tabsForDisplayMode") then
    ah.tabsForDisplayMode[mode] = index
  end
  return tab, mode
end

function T:Attach()
  local ah = _G.AuctionHouseFrame
  local modes = _G.AuctionHouseFrameDisplayMode
  if self.attached or not (ah and modes and rawget(ah, "Tabs")) or _G.Auctionator then
    return
  end
  self.attached = true -- once, whatever happens below: never a second panel or tab
  local panel = self:Create(ah)
  self.tab, self.displayMode = addTab(ah, "AMEShopping", L["Shopping"], panel)
  panel:HookScript("OnShow", function()
    T:Render()
  end)
  local sell = ns.AHSelling
  if sell then
    local sp = sell:Create(ah)
    sell.tab, sell.displayMode = addTab(ah, "AMESelling", L["Selling"], sp)
  end
  local function resize()
    for _, t in ipairs(T.ownTabs or {}) do
      if _G.PanelTemplates_TabResize and rawget(t, "Text") then
        pcall(
          _G.PanelTemplates_TabResize,
          t,
          rawget(ah, "tabPadding"),
          nil,
          rawget(ah, "minTabWidth"),
          rawget(ah, "maxTabWidth")
        )
      end
    end
    -- the template draws a new tab as the selected one, and the game set its tabs before ours existed (and doesn't
    -- again when it opens on the same tab): have it draw every tab's state, ours unselected unless they're on
    if _G.PanelTemplates_UpdateTabs and rawget(ah, "selectedTab") then
      pcall(_G.PanelTemplates_UpdateTabs, ah)
    end
  end
  resize()
  if C_Timer then
    C_Timer.After(0, resize)
  end
  if ah.HookScript then
    ah:HookScript("OnShow", function()
      if C_Timer then
        C_Timer.After(0, resize)
      end
    end)
  end
  -- each tab's title on the window, as the game's own tabs have theirs; a search running for the Shopping tab stops
  -- when you go elsewhere
  if ah.SetDisplayMode and hooksecurefunc then
    hooksecurefunc(ah, "SetDisplayMode", function(frame, mode)
      if mode == T.displayMode and frame.SetTitle then
        frame:SetTitle(L["Shopping"])
      elseif sell and mode == sell.displayMode and frame.SetTitle then
        frame:SetTitle(L["Selling"])
      end
      if mode ~= T.displayMode then
        ns.AHBrowse:Stop()
      end
    end)
  end
end
