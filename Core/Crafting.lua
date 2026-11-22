-- Crafting math (M16, phase 3): what a craft costs, what it earns, what to do with materials you hold, and which
-- recipes on the auction house are worth buying. Pure: every game fact comes in through `env`:
--
--   env.market(itemID)     -> the item's market summary (MarketIndex: market, avg30, sellRate) or nil
--   env.vendorBuy(itemID)  -> what a vendor charges for it (vials, thread, flux...), nil if no vendor sells it
--   env.vendorSell(itemID) -> what a vendor pays for it, nil / 0 if nothing
--   env.cut                -> the auction house's cut (0.05)
--   env.deposit(itemID)    -> the listing deposit for one unit (copper), optional
--   env.sellable(itemID)   -> false for items that can't be sold (bind on pickup), optional
--   env.producers(itemID)  -> recipes that make the item: { recipe, ... } (for chains: ore -> bar -> belt), optional
--   env.factor             -> outlier factor: prices are capped at factor x their 30-day average (fantasy listings)
--
-- A recipe here is { id, product, made, reagents = { {itemID, n}, ... } } (CraftingData:Recipe or a recorded one).
--
-- How things are valued (docs/plans/m16-crafting.md):
--   buying an input       its market price (buyers pay no cut)
--   an input you hold     what selling it would net (after the cut and deposit) - what you give up by using it
--   a vendor reagent      the vendor's price
--   a craftable input     the cheapest of the above and crafting it (recursive, cycles cut off)
--   the product           what selling it nets, at most as many a day as the market absorbs (its sell rate)
local _, ns = ...

local Crafting = {}
Crafting.__index = Crafting
ns.Crafting = Crafting

Crafting.MAX_DEPTH = 3 -- chains deeper than this aren't followed (ore -> bar -> part -> item is 3)

function Crafting.New(env)
  return setmetatable({ env = env, memo = {} }, Crafting)
end

-- Units of an item that sell a day: its sell rate, but never more than is listed (the rate counts expired and
-- cancelled listings too, and scales short observations up to a day). nil without a rate.
function Crafting:SalesPerDay(itemID)
  local s = self.env.market(itemID)
  local rate = s and s.sellRate
  if rate and s.qty and s.qty < rate then
    rate = s.qty
  end
  return rate
end

