-- Market tab: the screener over the market index. Layout (UI.Slots): a full-height category / watchlist sidebar on
-- the left (a dropdown on the toolbar when the window is narrow); toolbar with search, quality, price range, saved
-- views and the column chooser; a row with the signal filter and chips for the active filters; the table.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI
local DAY = ns.DAY
local avgDays, contentArea = UI.AvgDays, UI.ContentArea

---------------------------------------------------------------------------------------------------------------------
-- Market view (screener)

UI.STALE_DAYS = 3 -- rows whose data is older than this fade

-- optional = shown only when switched on in the column chooser (default: off unless `on`)
local COLUMNS = {
  { key = "name", label = L["Item"], width = 190, item = true, term = "name" },
  { key = "market", label = L["Market"], width = 86, format = "money", term = "market" },
  {
    key = "avg",
    money = true,
    export = function(s)
      return s["avg" .. avgDays()]
    end,
    width = 86,
    term = "avg",
    optional = true,
    label = function()
      return L["%dd avg"]:format(avgDays())
    end,
    sortKey = function()
      return "avg" .. avgDays()
    end,
    text = function(s)
      return W.Money(s["avg" .. avgDays()], true)
    end,
  },
  {
    key = "vsAvg",
    drop = 1,
    width = 76,
    format = "pct",
    term = "vsAvg",
    label = function()
      return L["vs %d-day avg"]:format(avgDays())
    end,
  },
  { key = "min", label = L["Lowest"], width = 80, format = "money", term = "min", optional = true },
  { key = "change7", drop = 6, label = L["7d"], width = 62, format = "pct", term = "change7", optional = true },
  {
    key = "vol30",
    drop = 5,
    label = L["Volatility"],
    width = 70,
    format = "plainpct",
    term = "vol30",
    optional = true,
  },
  { key = "qty", drop = 3, label = L["Supply"], width = 52, format = "count", term = "qty" },
  { key = "sellRate", label = L["Sales/day"], width = 58, format = "rate", term = "sellRate" },
  {
    key = "signal",
    label = L["Signal"],
    width = 64,
    align = "LEFT",
    term = "signal",
    sortKey = "signalRank",
    ascendingFirst = true,
    text = function(s)
      return W.SignalGlyph(s.signal)
    end,
  },
  { key = "score", drop = 2, label = L["Score"], width = 50, term = "score" },
  {
    key = "age",
    drop = 7,
    label = L["Age"],
    width = 50,
    optional = true,
    sortKey = "day",
    term = "age",
    text = function(s)
      local d = UI.index and UI.index.day and s.day and UI.index.day - s.day
      if not d then
        return W.NONE
      end
      return d <= 0 and L["today"] or L["%dd"]:format(d)
    end,
  },
  {
    key = "phase",
    drop = 8,
    label = L["Phase"],
    width = 110,
    optional = true,
    term = "phase",
    text = function(s)
      return s.phase and ns.Analytics.PHASE_LABEL[s.phase] or W.NONE
    end,
  },
}
UI.MARKET_COLUMNS = COLUMNS
local SIDEBAR_W = UI.SIDEBAR_W
local CAT_H = 19
local QUALITIES = {
  { nil, L["Any quality"] },
  { 1, L["Common+"] },
  { 2, L["Uncommon+"] },
  { 3, L["Rare+"] },
  { 4, L["Epic+"] },
}

local function itemInfo(itemID)
  return ns.ItemCache.Get(itemID)
end

