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

T.ROWS = 12
T.ROW_H = 18
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

local COLS = { 50, 50, 90, 100, 70 }
local HEADS = {
  list = { L["need"], L["have"], L["cheapest"], L["at or under top"], L["vs market"] },
  search = { L["ilvl"], L["for sale"], L["cheapest"], L["vs market"], L["signal"] },
}

-- a small labelled control in the filters (y: the row's top)
local function labeled(parent, text, control, x, y)
  local label = W.Text(parent, "GameFontDisableSmall")
  label:SetPoint("TOPLEFT", x, y or 0)
  label:SetText(text)
  control:SetPoint("TOPLEFT", x, (y or 0) - 13)
  return control
end

T.FILTERS_H = 76 -- two rows

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
  local box = CreateFrame("Frame", nil, main)
  box:SetPoint("TOPLEFT", 0, -28)
  box:SetPoint("RIGHT", 0, 0)
  box:SetHeight(T.FILTERS_H)
  box:Hide()
  p.filters = box
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

function T:Create(ah)
  local p = CreateFrame("Frame", nil, ah, "BackdropTemplate")
  W.Skin(p, W.COLORS.bg) -- the main window's discreet border
  p:SetPoint("TOPLEFT", ah, "TOPLEFT", 8, -60)
  p:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -8, 28)
  p:Hide()
  self.panel = p
  self.filters = self.filters or {}
  self.mode = self.mode or "list"
  self.offset = 0

  -- recent searches and the lists
  p.lists, p.recents = {}, {}
  local side = CreateFrame("Frame", nil, p)
  side:SetPoint("TOPLEFT", 8, -8)
  side:SetPoint("BOTTOMLEFT", 8, 8)
  side:SetWidth(T.SIDE_W - 10)
  p.side = side
  p.recentHead = W.Text(side, "GameFontNormalSmall")
  p.recentHead:SetText(L["Recent searches"])
  p.listHead = W.Text(side, "GameFontNormalSmall")
  p.listHead:SetText(L["Shopping lists"])

  -- search row, filters, then the table
  local main = CreateFrame("Frame", nil, p)
  main:SetPoint("TOPLEFT", side, "TOPRIGHT", 10, 0)
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
  top:SetHeight(20)
  top:SetPoint("RIGHT", 0, 0)
  p.top = top
  p.title = W.Text(top, "GameFontNormal")
  p.title:SetPoint("LEFT", 0, 0)
  p.status = W.Text(top, "GameFontDisableSmall", "RIGHT")
  p.status:SetPoint("RIGHT", -110, 0)
  p.searchAll = W.Button(top, L["Search all"], 100, 20, function()
    T:SearchAll()
  end)
  p.searchAll:SetPoint("RIGHT", 0, 0)
  local header = CreateFrame("Frame", nil, main)
  header:SetHeight(16)
  header:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -4)
  header:SetPoint("RIGHT", 0, 0)
  p.heads = {}
  local x = 0
  for k = #COLS, 1, -1 do
    local fs = cell(header, COLS[k])
    fs:SetPoint("RIGHT", -x, 0)
    p.heads[k] = fs
    x = x + COLS[k] + 8
  end
  p.header = header
  p.rows = {}
  for i = 1, T.ROWS do
    local r = CreateFrame("Button", nil, main)
    r:SetHeight(T.ROW_H)
    r:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -(i - 1) * T.ROW_H)
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
    for k = #COLS, 1, -1 do
      local fs = cell(r, COLS[k])
      fs:SetPoint("RIGHT", -cx, 0)
      r.cells[k] = fs
      cx = cx + COLS[k] + 8
    end
    r:SetScript("OnClick", function(self)
      T:Select(self.itemID)
    end)
    r:Hide() -- until Render fills it
    p.rows[i] = r
  end
  main:EnableMouseWheel(true)
  main:SetScript("OnMouseWheel", function(_, delta)
    T:Scroll(-delta * 3)
  end)

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

-- the title row sits under the search row, and under the filters when they're open
function T:Layout()
  local p = self.panel
  p.top:ClearAllPoints()
  p.top:SetPoint("TOPLEFT", p.main, "TOPLEFT", 0, p.filters:IsShown() and -(32 + T.FILTERS_H) or -30)
  p.top:SetPoint("RIGHT", p.main, "RIGHT", 0, 0)
  self:RenderFiltersButton()
  self:Render()
end

function T:RenderFiltersButton()
  local p = self.panel
  local n = ns.AHBrowse.Count(self.filters)
  p.filterButton:SetText(n > 0 and L["Filters (%d)"]:format(n) or L["Filters"])
  p.filterButton:SetSelected(p.filters:IsShown())
end

-- how many rows fit between the header and the listings (all of them before the frame has a size)
function T:VisibleRows()
  local p = self.panel
  local h = p.main:GetHeight() or 0
  local headerTop = (p.filters:IsShown() and (32 + T.FILTERS_H) or 30) + 20 + 4 + 16
  local detail = p.detail:IsShown() and (p.detail:GetHeight() + 6) or 0
  if h <= 0 then
    return T.ROWS
  end
  return math.max(1, math.min(T.ROWS, math.floor((h - headerTop - detail) / T.ROW_H)))
end

function T:Scroll(by)
  self.offset = math.max(0, (self.offset or 0) + by)
  self:Render()
end

function T:Select(key)
  self.selected = key
  if self.mode == "search" and key and not ns.AHSearch.results[key] then
    ns.AHSearch:Start({ key }, function()
      T:Render()
    end)
  end
  self:Render()
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
  self.mode, self.temp, self.selected, self.offset = "search", nil, nil, 0
  T.Remember(recent(), text, self.filters)
  ns.AHBrowse:Search(text, self.filters, function()
    T:Render()
  end)
  self:Render()
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

