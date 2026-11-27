-- WoW glue for the portfolio: AH sales and purchases from auction mail invoices, and what you hold (bags, bank,
-- active auctions) per character, account-wide. Logic lives in Ledger.lua and Portfolio.lua.
local _, ns = ...

local Trading = {}
ns.Trading = Trading

Trading.MAIL_DAYS = 30 -- auction mail stays this long; a mail's age comes from its days left

local function api(name)
  return (C_Container and C_Container[name]) or _G[name]
end

local function nameOf(itemID)
  return ns.ItemCache.Name(itemID)
end

local function charKey()
  return ns.AME:MarketRealmName() .. ":" .. (UnitName("player") or "?")
end

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

-- this character's key in the holdings ("<market>:<name>")
function Trading.CharKey()
  return charKey()
end

local function mine()
  local key = charKey()
  local h = AME_DB.holdings[key]
  if not h then
    h = {}
    AME_DB.holdings[key] = h
  end
  -- the character's faction: which auction houses your characters reach (Holdings.Factions)
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  if faction == "Horde" or faction == "Alliance" then
    h.faction = faction
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
      local a, b, _, _, _, _, link, _, _, id, bound = itemInfo(bag, slot)
      local itemID, count
      if type(a) == "table" then -- C_Container: an info table
        itemID, count, bound, link = a.itemID, a.stackCount, a.isBound, a.hyperlink
      else -- classic: texture, count, ..., link (7th), itemID (10th), isBound (11th)
        itemID, count = id, b
      end
      if itemID then -- a random-suffix variant is its own item: the auction house's item key for the slot names it
        local location = ItemLocation
          and ItemLocation.CreateFromBagAndSlot
          and ItemLocation:CreateFromBagAndSlot(bag, slot)
        local key = location and ns.ItemCache.KeyAt(location) or (link and ns.ItemCache.Learn(link))
        itemID = key and ns.BaseID(key) == itemID and key or itemID
      end
      if itemID and not isBound(bag, slot, bound) then
        out[itemID] = (out[itemID] or 0) + (count or 1)
      end
    end
  end
  return out
end

-- the old table when the new one holds the same counts: a table is only replaced when what it holds changed (Home
-- gathers again when one is - Home.Stamp - and bag events fire often for nothing it counts)
function Trading.Same(old, new)
  if type(old) ~= "table" or type(new) ~= "table" then
    return new
  end
  for k, v in pairs(new) do
    if old[k] ~= v then
      return new
    end
  end
  for k in pairs(old) do
    if new[k] == nil then
      return new
    end
  end
  return old
end

-- a copy of counts with n more of id (tables are replaced when they change, as Same says)
function Trading.Added(counts, id, n)
  local out = {}
  for k, v in pairs(counts or {}) do
    out[k] = v
  end
  out[id] = (out[id] or 0) + n
  return out
end

function Trading:ScanBags()
  local reagent = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
  local bags = countBags(0, math.max(NUM_BAG_SLOTS or 4, reagent))
  local h = mine() -- (and the character's faction, noted at login)
  if bags then
    h.bags, h.t = Trading.Same(h.bags, bags), GetServerTime()
  end
  Trading:ScanMoney()
end

Trading.GOLD_DAYS = 40 -- how many days of each character's gold are kept (Home draws 30)

-- the character's gold (Home's net worth): copper, and when it was seen. goldDays keeps the day's last figure for
-- Home's gold line: { [day] = copper }, the last GOLD_DAYS days.
function Trading:ScanMoney()
  if GetMoney then
    local h = mine()
    local now = GetServerTime()
    h.money, h.moneyAt = GetMoney(), now
    Trading.NoteGold(h, ns.Today(now), h.money)
  end
end

function Trading.NoteGold(h, today, copper)
  if type(copper) ~= "number" then
    return
  end
  h.goldDays = h.goldDays or {}
  h.goldDays[today] = copper
  for day in pairs(h.goldDays) do
    if day <= today - Trading.GOLD_DAYS then
      h.goldDays[day] = nil
    end
  end
end