-- Why an item has its signal, in words (row tooltips).
function UI.SignalReasons(s, today)
  local lines = {}
  local avg = s.avg30
  if s.market and avg and avg > 0 then
    lines[#lines + 1] = L["Price %s vs its 30-day average"]:format(W.Percent(s.market / avg - 1))
  end
  local sig = s.signal
  if sig == "buy" then
    lines[#lines + 1] = L["Unusually cheap for this item, given how much its price usually moves"]
  elseif sig == "sell" then
    lines[#lines + 1] = L["Unusually expensive for this item, given how much its price usually moves"]
  elseif sig == "hold" then
    lines[#lines + 1] = L["Within its usual range"]
  elseif sig == "wait" then
    lines[#lines + 1] = L["Cheap, but sellers are dumping: wait for the bottom"]
  elseif sig == "disenchant" and s.deValue then
    lines[#lines + 1] = L["Disenchanting is worth about %s; listing nets %s after the cut and deposit"]:format(
      W.Money(s.deValue),
      W.Money(s.vendorNet or 0)
    )
  elseif sig == "vendor" and s.vendorPrice then
    lines[#lines + 1] = L["A vendor pays %s; listing nets %s after the cut and deposit"]:format(
      W.Money(s.vendorPrice),
      W.Money(s.vendorNet)
    )
  else
    lines[#lines + 1] = L["Not enough history to judge yet (%d of %d days)"]:format(s.days or 0, ns.Analytics.MIN_DAYS)
  end
  if s.phase then
    lines[#lines + 1] = L["Market phase: %s"]:format(ns.Analytics.PHASE_LABEL[s.phase])
  end
  if (s.vol30 or 0) > 0.15 then
    lines[#lines + 1] = L["Volatile: its price swings a lot from day to day"]
  end
  if today and s.day and today - s.day > UI.STALE_DAYS then
    lines[#lines + 1] = W.Color("warn", L["Data is %d days old"]:format(today - s.day))
  end
  return lines
end

---------------------------------------------------------------------------------------------------------------------
-- categories: "All items", watchlists, classes in AH order, the selected class's subclasses indented

-- the sidebar entries for the current index and filters
function UI:CategoryEntries()
  local q = self.mq
  local watch = ns.AME.watch
  local shown, hiddenHere = self.index and self.index.count or 0, 0
  if watch and self.index then
    for id in pairs(watch:Hidden()) do
      if self.index.items[id] then
        hiddenHere = hiddenHere + 1
      end
    end
    shown = shown - hiddenHere
  end
  local entries = { { all = true, label = L["All items"], count = shown } }
  if watch then
    entries[#entries + 1] = { header = true, label = W.Dim(L["Watchlists"]), count = "" }
    for i, l in ipairs(watch:Lists()) do
      entries[#entries + 1] = {
        list = i,
        label = W.StarInline(12) .. " " .. l.name .. (l.shared and " " .. W.Color("brand", L["shared"]) or ""),
        name = l.name,
        count = watch:Count(i),
      }
    end
    entries[#entries + 1] = { newList = true, label = W.Dim("+ " .. L["New list"]), count = "" }
    if watch:HiddenCount() > 0 then -- items you hid (right-click a row): shown here so they can be unhidden
      entries[#entries + 1] = { hidden = true, label = W.Dim(L["Hidden"]), name = L["Hidden"], count = hiddenHere }
    end
    local guild = watch:GuildLists()
    if #guild > 0 then
      entries[#entries + 1] = { header = true, label = W.Dim(L["Guild watchlists"]), count = "" }
      for _, g in ipairs(guild) do
        local n = 0
        for _ in pairs(g.items) do
          n = n + 1
        end
        entries[#entries + 1] = {
          guild = g.key,
          label = "   " .. g.name .. " " .. W.Dim("(" .. g.owner .. ")"),
          name = g.name,
          count = n,
        }
      end
    end
  end
  local shop = ns.AME.shopping
  if shop then
    entries[#entries + 1] = { header = true, label = W.Dim(L["Shopping lists"]), count = "" }
    local index = ns.AME:FactionIndex()
    local holdings = ns.Trading:Holdings()
    for i, l in ipairs(shop:Lists()) do
      local _, totals = ns.Shopping.Progress(l.items, holdings, index and index.items or {})
      entries[#entries + 1] = {
        shop = i,
        label = l.name .. (l.shared and " " .. W.Color("brand", L["shared"]) or ""),
        name = l.name,
        count = totals.done and W.Color("good", L["done"]) or totals.missing,
      }
    end
    entries[#entries + 1] = { newShop = true, label = W.Dim("+ " .. L["New shopping list"]), count = "" }
    for _, g in ipairs(shop:GuildLists()) do
      entries[#entries + 1] = {
        shopGuild = g.key,
        label = "   " .. g.name .. " " .. W.Dim("(" .. g.owner .. ")"),
        name = g.name,
        count = "",
      }
    end
  end
  entries[#entries + 1] = { header = true, label = W.Dim(L["Categories"]), count = "" }
  for _, c in ipairs(self.categories or {}) do
    entries[#entries + 1] = { classID = c.classID, label = ns.ItemCache.ClassName(c.classID), count = c.count }
    if q.classID == c.classID then
      for _, s in ipairs(c.subs) do
        entries[#entries + 1] = {
          classID = c.classID,
          subClassID = s.subClassID,
          label = "   " .. ns.ItemCache.SubClassName(c.classID, s.subClassID),
          count = s.count,
        }
      end
    end
  end
  return entries
end

-- pick a sidebar entry (or the compact dropdown's option); anchor: for menus
function UI:SelectCategory(e, button, anchor)
  local q = self.mq
  if e.newList then
    UI:PromptNewList()
    return
  end
  if e.newShop then
    UI:PromptNewShoppingList()
    return
  end
  if e.shop and button == "RightButton" then
    UI:ShoppingListMenu(anchor, e.shop)
    return
  end
  if e.shopGuild and button == "RightButton" then
    W.Menu(anchor, {
      {
        text = L["Copy to my shopping lists"],
        func = function()
          UI:ShoppingChanged(ns.AME.shopping:CopyGuildList(e.shopGuild))
        end,
      },
    })
    return
  end
  if e.header then
    return
  end
  if e.list and button == "RightButton" then
    UI:ListMenu(anchor, e.list)
    return
  end
  if e.guild and button == "RightButton" then
    W.Menu(anchor, {
      {
        text = L["Copy to my watchlists"],
        func = function()
          ns.AME.watch:CopyGuildList(e.guild)
          UI:WatchChanged()
        end,
      },
    })
    return
  end
  q.list, q.only = nil, nil
  if e.shop or e.shopGuild then
    q.list = e.shop and ("s:" .. e.shop) or ("sg:" .. e.shopGuild)
    self.offset = 0
    self:RenderCategories()
    self:RefreshMarket(true)
    return
  end
  if e.hidden then
    q.classID, q.subClassID = nil, nil
    q.list, q.only = "hidden", ns.AME.watch:Hidden()
  elseif e.guild then
    local g = ns.AME.watch.db.guild[e.guild]
    q.classID, q.subClassID = nil, nil
    q.list, q.only = "g:" .. e.guild, g and g.items
  elseif e.list then
    q.classID, q.subClassID = nil, nil
    q.list, q.only = e.list, ns.AME.watch:Lists()[e.list].items
  elseif e.all then
    q.classID, q.subClassID = nil, nil
  elseif e.subClassID then
    q.classID, q.subClassID = e.classID, e.subClassID
  elseif q.classID == e.classID and not q.subClassID and not e.pick then
    q.classID = nil -- clicking the open class again closes it
  else
    q.classID, q.subClassID = e.classID, nil
  end
  self.offset = 0
  self:RenderCategories()
  self:RefreshMarket(true)
end

function UI:CreateCategories(v, side)
  side.pane:Hide() -- the list pages itself (it can be long: every subclass)
  side.lines = {}
  local function line(i)
    local b = CreateFrame("Button", nil, side)
    b:SetHeight(CAT_H)
    b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * CAT_H)
    b:SetPoint("RIGHT", -4, 0)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    W.Fill(b.sel, W.COLORS.rowSelected)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    W.Fill(b.hl, W.COLORS.rowHover)
    b.text = W.Text(b, "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -34, 0)
    b.text:SetWordWrap(false)
    b.count = W.Text(b, "GameFontDisableSmall", "RIGHT")
    b.count:SetPoint("RIGHT", -4, 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
      if self.entry then
        UI:SelectCategory(self.entry, button, self)
      end
    end)
    side.lines[i] = b
    return b
  end
  side.rows = 22
  for i = 1, side.rows do
    line(i)
  end
  -- as many lines as the sidebar's height holds
  side:SetScript("OnSizeChanged", function(_, _, h)
    local n = math.max(1, math.floor(((h or 0) - 8) / CAT_H))
    for i = #side.lines + 1, n do
      line(i)
    end
    side.rows = n
    if UI.index then
      UI:RenderCategories()
    end
  end)
  side:EnableMouseWheel(true)
  side:SetScript("OnMouseWheel", function(_, delta)
    UI.catOffset = math.max(0, (UI.catOffset or 0) - delta * 2)
    UI:RenderCategories()
  end)
  v.side = side
end

-- is entry e the current selection?
local function selected(q, e)
  if e.newList or e.header then
    return false
  elseif e.guild then
    return q.list == "g:" .. e.guild
  elseif e.hidden then
    return q.list == "hidden"
  elseif e.shop then
    return q.list == "s:" .. e.shop
  elseif e.shopGuild then
    return q.list == "sg:" .. e.shopGuild
  elseif e.list then
    return q.list == e.list
  elseif q.list then
    return false
  elseif e.all then
    return q.classID == nil
  elseif e.subClassID then
    return q.classID == e.classID and q.subClassID == e.subClassID
  end
  return q.classID == e.classID and q.subClassID == nil
end

function UI:RenderCategories()
  local v = self.marketView
  local q = self.mq
  local entries = self:CategoryEntries()
  local side = v.side
  local rows = side.rows or #side.lines
  self.catOffset = math.min(self.catOffset or 0, math.max(0, #entries - rows))
  for i, b in ipairs(side.lines) do
    local e = i <= rows and entries[(self.catOffset or 0) + i] or nil
    b.entry = e
    if e then
      b:Show()
      b.sel:SetShown(selected(q, e))
      b.text:SetText(e.label)
      b.text:SetFontObject(e.subClassID and "GameFontHighlightSmall" or "GameFontNormalSmall")
      b.count:SetText(type(e.count) == "number" and W.Thousands(e.count) or e.count)
    else
      b:Hide()
    end
  end
  -- the compact dropdown: lists and classes (subclasses from the sidebar when wide)
  local options, current = {}, 1
  for _, e in ipairs(entries) do
    if not (e.newList or e.header or e.subClassID) then
      options[#options + 1] = { #options + 1, e.name or e.label, entry = e }
      if selected(q, e) or (e.classID and q.classID == e.classID) then
        current = #options
      end
    end
  end
  v.category.entries = options
  v.category:SetOptions(options)
  v.category:SetValue(current)
end

---------------------------------------------------------------------------------------------------------------------
-- columns and saved views

-- the columns switched off: defaults (optional ones) overridden by the chooser (Settings "marketColumns")
function UI:MarketHiddenColumns()
  local chosen = ns.Settings:Table("marketColumns")
  local hidden = {}
  for _, col in ipairs(COLUMNS) do
    local on = chosen[col.key]
    if on == nil then
      on = not col.optional
    end
    if not on and not col.item then
      hidden[col.key] = true
    end
  end
  return hidden
end

UI.MARKET_COMPACT_HIDDEN = { qty = true, score = true }

function UI:ApplyMarketColumns()
  local v = self.marketView
  local hidden = self:MarketHiddenColumns()
  if self.marketCompact then
    for key in pairs(UI.MARKET_COMPACT_HIDDEN) do
      hidden[key] = true
    end
  end
  v.table:SetUserHidden(hidden)
  self:UpdateColumnsButton()
end

function UI:UpdateColumnsButton()
  local v = self.marketView
  local n = v.table:HiddenCount()
  v.columns.label:SetText(n > 0 and L["Columns  ·  %d hidden"]:format(n) or L["Columns"])
end

function UI:ColumnMenu(anchor)
  local hidden = self:MarketHiddenColumns()
  local dropped = self.marketView.table.hiddenColumns or {}
  local entries = {}
  for c, col in ipairs(COLUMNS) do
    if not col.item then
      local name = type(col.label) == "function" and col.label() or col.label
      if dropped[c] and not hidden[col.key] then
        name = name .. " " .. W.Dim(L["(no room)"])
      end
      entries[#entries + 1] = {
        text = name,
        checked = not hidden[col.key],
        func = function()
          ns.Settings:Table("marketColumns")[col.key] = hidden[col.key] and true or false
          UI:ApplyMarketColumns()
        end,
      }
    end
  end
  W.Menu(anchor, entries)
end

-- the filter fields a saved view keeps
local VIEW_FIELDS = { "text", "minQuality", "minPrice", "maxPrice", "signal", "classID", "subClassID", "sortKey" }

function UI:SaveMarketView(name)
  if not name or name == "" then
    return
  end
  local q, saved = self.mq, {}
  for _, k in ipairs(VIEW_FIELDS) do
    saved[k] = q[k]
  end
  saved.ascending = q.ascending or false
  local views = ns.Settings:Table("marketViews")
  for _, view in ipairs(views) do
    if view.name == name then
      view.q = saved
      return
    end
  end
  views[#views + 1] = { name = name, q = saved }
end

function UI:ApplyMarketView(view)
  local v = self.marketView
  local q = { minQuality = 1 }
  for _, k in ipairs(VIEW_FIELDS) do
    q[k] = view.q[k]
  end
  q.ascending = view.q.ascending
  q.sortKey = q.sortKey or "score"
  self.mq = q
  v.search:SetText(q.text or "")
  q.text = view.q.text -- SetText's handler rewrote it
  v.minBox:SetText(q.minPrice and tostring(math.floor(q.minPrice / 10000)) or "")
  v.maxBox:SetText(q.maxPrice and tostring(math.floor(q.maxPrice / 10000)) or "")
  q.minPrice, q.maxPrice = view.q.minPrice, view.q.maxPrice
  self.offset = 0
  self:RenderCategories()
  self:RefreshMarket(true)
end

function UI:ViewsMenu(anchor)
  local views = ns.Settings:Table("marketViews")
  local entries = {}
  for _, view in ipairs(views) do
    entries[#entries + 1] = {
      text = view.name,
      func = function()
        UI:ApplyMarketView(view)
      end,
    }
  end
  entries[#entries + 1] = {
    text = W.Color("gold", L["Save these filters as a view..."]),
    func = function()
      W.Prompt("AME_SAVE_VIEW", L["Name for this view:"], function(name)
        UI:SaveMarketView(name)
      end)
    end,
  }
  for i, view in ipairs(views) do
    entries[#entries + 1] = {
      text = W.Dim(L["Delete %s"]:format(view.name)),
      func = function()
        table.remove(views, i)
      end,
    }
  end
  W.Menu(anchor, entries)
end

-- chips for the active filters (each removable), shown after the signal filter
function UI:UpdateMarketChips()
  local v, q = self.marketView, self.mq
  local chips = {}
  local function add(label, clear)
    chips[#chips + 1] = {
      label,
      function()
        clear()
        UI.offset = 0
        UI:RenderCategories()
        UI:RefreshMarket(true)
      end,
    }
  end
  if q.text and q.text ~= "" then
    add('"' .. q.text .. '"', function()
      v.search:SetText("")
      q.text = nil
    end)
  end
  if q.minQuality ~= 1 then
    for _, o in ipairs(QUALITIES) do
      if o[1] == q.minQuality then
        add(o[2], function()
          q.minQuality = 1
        end)
      end
    end
  end
  if q.minPrice then
    add(L["from %s"]:format(W.Money(q.minPrice, true)), function()
      v.minBox:SetText("")
      q.minPrice = nil
    end)
  end
  if q.maxPrice then
    add(L["up to %s"]:format(W.Money(q.maxPrice, true)), function()
      v.maxBox:SetText("")
      q.maxPrice = nil
    end)
  end
  if q.list then
    for _, e in ipairs(self:CategoryEntries()) do
      if (e.list and q.list == e.list) or (e.guild and q.list == "g:" .. e.guild) then
        add(e.name or "", function()
          q.list, q.only = nil, nil
        end)
      end
    end
  elseif q.classID then
    local name = q.subClassID and ns.ItemCache.SubClassName(q.classID, q.subClassID)
      or ns.ItemCache.ClassName(q.classID)
    add(name, function()
      q.classID, q.subClassID = nil, nil
    end)
  end
  v.chips:Set(chips)
  v:PlaceSignals()
end

---------------------------------------------------------------------------------------------------------------------
-- the view

-- The Market tab's area holds two modes (UI:SetMarketMode): this screener and the overview (MarketOverview.lua).
function UI:CreateMarketView(parent)
  local area = contentArea(parent)
  local v = CreateFrame("Frame", nil, area)
  v:SetAllPoints(area)
  self.marketView = v
  self.mq = { sortKey = "score", ascending = false, minQuality = 1 } -- Common+: hide grey junk by default
  local slots = UI.Slots(v, { toolbar = 22, chips = 20, left = SIDEBAR_W, status = true })
  v.slots = slots
  self:CreateCategories(v, slots.left)
  local bar, main = slots.toolbar, slots.main
  v.main = main

  -- toolbar: Screener | Overview, (compact: category), search, quality, price range ... views, columns
  v.mode, v.modeDrop = self:MarketModeSwitch(bar)
  v.mode:SetPoint("LEFT", 0, 0)
  v.modeDrop:SetPoint("LEFT", 0, 0)
  v.category = W.Dropdown(bar, 130, { { 1, L["All items"] } }, function(value)
    local o = v.category.entries and v.category.entries[value]
    if o then
      local e = setmetatable({ pick = true }, { __index = o.entry })
      UI:SelectCategory(e, "LeftButton", v.category)
    end
  end, { neutral = true })
  v.category:SetPoint("LEFT", v.modeDrop, "RIGHT", 6, 0)
  local search = W.Input(bar, {
    width = 160,
    hint = L["Search items..."],
    onChange = function(text) -- also on SetText: a Shift-clicked item fills the box
      UI.mq.text = text
      UI.offset = 0
      UI:RefreshMarket(true)
    end,
    clearOnEscape = true,
  })
  v.search = search

  local qualityOptions = {}
  for i, q in ipairs(QUALITIES) do
    local c = q[1] and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q[1]]
    qualityOptions[i] = { q[1], q[2], c and c.hex and c.hex:match("|c(%x+)") }
  end
  local quality = W.Dropdown(bar, 104, qualityOptions, function(value)
    UI.mq.minQuality = value
    UI.offset = 0
    UI:RefreshMarket(true)
  end, { default = 1 }) -- Common+
  quality:SetPoint("LEFT", search, "RIGHT", 8, 0)
  v.quality = quality

  local minBox = W.GoldInput(bar, L["min g"], function(g)
    UI.mq.minPrice = g and g * 10000 or nil
    UI.offset = 0
    UI:RefreshMarket(true)
  end)
  minBox:SetPoint("LEFT", quality, "RIGHT", 8, 0)
  local maxBox = W.GoldInput(bar, L["max g"], function(g)
    UI.mq.maxPrice = g and g * 10000 or nil
    UI.offset = 0
    UI:RefreshMarket(true)
  end)
  maxBox:SetPoint("LEFT", minBox, "RIGHT", 6, 0)
  v.minBox, v.maxBox = minBox, maxBox

  v.columns = W.Button(bar, L["Columns"], 116, 20, function(self)
    UI:ColumnMenu(self)
  end)
  v.columns:SetPoint("RIGHT", 0, 0)
  v.views = W.Button(bar, L["Views"] .. W.ARROW_DOWN, 72, 20, function(self)
    UI:ViewsMenu(self)
  end)
  v.views:SetPoint("RIGHT", v.columns, "LEFT", -6, 0)

  -- second row: signal filter (text + glyph + colour) and chips for the other active filters
  local signals = { { "all", L["All"] } }
  for _, key in ipairs({ "buy", "hold", "sell", "wait", "vendor", "disenchant" }) do
    signals[#signals + 1] = { key, W.SignalGlyph(key), W.SignalTone(key) }
  end
  v.signals = W.Segmented(slots.chips, signals, {
    minWidth = 40,
    height = 20,
    onSelect = function(key)
      UI.mq.signal = key ~= "all" and key or nil
      UI.offset = 0
      UI:RefreshMarket(true)
    end,
  })
  v.filtersLabel = W.Text(slots.chips, "GameFontDisableSmall")
  v.filtersLabel:SetText(L["Filters:"])
  v.chips = W.Chips(slots.chips, function()
    UI:ResetMarketFilters()
  end)
  -- Where the signal filter goes: the toolbar when there's room after the price boxes (before Views / Columns),
  -- else the chips row. The chips row shows only when it has something (filters, or the signal filter).
  function v:PlaceSignals()
    if slots.compact then
      self.signals:Hide()
      self.filtersLabel:Hide()
      slots:ShowBar(slots.chips, false)
      return
    end
    self.signals:Show()
    local modes = ns.Settings:Get("marketOverview") and ((self.mode:GetWidth() or 0) + 8) or 0
    local need = modes + 160 + 104 + 64 + 64 + 8 * 4 + 10 + (self.signals:GetWidth() or 0) + 10 + 72 + 116 + 6
    local onToolbar = (bar:GetWidth() or 0) >= need
    self.signals:SetParent(onToolbar and bar or slots.chips)
    self.signals:ClearAllPoints()
    self.filtersLabel:ClearAllPoints()
    self.chips:ClearAllPoints()
    if onToolbar then
      self.signals:SetPoint("LEFT", self.maxBox, "RIGHT", 10, 0)
      self.filtersLabel:SetPoint("LEFT", 0, 0)
      self.chips:SetPoint("LEFT", self.filtersLabel, "RIGHT", 8, 0)
    else
      self.signals:SetPoint("LEFT", slots.chips, "LEFT", 0, 0)
      self.filtersLabel:SetPoint("LEFT", self.signals, "RIGHT", 12, 0)
      self.chips:SetPoint("LEFT", self.filtersLabel, "RIGHT", 8, 0)
    end
    self.chips:SetPoint("RIGHT", slots.chips, "RIGHT", 0, 0)
    local hasChips = (self.chips.count or 0) > 0
    self.filtersLabel:SetShown(hasChips)
    slots:ShowBar(slots.chips, hasChips or not onToolbar)
  end
  bar:HookScript("OnSizeChanged", function()
    v:PlaceSignals()
  end)

  -- the list (shared DataTable component)
  v.table = ns.DataTable.New(main, {
    columns = COLUMNS,
    rows = 17,
    fill = true, -- rows fill the tab down to the status line
    top = 0,
    itemID = function(s)
      return s.itemID
    end,
    itemMenu = { hide = true },
    star = true,
    confidence = function(s)
      return ns.Analytics.Confidence(s, UI.index and UI.index.day)
    end,
    rowAlpha = function(s)
      local today = UI.index and UI.index.day
      return (today and s.day and today - s.day > UI.STALE_DAYS) and 0.5 or 1
    end,
    sort = { key = UI.mq.sortKey, ascending = UI.mq.ascending },
    onSort = function(key, ascending)
      UI.mq.sortKey, UI.mq.ascending = key, ascending
      UI:RefreshMarket(true)
    end,
    offset = {
      get = function()
        return UI.offset
      end,
      set = function(n)
        UI.offset = n
      end,
    },
    onClick = function(s)
      if IsShiftKeyDown() and ns.AME.ahOpen then
        ns.AME:SearchAuctionHouse(s.itemID)
      else
        UI:ShowItem(s.itemID)
      end
    end,
    tooltip = function(tip, s)
      tip:AddLine(" ")
      tip:AddLine(W.Signal(s.signal) .. "  " .. W.Dim(L["why:"]))
      for _, line in ipairs(UI.SignalReasons(s, UI.index and UI.index.day)) do
        tip:AddLine(line, 0.85, 0.85, 0.85, true)
      end
      if ns.AME.ahOpen then
        tip:AddLine(L["Shift-click to search the auction house"], 0.6, 0.6, 0.6)
      end
    end,
    status = true, -- counts under the table; where the data comes from goes in the window's footer
  })
  v.headers, v.rows, v.bar, v.status = v.table.headers, v.table.rows, v.table.bar, slots.status
  self:CreateShoppingPanel(v) -- a shopping list, shown instead of the table
  v.counts = v.table.status
  v.table.frame:HookScript("OnSizeChanged", function()
    UI:UpdateColumnsButton()
  end)
  self:ApplyMarketColumns()

  main:EnableMouseWheel(true)
  main:SetScript("OnMouseWheel", function(_, delta)
    v.table:Scroll(delta)
  end)

  -- narrow: a short signal filter on the toolbar, and More for the rest (Wait / Vendor, price range, views, columns)
  local short = { { "all", L["All"] } }
  for _, key in ipairs({ "buy", "hold", "sell" }) do
    short[#short + 1] = { key, W.SignalGlyph(key) }
  end
  v.signalsShort = W.Segmented(bar, short, {
    minWidth = 40,
    onSelect = function(key)
      UI.mq.signal = key ~= "all" and key or nil
      UI.offset = 0
      UI:RefreshMarket(true)
    end,
  })
  v.signalsShort:SetPoint("LEFT", quality, "RIGHT", 8, 0)
  v.more = W.Button(bar, L["More"], 64, 20, function(self)
    UI:MarketMoreMenu(self)
  end)
  v.more:SetPoint("LEFT", v.signalsShort, "RIGHT", 8, 0)

  function v:SetCompact(on)
    slots:SetCompact(on)
    UI.marketCompact = on
    UI:ApplyMarketColumns()
    -- Screener | Overview only when the Overview is switched on (Settings)
    local modes = ns.Settings:Get("marketOverview") and true or false
    self.category:SetShown(on)
    self.mode:SetShown(modes and not on)
    self.modeDrop:SetShown(modes and on)
    self.category:ClearAllPoints()
    if modes then
      self.category:SetPoint("LEFT", self.modeDrop, "RIGHT", 6, 0)
    else
      self.category:SetPoint("LEFT", 0, 0)
    end
    self.search:ClearAllPoints()
    if on then
      self.search:SetPoint("LEFT", self.category, "RIGHT", 6, 0)
      self.search:SetWidth(modes and 140 or 160)
    elseif modes then
      self.search:SetPoint("LEFT", self.mode, "RIGHT", 8, 0)
      self.search:SetWidth(160)
    else
      self.search:SetPoint("LEFT", 0, 0)
      self.search:SetWidth(SIDEBAR_W) -- lines up with the sidebar under it
    end
    for _, w in ipairs({ self.minBox, self.maxBox, self.views, self.columns }) do
      w:SetShown(not on)
    end
    self.signalsShort:SetShown(on)
    self.more:SetShown(on)
    self:PlaceSignals()
    -- last: anchor the mode switch again. Laying out the rows above re-anchors the toolbar, and in game the switch
    -- anchored before that lost its position - and with it the search box, quality and price range chained to it.
    self.mode:ClearAllPoints()
    self.mode:SetPoint("LEFT", bar, "LEFT", 0, 0)
    self.modeDrop:ClearAllPoints()
    self.modeDrop:SetPoint("LEFT", bar, "LEFT", 0, 0)
  end
  v:SetCompact(slots.compact)
  -- Lay the toolbar out again when the screener is shown, and once more on the next frame: anchors set before the
  -- toolbar was first drawn could stay unresolved in game, leaving the search box, quality and price range (chained
  -- to the Screener | Overview switch) invisible until something re-anchored them.
  local function relayout()
    v:SetCompact(slots.compact) -- re-anchors the switch last
  end
  v:HookScript("OnShow", function()
    relayout()
    C_Timer.After(0, function()
      if v:IsVisible() then
        relayout()
      end
    end)
  end)

  ns.ItemCache.OnNamesChanged(function()
    local q = UI.mq
    if not v:IsShown() then
      return
    end
    if (q.text and q.text ~= "") or q.minQuality or q.sortKey == "name" or q.sortKey == "__name" then
      UI:RefreshMarket(true)
    else
      UI:RenderMarket()
    end
  end)

  area.screener = v
  area.overview = self:CreateMarketOverview(area)
  function area:SetCompact(on)
    v:SetCompact(on)
    self.overview:SetCompact(on)
  end
  local overview = self:MarketMode() == "overview"
  v:SetShown(not overview)
  area.overview:SetShown(overview)
  area.slots = overview and area.overview.slots or slots
  self:SyncModes()
  return area
end

-- narrow window: what doesn't fit on the toolbar
function UI:MarketMoreMenu(anchor)
  local q, v = self.mq, self.marketView
  local function signal(key)
    return {
      text = W.SignalGlyph(key),
      checked = q.signal == key,
      func = function()
        q.signal = q.signal ~= key and key or nil
        UI.offset = 0
        UI:RefreshMarket(true)
      end,
    }
  end
  local function price(field, prompt, box)
    return {
      text = (field == "minPrice" and L["Minimum price..."] or L["Maximum price..."])
        .. (q[field] and "  " .. W.Money(q[field], true) or ""),
      func = function()
        W.Prompt("AME_PRICE_" .. field, prompt, function(text)
          local g = tonumber(text)
          box:SetText(g and tostring(g) or "")
          q[field] = g and g * 10000 or nil
          UI.offset = 0
          UI:RefreshMarket(true)
        end)
      end,
    }
  end
  W.Menu(anchor, {
    signal("wait"),
    signal("vendor"),
    signal("disenchant"),
    price("minPrice", L["Minimum price in gold (empty: none):"], v.minBox),
    price("maxPrice", L["Maximum price in gold (empty: none):"], v.maxBox),
    {
      text = L["Views..."],
      func = function()
        C_Timer.After(0, function()
          UI:ViewsMenu(anchor)
        end)
      end,
    },
    {
      text = L["Columns..."],
      func = function()
        C_Timer.After(0, function()
          UI:ColumnMenu(anchor)
        end)
      end,
    },
    {
      text = L["Clear all filters"],
      func = function()
        UI:ResetMarketFilters()
      end,
    },
  })
end

function UI:ResetMarketFilters()
  local v = self.marketView
  self.mq = { sortKey = self.mq.sortKey, ascending = self.mq.ascending, minQuality = 1 }
  v.quality:Reset()
  v.search:SetText("")
  self.mq.text = nil
  v.minBox:SetText("")
  v.maxBox:SetText("")
  self.mq.minPrice, self.mq.maxPrice = nil, nil
  self.offset = 0
  self:RenderCategories()
  self:RefreshMarket(true)
end

-- Rebuild the filtered, sorted list (only when the index, filters or sort change), then render.
function UI:RefreshMarket(force)
  if self:MarketMode() == "overview" then
    self:RefreshOverview() -- the same triggers (new index, other auction house) refresh the overview
  end
  local v = self.marketView
  if not (v and v:IsShown()) then
    return
  end
  local index, why = self:ViewIndex()
  if not index then
    self.list = nil
    local text = ns.AME:HistoryLoaded() and L["Building market index..."] or L["Loading history..."]
    if why == "empty" then
      text = L["No price history for the %s yet: scan there (any character on this account counts)."]:format(
        ns.HOUSE_LABEL[self:ViewHouse()] or self:ViewHouse()
      )
    end
    v.table:SetMessage(text)
    v.status:SetText("")
    v.counts:SetText("")
    for _, row in ipairs(v.rows) do
      row:Hide()
    end
    if not ns.AME:HistoryLoaded() then
      ns.AME:LoadHistory()
      ns.AME:RebuildIndex()
    end
    return
  end
  if index ~= self.index then
    self.index = index
    self.categories = ns.MarketFilter.Categories(index, itemInfo, ns.AME.watch and ns.AME.watch:Hidden())
    local ids = {}
    for id in pairs(index.items) do
      ids[#ids + 1] = id
    end
    ns.ItemCache.Warm(ids)
    self:RenderCategories()
    force = true
  end
  if force or not self.list then
    local avgKey = "avg" .. avgDays()
    for _, s in pairs(index.items) do -- "vs avg" follows the chosen average period
      local avg = s[avgKey]
      s.vsAvg = s.market and avg and avg > 0 and s.market / avg - 1 or nil
    end
    -- hidden items stay out of every list but their own
    self.mq.hide = self.mq.list ~= "hidden" and ns.AME.watch and ns.AME.watch:Hidden() or nil
    self.list, self.unnamed = ns.MarketFilter.Apply(index, self.mq, itemInfo)
  end
  self:RenderMarket()
end

-- Draw the visible rows from the cached list: cheap, so scrolling stays smooth.
function UI:RenderMarket()
  local v = self.marketView
  if v and v.shop and v:IsShown() and self:RenderShopping() then
    return -- a shopping list is shown instead of the screener
  end
  local list = self.list
  if not (v and list and v:IsShown()) then
    return
  end
  local q = self.mq
  v.signals:Select(q.signal or "all", true)
  v.signalsShort:Select((q.signal == nil and "all") or (v.signalsShort.byKey[q.signal] and q.signal) or false, true)
  v.quality:SetValue(q.minQuality)
  local total = #list
  local t = v.table
  t.sort.key, t.sort.ascending = q.sortKey, q.ascending
  t:SetData(list)
  t:Render()
  t:SetMessage(total == 0 and L["Nothing matches these filters. Clear some (chips above) or pick All items."] or nil)
  self.offset = t:Offset()

  local cache = ns.ItemCache
  v.counts:SetText(
    L["%d items  ·  showing %d-%d"]:format(
      total,
      math.min(total, self.offset + 1),
      math.min(total, self.offset + t.visible)
    )
  )
  local status =
    L["%s  ·  market data from %s"]:format(ns.ShardLabel(self:ViewShard()), date("%b %d", self.index.day * DAY))
  if cache.warmTotal and cache.warmDone and cache.warmDone < cache.warmTotal then
    status = status .. W.SEP .. L["loading item names %d/%d"]:format(cache.warmDone, cache.warmTotal)
  elseif (self.unnamed or 0) > 0 then
    status = status .. W.SEP .. L["%d items not searchable yet (names loading)"]:format(self.unnamed)
  end
  if q.list and q.only and q.list ~= "hidden" then
    local n = 0
    for _ in pairs(q.only) do
      n = n + 1
    end
    if n > total then
      status = status .. W.SEP .. L["%d watched items have no price history here yet"]:format(n - total)
    end
  end
  v.status:SetText(status)
  self:UpdateMarketChips()
end
