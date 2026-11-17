-- Ledger (pure): your auction house sales and purchases, from the game's auction mail invoices.
--
--   db = { entries = { entry, ... oldest first }, keys = { [dedupe key] = t } }
--   entry = { t, kind = "sale" | "buy" | "pending", itemID?, name, qty, amount, cut, char }
--     pending: the game said an auction sold; the mail with the real quantity and price hasn't arrived yet
--     sale: amount = sale price (bid/buyout), cut = the auction house's cut; you received amount - cut
--     buy:  amount = what you paid
--
-- Realized profit matches sales against purchases first-in-first-out per item; units sold that you never bought
-- through the AH (looted, crafted) have no cost and count fully as profit.
local _, ns = ...

local Ledger = {}
Ledger.__index = Ledger
ns.Ledger = Ledger

Ledger.KEEP = 90 * 86400

function Ledger.New(db)
  db.entries = db.entries or {}
  db.keys = db.keys or {}
  return setmetatable({ db = db }, Ledger)
end

Ledger.PENDING_WINDOW = 12 * 3600 -- a mail settles a pending sale of the same item within this much time

-- returns true when added (false: already recorded under that key)
function Ledger:Add(e, key)
  if key and self.db.keys[key] then
    return false
  end
  if e.kind == "sale" then
    self:Settle(e)
  end
  local list = self.db.entries
  local pos = #list + 1
  while pos > 1 and list[pos - 1].t > e.t do
    pos = pos - 1
  end
  table.insert(list, pos, e)
  if key then
    self.db.keys[key] = e.t
  end
  return true
end

Ledger.SAME_MAIL = 3600 -- an invoice's arrival time is estimated from the mail's days left: this close = same mail

-- Record an auction invoice once. The game gives no mail ID, and the arrival time is only estimated, so an invoice
-- that matches an entry already recorded (same kind, item, amount, quantity and character, arriving within
-- SAME_MAIL) is that entry. claimed (one table per mailbox pass) lets two identical invoices - two equal sales -
-- each keep their own entry. Returns true when added.
function Ledger:AddInvoice(e, claimed)
  for _, x in ipairs(self.db.entries) do
    if
      not claimed[x]
      and x.kind == e.kind
      and x.name == e.name
      and x.amount == e.amount
      and x.qty == e.qty
      and x.char == e.char
      and math.abs(x.t - e.t) <= Ledger.SAME_MAIL
    then
      claimed[x] = true
      return false
    end
  end
  self:Add(e)
  claimed[e] = true
  return true
end

-- the mail for a sale arrived: drop the oldest pending sale of that item (and character) near its time
function Ledger:Settle(sale)
  local list = self.db.entries
  for k, e in ipairs(list) do
    if
      e.kind == "pending"
      and e.name == sale.name
      and (not sale.char or not e.char or e.char == sale.char)
      and math.abs(e.t - sale.t) <= Ledger.PENDING_WINDOW
    then
      table.remove(list, k)
      return e
    end
  end
end

