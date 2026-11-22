-- The craft queue (pure): what you've asked to make, worked out into steps and materials.
--
--   queue = { items = { { recipe = recipeID, count = crafts }, ... }, choice = { [itemID] = "make" | "buy" } }
--
-- CraftQueue.Plan(queue, env) turns it into:
--   steps      what to craft, parts first (bars before the gauntlets made from them): { recipe, count, item,
--              made (units), crafter (charKey or nil: nobody recorded knowing it), mine (this character knows it),
--              part (true: made for another step), profit (top-level items, all crafts), choice, saves (a part:
--              per unit, making vs buying), saved (a part: saves for all it makes) }
--   materials  every reagent with what's needed and its sources, in a fixed order: { item, need, sources = { { kind,
--              qty, char, cost } } } - kind: "carried" (this character's bags) | "bank" (its bank) | "alt" (another
--              character's bags, bank and mailbox) | "guild" (a guild bank) | "vendor" | "made" (by a step) | "ah"
--              (to buy)
--   toBuy      what the "ah" sources cost at market;  profit: the queued items' profit, all crafts
--   todo       the plan in words, as { kind, ... } lines for the UI ("buy", "craft", "alt", "bank", "guild")
--
-- env (every game fact comes in through it):
--   env.recipe(recipeID)  -> { id, product, made, reagents = { {itemID, n}, ... } } or nil
--   env.producers(itemID) -> { { recipe = recipeID, crafters = { charKey, ... } }, ... } recipes that make it
--   env.held(itemID)      -> Trading.Held(itemID) (per character, guild banks)
--   env.me                -> this character's key
--   env.craft             -> a Crafting instance (prices: what to make or buy)
--   env.vendorBuy(itemID) -> what a vendor charges, or nil
local _, ns = ...

local CraftQueue = {}
ns.CraftQueue = CraftQueue

CraftQueue.MAX_DEPTH = 3 -- parts of parts of parts (ore -> bar -> part -> item)

local function heldBy(held, me)
  local out = { carried = 0, bank = 0, mail = 0, alts = {}, guilds = {} }
  for _, c in ipairs(held and held.chars or {}) do
    if c.me or c.key == me then
      out.carried, out.bank, out.mail = c.bags or 0, c.bank or 0, c.mail or 0
    elseif (c.bags or 0) + (c.bank or 0) + (c.mail or 0) > 0 then
      -- what you can use of an alt's: its bags, bank and mailbox (Holdings.PLACES.usable)
      out.alts[#out.alts + 1] = { char = c.name, qty = (c.bags or 0) + (c.bank or 0) + (c.mail or 0) }
    end
  end
  for _, g in ipairs(held and held.guilds or {}) do
    out.guilds[#out.guilds + 1] = { char = g.name, qty = g.qty }
  end
  return out
end

-- the recipe that makes an item, preferring one this character knows, then one any of yours knows
local function producer(env, itemID)
  local best
  for _, p in ipairs(env.producers and env.producers(itemID) or {}) do
    local mine, anyone = false, p.crafters and p.crafters[1]
    for _, c in ipairs(p.crafters or {}) do
      if c == env.me then
        mine = true
      end
    end
    local score = mine and 2 or anyone and 1 or 0
    if not best or score > best.score then
      best = { recipe = p.recipe, crafter = mine and env.me or anyone, mine = mine, score = score }
    end
  end
  return best and best.score > 0 and best or nil
end

-- make or buy a part: what the player picked, else the cheaper one (craft cost per unit vs the market price)
local function decide(env, queue, itemID, prod)
  local choice = queue.choice and queue.choice[itemID]
  local r = env.recipe(prod.recipe)
  local perUnit, buy
  if env.craft and r then
    local cost = env.craft:CraftCost(r)
    perUnit = cost and cost / math.max(1, r.made or 1)
    buy = env.craft:Price(itemID)
  end
  local saves = perUnit and buy and (buy - perUnit) or nil
  if choice then
    return choice, saves
  end
  if buy and perUnit and perUnit >= buy then
    return "buy", saves
  end
  return "make", saves
end

function CraftQueue.Plan(queue, env)
  local plan = { steps = {}, materials = {}, toBuy = 0, profit = 0, todo = {} }
  local pending = {} -- { itemID, units } still to be sourced, in order of need (parts add their reagents)
  local stepFor = {} -- recipeID -> its step (crafts merge)
  local depthOf = {}

  local function addStep(recipeID, count, depth, part)
    local r = env.recipe(recipeID)
    if not r then
      return
    end
    local s = stepFor[recipeID]
    if not s then
      s = { recipe = recipeID, count = 0, item = r.product, part = part, depth = depth, profit = not part and 0 or nil }
      stepFor[recipeID] = s
      plan.steps[#plan.steps + 1] = s
    end
    s.count = s.count + count
    s.depth = math.max(s.depth, depth)
    s.made = s.count * (r.made or 1)
    for _, g in ipairs(r.reagents or {}) do
      pending[#pending + 1] = { g[1], g[2] * count }
      depthOf[g[1]] = math.max(depthOf[g[1]] or 0, depth + 1)
    end
  end

  for _, q in ipairs(queue.items or {}) do
    addStep(q.recipe, q.count, 0, false)
    local s = stepFor[q.recipe]
    if s and env.craft then
      local r = env.recipe(q.recipe)
      local e = r and env.craft:Evaluate(r)
      if e and e.profit then
        s.profit = (s.profit or 0) + e.profit * q.count
        plan.profit = plan.profit + e.profit * q.count
      end
    end
  end

  -- each material once, however many steps need it: what's left of your stock (in the fixed order) goes first, then
  -- a vendor, a part made by a step (when that's cheaper, or picked), and the auction house for the rest
  local mats, stock = {}, {}
  local i = 1
  while i <= #pending do
    local itemID, n = pending[i][1], pending[i][2]
    i = i + 1
    local m = mats[itemID]
    if not m then
      m = { item = itemID, need = 0, sources = {} }
      mats[itemID] = m
      plan.materials[#plan.materials + 1] = m
      local held = heldBy(env.held and env.held(itemID), env.me)
      local list = { { "carried", held.carried }, { "bank", held.bank }, { "mail", held.mail } }
      for _, a in ipairs(held.alts) do
        list[#list + 1] = { "alt", a.qty, a.char }
      end
      for _, g in ipairs(held.guilds) do
        list[#list + 1] = { "guild", g.qty, g.char }
      end
      stock[itemID] = list
    end
    m.need = m.need + n
    local left = n
    local function add(kind, qty, char, extra)
      for _, src in ipairs(m.sources) do
        if src.kind == kind and src.char == char then
          src.qty = src.qty + qty
          if extra and extra.cost then
            src.cost = (src.cost or 0) + extra.cost
          end
          return src
        end
      end
      local src = { kind = kind, qty = qty, char = char }
      for k, v in pairs(extra or {}) do
        src[k] = v
      end
      m.sources[#m.sources + 1] = src
      return src
    end
    for _, e in ipairs(stock[itemID]) do
      local qty = math.min(e[2] or 0, left)
      if qty > 0 then
        add(e[1], qty, e[3])
        e[2], left = e[2] - qty, left - qty
      end
    end
    if left > 0 then
      local vendor = env.vendorBuy and env.vendorBuy(itemID)
      local prod = (depthOf[itemID] or 1) <= CraftQueue.MAX_DEPTH and producer(env, itemID)
      local choice, saves
      if prod then
        choice, saves = decide(env, queue, itemID, prod)
        m.part, m.choice, m.saves = prod.recipe, choice, saves
      end
      local picked = queue.choice and queue.choice[itemID]
      if vendor and vendor > 0 and picked ~= "make" then
        add("vendor", left, nil, { cost = vendor * left })
        left = 0
      elseif prod and choice == "make" then
        local r = env.recipe(prod.recipe)
        local made = math.max(1, r and r.made or 1)
        local before = stepFor[prod.recipe] and stepFor[prod.recipe].made or 0
        local spare = before - (m.madeUsed or 0) -- a step already making some covers what it has to spare
        local crafts = math.max(0, math.ceil((left - spare) / made))
        if crafts > 0 then
          addStep(prod.recipe, crafts, depthOf[itemID] or 1, true)
        end
        local st = stepFor[prod.recipe]
        if st then
          st.crafter, st.mine, st.choice, st.saves = prod.crafter, prod.mine, "make", saves
        end
        m.madeUsed = (m.madeUsed or 0) + left
        add("made", left, nil, { step = st })
        left = 0
      end
    end
    if left > 0 then
      local price = env.craft and env.craft:Price(itemID)
      add("ah", left, nil, { cost = price and price * left })
      if price then
        plan.toBuy = plan.toBuy + price * left
      end
    end
  end
  for _, m in ipairs(plan.materials) do
    m.madeUsed = nil
  end

  -- steps: deepest parts first, then in the order queued
  for k, s in ipairs(plan.steps) do
    s.index = k
    if not s.crafter then
      for _, p in ipairs(s.item and env.producers and env.producers(s.item) or {}) do
        if p.recipe == s.recipe then
          for _, c in ipairs(p.crafters or {}) do
            if c == env.me then
              s.mine = true
            end
          end
          s.crafter = s.mine and env.me or (p.crafters and p.crafters[1])
        end
      end
      s.mine = s.mine or false
    end
    -- a part made rather than bought: what making all of it saves
    if s.part and s.saves and s.saves > 0 then
      s.saved = s.saves * (s.made or s.count)
    end
  end
  table.sort(plan.steps, function(a, b)
    if a.depth ~= b.depth then
      return a.depth > b.depth
    end
    return a.index < b.index
  end)

  -- the plan in words: buy what's missing, fetch from alts and banks, then craft in order
  for _, m in ipairs(plan.materials) do
    for _, src in ipairs(m.sources) do
      if src.kind == "ah" then
        plan.todo[#plan.todo + 1] = { kind = "buy", item = m.item, qty = src.qty, cost = src.cost }
      elseif src.kind == "vendor" then
        plan.todo[#plan.todo + 1] = { kind = "vendor", item = m.item, qty = src.qty, cost = src.cost }
      end
    end
  end
  for _, m in ipairs(plan.materials) do
    for _, src in ipairs(m.sources) do
      if src.kind == "alt" or src.kind == "guild" or src.kind == "bank" or src.kind == "mail" then
        plan.todo[#plan.todo + 1] = { kind = src.kind, item = m.item, qty = src.qty, char = src.char }
      end
    end
  end
  for _, s in ipairs(plan.steps) do
    plan.todo[#plan.todo + 1] = { kind = "craft", step = s, item = s.item, qty = s.made, char = s.crafter }
  end
  return plan
end

---------------------------------------------------------------------------------------------------------------------
-- the saved queue

function CraftQueue.New(db)
  db.items = db.items or {}
  db.choice = db.choice or {}
  return setmetatable({ db = db }, { __index = CraftQueue })
end

-- add crafts of a recipe (merged with any already queued)
function CraftQueue:Add(recipeID, count)
  count = math.max(1, math.floor(count or 1))
  for _, q in ipairs(self.db.items) do
    if q.recipe == recipeID then
      q.count = q.count + count
      return
    end
  end
  self.db.items[#self.db.items + 1] = { recipe = recipeID, count = count }
end

function CraftQueue:Remove(recipeID)
  for k, q in ipairs(self.db.items) do
    if q.recipe == recipeID then
      table.remove(self.db.items, k)
      return true
    end
  end
  return false
end

-- one craft done: count it off (the queued item, or a part's crafts are recomputed by Plan)
function CraftQueue:Crafted(recipeID, crafts)
  for k, q in ipairs(self.db.items) do
    if q.recipe == recipeID then
      q.count = q.count - (crafts or 1)
      if q.count <= 0 then
        table.remove(self.db.items, k)
      end
      return true
    end
  end
  return false
end

function CraftQueue:SetChoice(itemID, choice)
  self.db.choice[itemID] = choice
end

function CraftQueue:Clear()
  self.db.items = {}
end

function CraftQueue:Empty()
  return #self.db.items == 0
end

-- the next step this character can craft now (it knows the recipe, its materials are at hand), or nil
--   canCraft(step) -> true when the profession window says it can be made now
function CraftQueue.Next(plan, canCraft)
  for _, s in ipairs(plan.steps) do
    if s.mine ~= false and canCraft(s) then
      return s
    end
  end
  return nil
end