-- the side: recent searches, then the lists
function T:RenderSide()
  local p = self.panel
  local y = 0
  p.recentHead:ClearAllPoints()
  p.recentHead:SetPoint("TOPLEFT", p.side, "TOPLEFT", 0, y)
  y = y - 16
  local searches = recent()
  for i = 1, T.RECENT do
    local b = p.recents[i]
    local s = searches[i]
    if not b then
      b = W.Button(p.side, "", T.SIDE_W - 14, 20)
      b.label:ClearAllPoints()
      b.label:SetPoint("LEFT", 6, 0)
      b.label:SetPoint("RIGHT", -6, 0)
      b.label:SetJustifyH("LEFT")
      b.label:SetWordWrap(false)
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      p.recents[i] = b
    end
    if s then
      local head, note = ns.AHBrowse.Label(s.text, s.f, _G.AuctionCategories)
      b:SetText(head .. (note ~= "" and W.Dim("  · " .. note) or ""))
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", p.side, "TOPLEFT", 0, y)
      b:SetSelected(self.mode == "search" and i == 1)
      b:SetScript("OnClick", function(_, button)
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
      end)
      b:Show()
      y = y - 22
    else
      b:Hide()
    end
  end
  if #searches == 0 then
    y = y - 4
  end
  y = y - 10
  p.listHead:ClearAllPoints()
  p.listHead:SetPoint("TOPLEFT", p.side, "TOPLEFT", 0, y)
  y = y - 16
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
      b = W.Button(p.side, "", T.SIDE_W - 14, 20)
      p.lists[i] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", p.side, "TOPLEFT", 0, y)
    b:SetText(e.name)
    b:SetSelected(
      self.mode == "list" and ((e.temp and self.temp ~= nil) or (not self.temp and e.index == (self.list or 1)))
    )
    b:SetScript("OnClick", function()
      if not e.temp then
        T.temp, T.list = nil, e.index
      end
      T.mode, T.selected, T.offset = "list", nil, 0
      ns.AHBrowse:Stop()
      T:Render()
    end)
    b:Show()
    y = y - 22
  end
  for i = #entries + 1, #p.lists do
    p.lists[i]:Hide()
  end
end

-- the table's rows for the mode: { itemID, name, cells = { 5 texts } }, title, status
function T:TableRows()
  local index = ns.AME:FactionIndex()
  if self.mode == "search" then
    local B = ns.AHBrowse
    local rows = B.Rows(B.results, self.filters, index and index.items)
    local out = {}
    for i, r in ipairs(rows) do
      out[i] = {
        itemID = r.key,
        name = name(r.key),
        cells = {
          r.ilvl and tostring(r.ilvl) or W.Dim("·"),
          W.Count(r.qty),
          money(r.cheapest),
          r.vs and W.Percent(r.vs, 0) or W.Dim(L["new"]),
          r.signal and r.signal ~= "none" and W.Signal(r.signal) or W.Dim("·"),
        },
      }
    end
    local head = B.Label(B.text or self.panel.search:GetText(), self.filters, _G.AuctionCategories)
    local status = B.active and L["searching..."] or L["%d found"]:format(#out)
    return out, head, status
  end
  local items, title = self:Items()
  local rows, totals = T.Rows(items, AME_DB.holdings, index and index.items, ns.AHSearch.results)
  self.rowsShown = rows
  local out = {}
  for i, row in ipairs(rows) do
    out[i] = {
      itemID = row.itemID,
      name = name(row.itemID) .. (row.missing == 0 and W.Dim("  " .. L["(enough)"]) or ""),
      cells = {
        W.Count(row.need),
        W.Count(row.held),
        row.cheapest and money(row.cheapest) or W.Dim(row.searched and L["none"] or "·"),
        row.underTop and W.Count(row.underTop) or W.Dim("·"),
        row.cheapest and row.market and W.Percent(row.cheapest / row.market - 1, 0) or W.Dim("·"),
      },
    }
  end
  local S = ns.AHSearch
  local status
  if S:Busy() then
    status = L["searching %d of %d"]:format(math.min(S.done + 1, S.total), S.total)
  else
    status = W.Dim(L["left to buy"] .. " ") .. money(totals.left)
  end
  return out, title or L["no shopping lists yet"], status
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
  for k, fs in ipairs(p.heads) do
    fs:SetText(W.Dim(HEADS[self.mode][k]))
  end
  p.detail:SetShown(self.selected ~= nil)
  local visible = self:VisibleRows()
  self.offset = math.max(0, math.min(self.offset or 0, #rows - visible))
  for i, r in ipairs(p.rows) do
    local row = i <= visible and rows[i + self.offset]
    r.itemID = row and row.itemID
    if row then
      r.name:SetText(row.name)
      for k = 1, #COLS do
        r.cells[k]:SetText(row.cells[k])
      end
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
  local note = book and L["cheapest first"] or L["searching..."]
  p.detailTitle:SetText(name(key) .. W.Dim("  ·  " .. note))
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
    for _, r in ipairs(self.mode == "list" and self.rowsShown or {}) do
      if r.itemID == key then
        missing = r.missing
      end
    end
    if commodity and p.qty:GetText() == "" then
      p.qty:SetText(tostring(missing and missing > 0 and missing or 1))
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
  self.mode, self.selected, self.offset = "list", nil, 0
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
  -- the template sizes a tab when it shows; this one showed (with the window already open) before it had its label
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
