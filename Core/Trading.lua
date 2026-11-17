-- WoW glue for the portfolio: AH sales and purchases from auction mail invoices, and what you hold (bags, bank,
-- active auctions) per character, account-wide. Logic lives in Ledger.lua and Portfolio.lua.
local _, ns = ...

local Trading = {}
ns.Trading = Trading

Trading.MAIL_DAYS = 30 -- auction mail stays this long; a mail's age comes from its days left

local function api(name)
  return (C_Container and C_Container[name]) or _G[name]
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

-- item counts in container bags first..last
local function countBags(first, last)
  local numSlots, itemInfo = api("GetContainerNumSlots"), api("GetContainerItemInfo")
  if not (numSlots and itemInfo) then
    return nil
  end
  local out = {}
  for bag = first, last do
    for slot = 1, numSlots(bag) or 0 do
      local a, b, _, _, _, _, _, _, _, id = itemInfo(bag, slot)
      local itemID, count
      if type(a) == "table" then -- C_Container: an info table
        itemID, count = a.itemID, a.stackCount
      else -- classic: texture, count, ..., itemID (10th)
        itemID, count = id, b
      end
      if itemID then
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
    end
  end
  local h = mine()
  h.auctions, h.auctionsAt, h.listed = out, GetServerTime(), listed
end

function Trading:QueryAuctions()
  local ah = C_AuctionHouse
  if ah and ah.QueryOwnedAuctions then
    pcall(ah.QueryOwnedAuctions, {})
  end
end

-- item ID from an invoice's item name (when the client knows the item)
local function idFromName(name)
  local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if name and instant then
    local ok, id = pcall(instant, name)
    if ok and type(id) == "number" then
      return id
    end
  end
  return nil
end

-- Record AH invoices in the inbox (sold: "seller", bought: "buyer"); each mail once.
function Trading:ScanMail()
  if not (GetInboxNumItems and GetInboxInvoiceInfo and GetInboxHeaderInfo) then
    return 0
  end
  local now, added = GetServerTime(), 0
  for i = 1, GetInboxNumItems() or 0 do
    local invoiceType, itemName, _, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
    if (invoiceType == "seller" or invoiceType == "buyer") and itemName and bid then
      local daysLeft = select(7, GetInboxHeaderInfo(i)) or Trading.MAIL_DAYS
      local t = now - math.floor((Trading.MAIL_DAYS - daysLeft) * 86400)
      local key = ("%s|%s|%d|%d|%d"):format(invoiceType, itemName, bid, count or 1, math.floor(daysLeft * 1440))
      local entry = {
        t = t,
        kind = invoiceType == "seller" and "sale" or "buy",
        itemID = idFromName(itemName),
        name = itemName,
        qty = count or 1,
        amount = bid,
        cut = invoiceType == "seller" and (consignment or 0) or nil,
        char = UnitName("player"),
      }
      if self.ledger:Add(entry, key) then
        added = added + 1
      end
    end
  end
  if added > 0 and ns.UI and ns.UI.RefreshPortfolio then
    ns.UI:RefreshPortfolio()
  end
  return added
end
