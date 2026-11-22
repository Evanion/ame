-- Recipes: one recipe model for every view. A recipe comes from the profession window that's open (live), from what
-- your characters' windows recorded (the catalog, Core/Professions.lua), or from the crafting data library (shipped,
-- Core/CraftingData.lua). (Data core, step 5: today's lookups, moved here unchanged; docs/plans/data-core.md. Their
-- source orders still differ by caller - step 9 makes them one.)
--
--   Recipes.Get(id, profession)  that profession's catalog first (none with nil), else shipped:
--                                { id, profession, product, made, reagents = { {itemID, n}, ... }, cooldown }
--   Recipes.Recorded(id)         the open window first, else the catalog; never shipped, no cooldown (the profession
--                                bar and craft queue): { id, product, made, reagents }
--   Recipes.Producers(itemID)    { { recipe = id, crafters = { charKey, ... } }, ... }: catalog recipes that make it
--   Recipes.Teaches(itemID)      what a recipe item teaches (CraftingData:Teaches)
--   Recipes.Stamp()              changes whenever what's recorded does (a memo key for what's built from it)
local _, ns = ...

local Recipes = {}
ns.Recipes = Recipes

local function catalog()
  return AME_DB and AME_DB.crafting and AME_DB.crafting.catalog or {}
end

local function made(r)
  return ((r.min or 1) + (r.max or r.min or 1)) / 2
end

function Recipes.Get(id, profession)
  local recorded = ns.Professions:Catalog(profession)
  local r = recorded and recorded[id]
  if r then
    return {
      id = id,
      profession = profession,
      product = r.out,
      made = made(r),
      reagents = r.r or {},
      cooldown = ns.CraftingData:Cooldown(id),
    }
  end
  local d = ns.CraftingData:Recipe(id)
  if d then
    return {
      id = id,
      profession = d.profession,
      product = d.product,
      made = d.made,
      reagents = d.reagents,
      cooldown = ns.CraftingData:Cooldown(id),
    }
  end
end

-- a recorded or live recipe as Crafting and CraftQueue take it
local function shape(id, r)
  if not r then
    return nil
  end
  local reagents = {}
  for _, g in ipairs(r.r or {}) do
    reagents[#reagents + 1] = { g[1], g[2] }
  end
  return { id = id, product = r.out, made = made(r), reagents = reagents }
end

local recordedCache = {}
function Recipes.Recorded(id)
  if not id then
    return nil
  end
  local live = C_TradeSkillUI and ns.Professions.Recipe(C_TradeSkillUI, id)
  if live and live.out then
    local r = shape(id, live)
    recordedCache[id] = r
    return r
  end
  if recordedCache[id] then
    return recordedCache[id]
  end
  for _, c in pairs(catalog()) do
    local r = c.recipes and c.recipes[id]
    if r then
      recordedCache[id] = shape(id, r)
      return recordedCache[id]
    end
  end
  return nil
end

-- a recipe learned with no window open (Professions:Learned) changes no recording time: it counts too
local generation = 0
ns.Events.On("RecipesChanged", function()
  generation = generation + 1
end)

function Recipes.Stamp()
  local db = AME_DB and AME_DB.crafting or {}
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
