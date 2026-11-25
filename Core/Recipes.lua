-- Recipes: one recipe model for every view. A recipe comes from the profession window that's open (live), from what
-- your characters' windows recorded (the catalog, Core/Professions.lua), or from the crafting data library (shipped,
-- Core/CraftingData.lua), in that order, merged per field: the product, yield and reagents from the first that has
-- the recipe, skill colours from the shipped data even when it's been scanned, the cooldown from the shipped data.
-- (Data core, step 9; docs/plans/data-core.md.)
--
--   Recipes.Get(id) -> { id, profession, product, made, madeMin, madeMax, reagents = { {itemID, n, alt}, ... },
--                        cooldown, yellow, grey, src } or nil
--     an enchant makes no item: product nil, made 1. The open window is recorded into the catalog whenever it
--     changes, so it's only asked for a recipe the catalog hasn't got yet.
--     recorded = true: one of your characters' windows (or the open one) has it, not only the shipped data
--   Recipes.Producers(itemID)    { { recipe = id, crafters = { charKey, ... } }, ... }: catalog recipes that make it
--   Recipes.Teaches(itemID)      what a recipe item teaches (CraftingData:Teaches, its corrections applied)
--   Recipes.TaughtBy(spell)      the reverse: { { item, rank }, ... } recipe items that teach it
--   Recipes.Learnable(id, skill) -> { via = "item", items = TaughtBy } | { via = "trainer", learnAt, estimated }
--   Recipes.Stamp()              changes whenever what's recorded does (a memo key for what's built from it)
local _, ns = ...

local Recipes = {}
ns.Recipes = Recipes

-- trainer recipes without a known level: assume they're trained this far below where they turn yellow
Recipes.TRAINER_GUESS = 20

local function catalog()
  return AME_DB and AME_DB.crafting and AME_DB.crafting.catalog or {}
end

-- a recipe learned with no window open (Professions:Learned) changes no recording time: it counts too
local generation = 0
ns.Events.On("RecipesChanged", function()
  generation = generation + 1
end)

local NONE = {}
function Recipes.Stamp()
  local db = AME_DB and AME_DB.crafting or NONE -- (one table: a new {} each call would change the stamp every time)
  local key = 0
  for _, c in pairs(db.catalog or {}) do
    key = key + (c.at or 0)
  end
  for _, ch in pairs(db.chars or {}) do
    for _, p in pairs(ch.professions or {}) do
      key = key + (p.at or 0)
    end
  end
  return tostring(db) .. ":" .. key .. ":" .. generation
end

-- recipes worked out once per change of what's recorded and of the shipped data
local cache, cacheKey = {}, nil
local function fresh()
  local key = Recipes.Stamp() .. ":" .. tostring(ns.CraftingData and ns.CraftingData.data)
  if cacheKey ~= key then
    cache, cacheKey = {}, key
  end
  return cache
end

-- a recorded or live recipe: its profession (skill line) and the saved shape
local function recorded(id)
  for skillLine, c in pairs(catalog()) do
    local r = c.recipes and c.recipes[id]
    if r then
      return r, skillLine
    end
  end
  local live = C_TradeSkillUI and ns.Professions.Recipe(C_TradeSkillUI, id)
  if live and (live.out or #live.r > 0) then
    return live, nil
  end
end

local function build(id)
  local r, skillLine = recorded(id)
  local d = ns.CraftingData and ns.CraftingData:Recipe(id)
  if not (r or d) then
    return nil
  end
  local out = {
    id = id,
    profession = skillLine or (d and d.profession),
    cooldown = ns.CraftingData and ns.CraftingData:Cooldown(id),
    yellow = d and d.yellow,
    grey = d and d.grey,
    reagents = {},
  }
  if r then
    out.product = r.out
    out.madeMin, out.madeMax = r.min or 1, r.max or r.min or 1
    out.src = r.src
    out.tools = r.tools -- the tools it needs ("Salt Shaker"), as the profession window said
    out.at = r.at -- where it's made ("Forge", a campfire, a camp object)
    out.toolIDs = r.toolIDs -- [tool name] = item ID, where known (the tool shows as a link)
    for _, g in ipairs(r.r or {}) do
      out.reagents[#out.reagents + 1] = { g[1], g[2], alt = g.alt }
    end
    out.recorded = true
  else
    out.product = d.product
    out.madeMin, out.madeMax = d.made, d.made
    for _, g in ipairs(d.reagents or {}) do
      out.reagents[#out.reagents + 1] = { g[1], g[2] }
    end
  end
  if not out.product then
    out.madeMin, out.madeMax = 1, 1 -- an enchant: the shipped data says it makes 0 items
  end
  out.made = (math.max(1, out.madeMin or 1) + math.max(1, out.madeMax or 1)) / 2
  return out
end

function Recipes.Get(id)
  if not id then
    return nil
  end
  local c = fresh()
  if c[id] == nil then
    c[id] = build(id) or false
  end
  return c[id] or nil
end

-- item -> { { recipe, crafters = { charKey, ... } } }: what your characters' windows recorded (built once per change)
local producers, producersKey
local function producerMap()
  local db = AME_DB and AME_DB.crafting or {}
  local key = Recipes.Stamp()
  if producers and producersKey == key then
    return producers
  end
  producers, producersKey = {}, key
  for skillLine, c in pairs(db.catalog or {}) do
    for id, r in pairs(c.recipes or {}) do
      if r.out then
        local crafters = {}
        for charKey, ch in pairs(db.chars or {}) do
          local p = ch.professions and ch.professions[skillLine]
          if p and p.learned and p.learned[id] then
            crafters[#crafters + 1] = charKey
          end
        end
        table.sort(crafters)
        local list = producers[r.out] or {}
        producers[r.out] = list
        list[#list + 1] = { recipe = id, crafters = crafters }
      end
    end
  end
  return producers
end

function Recipes.Producers(itemID)
  return producerMap()[itemID] or {}
end

function Recipes.Teaches(itemID)
  return ns.CraftingData:Teaches(itemID)
end

-- spell -> recipe items, from every recipe item the shipped data knows (through Teaches: its corrections applied)
local taught, taughtData
function Recipes.TaughtBy(spell)
  local data = ns.CraftingData and ns.CraftingData.data
  if taughtData ~= data or not taught then
    taught, taughtData = {}, data
    local items = {}
    for item in pairs(data and data.items or {}) do
      items[item] = true
    end
    for item in pairs(ns.CraftingData.OVERRIDES and ns.CraftingData.OVERRIDES.items or {}) do
      items[item] = true
    end
    for item in pairs(items) do
      local t = ns.CraftingData:Teaches(item)
      for _, s in ipairs(t and t.spells or {}) do
        taught[s] = taught[s] or {}
        table.insert(taught[s], { item = item, rank = t.rank })
      end
    end
    for _, list in pairs(taught) do
      table.sort(list, function(a, b)
        return a.item < b.item
      end)
    end
  end
  return taught[spell] or {}
end

-- how a recipe nobody knows yet is learned: from a recipe item, else from a trainer (the game data has no training
-- level for most: estimated from where it turns yellow)
function Recipes.Learnable(id)
  local items = Recipes.TaughtBy(id)
  if #items > 0 then
    return { via = "item", items = items }
  end
  local r = Recipes.Get(id)
  local yellow = r and r.yellow or 1
  return {
    via = "trainer",
    learnAt = yellow <= 50 and 1 or math.max(1, yellow - Recipes.TRAINER_GUESS),
    estimated = true,
  }
end
