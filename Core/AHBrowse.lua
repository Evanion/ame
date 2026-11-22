-- A search of the auction house by name and filters (the Shopping tab's search box): the game's browse query, and
-- what comes back as rows with AME's view of each (cheapest, against the market price, the signal).
--
--   filters = { category (AuctionCategories path "3" / "3.2"), minLevel, maxLevel (required level),
--               minItemLevel, maxItemLevel, quality (lowest: 0 poor .. 5 legendary), maxPrice (copper, each),
--               exact, usable }
-- The game filters the name, category, required level, quality, exact name and "usable by you"; item level and price
-- are filtered here, on what comes back. Query and Rows are pure (the enums and categories are passed in).
local _, ns = ...

local B = { results = {}, text = nil }
ns.AHBrowse = B

B.MAX_RESULTS = 500 -- pages asked for until the game has them all, or this many
B.PAGE_DELAY = 0.1

-- quality -> the game's filter names, lowest first
B.QUALITY_FILTERS = {
  "PoorQuality",
  "CommonQuality",
  "UncommonQuality",
  "RareQuality",
  "EpicQuality",
  "LegendaryQuality",
  "ArtifactQuality",
}

-- the category a path picks in the game's category tree ("3" a top category, "3.2" one under it)
function B.Category(categories, path)
  if not (categories and path) then
    return nil
  end
  local top, sub = path:match("^(%d+)%.?(%d*)$")
  local c = categories[tonumber(top or "")]
  if c and sub ~= "" then
    c = c.subCategories and c.subCategories[tonumber(sub)]
  end
  return c
end

-- the dropdown's choices: every top category and the ones under it ({ path, label })
function B.CategoryOptions(categories)
  local out = {}
  for i, c in ipairs(categories or {}) do
    if c.name then
      out[#out + 1] = { tostring(i), c.name }
      for j, sub in ipairs(c.subCategories or {}) do
        if sub.name then
          out[#out + 1] = { i .. "." .. j, c.name .. " - " .. sub.name }
        end
      end
    end
  end
  return out
end

-- the game's browse query for a name and filters. filterEnum: Enum.AuctionHouseFilter; sortEnum:
-- Enum.AuctionHouseSortOrder; categories: AuctionCategories
function B.Query(text, f, filterEnum, sortEnum, categories)
  f = f or {}
  filterEnum = filterEnum or {}
  local filters = {}
  -- the qualities from the lowest asked for up (every one when none is: an empty list would mean none to some
  -- versions of the game, and the game's own window always sends them)
  for q = (f.quality or 0) + 1, #B.QUALITY_FILTERS do
    local v = filterEnum[B.QUALITY_FILTERS[q]]
    if v then
      filters[#filters + 1] = v
    end
  end
  if f.usable and filterEnum.UsableOnly then
    filters[#filters + 1] = filterEnum.UsableOnly
  end
  if f.exact and filterEnum.ExactMatch then
    filters[#filters + 1] = filterEnum.ExactMatch
  end
  local category = B.Category(categories, f.category)
  return {
    searchString = text or "",
    sorts = { { sortOrder = sortEnum and sortEnum.Price or 0, reverseSort = false } },
    filters = filters,
    itemClassFilters = category and category.filters or {},
    minLevel = f.minLevel,
    maxLevel = f.maxLevel,
  }
end

-- browse results -> rows, filtered by item level and price, cheapest first:
--   { key, ilvl, qty, cheapest, market, vs (cheapest / market - 1), signal }
-- index: the market index's items (AME's view of each), or nil
function B.Rows(results, f, index)
  f = f or {}
  local rows = {}
  for _, r in ipairs(results or {}) do
    local k = r.itemKey
    local key = k and ns.ItemKey(k.itemID, k.itemSuffix)
    local ilvl = k and k.itemLevel
    local price = r.minPrice
    local keep = key and price and price > 0 and (r.totalQuantity or 0) > 0
    if keep and f.minItemLevel and (ilvl or 0) < f.minItemLevel then
      keep = false
    end
    if keep and f.maxItemLevel and ilvl and ilvl > f.maxItemLevel then
      keep = false
    end
    if keep and f.maxPrice and price > f.maxPrice then
      keep = false
    end
    if keep then
      local s = index and index[key]
      local market = s and s.market
      rows[#rows + 1] = {
        key = key,
        ilvl = ilvl,
        qty = r.totalQuantity,
        cheapest = price,
        market = market,
        vs = market and market > 0 and price / market - 1 or nil,
        signal = s and s.signal,
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.cheapest ~= b.cheapest then
      return a.cheapest < b.cheapest
    end
    return a.key < b.key
  end)
  return rows
end

-- how many filters are set (the Filters button shows it)
function B.Count(f)
  local n = 0
  for _, k in ipairs({ "category", "minLevel", "maxLevel", "minItemLevel", "maxItemLevel", "maxPrice" }) do
    if f and f[k] then
      n = n + 1
    end
  end
  if f and (f.quality or 0) > 0 then
    n = n + 1
  end
  for _, k in ipairs({ "exact", "usable" }) do
    if f and f[k] then
      n = n + 1
    end
  end
  return n
end

-- A recent search's label: its text, then a short note of its filters ("Swords · lvl 40-50 · rare+")
function B.Label(text, f, categories)
  local parts = {}
  local c = B.Category(categories, f and f.category)
  local head = (text and text ~= "") and text or (c and c.name) or ns.L["Everything"]
  if c and text and text ~= "" then
    parts[#parts + 1] = c.name
  end
  if f and (f.minLevel or f.maxLevel) then
    parts[#parts + 1] = ns.L["lvl %s"]:format((f.minLevel or "") .. "-" .. (f.maxLevel or ""))
  end
  if f and (f.minItemLevel or f.maxItemLevel) then
    parts[#parts + 1] = ns.L["ilvl %s"]:format((f.minItemLevel or "") .. "-" .. (f.maxItemLevel or ""))
  end
  if f and (f.quality or 0) > 0 then
    local name = _G["ITEM_QUALITY" .. f.quality .. "_DESC"]
    parts[#parts + 1] = (type(name) == "string" and name or tostring(f.quality)):lower() .. "+"
  end
  return head, table.concat(parts, " · ")
end

---------------------------------------------------------------------------------------------------------------------
-- in game: send it, and page through the results

local function api()
  return C_AuctionHouse
end

-- search: send the query; onChange() as results come in
function B:Search(text, f, onChange)
  local a = api()
  if not (a and a.SendBrowseQuery) then
    return false
  end
  self.text, self.filters, self.onChange = text, f, onChange
  self.active, self.pending = true, false
  self.results = {}
  local query =
    B.Query(text, f, Enum and Enum.AuctionHouseFilter, Enum and Enum.AuctionHouseSortOrder, _G.AuctionCategories)
  local ok = pcall(a.SendBrowseQuery, query)
  if not ok then
    self.active = false
  end
  return ok
end

function B:OnResults()
  local a = api()
  if not (self.active and a) then
    return
  end
  self.results = a.GetBrowseResults and a.GetBrowseResults() or {}
  if self.onChange then
    self.onChange()
  end
  local full = a.HasFullBrowseResults and a.HasFullBrowseResults()
  if full or #self.results >= B.MAX_RESULTS then
    self.active = false
    return
  end
  if not self.pending and a.RequestMoreBrowseResults then
    self.pending = true
    C_Timer.After(B.PAGE_DELAY, function()
      self.pending = false
      if self.active then
        pcall(a.RequestMoreBrowseResults)
      end
    end)
  end
end

function B:Stop()
  self.active = false
end

if CreateFrame then -- not in the pure specs
  local events = CreateFrame("Frame")
  pcall(events.RegisterEvent, events, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  pcall(events.RegisterEvent, events, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
  pcall(events.RegisterEvent, events, "AUCTION_HOUSE_CLOSED")
  events:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_CLOSED" then
      B:Stop()
    else
      B:OnResults()
    end
  end)
end
