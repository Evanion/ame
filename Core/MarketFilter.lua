-- Market screener filtering: AH-style categories, name search, quality, price range and signal filters over the
-- market index. Pure: item facts come from an injected info(itemID) function returning
--   { classID, subClassID, name (nil until the client has the item cached), quality }
local _, ns = ...

local MarketFilter = {}
ns.MarketFilter = MarketFilter

-- auction house category order (item class IDs), like the AH and Auctionator; unknown classes go last
MarketFilter.CLASS_ORDER = { 2, 4, 1, 3, 8, 0, 16, 7, 9, 19, 17, 12, 15, 5, 6, 11, 13, 18 }

local rank = {}
for i, classID in ipairs(MarketFilter.CLASS_ORDER) do
  rank[classID] = i
end

local function classRank(classID)
  return rank[classID] or (100 + classID)
end

-- Category tree for the items in the index:
--   { { classID, count, subs = { { subClassID, count }, ... } }, ... } in AH order (subclasses by id)
function MarketFilter.Categories(index, info)
  local byClass = {}
  for itemID in pairs(index.items) do
    local i = info(itemID)
    if i and i.classID then
      local c = byClass[i.classID]
      if not c then
        c = { classID = i.classID, count = 0, subs = {}, bySub = {} }
        byClass[i.classID] = c
      end
      c.count = c.count + 1
      local sub = i.subClassID or 0
      local s = c.bySub[sub]
      if not s then
        s = { subClassID = sub, count = 0 }
        c.bySub[sub] = s
        c.subs[#c.subs + 1] = s
      end
      s.count = s.count + 1
    end
  end
  local out = {}
  for _, c in pairs(byClass) do
    c.bySub = nil
    table.sort(c.subs, function(a, b)
      return a.subClassID < b.subClassID
    end)
    out[#out + 1] = c
  end
  table.sort(out, function(a, b)
    return classRank(a.classID) < classRank(b.classID)
  end)
  return out
end

-- Items whose (cached) name contains text, best first: exact name, then names starting with it, then the rest;
-- shorter names first within each group. returns { { itemID, name, quality }, ... } (at most limit)
function MarketFilter.FindByName(index, text, info, limit)
  local needle = (text or ""):lower()
  if needle == "" then
    return {}
  end
  local hits = {}
  for itemID in pairs(index and index.items or {}) do
    local i = info(itemID)
    local name = i and i.name
    if name then
      local lower = name:lower()
      local at = lower:find(needle, 1, true)
      if at then
        local order = lower == needle and 0 or at == 1 and 1 or 2
        hits[#hits + 1] = { itemID = itemID, name = name, quality = i.quality, rank = order }
      end
    end
  end
  table.sort(hits, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    if #a.name ~= #b.name then
      return #a.name < #b.name
    end
    return a.name < b.name
  end)
  for k = (limit or 10) + 1, #hits do
    hits[k] = nil
  end
  return hits
end

-- query: { text, classID, subClassID, only (set of itemIDs, e.g. a watchlist), minQuality, signal ("buy"/"sell"),
--          minPrice, maxPrice (copper, on market),
--          sortKey, ascending }
-- Name search only matches items whose name is known (info().name); returns list, unnamed (count of items that
-- couldn't be checked against the search text yet).
function MarketFilter.Apply(index, query, info)
  local text = query.text and query.text ~= "" and query.text:lower() or nil
  local key = query.sortKey or "score"
  if key == "__name" then -- the Item column header (DataTable's sort key for item columns)
    key = "name"
  end
  local list, unnamed = {}, 0
  for itemID, s in pairs(index.items) do
    local ok = s[key] ~= nil or key == "name"
    if ok and query.only and not query.only[itemID] then
      ok = false
    end
    if ok and query.signal and s.signal ~= query.signal then
      ok = false
    end
    if ok and query.minPrice and (s.market or 0) < query.minPrice then
      ok = false
    end
    if ok and query.maxPrice and (s.market or math.huge) > query.maxPrice then
      ok = false
    end
    local i
    if ok and (query.classID or query.minQuality or text or key == "name") then
      i = info(itemID) or {}
      if query.classID and i.classID ~= query.classID then
        ok = false
      elseif query.subClassID and i.subClassID ~= query.subClassID then
        ok = false
      elseif query.minQuality and (i.quality or -1) < query.minQuality then
        ok = false
      elseif text then
        if not i.name then
          unnamed = unnamed + 1
          ok = false
        elseif not i.name:lower():find(text, 1, true) then
          ok = false
        end
      end
    end
    if ok then
      list[#list + 1] = s
    end
  end

  local asc = query.ascending
  if key == "name" then
    local names = {}
    for _, s in ipairs(list) do
      local i = info(s.itemID)
      names[s.itemID] = i and i.name or ("~" .. s.itemID)
    end
    table.sort(list, function(a, b)
      local x, y = names[a.itemID], names[b.itemID]
      if x == y then
        return a.itemID < b.itemID
      end
      if asc then
        return x > y
      end
      return x < y
    end)
  else
    table.sort(list, function(a, b)
      local x, y = a[key], b[key]
      if x == y then
        return a.itemID < b.itemID
      end
      if asc then
        return x < y
      end
      return x > y
    end)
  end
  return list, unnamed
end