-- the market price, capped at factor x the 30-day average (a fantasy listing isn't a price)
function Crafting:Price(itemID)
  local s = self.env.market(itemID)
  local p = s and s.market
  if not p or p <= 0 then
    return nil
  end
  local f = self.env.factor
  if f and f > 1 and s.avg30 and s.avg30 > 0 then
    p = math.min(p, f * s.avg30)
  end
  return p
end

-- what selling one unit nets: on the AH after the cut and deposit, or at a vendor, whichever is more (nil: neither)
function Crafting:NetSale(itemID)
  local env = self.env
  if env.sellable and env.sellable(itemID) == false then
    return nil, "unsellable"
  end
  local best, where
  local p = self:Price(itemID)
  if p then
    best, where = p * (1 - (env.cut or 0)) - (env.deposit and env.deposit(itemID) or 0), "ah"
  end
  local v = env.vendorSell and env.vendorSell(itemID)
  if v and v > 0 and (not best or v > best) then
    best, where = v, "vendor"
  end
  return best, where
end

-- One input's cost per unit and where it comes from: "buy" | "vendor" | "craft" | "held".
-- held: you have it - its cost is what selling it would net. depth / seen: chain guards.
-- -> cost, source, recipe (when crafted) - or nil when there's no way to get it
function Crafting:InputCost(itemID, held, depth, seen)
  depth = depth or 0
  local options = {}
  local p = self:Price(itemID)
  if p then
    options[#options + 1] = { p, "buy" }
  end
  local v = self.env.vendorBuy and self.env.vendorBuy(itemID)
  if v and v > 0 then
    options[#options + 1] = { v, "vendor" }
  end
  if held then
    local net = self:NetSale(itemID)
    if net then
      options[#options + 1] = { net, "held" }
    end
  end
  if depth < Crafting.MAX_DEPTH and self.env.producers then
    seen = seen or {}
    if not seen[itemID] then
      seen[itemID] = true
      for _, r in ipairs(self.env.producers(itemID) or {}) do
        local cost = self:CraftCost(r, depth + 1, seen)
        if cost then
          options[#options + 1] = { cost / math.max(1, r.made or 1), "craft", r }
        end
      end
      seen[itemID] = nil
    end
  end
  local best
  for _, o in ipairs(options) do
    if not best or o[1] < best[1] then
      best = o
    end
  end
  if best then
    return best[1], best[2], best[3]
  end
end

-- what one craft's reagents cost (nil if a reagent can't be had). heldSet: { [itemID] = true } for inputs you hold.
function Crafting:CraftCost(recipe, depth, seen, heldSet, breakdown)
  local total = 0
  for _, r in ipairs(recipe.reagents or {}) do
    local cost, source, via = self:InputCost(r[1], heldSet and heldSet[r[1]], depth, seen)
    if not cost then
      if breakdown then
        breakdown.missing = breakdown.missing or {}
        breakdown.missing[#breakdown.missing + 1] = r[1]
      end
      return nil
    end
    total = total + cost * r[2]
    if breakdown then
      breakdown[#breakdown + 1] = { item = r[1], n = r[2], each = cost, source = source, via = via }
    end
  end
  return total
end

-- Everything about one recipe: { cost, revenue (per craft), profit, made, sellRate (product units a day),
-- perDay (gold a day the whole market absorbs), canPerDay (crafts a day its cooldown allows you, or nil),
-- reagents (breakdown), why (nil, or "unsellable" / "unpriced" / "enchant") }
function Crafting:Evaluate(recipe, heldSet)
  local out = { recipe = recipe, made = recipe.made or 1, reagents = {} }
  out.cost = self:CraftCost(recipe, 0, nil, heldSet, out.reagents)
  if not recipe.product then
    out.why = "enchant" -- enchants make no item to sell (valued later)
    return out
  end
  local net, where = self:NetSale(recipe.product)
  out.saleVia = where
  if not net then
    out.why = where == "unsellable" and "unsellable" or "unpriced"
    return out
  end
  if not out.cost then
    out.why = "unpriced"
    return out
  end
  out.revenue = net * out.made
  out.profit = out.revenue - out.cost
  out.sellRate = self:SalesPerDay(recipe.product)
  if recipe.cooldown and recipe.cooldown > 0 then
    out.canPerDay = 86400 / recipe.cooldown -- yours to make, not the market's to take
  end
  if out.sellRate and where == "ah" then
    out.perDay = out.profit * out.sellRate / out.made -- crafts a day the market absorbs
  elseif where == "vendor" then
    out.perDay = nil -- a vendor takes any amount: profit per craft is the measure
  end
  return out
end

-- Rank recipes by gold a day (then profit per craft); losing and unpriced ones last.
-- entries: { { recipe = ..., crafter = ..., ... }, ... } -> the same entries with .eval, sorted
function Crafting:TopEarners(entries, heldSet)
  for _, e in ipairs(entries) do
    e.eval = self:Evaluate(e.recipe, heldSet)
  end
  local function key(e)
    local v = e.eval
    if not v.profit then
      return -math.huge, -math.huge
    end
    return v.perDay or (v.profit > 0 and 0 or v.profit), v.profit
  end
  table.sort(entries, function(a, b)
    local a1, a2 = key(a)
    local b1, b2 = key(b)
    if a1 ~= b1 then
      return a1 > b1
    end
    if a2 ~= b2 then
      return a2 > b2
    end
    return (a.recipe.id or 0) < (b.recipe.id or 0)
  end)
  return entries
end

-- Sell a stack raw, or craft it into something and sell that? For qty of itemID you hold and the known recipes that
-- use it: { raw = net of selling it all, options = { { recipe, crafts, net, gain, days }, ... } best first,
-- best = the best option (or nil when selling raw is best) }. Other reagents are valued as InputCost says (bought);
-- leftovers count as sold raw; days = how long the market needs to absorb the products.
function Crafting:SellOrRefine(itemID, qty, recipes)
  local each = self:NetSale(itemID) or 0
  local out = { item = itemID, qty = qty, raw = each * qty, options = {} }
  for _, recipe in ipairs(recipes or {}) do
    local need = 0
    for _, r in ipairs(recipe.reagents or {}) do
      if r[1] == itemID then
        need = need + r[2]
      end
    end
    local productNet = recipe.product and self:NetSale(recipe.product)
    if need > 0 and productNet then
      local others, ok = 0, true
      for _, r in ipairs(recipe.reagents) do
        if r[1] ~= itemID then
          local cost = self:InputCost(r[1])
          if not cost then
            ok = false
            break
          end
          others = others + cost * r[2]
        end
      end
      local crafts = math.floor(qty / need)
      if ok and crafts > 0 then
        local made = recipe.made or 1
        local net = crafts * (productNet * made - others) + (qty - crafts * need) * each
        local rate = self:SalesPerDay(recipe.product)
        out.options[#out.options + 1] = {
          recipe = recipe,
          crafts = crafts,
          net = net,
          gain = net - out.raw,
          days = rate and rate > 0 and crafts * made / rate or nil,
        }
      end
    end
  end
  table.sort(out.options, function(a, b)
    return a.gain > b.gain
  end)
  local top = out.options[1]
  out.best = top and top.gain > 0 and top or nil
  return out
end

-- Recipe items worth buying. listings: { { item = recipeItemID, price = copper }, ... } (cheapest each, from scans);
-- teaches(itemID) -> { profession, rank, spells } (CraftingData:Teaches); recipe(spellID) -> recipe;
-- chars: { [charKey] = { professions = { [profession] = { skill, learned = { [spellID] = true } } } } }.
-- -> { { item, price, spell, recipe, eval, learners = { { char, skill, ready } }, payback (days) }, ... } best first:
-- learnable now before needing skill, then by payback. Recipes nobody could learn are left out; known ones too.
-- knows(charKey, spellID) -> true: the game says that character knows it (optional; recorded data can lag behind)
function Crafting:RecipesToBuy(listings, teaches, recipe, chars, knows)
  local out = {}
  for _, l in ipairs(listings) do
    local t = teaches(l.item)
    for _, spell in ipairs(t and t.spells or {}) do
      local learners = {}
      local known = false
      for key, c in pairs(chars or {}) do
        local p = c.professions and c.professions[t.profession]
        if p then
          if (p.learned and p.learned[spell]) or (knows and knows(key, spell)) then
            known = true
          else
            learners[#learners + 1] = { char = key, skill = p.skill or 0, ready = (p.skill or 0) >= (t.rank or 0) }
          end
        end
      end
      local r = recipe(spell)
      if r and not known and #learners > 0 then
        table.sort(learners, function(a, b)
          if a.skill ~= b.skill then
            return a.skill > b.skill
          end
          return a.char < b.char
        end)
        local eval = self:Evaluate(r)
        out[#out + 1] = {
          item = l.item,
          price = l.price,
          spell = spell,
          rank = t.rank,
          recipe = r,
          eval = eval,
          learners = learners,
          ready = learners[1].ready,
          payback = eval.perDay and eval.perDay > 0 and l.price / eval.perDay or nil,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.ready ~= b.ready then
      return a.ready
    end
    local pa, pb = a.payback or math.huge, b.payback or math.huge
    if pa ~= pb then
      return pa < pb
    end
    return a.item < b.item
  end)
  return out
end
