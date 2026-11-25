-- CraftModel: the Crafting tab's model, built in core so every view that needs it (the Crafting pages, "craft it
-- instead" on the item page and the Selling tab) gets the same one. (Data core, step 7: moved from
-- Core/UI/CraftingView.lua unchanged; docs/plans/data-core.md.)
--
--   CraftModel.Build(only) -> { hasData, index, quote, craft, entries, held, heldSet, uses, chars } or nil, "loading"
--     only: one character's key (nil: every character). entries: the recipes your characters know, one per recipe
--     with every character who knows it; craft: a Crafting instance on the faction auction house's quote.
--   CraftModel.Instead(itemID) -> { product, where, each, raw, crafter, recipe } or nil (recipe: Recipes.Get's)
--   CraftModel.Producers() -> { [product] = { recipe, ... } }: the recipes your characters know that make each item
--   CraftModel.Craft() -> the one Crafting env every view prices crafts with (the Crafting tab, the profession bar
--     and craft queue, recipe tooltips): your faction's auction house quote (fresh searches, bind-on-pickup products
--     unsellable) and parts crafted when that's cheaper; and that quote (an item's sales rate and signal). nil before
--     there's a market index.
local _, ns = ...

local M = {}
ns.CraftModel = M

-- gathering professions craft nothing worth ranking
M.GATHERING = { [182] = true, [356] = true, [393] = true }
local GATHERING = M.GATHERING

-- product -> the known recipes that make it, worked out again only when what your characters know changes.
-- step (optional): called between recipes while it's worked out (a background job's pause)
local producers, producersKey
function M.Producers(step)
  local key = ns.Recipes.Stamp()
  if producers and producersKey == key then
    return producers
  end
  producers, producersKey = {}, key
  local seen = {}
  for _, c in pairs(ns.Professions:Characters()) do
    for profession, p in pairs(c.professions or {}) do
      if not GATHERING[profession] or next(p.learned or {}) then -- a gathering profession with recipes (Forever) counts
        for id in pairs(p.learned or {}) do
          if not seen[id] then
            seen[id] = true
            local r = ns.Recipes.Get(id)
            if r and r.product then
              producers[r.product] = producers[r.product] or {}
              table.insert(producers[r.product], r)
            end
            if step then
              step()
            end
          end
        end
      end
    end
  end
  return producers
end

-- Crafting on your faction's auction house (index): its quote, and the recipes that make each product (chains)
-- -> craft, quote
local function env(index, step)
  local q = ns.Quote.For(ns.AME:FactionShard(), index)
  return q:CraftEnv(M.Producers(step)), q
end

function M.Craft()
  local index = ns.AME and ns.AME:FactionIndex()
  if not index then
    return nil
  end
  return env(index) -- craft, quote
end

-- Make something of an item instead of vendoring it? Recipes your characters know that use it, valued as the
-- refine page does (Crafting:SellOrRefine: the product sold where it nets most, AH or vendor; other reagents bought).
-- -> { product, where ("ah" | "vendor"), each (per unit of the item), raw (selling it as is, per unit), crafter }
-- or nil when no known recipe beats selling it as it is
--
-- What it works from (InsteadSetup) is built once and shared by every item that asks - the bag corners ask for a
-- whole bag in one round: your faction's index, a Crafting env on its quote, and your known recipes by the reagents
-- they use, with a character who knows each. Kept while the index and your recipes stay the same, for at most
-- SETUP_SECONDS (searches at the auction house make prices fresher). step (optional): called between recipes while
-- it's built, so a background job can pause there (job:Checkpoint).
M.INSTEAD_QTY = 100 -- valued over this many (whole crafts; per unit after)
M.SETUP_SECONDS = 60
local setup
local function clock()
  return _G.GetTime and _G.GetTime() or os.time()
end

