-- WoW glue for the portfolio: AH sales and purchases from auction mail invoices, and what you hold (bags, bank,
-- active auctions) per character, account-wide. Logic lives in Ledger.lua and Portfolio.lua.
local _, ns = ...

local Trading = {}
ns.Trading = Trading

Trading.MAIL_DAYS = 30 -- auction mail stays this long; a mail's age comes from its days left

local function api(name)
  return (C_Container and C_Container[name]) or _G[name]
end

-- item name for an ID when the client knows it
local function W_ItemName(itemID)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return getInfo and getInfo(itemID) or nil
end

local function charKey()
  return ns.AME:MarketRealmName() .. ":" .. (UnitName("player") or "?")
end
Trading.CharKey = charKey

function Trading:Init()
  AME_DB.ledger = AME_DB.ledger or {}
  AME_DB.holdings = AME_DB.holdings or {}
  self.ledger = ns.Ledger.New(AME_DB.ledger)
  ns.AME.ledger = self.ledger
  self.ledger:Prune(GetServerTime())
end

function Trading:Holdings()
  return AME_DB.holdings
end

local function mine()
  local key = charKey()
  local h = AME_DB.holdings[key]
  if not h then
    h = {}
    AME_DB.holdings[key] = h
  end
  return h
end

-- soulbound: can't be sold, so it isn't stock. The slot info usually says; otherwise ask the item API.
local function isBound(bag, slot, flag)
  if flag ~= nil then
    return flag and true or false
  end
  if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
    local ok, bound = pcall(function()
      return C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot))
    end)
    return ok and bound == true
  end
  return false
end

-- item counts in container bags first..last (soulbound items left out: only what you could sell counts)
local function countBags(first, last)
  local numSlots, itemInfo = api("GetContainerNumSlots"), api("GetContainerItemInfo")
  if not (numSlots and itemInfo) then
    return nil
  end
  local out = {}
  for bag = first, last do
    for slot = 1, numSlots(bag) or 0 do
      local a, b, _, _, _, _, _, _, _, id, bound = itemInfo(bag, slot)
      local itemID, count
      if type(a) == "table" then -- C_Container: an info table
        itemID, count, bound = a.itemID, a.stackCount, a.isBound
      else -- classic: texture, count, ..., itemID (10th), isBound (11th)
        itemID, count = id, b
      end
      if itemID and not isBound(bag, slot, bound) then
        out[itemID] = (out[itemID] or 0) + (count or 1)
      end
    end
  end
  return out
end

function Trading:ScanBags()
  local reagent = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
  local bags = countBags(0, math.max(NUM_BAG_SLOTS or 4, reagent))
  if bags then
    local h = mine()
    h.bags, h.t = bags, GetServerTime()
  end
end

