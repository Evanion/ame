-- Market depth (pure): an item's order book - price tiers from a search, cheapest first - and what buying from it
-- costs. Lets the Arbitrage tab say how many units a route stays profitable for, instead of quoting one unit.
--
--   book = { t = time, prices = { unit copper, ... ascending }, qtys = { units at that price, ... } }
local _, ns = ...

local Depth = {}
ns.Depth = Depth

Depth.MAX_TIERS = 60 -- keep the cheapest tiers; enough for any sensible purchase

-- rows: { { unitPrice, qty }, ... } in any order (several rows at one price are merged)
function Depth.Book(rows, t)
  local byPrice = {}
  for _, r in ipairs(rows) do
    local p, q = r[1], r[2]
    if p and q and p > 0 and q > 0 then
      byPrice[p] = (byPrice[p] or 0) + q
    end
  end
  local prices = {}
  for p in pairs(byPrice) do
    prices[#prices + 1] = p
  end
  table.sort(prices)
  local book = { t = t, prices = {}, qtys = {} }
  for i = 1, math.min(#prices, Depth.MAX_TIERS) do
    book.prices[i], book.qtys[i] = prices[i], byPrice[prices[i]]
  end
  return book
end

-- compact storage: "price:qty;price:qty"
function Depth.Encode(book)
  local parts = {}
  for i, p in ipairs(book.prices) do
    parts[i] = p .. ":" .. book.qtys[i]
  end
  return table.concat(parts, ";")
end

function Depth.Decode(text, t)
  local book = { t = t, prices = {}, qtys = {} }
  for p, q in (text or ""):gmatch("(%d+):(%d+)") do
    book.prices[#book.prices + 1], book.qtys[#book.qtys + 1] = tonumber(p), tonumber(q)
  end
  return book
end

-- buying n units from the cheapest up: total, average unit price, the last unit's price, units actually available
function Depth.Cost(book, n)
  local total, got, last = 0, 0, nil
  for i, p in ipairs(book.prices) do
    if got >= n then
      break
    end
    local take = math.min(book.qtys[i], n - got)
    total, got, last = total + take * p, got + take, p
  end
  return total, got > 0 and total / got or nil, last, got
end

-- How far an arbitrage route goes: buy every unit priced below what one sells for after the cut (sellNet).
-- returns units, cost, profit (units * sellNet - cost)
function Depth.Route(book, sellNet)
  local units, cost = 0, 0
  for i, p in ipairs(book.prices) do
    if p >= sellNet then
      break
    end
    units, cost = units + book.qtys[i], cost + book.qtys[i] * p
  end
  return units, cost, units * sellNet - cost
end
