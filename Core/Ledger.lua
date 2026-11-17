-- Ledger (pure): your auction house sales and purchases, from the game's auction mail invoices.
--
--   db = { entries = { entry, ... oldest first }, keys = { [dedupe key] = t } }
--   entry = { t, kind = "sale" | "buy", itemID?, name, qty, amount, cut, char }
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

-- returns true when added (false: already recorded under that key)
function Ledger:Add(e, key)
  if key and self.db.keys[key] then
    return false
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

local function itemKey(e)
  return e.itemID or e.name
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
      else
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
  local out = {}
  for key, q in pairs(lots) do
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

-- realized profit of one sale entry
function Ledger:Profit(entry)
  local _, profits = match(self.db.entries)
  return profits[entry]
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
