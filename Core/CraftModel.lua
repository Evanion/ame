-- CraftModel: the Crafting tab's model, built in core so every view that needs it (the Crafting pages, "craft it
-- instead" on the item page and the Selling tab) gets the same one. (Data core, step 7: moved from
-- Core/UI/CraftingView.lua unchanged; docs/plans/data-core.md.)
--
--   CraftModel.Build(only) -> { hasData, index, craft, entries, held, heldSet, uses, chars } or nil, "loading"
--     only: one character's key (nil: every character). entries: the recipes your characters know, one per recipe
--     with every character who knows it; craft: a Crafting instance on the faction auction house's quote.
--   CraftModel.Instead(itemID) -> { product, where, each, raw, crafter } or nil
local _, ns = ...

local M = {}
ns.CraftModel = M

-- gathering professions craft nothing worth ranking
M.GATHERING = { [182] = true, [356] = true, [393] = true }
local GATHERING = M.GATHERING

-- Crafting on your faction's auction house (index): its quote, and the recipes that make each product (chains)
local function env(index, producers)
  return ns.Quote.For(ns.AME:FactionShard(), index):CraftEnv(producers)
end

-- Make something of an item instead of vendoring it? Recipes your characters know that use it, valued as the
-- refine page does (Crafting:SellOrRefine: the product sold where it nets most, AH or vendor; other reagents bought).
-- -> { product, where ("ah" | "vendor"), each (per unit of the item), raw (selling it as is, per unit), crafter }
-- or nil when no known recipe beats selling it as it is
M.INSTEAD_QTY = 100 -- valued over this many (whole crafts; per unit after)
function M.Instead(itemID)
  local index = ns.AME:FactionIndex()
  if not (index and itemID) then
    return nil
  end
  local recipes, crafters = {}, {}
  for key, c in pairs(ns.Professions:Characters()) do
    for profession, p in pairs(c.professions or {}) do
      if not GATHERING[profession] then
        for id in pairs(p.learned or {}) do
          if not crafters[id] then
            local r = ns.Recipes.Get(id, profession)
            local uses = false
            for _, reagent in ipairs(r and r.reagents or {}) do
              uses = uses or reagent[1] == itemID
            end
            if uses and r.product then
              recipes[#recipes + 1] = r
              crafters[id] = key:match("[^:]+$") or key
            end
          end
        end
      end
    end
  end
  if #recipes == 0 then
    return nil
  end
  local craft = env(index)
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
    crafter = crafters[best.recipe.id],
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

  -- known recipes, one entry per recipe with every character who knows it; product -> recipes (chains)
  local byRecipe, producers, uses, entries = {}, {}, {}, {}
  for key, c in pairs(chars) do
    for profession, p in pairs(c.professions or {}) do
      if not GATHERING[profession] then
        for id in pairs(p.learned or {}) do
          local r = ns.Recipes.Get(id, profession)
          if r then
            local e = byRecipe[id]
            if not e then
              e = { recipe = r, crafters = {}, profession = profession, cooldown = nil }
              byRecipe[id] = e
              if r.product then
                producers[r.product] = producers[r.product] or {}
                table.insert(producers[r.product], r)
              end
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

  -- what you hold (bags and bank), per item across the characters in view
  local held = ns.Holdings.Totals(ns.Trading:Holdings(), "stored", only and function(key)
    return key == only
  end)
  local heldSet = {}
  for id, n in pairs(held) do
    heldSet[id] = n > 0 or nil
  end

  local craft = env(index, producers)
  return {
    hasData = hasData,
    index = index,
    craft = craft,
    entries = entries,
    held = held,
    heldSet = heldSet,
    uses = uses,
    chars = chars,
  }
end