function M.InsteadSetup(step)
  local index = ns.AME:FactionIndex()
  if not index then
    return nil
  end
  local stamp, now = ns.Recipes.Stamp(), clock()
  if setup and setup.index == index and setup.stamp == stamp and now - setup.at < M.SETUP_SECONDS then
    return setup
  end
  local uses, crafters = {}, {}
  for key, c in pairs(ns.Professions:Characters()) do
    for profession, p in pairs(c.professions or {}) do
      if not GATHERING[profession] or next(p.learned or {}) then -- a gathering profession with recipes (Forever) counts
        for id in pairs(p.learned or {}) do
          if crafters[id] == nil then
            local r = ns.Recipes.Get(id)
            crafters[id] = false
            if r and r.product then
              crafters[id] = key:match("[^:]+$") or key
              local seen = {}
              for _, reagent in ipairs(r.reagents or {}) do
                local item = reagent[1]
                if not seen[item] then
                  seen[item] = true
                  uses[item] = uses[item] or {}
                  table.insert(uses[item], r)
                end
              end
            end
            if step then
              step()
            end
          end
        end
      end
    end
  end
  setup = { index = index, stamp = stamp, at = now, craft = env(index, step), uses = uses, crafters = crafters }
  return setup
end

function M.Instead(itemID, step)
  if not itemID then
    return nil
  end
  local s = M.InsteadSetup(step)
  local recipes = s and s.uses[itemID]
  if not recipes then
    return nil
  end
  local craft = s.craft
  local n = M.INSTEAD_QTY
  local r = craft:SellOrRefine(itemID, n, recipes)
  local best = r.best
  if not best then
    return nil
  end
  local _, where = craft:NetSale(best.recipe.product)
  return {
    product = best.recipe.product,
    where = where,
    each = best.net / n,
    raw = r.raw / n,
    crafter = s.crafters[best.recipe.id],
    recipe = best.recipe, -- how: its profession, name and tools (the hint says them)
  }
end

-- everything the Crafting pages need, for the faction auction house's prices. only: one character's key (nil: all)
function M.Build(only)
  local index = ns.AME:FactionIndex()
  if not index then
    return nil, "loading"
  end
  -- the data library: every recipe in the game (Recipes to buy, Leveling); the other pages work from what your
  -- characters' profession windows recorded, so they don't need it
  local hasData = ns.CraftingData:Load()
  local chars = ns.Professions:Characters()

  -- known recipes, one entry per recipe with every character who knows it
  local byRecipe, uses, entries = {}, {}, {}
  for key, c in pairs(chars) do
    for profession, p in pairs(c.professions or {}) do
      if not GATHERING[profession] or next(p.learned or {}) then -- a gathering profession with recipes (Forever) counts
        for id in pairs(p.learned or {}) do
          local r = ns.Recipes.Get(id)
          if r then
            local e = byRecipe[id]
            if not e then
              e = { recipe = r, crafters = {}, profession = profession, cooldown = nil }
              byRecipe[id] = e
              for _, reagent in ipairs(r.reagents) do
                uses[reagent[1]] = uses[reagent[1]] or {}
                table.insert(uses[reagent[1]], r)
              end
            end
            e.crafters[#e.crafters + 1] = key
            local ready = p.cooldowns and p.cooldowns[id]
            if ready then
              e.cooldown = math.min(e.cooldown or ready, ready)
            end
          end
        end
      end
    end
  end
  for _, e in pairs(byRecipe) do
    local mine = not only
    for _, k in ipairs(e.crafters) do
      mine = mine or k == only
    end
    if mine then
      table.sort(e.crafters)
      entries[#entries + 1] = e
    end
  end

  -- what you have to use (Holdings.PLACES.usable), per item: your characters on this market, or the one in view
  local held, heldSet = {}, {}
  for id, e in pairs(ns.Holdings.Of("usable", only or "market")) do
    held[id] = e.qty
    heldSet[id] = e.qty > 0 or nil
  end

  local craft, quote = env(index)
  return {
    hasData = hasData,
    index = index,
    quote = quote,
    craft = craft,
    entries = entries,
    held = held,
    heldSet = heldSet,
    uses = uses,
    chars = chars,
  }
end
