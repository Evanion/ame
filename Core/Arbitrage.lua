-- Cross-auction-house arbitrage (pure): buy at one house, sell at another (faction AH <-> goblin AH, or between the
-- factions through the goblin AH), after the selling house's cut.
--
-- Buy price  = the cheapest listing at the buy house (what you'd actually pay for the first units).
-- Sell price = the market price at the sell house (what it typically sells for), minus the house's cut.
-- Deposits are not included: they're refunded when the item sells.
local _, ns = ...

local Arbitrage = {}
ns.Arbitrage = Arbitrage

-- Routes paying more than this (20 = 2000%) are gold transfers between factions, not trades: junk listed at the
-- other house for thousands of gold so a friend can "buy" it. They're left out (and counted).
Arbitrage.MAX_MARGIN = 20 -- real routes pay a few hundred % at most; transfer listings pay 100,000%+

-- seller's cut per house (classic rules: 5% at faction auction houses, 15% at the goblin ones)
Arbitrage.DEFAULT_CUT = { Alliance = 0.05, Horde = 0.05, Neutral = 0.15 }

-- buy, sell: market indexes ({ items = { [itemID] = summary } }, summaries have min, market, qty, day)
-- opts: cut (fraction), minProfit (copper), minMargin (fraction), maxAge (days), today (day number),
--       maxMargin (fraction, default Arbitrage.MAX_MARGIN; false: no limit), sortKey ("profit" default), ascending
-- returns rows { itemID, buy, sell, fee, profit, margin, buyQty, sellQty, age }, and how many routes were left out
-- as likely gold transfers
function Arbitrage.Find(buy, sell, opts)
  opts = opts or {}
  local cut = opts.cut or 0
  local rows, transfers = {}, 0
  for id, b in pairs(buy and buy.items or {}) do
    local s = sell and sell.items[id]
    local cost = b.min or b.market
    if opts.hide and opts.hide[id] then
      s = nil -- hidden from lists
    end
    if s and s.market and cost and cost > 0 then
      local fee = s.market * cut
      local profit = s.market - fee - cost
      local margin = profit / cost
      local age, buyAge, sellAge = 0, nil, nil
      if opts.today then
        buyAge, sellAge = opts.today - (b.day or opts.today), opts.today - (s.day or opts.today)
        age = math.max(buyAge, sellAge)
      end
      local ok = profit >= (opts.minProfit or 1)
        and margin >= (opts.minMargin or 0)
        and (not opts.maxAge or age <= opts.maxAge)
      local maxMargin = opts.maxMargin == nil and Arbitrage.MAX_MARGIN or opts.maxMargin
      if ok and maxMargin and margin > maxMargin then
        ok, transfers = false, transfers + 1
      end
      if ok then
        rows[#rows + 1] = {
          itemID = id,
          buy = cost,
          sell = s.market,
          fee = fee,
          profit = profit,
          margin = margin,
          buyQty = b.qty,
          sellQty = s.qty,
          sellRate = s.sellRate,
          age = age,
          buyAge = buyAge,
          sellAge = sellAge,
        }
      end
    end
  end
  local key, asc = opts.sortKey or "profit", opts.ascending
  table.sort(rows, function(x, y)
    local a, b = x[key] or 0, y[key] or 0
    if a == b then
      return x.itemID < y.itemID
    end
    if asc then
      return a < b
    end
    return a > b
  end)
  return rows, transfers
end

-- Listing deposit: a share of the item's vendor sell price by listing length, refunded when the item sells and lost
-- when it doesn't (sources: Classic rules, confirmed for WoW Forever by community guides, Nov 2026). Goblin
-- (neutral) auction houses charge 5x the faction rate. At least 1 silver per post, however few
-- items it holds.
Arbitrage.DEPOSIT_RATE = { [2] = 0.05, [8] = 0.20, [24] = 0.60 }
Arbitrage.NEUTRAL_DEPOSIT_FACTOR = 5
Arbitrage.MIN_DEPOSIT = 100

function Arbitrage.Deposit(vendorPrice, house, hours, minDeposit)
  if not vendorPrice then
    return nil
  end
  local rate = (Arbitrage.DEPOSIT_RATE[hours or 24] or Arbitrage.DEPOSIT_RATE[24])
    * (house == "Neutral" and Arbitrage.NEUTRAL_DEPOSIT_FACTOR or 1)
  return math.max(minDeposit or Arbitrage.MIN_DEPOSIT, math.floor(vendorPrice * rate + 0.5))
end
