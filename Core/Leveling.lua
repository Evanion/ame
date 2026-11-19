-- Profession leveling guides (M16, phase 6): the path from a skill to a target at today's prices. Pure: prices come
-- through a Crafting instance (Core/Crafting.lua) and the rest through `opts`.
--
-- For every skill point, each usable recipe has an expected cost per point: crafts needed (1 / skill-up chance) x
-- what a craft costs minus what its result gets back (by goal). The cheapest wins; consecutive points with the same
-- recipe become a step. Then each step's money is worked out in order: reagents kept from earlier steps are free,
-- big buys priced along the listings (opts.buyCost), results sold as far as the market takes them (sellRate x
-- HORIZON days), the rest to a vendor or disenchanted (opts.deValue), or kept for a later step that needs them.
--
-- Skill-up chance (community formula, classic): 100% below yellow; (grey - skill) / (grey - yellow) from yellow to
-- grey; 0 at grey.
local _, ns = ...

local Leveling = {}
ns.Leveling = Leveling

Leveling.HORIZON = 3 -- results count as sellable on the AH up to this many days of the market's sales
Leveling.RANKS = { 75, 150, 225, 300 } -- Apprentice, Journeyman, Expert, Artisan: training raises the cap
Leveling.RANK_NAMES = { "Apprentice", "Journeyman", "Expert", "Artisan" }
Leveling.GOALS = { "cheapest", "recovery", "fewest", "materials" }

-- the chance a craft at `skill` raises it (nil yellow / grey: always)
function Leveling.Chance(skill, yellow, grey)
  if not yellow or not grey or grey <= yellow then
    return skill < (grey or math.huge) and 1 or 0
  end
  if skill < yellow then
    return 1
  elseif skill >= grey then
    return 0
  end
  return (grey - skill) / (grey - yellow)
end

local function nextCap(cap)
  for _, r in ipairs(Leveling.RANKS) do
    if r > cap then
      return r
    end
  end
end

