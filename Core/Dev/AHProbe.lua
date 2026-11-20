-- Dev-only: /amedev ah [item]. Answers what telling sales from expiries needs to know about the client's auction
-- house APIs, and saves it to AME_DB.dev.ahProbe (read from the SavedVariables file after /reload). Run it at the
-- auction house right after a full scan, and after searching the item (a commodity like Raptor Hide). Never ships
-- (Core/Dev is stripped from packages).
--   - which functions and strings exist (time-left calls, mail subjects, chat messages, listing durations)
--   - the full scan: does every row carry time left (GetReplicateItemTimeLeft) and an owner? one row per auction
--     or per price for commodities? (the item's rows, prices and quantities)
--   - the item's commodity / item search results: every field (auctionID, owners, timeLeftSeconds?)
--   - your own auctions: every field
local _, ns = ...

local Dev = ns.Dev

local function safe(v)
  local secret = _G.issecretvalue
  if secret and secret(v) then
    return "<secret>"
  end
  if type(v) == "function" or type(v) == "userdata" then
    return "<" .. type(v) .. ">"
  end
  if type(v) == "table" then
    local out = {}
    for k, x in pairs(v) do
      out[tostring(k)] = safe(x)
    end
    return out
  end
  return v
end

local function has(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then
      return false
    end
    t = t[part]
  end
  return type(t) == "function"
end

local FUNCTIONS = {
  "C_AuctionHouse.ReplicateItems",
  "C_AuctionHouse.GetNumReplicateItems",
  "C_AuctionHouse.GetReplicateItemInfo",
  "C_AuctionHouse.GetReplicateItemLink",
  "C_AuctionHouse.GetReplicateItemTimeLeft",
  "C_AuctionHouse.GetReplicateItemBattlePetInfo",
  "C_AuctionHouse.GetTimeLeftBandInfo",
  "C_AuctionHouse.GetNumCommoditySearchResults",
  "C_AuctionHouse.GetCommoditySearchResultInfo",
  "C_AuctionHouse.GetNumItemSearchResults",
  "C_AuctionHouse.GetItemSearchResultInfo",
  "C_AuctionHouse.MakeItemKey",
  "C_AuctionHouse.GetNumOwnedAuctions",
  "C_AuctionHouse.GetOwnedAuctionInfo",
  "C_AuctionHouse.CancelAuction",
  "C_AuctionHouse.GetAuctionInfoByID",
  "C_AuctionHouse.GetItemCommodityStatus",
  "GetInboxItem",
  "GetInboxHeaderInfo",
  "GetInboxInvoiceInfo",
}

local STRINGS = {
  "AUCTION_EXPIRED_MAIL_SUBJECT",
  "AUCTION_REMOVED_MAIL_SUBJECT",
  "AUCTION_SOLD_MAIL_SUBJECT",
  "AUCTION_OUTBID_MAIL_SUBJECT",
  "AUCTION_WON_MAIL_SUBJECT",
  "ERR_AUCTION_SOLD_S",
  "ERR_AUCTION_EXPIRED_S",
  "ERR_AUCTION_REMOVED_S",
  "AUCTION_DURATION_ONE",
  "AUCTION_DURATION_TWO",
  "AUCTION_DURATION_THREE",
  "AUCTION_TIME_LEFT1",
  "AUCTION_TIME_LEFT2",
  "AUCTION_TIME_LEFT3",
  "AUCTION_TIME_LEFT4",
}

local function itemArg(msg)
  msg = msg or ""
  return tonumber(msg:match("item:(%d+)")) or tonumber(msg:match("(%d+)"))
end

-- every row of the last full scan still in the client: counts, and the item's own rows
local function probeReplicate(out, itemID)
  local ah = C_AuctionHouse
  if not (has("C_AuctionHouse.GetNumReplicateItems") and has("C_AuctionHouse.GetReplicateItemInfo")) then
    return
  end
  local n = ah.GetNumReplicateItems() or 0
  local r = { rows = n, sample = {}, timeLeft = {}, owners = 0, ownersOthers = 0, itemRows = {}, rowsPerItem = {} }
  out.replicate = r
  local timeLeft = has("C_AuctionHouse.GetReplicateItemTimeLeft") and ah.GetReplicateItemTimeLeft
  local perItem = {}
  local me = UnitName("player")
  for i = 0, math.min(n, 200000) - 1 do
    local info = { ah.GetReplicateItemInfo(i) }
    local tl
    if timeLeft then
      local ok, v = pcall(timeLeft, i)
      tl = ok and v or ("error: " .. tostring(v))
    end
    local key = tostring(safe(tl))
    r.timeLeft[key] = (r.timeLeft[key] or 0) + 1
    local owner = info[14]
    if owner ~= nil and owner ~= "" then
      r.owners = r.owners + 1
      if safe(owner) ~= me then
        r.ownersOthers = r.ownersOthers + 1
      end
    end
    local id = info[17]
    if id then
      perItem[id] = (perItem[id] or 0) + 1
    end
    if i < 15 then
      local row = {}
      for k = 1, 18 do
        row[k] = safe(info[k])
      end
      row.timeLeft = safe(tl)
      r.sample[#r.sample + 1] = row
    end
    if itemID and id == itemID and #r.itemRows < 60 then
      r.itemRows[#r.itemRows + 1] = { count = info[3], buyout = info[10], owner = safe(owner), timeLeft = safe(tl) }
    end
  end
  -- items with the most rows: one row per auction (many) or per price (few)?
  local top = {}
  for id, c in pairs(perItem) do
    top[#top + 1] = { id = id, rows = c }
  end
  table.sort(top, function(a, b)
    return a.rows > b.rows
  end)
  for i = 1, math.min(10, #top) do
    r.rowsPerItem[i] = top[i]
  end
  r.items = #top
end

local function probeSearch(out, itemID)
  local ah = C_AuctionHouse
  if not itemID then
    return
  end
  local s = { commodity = {}, item = {} }
  out.search = s
  if has("C_AuctionHouse.GetNumCommoditySearchResults") then
    local n = ah.GetNumCommoditySearchResults(itemID) or 0
    s.commodityCount = n
    for i = 1, math.min(n, 15) do
      s.commodity[i] = safe(ah.GetCommoditySearchResultInfo(itemID, i))
    end
  end
  if has("C_AuctionHouse.MakeItemKey") and has("C_AuctionHouse.GetNumItemSearchResults") then
    local key = ah.MakeItemKey(itemID)
    local n = ah.GetNumItemSearchResults(key) or 0
    s.itemCount = n
    for i = 1, math.min(n, 15) do
      s.item[i] = safe(ah.GetItemSearchResultInfo(key, i))
    end
  end
end

function Dev.ProbeAH(say, msg)
  local out = { at = GetServerTime(), functions = {}, strings = {}, bands = {}, owned = {} }
  for _, f in ipairs(FUNCTIONS) do
    out.functions[f] = has(f)
  end
  for _, k in ipairs(STRINGS) do
    out.strings[k] = safe(_G[k])
  end
  local ah = C_AuctionHouse
  if has("C_AuctionHouse.GetTimeLeftBandInfo") then
    for band = 0, 4 do
      local ok, a, b = pcall(ah.GetTimeLeftBandInfo, band)
      out.bands[band] = ok and { safe(a), safe(b) } or ("error: " .. tostring(a))
    end
  end
  local itemID = itemArg(msg)
  out.itemID = itemID
  probeReplicate(out, itemID)
  probeSearch(out, itemID)
  if has("C_AuctionHouse.GetNumOwnedAuctions") then
    for i = 1, math.min(ah.GetNumOwnedAuctions() or 0, 10) do
      out.owned[i] = safe(ah.GetOwnedAuctionInfo(i))
    end
  end
  AME_DB.dev.ahProbe = out

  local r = out.replicate
  if r then
    local bands = {}
    for k, c in pairs(r.timeLeft) do
      bands[#bands + 1] = k .. "=" .. c
    end
    say(
      "full scan in the client: %d rows, %d items; time left: %s; owner on %d rows (%d not you)",
      r.rows,
      r.items or 0,
      table.concat(bands, ", "),
      r.owners,
      r.ownersOthers
    )
    if itemID then
      say("item %d: %d rows in the full scan", itemID, #r.itemRows)
    end
  else
    say("no full scan API")
  end
  local s = out.search
  if s then
    local first = s.commodity[1] or s.item[1]
    local fields = {}
    for k, v in pairs(type(first) == "table" and first or {}) do
      if type(v) ~= "table" then
        fields[#fields + 1] = k .. "=" .. tostring(v)
      end
    end
    table.sort(fields)
    say(
      "search: %d commodity rows, %d item rows; first: %s",
      s.commodityCount or 0,
      s.itemCount or 0,
      #fields > 0 and table.concat(fields, " ") or "none (search the item first)"
    )
  end
  say("%d of your auctions; saved - /reload to write it to disk", #out.owned)
end