-- The bank's containers: the character bank tabs where the game has them (Enum.BagIndex.CharacterBankTab_1...),
-- else the bank itself, the reagent bank and the bank bags (which come after the bags and, where there is one, the
-- reagent bag: never counted twice).
function Trading.BankBags(bagIndex)
  local B = bagIndex or (Enum and Enum.BagIndex) or {}
  local list = {}
  if B.CharacterBankTab_1 then
    for i = 1, 12 do
      if B["CharacterBankTab_" .. i] then
        list[#list + 1] = B["CharacterBankTab_" .. i]
      end
    end
    return list
  end
  list[1] = B.Bank or -1
  if B.Reagentbank then
    list[#list + 1] = B.Reagentbank
  end
  local first = B.BankBag_1 or ((B.ReagentBag and B.ReagentBag + 1) or (NUM_BAG_SLOTS or 4) + 1)
  for i = 0, (NUM_BANKBAGSLOTS or 7) - 1 do
    list[#list + 1] = first + i
  end
  return list
end

function Trading:ScanBank()
  local main = {}
  for _, bag in ipairs(Trading.BankBags()) do
    for id, n in pairs(countBags(bag, bag) or {}) do
      main[id] = (main[id] or 0) + n
    end
  end
  local h = mine()
  h.bank, h.bankAt = Trading.Same(h.bank, main), GetServerTime()
end

-- The guild bank: what's in it, per tab, as last seen. The game only hands addons a tab's items once it has been
-- shown or queried, so a scan keeps tabs it found empty only if they're the one on screen (an unloaded tab looks
-- empty too). AME_DB.guildBanks["<market>:<guild>"] = { tabs = { [tab] = { [itemID] = qty } }, t }
local function guildKey()
  local guild = GetGuildInfo and GetGuildInfo("player")
  return guild and (ns.AME:MarketRealmName() .. ":" .. guild) or nil
end

function Trading:ScanGuildBank(query)
  local key = guildKey()
  local info, link = _G.GetGuildBankItemInfo, _G.GetGuildBankItemLink
  if not (key and info and link and GetNumGuildBankTabs) then
    return
  end
  AME_DB.guildBanks = AME_DB.guildBanks or {}
  local bank = AME_DB.guildBanks[key] or { tabs = {} }
  AME_DB.guildBanks[key] = bank
  local current = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
  local tabs = GetNumGuildBankTabs() or 0
  for tab = 1, tabs do
    local viewable = true
    if GetGuildBankTabInfo then
      viewable = select(3, GetGuildBankTabInfo(tab)) ~= false
    end
    if viewable then
      if query and QueryGuildBankTab and tab ~= current then
        pcall(QueryGuildBankTab, tab) -- its items arrive with GUILDBANKBAGSLOTS_CHANGED
      end
      local items, any = {}, false
      for slot = 1, (MAX_GUILDBANK_SLOTS_PER_TAB or 98) do
        local itemLink = link(tab, slot)
        if itemLink then
          local _, count = info(tab, slot)
          local id = ns.ItemCache.Learn(itemLink)
          if id then
            items[id] = (items[id] or 0) + (count or 1)
            any = true
          end
        end
      end
      if any or tab == current then
        bank.tabs[tab] = items
      end
    end
  end
  for tab in pairs(bank.tabs) do
    if tab > tabs then
      bank.tabs[tab] = nil
    end
  end
  bank.t = GetServerTime()
end

-- How many of an item your characters on this market have, and where: per character, and each guild bank
-- (Holdings.Count, every place).
--   { total, bags, bank, auctions, guildBank, chars = { { name, bags, bank, auctions, me } },
--     guilds = { { name, qty } } }
-- holdings / guildBanks / market / me: for specs (default: the saved data, this market, this character)
function Trading.Held(itemID, holdings, guildBanks, market, me)
  local prefix = (market or ns.AME:MarketRealmName()) .. ":"
  return ns.Holdings.Count(holdings or AME_DB.holdings, guildBanks or AME_DB.guildBanks, itemID, function(key)
    return key:sub(1, #prefix) == prefix
  end, me or charKey())
end

-- Won an auction ("You won an auction for Murloc Eye (x40)"): it waits in your mailbox until you take it, so it
-- counts as yours there (the craft queue, the tooltip). Reading the inbox replaces this with what's really in it.
-- Pure: the message -> item name, count, or nil
function Trading.WonFrom(msg, fmt)
  local p = Trading.Pattern(fmt, "You won an auction for %s")
  local what = msg:match(p)
  if not what then
    return nil
  end
  local name, n = what:match("^(.-) %(x(%d+)%)$")
  return name or what, tonumber(n) or 1
end

-- Bought on the Shopping tab: in your mailbox now. The game's "you won" message for it, if it sends one, is then
-- already counted (one purchase, counted once).
Trading.BOUGHT_WINDOW = 60
function Trading:OnBought(id, n)
  local h = mine()
  h.mail = Trading.Added(h.mail, id, n)
  self.bought = self.bought or {}
  self.bought[id] = { n = (self.bought[id] and self.bought[id].n or 0) + n, t = GetServerTime() }
end

function Trading:OnWon(name, n)
  local id = Trading.NameResolver()(name)
  if not id then
    return
  end
  local b = self.bought and self.bought[id]
  if b and b.n >= n and GetServerTime() - b.t <= Trading.BOUGHT_WINDOW then
    b.n = b.n - n
    return
  end
  local h = mine()
  h.mail = Trading.Added(h.mail, id, n)
end

-- what the inbox holds, attachment by attachment (when it's open and read)
-- a number the game hands over, or nil where it is secret
local function num(v)
  local secret = _G.issecretvalue
  if type(v) ~= "number" or (secret and secret(v)) then
    return nil
  end
  return v
end

-- What waits in this character's mailbox (Home's "Waiting in your mail"): mail.items by item, and inbox = { at,
-- money, sales, items, firstOut } — the gold in it, how many AH sale mails, how many items, and when the first mail
-- holding gold or items runs out (server time). Taking things out updates it, as the mailbox is read again.
function Trading:ScanMailItems()
  local getItem, n = _G.GetInboxItem, GetInboxNumItems and GetInboxNumItems() or 0
  if not getItem then
    return
  end
  local now = GetServerTime()
  local items = {}
  local inbox = { at = now, money = 0, sales = 0, items = 0 }
  local header, invoice = _G.GetInboxHeaderInfo, _G.GetInboxInvoiceInfo
  for i = 1, n do
    local units = 0
    for a = 1, (_G.ATTACHMENTS_MAX_RECEIVE or 16) do
      local _, itemID, _, count = getItem(i, a)
      if itemID then
        items[itemID] = (items[itemID] or 0) + (count or 1)
        units = units + (num(count) or 1)
      end
    end
    local money, daysLeft
    if header then
      local _, _, _, _, m, _, d = header(i)
      money, daysLeft = num(m) or 0, num(d)
    end
    if invoice and invoice(i) == "seller" and (money or 0) > 0 then
      inbox.sales = inbox.sales + 1
    end
    inbox.money = inbox.money + (money or 0)
    inbox.items = inbox.items + units
    if daysLeft and ((money or 0) > 0 or units > 0) then
      local out = now + math.floor(daysLeft * 86400)
      inbox.firstOut = math.min(inbox.firstOut or out, out)
    end
  end
  local h = mine()
  h.mail, h.inbox = items, inbox
end

-- the game holds a sold auction's gold about an hour, then mails it
Trading.MAIL_DELAY = 3600

-- A sold auction in your owned list: its sale is pending until the mail. The game's chat message usually recorded
-- it already (that pending sale takes this auction); missed (in a dungeon, offline), it's recorded from here. Each
-- auction once (the ledger's keys), however often the list is read. -> when AME first saw it sold
function Trading:SoldListed(id, qty, unit, key, t)
  local keys = self.ledger.db.keys
  if keys[key] then
    return keys[key]
  end
  local name, me = nameOf(id), UnitName("player")
  if not name then
    return t -- not cached yet: the next read records it
  end
  for _, e in ipairs(self.ledger.db.entries) do
    if
      e.kind == "pending"
      and e.name == name
      and e.char == me
      and not e.listed
      and math.abs(e.t - t) <= ns.Ledger.PENDING_WINDOW
    then
      e.listed, e.told, e.itemID, e.qty = key, true, e.itemID or id, e.qty or qty -- the message made it
      keys[key] = t
      return t
    end
  end
  self.ledger:Add(
    { t = t, kind = "pending", name = name, itemID = id, qty = qty, amount = unit, char = me, listed = key },
    key
  )
  return t
end

-- The game's message that an auction sold, for a sale AME recorded from your auction list first: that pending sale
-- takes the message (each once), and no second one is recorded. -> true when one took it
function Trading:SoldTold(name)
  local me, t = UnitName("player"), GetServerTime()
  for _, e in ipairs(self.ledger.db.entries) do
    if
      e.kind == "pending"
      and e.listed
      and not e.told
      and e.name == name
      and e.char == me
      and math.abs(e.t - t) <= ns.Ledger.PENDING_WINDOW
    then
      e.told = true
      return true
    end
  end
  return false
end

-- your auctions (C_AuctionHouse owned auctions): the active ones, and the sold ones until their gold is mailed
function Trading:ScanAuctions()
  local ah = C_AuctionHouse
  if not (ah and ah.GetNumOwnedAuctions and ah.GetOwnedAuctionInfo) then
    return
  end
  local out, listed = {}, { count = 0, value = 0, house = ns.AME:CurrentHouse() }
  local list, sold, t = {}, {}, GetServerTime()
  for i = 1, ah.GetNumOwnedAuctions() or 0 do
    local info = ah.GetOwnedAuctionInfo(i)
    local active = info and (info.status == nil or info.status == 0)
    local isSold = info and info.status == 1
    local id = info and info.itemKey and ns.ItemKey(info.itemKey.itemID, info.itemKey.itemSuffix)
    if id and info.itemLink then
      id = ns.ItemCache.Pair(info.itemLink, info.itemKey.itemID, info.itemKey.itemSuffix)
    end
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
    elseif isSold and id then
      local qty, unit = info.quantity or 1, info.buyoutAmount or info.bidAmount
      local key = "sold:"
        .. charKey()
        .. ":"
        .. (info.auctionID and tostring(info.auctionID) or (tostring(id) .. ":" .. qty .. ":" .. tostring(unit)))
      local first = self:SoldListed(id, qty, unit, key, t)
      -- the game's time left on a sold auction is the mail's, when it gives one; else an hour from the sale
      local left = info.timeLeftSeconds
      local mailAt = (left and left > 0 and left <= Trading.MAIL_DELAY) and t + left or first + Trading.MAIL_DELAY
      sold[#sold + 1] = {
        itemID = id,
        qty = qty,
        unit = unit,
        total = unit and unit * qty,
        auctionID = info.auctionID,
        mailAt = mailAt,
      }
    end
  end
  local h = mine()
  h.auctions, h.auctionsAt, h.listed = Trading.Same(h.auctions, out), t, listed
  h.auctionList, h.soldList = list, sold
end

-- every character's sold auctions whose mail hasn't come yet: { itemID, qty, unit, total, mailAt, char, sold }
function Trading:SoldAuctions(holdings, t)
  local out = {}
  for char, h in pairs(holdings or AME_DB.holdings) do
    for _, a in ipairs(h.soldList or {}) do
      if (a.mailAt or 0) > t then
        local e = { sold = true }
        for k, v in pairs(a) do
          e[k] = v
        end
        e.char, e.house, e.seen = char:gsub("^[^:]*:", ""), h.listed and h.listed.house, h.auctionsAt
        out[#out + 1] = e
      end
    end
  end
  table.sort(out, function(a, b)
    return a.mailAt < b.mailAt
  end)
  return out
end

-- every active auction on all characters: { itemID, qty, unit, total, timeLeft, char, house, seen }
function Trading:ActiveAuctions(holdings)
  local out = {}
  for char, h in pairs(holdings or AME_DB.holdings) do
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
-- A Lua pattern matching the game's message for a format string like ERR_AUCTION_SOLD_S, capturing each %s (also
-- written %1$s in some languages); magic characters in the text are escaped.
function Trading.Pattern(fmt, fallback)
  fmt = type(fmt) == "string" and fmt or fallback
  fmt = fmt:gsub("%%%d+%$s", "%%s")
  local parts = {}
  for piece in (fmt .. "%s"):gmatch("(.-)%%s") do
    piece = piece:gsub("%%%%", "%%") -- "%%" in a format string is one "%" in the message
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
    local n = nameOf(a.itemID)
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
  -- in dungeons, raids and encounters (12.x) the game hands addons chat as secret values: unreadable, so skipped
  local secret = _G.issecretvalue
  if (secret and secret(msg)) or type(msg) ~= "string" then
    return
  end
  self.soldPattern = self.soldPattern or pattern(ERR_AUCTION_SOLD_S, "A buyer has been found for your auction of %s.")
  self.expiredPattern = self.expiredPattern or pattern(ERR_AUCTION_EXPIRED_S, "Your auction of %s has expired.")
  local wonName, wonCount = Trading.WonFrom(msg, ERR_AUCTION_WON_S)
  if wonName then
    self:OnWon(wonName, wonCount)
  end
  local sold = msg:match(self.soldPattern)
  local expired = not sold and msg:match(self.expiredPattern)
  if (sold or expired) and ns.Posting then
    ns.Posting:OnOutcome(sold or expired, sold ~= nil) -- the pricing model learns how its chances held up
  end
  if sold then
    if ns.Sound then
      ns.Sound.Play("auction") -- off unless Settings · Sound has "an auction sells" on
    end
    if not self:SoldTold(sold) then
      self.ledger:Add({
        t = GetServerTime(),
        kind = "pending",
        name = sold,
        itemID = nil,
        qty = nil,
        amount = listedUnit(sold),
        char = UnitName("player"),
      })
    end
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
-- byName (optional): Trading.HeldByName(), built once by callers resolving many names
local function idFromName(name, byName)
  if not name then
    return nil
  end
  -- a random-suffix variant's full name ("... of Magic"), learned from its links
  local variant = ns.ItemCache.byName and ns.ItemCache.byName[name]
  if variant then
    return variant
  end
  local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if instant then
    local ok, id = pcall(instant, name)
    if ok and type(id) == "number" then
      return id
    end
  end
  return byName and byName[name]
end

-- resolve many invoice names: the held-items map is built once, and only if the client's cache doesn't know a name
function Trading.NameResolver()
  local byName, indexed
  return function(name)
    local id = idFromName(name)
    if id or not name then
      return id
    end
    byName = byName or Trading.HeldByName()
    if byName[name] then
      return byName[name]
    end
    -- not in the client's cache, nor held (a recipe bought and learned): the items of this market's scans, by the
    -- names AME has cached for them
    if not indexed then
      indexed = {}
      local AME = ns.AME
      local index = AME and AME.FactionIndex and AME:FactionIndex()
      for itemID in pairs(index and index.items or {}) do
        local info = ns.ItemCache and ns.ItemCache.Get and ns.ItemCache.Get(itemID)
        local n = info and info.name
        if n and not indexed[n] then
          indexed[n] = itemID
        end
      end
    end
    return indexed[name]
  end
end

-- name -> item ID for everything your characters hold or list (names of items the client has loaded)
function Trading.HeldByName()
  local out = {}
  local function add(itemID)
    local name = nameOf(itemID)
    if name and not out[name] then
      out[name] = itemID
    end
  end
  for _, h in pairs(AME_DB.holdings or {}) do
    for _, place in ipairs({ "bags", "bank", "auctions" }) do
      for itemID in pairs(h[place] or {}) do
        add(itemID)
      end
    end
    for _, a in ipairs(h.auctionList or {}) do
      add(a.itemID)
    end
  end
  return out
end

-- the item a mail carries (a purchase mail has the bought item attached)
local function mailItemID(i)
  if not GetInboxItemLink then
    return nil
  end
  for slot = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
    local link = GetInboxItemLink(i, slot)
    local id = ns.ItemCache.Learn(link)
    if id then
      return id
    end
  end
  return nil
end

-- Ledger entries recorded before their item was known get their ID once it can be found (needed to match purchases
-- against holdings for the average cost, and to show icons). Returns how many were filled in.
function Trading:ResolveLedger()
  local n, resolve = 0, Trading.NameResolver()
  for _, e in ipairs(AME_DB.ledger and AME_DB.ledger.entries or {}) do
    if not e.itemID and e.name then
      e.itemID = resolve(e.name)
      if e.itemID then
        n = n + 1
      end
    end
  end
  return n
end

Trading.SAME_MAIL = 1800 -- seconds: a mail's arrival time, worked out from its days left, wobbles this little

-- An auction of yours that expired: its items come back in a mail titled "Auction expired: <item>" when the listing
-- ends, and its units count as not sold. Each mail once, however often the mailbox is opened: AME_DB.expiredMail
-- remembers the ones counted (item, arrival time, units) as long as the game keeps them.
-- claimed: the records matched in this pass over the inbox
function Trading:ExpiredMail(i, now, claimed)
  local _, _, _, subject, _, _, daysLeft = GetInboxHeaderInfo(i)
  local secret = _G.issecretvalue
  if type(subject) ~= "string" or (secret and secret(subject)) then
    return
  end
  self.expiredMailPattern = self.expiredMailPattern or pattern(_G.AUCTION_EXPIRED_MAIL_SUBJECT, "Auction expired: %s")
  local name = subject:match(self.expiredMailPattern)
  if not name then
    return
  end
  local units = 0
  for slot = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
    local _, _, _, count = (_G.GetInboxItem or function() end)(i, slot)
    units = units + (count or 0)
  end
  local t = now - math.floor((Trading.MAIL_DAYS - (daysLeft or Trading.MAIL_DAYS)) * 86400)
  AME_DB.expiredMail = AME_DB.expiredMail or {}
  local seen = AME_DB.expiredMail
  for k = #seen, 1, -1 do
    local m = seen[k]
    if now - m.t > (Trading.MAIL_DAYS + 1) * 86400 then
      table.remove(seen, k)
    elseif not claimed[m] and m.name == name and m.units == units and math.abs(m.t - t) <= Trading.SAME_MAIL then
      claimed[m] = true -- (two alike mails in one inbox are two listings: each claims one record)
      return -- counted when the mailbox was opened before
    end
  end
  seen[#seen + 1] = { name = name, t = t, units = units }
  claimed[seen[#seen]] = true
  ns.Posting:OnOutcome(name, false, t, units > 0 and units or nil)
end

-- Record AH invoices in the inbox (sold: "seller", bought: "buyer"); each mail once, however often the mailbox is
-- opened (Ledger:AddInvoice matches invoices to what is already recorded).
function Trading:ScanMail()
  if not (GetInboxNumItems and GetInboxInvoiceInfo and GetInboxHeaderInfo) then
    return 0
  end
  local now, added = GetServerTime(), 0
  local claimed = {} -- ledger entries matched to an invoice in this pass (see Ledger:AddInvoice)
  local expiredClaimed = {} -- expired mails counted before, matched in this pass (see ExpiredMail)
  local resolve = Trading.NameResolver()
  for i = 1, GetInboxNumItems() or 0 do
    local invoiceType, itemName, playerName, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
    if (invoiceType == "seller" or invoiceType == "buyer") and itemName and bid then
      local daysLeft = select(7, GetInboxHeaderInfo(i)) or Trading.MAIL_DAYS
      local t = now - math.floor((Trading.MAIL_DAYS - daysLeft) * 86400)
      local entry = {
        t = t,
        kind = invoiceType == "seller" and "sale" or "buy",
        itemID = (invoiceType == "buyer" and mailItemID(i)) or resolve(itemName),
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
        if entry.kind == "sale" and ns.Posting then
          ns.Posting:OnOutcome(itemName, true, t, entry.qty) -- sold some time before this mail arrived
        end
      end
    elseif not invoiceType and ns.Posting then
      self:ExpiredMail(i, now, expiredClaimed)
    end
  end
  if (added > 0 or self:ResolveLedger() > 0) and ns.UI and ns.UI.RefreshPortfolio then
    ns.UI:RefreshPortfolio()
  end
  return added
end