-- opts:
--   craft       Crafting instance (reagent costs, what results sell for)
--   recipes     { { recipe = {id, product, made, reagents}, yellow, grey, learnAt, known, itemPrice, estimated }, ... }
--   from, to    skill now and the target; cap = the current maximum (training needed beyond it)
--   goal        "cheapest" (gold spent) | "recovery" (net of results) | "fewest" (crafts) | "materials" (held first)
--   held        { [itemID] = qty } materials you hold (used first, valued at what selling them would net)
--   deValue     fn(itemID) -> what disenchanting one is worth (nil: can't / no enchanter)
--   buyCost     fn(itemID, units) -> what buying that many costs along the listings (nil: market price each)
-- -> { steps = { { from, to, entry, crafts, cost, back, net, chance = {start, finish}, results = { sell, vendor,
--      de, keep }, learn = price or nil, train = rank name (a train step) }, ... }, cost, back, net, crafts,
--      complete (reached the target), stuck (skill where no recipe was usable) }
function Leveling.Plan(opts)
  local craft, goal = opts.craft, opts.goal or "recovery"
  local held = {}
  for id, n in pairs(opts.held or {}) do
    held[id] = n
  end
  local heldSet = goal == "materials" and {} or nil
  local function refreshHeld()
    if heldSet then
      for id in pairs(heldSet) do
        heldSet[id] = nil
      end
      for id, n in pairs(held) do
        heldSet[id] = n > 0 or nil
      end
    end
  end
  refreshHeld()
  local sold, bought = {}, {} -- results allocated to the AH so far; recipe items paid for
  local function unitValue(product)
    local cap = (craft:SalesPerDay(product) or 0) * Leveling.HORIZON
    local net = craft:NetSale(product)
    local other =
      math.max(craft.env.vendorSell and craft.env.vendorSell(product) or 0, opts.deValue and opts.deValue(product) or 0)
    if net and (sold[product] or 0) < cap then
      return math.max(net, other)
    end
    return other
  end

  -- 1. pick a recipe per point
  local points = {}
  local cap = opts.cap or opts.to
  local s = opts.from
  local stuck
  while s < opts.to do
    if s >= cap then
      local n = nextCap(cap)
      if not n then
        break
      end
      points[#points + 1] = { train = n, at = s }
      cap = n
    end
    local best, bestScore
    for _, c in ipairs(opts.recipes) do
      -- a recipe on a cooldown (transmutes) can't carry a path: one craft a day or two
      local usable = not (c.recipe.cooldown and c.recipe.cooldown > 0) and (c.known or (c.learnAt or 1) <= s)
      local p = usable and Leveling.Chance(s, c.yellow, c.grey) or 0
      if p > 0 then
        local cost = craft:CraftCost(c.recipe, 0, nil, heldSet)
        if cost then
          local back = c.recipe.product and (c.recipe.made or 1) * unitValue(c.recipe.product) or 0
          local learn = 0
          if c.itemPrice and not c.known and not bought[c] then
            local span = math.max(5, math.floor((c.yellow + c.grey) / 2) - math.max(s, c.learnAt or 1))
            learn = c.itemPrice / span
          end
          local e = 1 / p
          local score
          if goal == "cheapest" then
            score = e * cost + learn
          elseif goal == "fewest" then
            score = e * 1e9 + e * (cost - back) + learn
          else
            score = e * (cost - back) + learn
          end
          if not bestScore or score < bestScore then
            best, bestScore = { c = c, e = e, p = p }, score
          end
        end
      end
    end
    if not best then
      stuck = s
      break
    end
    local c = best.c
    if c.itemPrice and not c.known then
      bought[c] = true
    end
    if c.recipe.product then
      sold[c.recipe.product] = (sold[c.recipe.product] or 0) + best.e * (c.recipe.made or 1)
    end
    if heldSet then
      for _, r in ipairs(c.recipe.reagents) do
        if held[r[1]] then
          held[r[1]] = math.max(0, held[r[1]] - best.e * r[2])
        end
      end
      refreshHeld()
    end
    points[#points + 1] = { c = c, e = best.e, p = best.p, at = s }
    s = s + 1
  end

  -- 2. merge points into steps
  local steps = {}
  for _, pt in ipairs(points) do
    local last = steps[#steps]
    if pt.train then
      steps[#steps + 1] = { from = pt.at, to = pt.at, train = Leveling.RANK_NAMES[#Leveling.RANKS] }
      for i, r in ipairs(Leveling.RANKS) do
        if r == pt.train then
          steps[#steps].train = Leveling.RANK_NAMES[i]
        end
      end
    elseif last and last.entry == pt.c then
      last.to, last.e = pt.at + 1, last.e + pt.e
      last.chance[2] = pt.p
    else
      steps[#steps + 1] = { from = pt.at, to = pt.at + 1, entry = pt.c, e = pt.e, chance = { pt.p, pt.p } }
    end
  end

  -- 3. each step's money, in order
  local need = {} -- [item] = units later steps still need (for keeping results)
  for _, st in ipairs(steps) do
    if st.entry then
      st.crafts = math.ceil(st.e - 1e-9)
      for _, r in ipairs(st.entry.recipe.reagents) do
        need[r[1]] = (need[r[1]] or 0) + st.crafts * r[2]
      end
    end
  end
  held = {}
  for id, n in pairs(opts.held or {}) do
    held[id] = n
  end
  local kept, soldAH, charged = {}, {}, {}
  local out = { steps = steps, cost = 0, back = 0, crafts = 0, stuck = stuck }
  for _, st in ipairs(steps) do
    if st.entry then
      local c, recipe = st.entry, st.entry.recipe
      local cost = 0
      for _, r in ipairs(recipe.reagents) do
        local units = st.crafts * r[2]
        need[r[1]] = (need[r[1]] or 0) - units
        local fromKept = math.min(units, kept[r[1]] or 0) -- made by an earlier step: already paid for
        kept[r[1]] = (kept[r[1]] or 0) - fromKept
        units = units - fromKept
        if goal == "materials" and (held[r[1]] or 0) > 0 then
          local use = math.min(units, held[r[1]])
          held[r[1]] = held[r[1]] - use
          cost = cost + use * (craft:NetSale(r[1]) or 0)
          units = units - use
        end
        if units > 0 then
          local each, source = craft:InputCost(r[1])
          local total = source == "buy" and opts.buyCost and opts.buyCost(r[1], units) or nil
          cost = cost + (total or (each or 0) * units)
        end
      end
      if c.itemPrice and not c.known and not charged[c] then
        charged[c] = true
        st.learn = c.itemPrice
        cost = cost + c.itemPrice
      end
      local results = { sell = 0, vendor = 0, de = 0, keep = 0 }
      local back = 0
      local product = recipe.product
      if product then
        local units = st.crafts * (recipe.made or 1)
        local keep = math.max(0, math.min(units, need[product] or 0))
        results.keep = keep
        kept[product] = (kept[product] or 0) + keep
        units = units - keep
        local room = math.max(0, (craft:SalesPerDay(product) or 0) * Leveling.HORIZON - (soldAH[product] or 0))
        local net = craft:NetSale(product)
        local vendor = craft.env.vendorSell and craft.env.vendorSell(product) or 0
        local de = opts.deValue and opts.deValue(product) or 0
        local sell = (net and net > math.max(vendor, de)) and math.min(units, math.floor(room)) or 0
        results.sell = sell
        soldAH[product] = (soldAH[product] or 0) + sell
        back = back + sell * (net or 0)
        units = units - sell
        if units > 0 then
          if de > vendor then
            results.de, back = units, back + units * de
          else
            results.vendor, back = units, back + units * vendor
          end
        end
      end
      st.cost, st.back, st.net, st.results = cost, back, back - cost, results
      out.cost, out.back, out.crafts = out.cost + cost, out.back + back, out.crafts + st.crafts
    end
  end
  out.net = out.back - out.cost
  out.complete = not stuck and s >= opts.to
  return out
end