function Trading:ScanBank()
  local bankBag = (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or -1
  local first = (NUM_BAG_SLOTS or 4) + 1
  local last = first + (NUM_BANKBAGSLOTS or 7)
  local main = countBags(bankBag, bankBag) or {}
  local bags = countBags(first, last) or {}
  for id, n in pairs(bags) do
    main[id] = (main[id] or 0) + n
  end
  local h = mine()
  h.bank, h.bankAt = main, GetServerTime()
end

-- your active auctions (C_AuctionHouse owned auctions; sold ones wait in the mail)
function Trading:ScanAuctions()
  local ah = C_AuctionHouse
  if not (ah and ah.GetNumOwnedAuctions and ah.GetOwnedAuctionInfo) then
    return
  end
  local out, listed = {}, { count = 0, value = 0, house = ns.AME:CurrentHouse() }
  local list = {}
  for i = 1, ah.GetNumOwnedAuctions() or 0 do
    local info = ah.GetOwnedAuctionInfo(i)
    local active = info and (info.status == nil or info.status == 0)
    local id = info and info.itemKey and info.itemKey.itemID
    if active and id then
      local qty = info.quantity or 1
      out[id] = (out[id] or 0) + qty
      -- asking price: buyout (per unit, times the quantity), else the bid
      local unit = info.buyoutAmount or info.bidAmount
      if unit then
        listed.value = listed.value + unit * qty
      end
      listed.count = listed.count + 1
      list[#list + 1] = {
        itemID = id,
        qty = qty,
        unit = unit,
        total = unit and unit * qty,
        timeLeft = info.timeLeftSeconds,
        timeLeftBand = info.timeLeft,
      }
    end
  end
  local h = mine()
  h.auctions, h.auctionsAt, h.listed = out, GetServerTime(), listed
  h.auctionList = list
end

-- every active auction on all characters: { itemID, qty, unit, total, timeLeft, char, house, seen }
function Trading:ActiveAuctions()
  local out = {}
  for char, h in pairs(AME_DB.holdings) do
    for _, a in ipairs(h.auctionList or {}) do
      local e = {}
      for k, v in pairs(a) do
        e[k] = v
      end
      e.char, e.house, e.seen = char:gsub("^[^:]*:", ""), h.listed and h.listed.house, h.auctionsAt
      out[#out + 1] = e
    end
  end
  table.sort(out, function(a, b)
    return (a.total or 0) > (b.total or 0)
  end)
  return out
end

-- "A buyer has been found for your auction of %s." / "Your auction of %s has expired." as Lua patterns
function Trading.Pattern(fmt, fallback)
  fmt = type(fmt) == "string" and fmt or fallback
  local parts = {}
  for piece in (fmt .. "%s"):gmatch("(.-)%%s") do
    parts[#parts + 1] = (piece:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
  end
  return "^" .. table.concat(parts, "(.+)") .. "$"
end
local pattern = Trading.Pattern

-- the listing price of an item this character has up, when there's exactly one price (for the notification)
local function listedUnit(name)
  local h = AME_DB.holdings[charKey()]
  local unit
  for _, a in ipairs(h and h.auctionList or {}) do
    local n = W_ItemName and W_ItemName(a.itemID)
    if n == name and a.unit then
      if unit and unit ~= a.unit then
        return nil
      end
      unit = a.unit
    end
  end
  return unit
end

-- System chat: your auction sold or expired. The game shows the message; AME records a pending sale in the ledger
-- (quantity and price come with the auction mail, which settles it).
function Trading:OnSystemMessage(msg)
  if type(msg) ~= "string" then
    return
  end
  self.soldPattern = self.soldPattern or pattern(ERR_AUCTION_SOLD_S, "A buyer has been found for your auction of %s.")
  self.expiredPattern = self.expiredPattern or pattern(ERR_AUCTION_EXPIRED_S, "Your auction of %s has expired.")
  local sold = msg:match(self.soldPattern)
  local expired = not sold and msg:match(self.expiredPattern)
  if (sold or expired) and ns.Posting then
    ns.Posting:OnOutcome(sold or expired, sold ~= nil) -- the pricing model learns how its chances held up
  end
  if sold then
    local unit = listedUnit(sold)
    self.ledger:Add({
      t = GetServerTime(),
      kind = "pending",
      name = sold,
      itemID = nil,
      qty = nil,
      amount = unit,
      char = UnitName("player"),
    })
  end
  -- the game already announces it in chat; AME only records the sale until its mail arrives
  if (sold or expired) and ns.UI and ns.UI.RefreshPortfolio then
    ns.UI:RefreshPortfolio()
  end
end

function Trading:QueryAuctions()
  local ah = C_AuctionHouse
  if ah and ah.QueryOwnedAuctions then
    pcall(ah.QueryOwnedAuctions, {})
  end
end

-- Item ID from an invoice's item name. Invoices only carry the name, and GetItemInfoInstant(name) only works for
-- items the client has cached, so also look through what your characters hold and list (a bought item is usually
-- still in your bags, a sold one was in your auction list).
local function idFromName(name)
  if not name then
    return nil
  end
  local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if instant then
    local ok, id = pcall(instant, name)
    if ok and type(id) == "number" then
      return id
    end
  end
  for _, h in pairs(AME_DB.holdings or {}) do
    for _, place in ipairs({ "bags", "bank", "auctions" }) do
      for itemID in pairs(h[place] or {}) do
        if W_ItemName(itemID) == name then
          return itemID
        end
      end
    end
    for _, a in ipairs(h.auctionList or {}) do
      if a.itemID and W_ItemName(a.itemID) == name then
        return a.itemID
      end
    end
  end
  return nil
end
Trading.IDFromName = idFromName

-- the item a mail carries (a purchase mail has the bought item attached)
local function mailItemID(i)
  if not GetInboxItemLink then
    return nil
  end
  for slot = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
    local link = GetInboxItemLink(i, slot)
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if id then
      return id
    end
  end
  return nil
end

-- Ledger entries recorded before their item was known get their ID once it can be found (needed to match purchases
-- against holdings for the average cost, and to show icons). Returns how many were filled in.
function Trading:ResolveLedger()
  local n = 0
  for _, e in ipairs(AME_DB.ledger and AME_DB.ledger.entries or {}) do
    if not e.itemID and e.name then
      e.itemID = idFromName(e.name)
      if e.itemID then
        n = n + 1
      end
    end
  end
  return n
end

-- Record AH invoices in the inbox (sold: "seller", bought: "buyer"); each mail once, however often the mailbox is
-- opened (Ledger:AddInvoice matches invoices to what is already recorded).
function Trading:ScanMail()
  if not (GetInboxNumItems and GetInboxInvoiceInfo and GetInboxHeaderInfo) then
    return 0
  end
  local now, added = GetServerTime(), 0
  local claimed = {} -- ledger entries matched to an invoice in this pass (see Ledger:AddInvoice)
  for i = 1, GetInboxNumItems() or 0 do
    local invoiceType, itemName, playerName, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
    if (invoiceType == "seller" or invoiceType == "buyer") and itemName and bid then
      local daysLeft = select(7, GetInboxHeaderInfo(i)) or Trading.MAIL_DAYS
      local t = now - math.floor((Trading.MAIL_DAYS - daysLeft) * 86400)
      local entry = {
        t = t,
        kind = invoiceType == "seller" and "sale" or "buy",
        itemID = (invoiceType == "buyer" and mailItemID(i)) or idFromName(itemName),
        name = itemName,
        qty = count or 1,
        amount = bid,
        cut = invoiceType == "seller" and (consignment or 0) or nil,
        char = UnitName("player"),
        -- the buyer (on your sales) or seller (on your purchases), when the mail names them
        counterparty = type(playerName) == "string" and playerName:match("%S") and playerName ~= "?" and playerName
          or nil,
      }
      if self.ledger:AddInvoice(entry, claimed) then
        added = added + 1
      end
    end
  end
  if (added > 0 or self:ResolveLedger() > 0) and ns.UI and ns.UI.RefreshPortfolio then
    ns.UI:RefreshPortfolio()
  end
  return added
end