function Ledger:Pending()
  local out = {}
  for _, e in ipairs(self.db.entries) do
    if e.kind == "pending" then
      out[#out + 1] = e
    end
  end
  return out
end

function Ledger:Prune(now)
  local cutoff = now - Ledger.KEEP
  local list = self.db.entries
  local keep = {}
  for _, e in ipairs(list) do
    if e.t >= cutoff then
      keep[#keep + 1] = e
    end
  end
  self.db.entries = keep
  for k, t in pairs(self.db.keys) do
    if t < cutoff then
      self.db.keys[k] = nil
    end
  end
end

-- Entries are matched by item name: invoices always carry it, while the item ID is sometimes only known later
-- (or only on some of an item's entries).
local function itemKey(e)
  return e.name or e.itemID
end

-- Walk all entries in time order, matching sales to bought lots (FIFO). Returns
--   lots    = { [item] = { { qty, unit }, ... } }  units bought and not sold yet
--   profits = { [entry] = realized profit }       per sale
local function match(entries)
  local lots, profits = {}, {}
  for _, e in ipairs(entries) do
    local key = itemKey(e)
    local q = lots[key] or {}
    lots[key] = q
    if e.kind == "buy" and (e.qty or 0) > 0 then
      q[#q + 1] = { qty = e.qty, unit = e.amount / e.qty }
    elseif e.kind == "sale" then
      local left, cost = e.qty or 0, 0
      while left > 0 and q[1] do
        local lot = q[1]
        local take = math.min(left, lot.qty)
        cost, left, lot.qty = cost + take * lot.unit, left - take, lot.qty - take
        if lot.qty == 0 then
          table.remove(q, 1)
        end
      end
      profits[e] = e.amount - (e.cut or 0) - cost
    end
  end
  return lots, profits
end

-- totals since a time: income (sales after the cut), spent (purchases), profit (realized), counts
function Ledger:Summary(since)
  local _, profits = match(self.db.entries)
  local s = { income = 0, spent = 0, profit = 0, sales = 0, buys = 0 }
  for _, e in ipairs(self.db.entries) do
    if e.t >= (since or 0) then
      if e.kind == "sale" then
        s.income = s.income + e.amount - (e.cut or 0)
        s.profit = s.profit + (profits[e] or 0)
        s.sales = s.sales + 1
      elseif e.kind == "buy" then
        s.spent = s.spent + e.amount
        s.buys = s.buys + 1
      end
    end
  end
  return s
end

-- per item: units still held from AH purchases and their average unit cost
function Ledger:CostBasis()
  local lots = match(self.db.entries)
  local ids = {} -- name -> an item ID seen on any of its entries
  for _, e in ipairs(self.db.entries) do
    if e.itemID and e.name then
      ids[e.name] = e.itemID
    end
  end
  local out = {}
  for name, q in pairs(lots) do
    local key = ids[name] or name
    local units, cost = 0, 0
    for _, lot in ipairs(q) do
      units, cost = units + lot.qty, cost + lot.qty * lot.unit
    end
    if units > 0 then
      out[key] = { units = units, unit = cost / units }
    end
  end
  return out
end

-- realized profit of every sale: { [sale entry] = profit } (one FIFO pass; use this for lists)
function Ledger:Profits()
  local _, profits = match(self.db.entries)
  return profits
end

-- realized profit of one sale entry
function Ledger:Profit(entry)
  return self:Profits()[entry]
end

-- Who you trade with: kind "sale" -> your customers (buyers), "buy" -> your suppliers (sellers). Only entries whose
-- mail named the other player count. Sorted by gold, biggest first:
--   { { name, trades, amount, units, last, favourite = item name }, ... }
function Ledger:Counterparties(kind, since)
  local by = {}
  for _, e in ipairs(self.db.entries) do
    if e.kind == kind and e.counterparty and e.t >= (since or 0) then
      local c = by[e.counterparty]
      if not c then
        c = { name = e.counterparty, trades = 0, amount = 0, units = 0, last = 0, items = {} }
        by[e.counterparty] = c
      end
      c.trades, c.amount, c.units = c.trades + 1, c.amount + (e.amount or 0), c.units + (e.qty or 0)
      c.last = math.max(c.last, e.t)
      local item = e.name or "?"
      c.items[item] = (c.items[item] or 0) + (e.amount or 0)
    end
  end
  local out = {}
  for _, c in pairs(by) do
    local best, bestAmount = nil, -1
    for item, amount in pairs(c.items) do
      if amount > bestAmount or (amount == bestAmount and item < best) then
        best, bestAmount = item, amount
      end
    end
    c.favourite, c.items = best, nil
    out[#out + 1] = c
  end
  table.sort(out, function(a, b)
    if a.amount == b.amount then
      return a.name < b.name
    end
    return a.amount > b.amount
  end)
  return out
end

-- newest first, optionally since a time
function Ledger:Recent(since, limit)
  local out = {}
  local list = self.db.entries
  for k = #list, 1, -1 do
    local e = list[k]
    if e.t < (since or 0) or (limit and #out >= limit) then
      break
    end
    out[#out + 1] = e
  end
  return out
end
