-- Market tab: the screener over the market index, with the category / watchlist sidebar and filters.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI
local DAY = ns.DAY
local avgDays, contentArea = UI.AvgDays, UI.ContentArea

---------------------------------------------------------------------------------------------------------------------
-- Market view (screener)

local COLUMNS = {
  { key = "name", label = L["Item"], width = 190, item = true, term = "name" },
  { key = "market", label = L["Market"], width = 86, format = "money", term = "market" },
  {
    key = "avg",
    width = 86,
    term = "avg",
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
  { key = "change7", label = L["7d"], width = 62, format = "pct", term = "change7" },
  { key = "vol30", label = L["Volatility"], width = 70, format = "plainpct", term = "vol30" },
  { key = "qty", label = L["Supply"], width = 52, term = "qty" },
  { key = "sellRate", label = L["Sells/d"], width = 58, format = "rate", term = "sellRate" },
  {
    key = "signal",
    label = L["Signal"],
    width = 50,
    format = "signal",
    term = "signal",
    sortKey = "signalRank",
    ascendingFirst = true,
  },
  { key = "score", label = L["Score"], width = 50, term = "score" },
}
local ROWS = 17
local SIDEBAR_W = 170
local CAT_ROWS = 22
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

local function goldBox(parent, hint, onChange)
  local box = W.Input(parent)
  box:SetSize(58, 20)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box.hint = W.Text(box, "GameFontDisableSmall")
  box.hint:SetPoint("LEFT", 6, 0)
  box.hint:SetPoint("RIGHT", -6, 0) -- clipped to the box (translations run longer)
  box.hint:SetJustifyH("LEFT")
  box.hint:SetWordWrap(false)
  box.hint:SetText(hint)
  box:SetScript("OnTextChanged", function(self)
    self.hint:SetShown(self:GetText() == "")
    onChange(tonumber(self:GetText()))
  end)
  box:SetScript("OnEnterPressed", box.ClearFocus)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  return box
end

-- category sidebar: "All items", classes in AH order, the selected class's subclasses indented
function UI:CreateCategories(v)
  local side = CreateFrame("Frame", nil, v, "BackdropTemplate")
  W.Skin(side, W.COLORS.panel)
  side:SetPoint("TOPLEFT", 0, 0)
  side:SetPoint("BOTTOMLEFT", 0, 0)
  side:SetWidth(SIDEBAR_W)
  side.lines = {}
  for i = 1, CAT_ROWS do
    local b = CreateFrame("Button", nil, side)
    b:SetSize(SIDEBAR_W - 8, CAT_H)
    b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * CAT_H)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(W.COLORS.accent[1], W.COLORS.accent[2], W.COLORS.accent[3], 0.2)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.06)
    b.text = W.Text(b, "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -34, 0)
    b.text:SetWordWrap(false)
    b.count = W.Text(b, "GameFontDisableSmall", "RIGHT")
    b.count:SetPoint("RIGHT", -4, 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
      local e = self.entry
      if not e then
        return
      end
      local q = UI.mq
      if e.newList then
        UI:PromptNewList()
        return
      end
      if e.header then
        return
      end
      if e.list and button == "RightButton" then
        UI:ListMenu(self, e.list)
        return
      end
      if e.guild and button == "RightButton" then
        W.Menu(self, {
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
      if e.guild then
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
      elseif q.classID == e.classID and not q.subClassID then
        q.classID = nil -- clicking the open class again closes it
      else
        q.classID, q.subClassID = e.classID, nil
      end
      UI.offset = 0
      UI:RenderCategories()
      UI:RefreshMarket(true)
    end)
    side.lines[i] = b
  end
  side:EnableMouseWheel(true)
  side:SetScript("OnMouseWheel", function(_, delta)
    UI.catOffset = math.max(0, (UI.catOffset or 0) - delta * 2)
    UI:RenderCategories()
  end)
  v.side = side
end

function UI:RenderCategories()
  local v = self.marketView
  local q = self.mq
  local entries = { { all = true, label = L["All items"], count = self.index and self.index.count or 0 } }
  local watch = ns.AME.watch
  if watch then
    for i, l in ipairs(watch:Lists()) do
      entries[#entries + 1] = {
        list = i,
        label = W.StarInline(12) .. " " .. l.name .. (l.shared and (" |cff33ccff%s|r"):format(L["shared"]) or ""),
        count = watch:Count(i),
      }
    end
    entries[#entries + 1] = { newList = true, label = "|cff999999+ " .. L["New list"] .. "|r", count = "" }
    local guild = watch:GuildLists()
    if #guild > 0 then
      entries[#entries + 1] = { header = true, label = "|cff999999" .. L["Guild watchlists"] .. "|r", count = "" }
      for _, g in ipairs(guild) do
        local n = 0
        for _ in pairs(g.items) do
          n = n + 1
        end
        entries[#entries + 1] = {
          guild = g.key,
          label = ("   %s |cff999999(%s)|r"):format(g.name, g.owner),
          count = n,
        }
      end
    end
  end
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
  self.catOffset = math.min(self.catOffset or 0, math.max(0, #entries - CAT_ROWS))
  for i, b in ipairs(v.side.lines) do
    local e = entries[(self.catOffset or 0) + i]
    b.entry = e
    if e then
      b:Show()
      local selected
      if e.newList or e.header then
        selected = false
      elseif e.guild then
        selected = q.list == "g:" .. e.guild
      elseif e.list then
        selected = q.list == e.list
      elseif q.list then
        selected = false
      elseif e.all then
        selected = q.classID == nil
      elseif e.subClassID then
        selected = q.classID == e.classID and q.subClassID == e.subClassID
      else
        selected = q.classID == e.classID and q.subClassID == nil
      end
      b.sel:SetShown(selected)
      b.text:SetText(e.label)
      b.text:SetFontObject(e.subClassID and "GameFontHighlightSmall" or "GameFontNormalSmall")
      b.count:SetText(e.count)
    else
      b:Hide()
    end
  end
end

function UI:CreateMarketView(parent)
  local v = contentArea(parent)
  self.marketView = v
  self.mq = { sortKey = "score", ascending = false, minQuality = 1 } -- Common+: hide grey junk by default
  self:CreateCategories(v)

  local main = CreateFrame("Frame", nil, v)
  main:SetPoint("TOPLEFT", SIDEBAR_W + 10, 0)
  main:SetPoint("BOTTOMRIGHT", 0, 0)
  v.main = main

  -- toolbar: search, quality, price range, signals, reset
  local search = W.Input(main)
  search:SetSize(170, 20)
  search:SetPoint("TOPLEFT", 6, 0)
  search:SetAutoFocus(false)
  search.hint = W.Text(search, "GameFontDisableSmall")
  search.hint:SetPoint("LEFT", 6, 0)
  search.hint:SetPoint("RIGHT", -6, 0) -- clipped to the box (translations run longer)
  search.hint:SetJustifyH("LEFT")
  search.hint:SetWordWrap(false)
  search.hint:SetText(L["Search items..."])
  search:SetScript("OnTextChanged", function(self)
    self.hint:SetShown(self:GetText() == "")
    UI.mq.text = self:GetText()
    UI.offset = 0
    UI:RefreshMarket(true)
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)
  search:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
  end)
  v.search = search

  local qualityOptions = {}
  for i, q in ipairs(QUALITIES) do
    local c = q[1] and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q[1]]
    qualityOptions[i] = { q[1], q[2], c and c.hex and c.hex:match("|c(%x+)") }
  end
  local quality = W.Dropdown(main, 104, qualityOptions, function(value)
    UI.mq.minQuality = value
    UI.offset = 0
    UI:RefreshMarket(true)
  end)
  quality:SetPoint("LEFT", search, "RIGHT", 8, 0)
  quality.defaultIndex = 2
  quality:SetIndex(2)
  v.quality = quality

  local minBox = goldBox(main, L["min g"], function(g)
    UI.mq.minPrice = g and g * 10000 or nil
    UI.offset = 0
    UI:RefreshMarket(true)
  end)
  minBox:SetPoint("LEFT", quality, "RIGHT", 10, 0)
  local maxBox = goldBox(main, L["max g"], function(g)
    UI.mq.maxPrice = g and g * 10000 or nil
    UI.offset = 0
    UI:RefreshMarket(true)
  end)
  maxBox:SetPoint("LEFT", minBox, "RIGHT", 6, 0)
  v.minBox, v.maxBox = minBox, maxBox

  local filters = { { nil, L["All"] }, { "buy", L["Buy"] }, { "hold", L["Hold"] }, { "sell", L["Sell"] } }
  v.filterButtons = {}
  for i, fdef in ipairs(filters) do
    local b = W.Button(main, fdef[2], 46, 20, function()
      UI.mq.signal = fdef[1]
      UI.offset = 0
      UI:RefreshMarket(true)
    end)
    b.key = fdef[1] or "all"
    if i == 1 then
      b:SetPoint("LEFT", maxBox, "RIGHT", 10, 0)
    else
      b:SetPoint("LEFT", v.filterButtons[i - 1], "RIGHT", 3, 0)
    end
    v.filterButtons[i] = b
  end
  local reset = W.Button(main, L["Reset"], 52, 20, function()
    UI:ResetMarketFilters()
  end)
  reset:SetPoint("LEFT", v.filterButtons[#filters], "RIGHT", 10, 0)

  -- the list (shared DataTable component)
  v.table = ns.DataTable.New(main, {
    columns = COLUMNS,
    rows = ROWS,
    top = -28,
    itemID = function(s)
      return s.itemID
    end,
    star = true,
    confidence = function(s)
      return ns.Analytics.Confidence(s, UI.index and UI.index.day)
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
    tooltip = function(tip)
      if ns.AME.ahOpen then
        tip:AddLine(L["Shift-click to search the auction house"], 0.6, 0.6, 0.6)
      end
    end,
  })
  v.headers, v.rows, v.bar = v.table.headers, v.table.rows, v.table.bar

  v.status = W.Text(main, "GameFontDisableSmall", "LEFT")
  v.status:SetPoint("BOTTOMLEFT", 2, 0)

  main:EnableMouseWheel(true)
  main:SetScript("OnMouseWheel", function(_, delta)
    v.table:Scroll(delta)
  end)

  ns.ItemCache.OnNamesChanged(function()
    local q = UI.mq
    if not v:IsShown() then
      return
    end
    if (q.text and q.text ~= "") or q.minQuality or q.sortKey == "name" then
      UI:RefreshMarket(true)
    else
      UI:RenderMarket()
    end
  end)
  return v
end

function UI:ResetMarketFilters()
  local v = self.marketView
  self.mq = { sortKey = self.mq.sortKey, ascending = self.mq.ascending, minQuality = 1 }
  v.quality:SetIndex(v.quality.defaultIndex)
  v.search:SetText("")
  v.minBox:SetText("")
  v.maxBox:SetText("")
  self.offset = 0
  self:RenderCategories()
  self:RefreshMarket(true)
end

-- Rebuild the filtered, sorted list (only when the index, filters or sort change), then render.
function UI:RefreshMarket(force)
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
    v.status:SetText(text)
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
    self.categories = ns.MarketFilter.Categories(index, itemInfo)
    local ids = {}
    for id in pairs(index.items) do
      ids[#ids + 1] = id
    end
    ns.ItemCache.Warm(ids)
    self:RenderCategories()
    force = true
  end
  if force or not self.list then
    self.list, self.unnamed = ns.MarketFilter.Apply(index, self.mq, itemInfo)
  end
  self:RenderMarket()
end

-- Draw the visible rows from the cached list: cheap, so scrolling stays smooth.
function UI:RenderMarket()
  local v = self.marketView
  local list = self.list
  if not (v and list and v:IsShown()) then
    return
  end
  local q = self.mq
  for _, b in ipairs(v.filterButtons) do
    b:SetSelected(b.key == (q.signal or "all"))
  end
  v.quality:SetIndex(v.quality.index)
  local total = #list
  local t = v.table
  t.sort.key, t.sort.ascending = q.sortKey, q.ascending
  t:SetData(list)
  t:Render()
  self.offset = t:Offset()

  local cache = ns.ItemCache
  local status = L["%d items  -  showing %d-%d  -  index from %s"]:format(
    total,
    math.min(total, self.offset + 1),
    math.min(total, self.offset + ROWS),
    date("%b %d", self.index.day * DAY)
  )
  if cache.warmTotal and cache.warmDone and cache.warmDone < cache.warmTotal then
    status = status .. "  -  " .. L["loading item names %d/%d"]:format(cache.warmDone, cache.warmTotal)
  elseif (self.unnamed or 0) > 0 then
    status = status .. "  -  " .. L["%d items not searchable yet (names loading)"]:format(self.unnamed)
  end
  if q.list and q.only then
    local n = 0
    for _ in pairs(q.only) do
      n = n + 1
    end
    if n > total then
      status = status .. "  -  " .. L["%d watched items have no price history here yet"]:format(n - total)
    end
  end
  v.status:SetText(status)
end
