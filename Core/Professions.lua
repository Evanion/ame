-- Professions: what each of your characters can craft, recorded when a profession window opens (Crafting, M16).
--
-- The game answers profession questions only while a profession window is open: then C_TradeSkillUI lists the
-- profession's whole catalog - unlearned recipes included - with each recipe's product, yield and reagents
-- (checked on WoW Forever 1.60.1 with /amedev recipes). So:
--   catalog: per profession (skill line), every recipe's product, yield and reagents - the same for every character,
--            saved once per account and refreshed whenever any character opens that profession
--   chars:   per character, per profession: skill, max skill, which recipes are learned, cooldowns, when recorded
-- Recorded for every character: the profession window's bar and craft queue use it, as does Crafting.
--
-- AME_DB.crafting = {
--   catalog = { [skillLine] = { at, recipes = { [recipeID] = { out, min, max, type, r = { {itemID, n}, ... } } } } },
--   chars = { [charKey] = { professions = { [skillLine] = { name, skill, max, at, learned = { [recipeID] = true },
--             cooldowns = { [recipeID] = readyAt } } }, spellbook = { { name, skillLine, skill, max }, ... } } },
-- }
-- Snapshot and Save are pure (the client API is passed in), so they're tested with a fake C_TradeSkillUI.
local _, ns = ...

local Professions = {}
ns.Professions = Professions

Professions.DEBOUNCE = 0.5 -- profession events come in bursts; read once they settle
Professions.BASIC_REAGENT = 1 -- Enum.CraftingReagentType.Basic: the reagents a recipe always needs

local function call(api, name, ...)
  local f = api and api[name]
  if type(f) ~= "function" then
    return nil
  end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then
    return a, b, c, d
  end
end

local function plain(v)
  local secret = _G.issecretvalue
  if secret and secret(v) then
    return nil
  end
  return v
end

-- One recipe's schematic as saved: product, yield, recipe type and its basic reagents. A reagent slot that accepts
-- several items keeps them all: { {itemID, n, alt = { otherID, ... }} }. tools: the tools it needs, by name ("Salt
-- Shaker"; the game's recipe requirements of the tool kind), when it needs any.
function Professions.Recipe(api, recipeID)
  local s = call(api, "GetRecipeSchematic", recipeID, false)
  if type(s) ~= "table" then
    return nil
  end
  local out = {
    out = plain(s.outputItemID),
    min = plain(s.quantityMin) or 1,
    max = plain(s.quantityMax) or plain(s.quantityMin) or 1,
    type = plain(s.recipeType),
    r = {},
  }
  local totem = _G.Enum and _G.Enum.RecipeRequirementType and _G.Enum.RecipeRequirementType.Totem
  local requirements = totem and call(api, "GetRecipeRequirements", recipeID)
  for _, req in ipairs(type(requirements) == "table" and requirements or {}) do
    local name = type(req) == "table" and req.type == totem and plain(req.name)
    if type(name) == "string" and name ~= "" then
      out.tools = out.tools or {}
      out.tools[#out.tools + 1] = name
    end
  end
  for _, slot in ipairs(s.reagentSlotSchematics or {}) do
    local kind = plain(slot.reagentType)
    local items = slot.reagents or {}
    local first = items[1] and plain(items[1].itemID)
    if first and (kind == nil or kind == Professions.BASIC_REAGENT) then
      local r = { first, plain(slot.quantityRequired) or 1 }
      if #items > 1 then
        r.alt = {}
        for i = 2, #items do
          r.alt[#r.alt + 1] = plain(items[i].itemID)
        end
      end
      out.r[#out.r + 1] = r
    end
  end
  return out
end

-- The open profession, read through api (C_TradeSkillUI). nil when nothing worth saving is open: not ready yet, a
-- linked / guild / NPC window (someone else's recipes), or no profession reported.
-- -> { skillLine, name, skill, max, recipes = { [id] = recipe }, learned = { [id] = true }, cooldowns = {...} }
function Professions.Snapshot(api, now)
  if call(api, "IsTradeSkillReady") == false then
    return nil
  end
  if call(api, "IsTradeSkillLinked") or call(api, "IsTradeSkillGuild") or call(api, "IsNPCCrafting") then
    return nil
  end
  local p = call(api, "GetBaseProfessionInfo")
  local skillLine = type(p) == "table" and plain(p.professionID)
  local name = type(p) == "table" and plain(p.professionName)
  if not skillLine or skillLine == 0 or not name or name == "" then
    return nil
  end
  local ids = call(api, "GetAllRecipeIDs")
  if type(ids) ~= "table" or #ids == 0 then
    return nil
  end
  local snap = {
    skillLine = skillLine,
    name = name,
    skill = plain(p.skillLevel) or 0,
    max = plain(p.maxSkillLevel) or 0,
    recipes = {},
    learned = {},
    cooldowns = {},
  }
  for _, id in ipairs(ids) do
    local recipe = Professions.Recipe(api, id)
    if recipe then
      snap.recipes[id] = recipe
    end
    local info = call(api, "GetRecipeInfo", id)
    if recipe and type(info) == "table" and not plain(info.learned) then
      -- where to get it, in the game's own words ("Vendor: ...|nZone: ...|nCost: ..."), for the recipe's tooltip
      local src = plain(call(api, "GetRecipeSourceText", id))
      if type(src) == "string" and src ~= "" then
        recipe.src = src
      end
    end
    if type(info) == "table" and plain(info.learned) then
      snap.learned[id] = true
      local cooldown = call(api, "GetRecipeCooldown", id)
      if type(cooldown) == "number" and cooldown > 0 then
        snap.cooldowns[id] = now + cooldown
      end
    end
  end
  return snap
end

-- Save a snapshot for a character: the profession's catalog (shared) and what this character knows.
function Professions.Save(db, charKey, snap, now)
  db.catalog = db.catalog or {}
  db.chars = db.chars or {}
  db.catalog[snap.skillLine] = { at = now, name = snap.name, recipes = snap.recipes }
  local char = db.chars[charKey] or {}
  db.chars[charKey] = char
  char.professions = char.professions or {}
  char.professions[snap.skillLine] = {
    name = snap.name,
    skill = snap.skill,
    max = snap.max,
    at = now,
    learned = snap.learned,
    cooldowns = snap.cooldowns,
  }
end

-- The character's professions from the spellbook (known even before their windows were opened).
-- getProfessions / getProfessionInfo: the client's GetProfessions / GetProfessionInfo.
function Professions.Spellbook(getProfessions, getProfessionInfo)
  local out = {}
  if not (getProfessions and getProfessionInfo) then
    return out
  end
  local ok, a, b, c, d, e = pcall(getProfessions)
  if not ok then
    return out
  end
  for _, index in ipairs({ a or false, b or false, c or false, d or false, e or false }) do
    if index then
      local ok2, name, _, rank, maxRank, _, _, skillLine = pcall(getProfessionInfo, index)
      if ok2 and plain(name) then
        out[#out + 1] = { name = plain(name), skill = plain(rank), max = plain(maxRank), skillLine = plain(skillLine) }
      end
    end
  end
  return out
end

-- Professions recorded for every character: { [charKey] = { professions = {...}, spellbook = {...} } }
function Professions:Characters()
  return AME_DB.crafting and AME_DB.crafting.chars or {}
end

-- Pure: what the recorded professions leave out. The spellbook's professions whose window hasn't been opened on that
-- character (noWindow ones - Herbalism, Skinning, Fishing - have no window: their skill is all there is to know),
-- and characters known only from elsewhere (others: their bags were seen) with nothing recorded at all.
--   chars: Professions:Characters(); others: { charKey, ... }; noWindow: { [skillLine] = true }
--   -> { { key, skillLine, name, skill, max, noWindow } | { key, none = true } }, by key, then name
function Professions.Unrecorded(chars, others, noWindow)
  local out = {}
  for key, c in pairs(chars or {}) do
    for _, s in ipairs(c.spellbook or {}) do
      if s.skillLine and not (c.professions and c.professions[s.skillLine]) then
        out[#out + 1] = {
          key = key,
          skillLine = s.skillLine,
          name = s.name,
          skill = s.skill,
          max = s.max,
          noWindow = noWindow and noWindow[s.skillLine] or false,
        }
      end
    end
  end
  for _, key in ipairs(others or {}) do
    if not (chars and chars[key]) then
      out[#out + 1] = { key = key, none = true }
    end
  end
  table.sort(out, function(a, b)
    if a.key ~= b.key then
      return a.key < b.key
    end
    return (a.name or "") < (b.name or "")
  end)
  return out
end

-- a profession's recipes (recorded by any character): { [recipeID] = recipe } or nil
function Professions:Catalog(skillLine)
  local c = AME_DB.crafting and AME_DB.crafting.catalog and AME_DB.crafting.catalog[skillLine]
  return c and c.recipes
end

function Professions:Record()
  local snap = Professions.Snapshot(C_TradeSkillUI, GetServerTime())
  if not snap then
    return
  end
  AME_DB.crafting = AME_DB.crafting or {}
  Professions.Save(AME_DB.crafting, ns.Trading.CharKey(), snap, GetServerTime())
  self.changed = true -- goes out with the next sync (who can make it)
  if ns.RecipeSources then
    ns.RecipeSources.CatalogChanged()
  end
  ns.Events.Fire("RecipesChanged", snap.skillLine)
end

function Professions:RecordSpellbook()
  AME_DB.crafting = AME_DB.crafting or {}
  local chars = AME_DB.crafting.chars or {}
  AME_DB.crafting.chars = chars
  local key = ns.Trading.CharKey()
  chars[key] = chars[key] or {}
  chars[key].spellbook = Professions.Spellbook(_G.GetProfessions, _G.GetProfessionInfo)
end

-- A recipe learned (from a recipe item, say) with no profession window open, which Record can't read: marked as
-- learned for its profession (the one whose recorded catalog has it, else the crafting data's)
function Professions:Learned(recipeID)
  recipeID = plain(recipeID)
  local db = AME_DB.crafting
  local char = db and db.chars and db.chars[ns.Trading.CharKey()]
  if not (type(recipeID) == "number" and char and char.professions) then
    return
  end
  local skillLine
  for line, c in pairs(db.catalog or {}) do
    if c.recipes and c.recipes[recipeID] then
      skillLine = line
    end
  end
  if not skillLine and ns.CraftingData and ns.CraftingData.data then
    local r = ns.CraftingData:Recipe(recipeID)
    skillLine = r and r.profession
  end
  local p = skillLine and char.professions[skillLine]
  if not p then
    return
  end
  p.learned = p.learned or {}
  p.learned[recipeID] = true
  self.changed = true
  ns.Events.Fire("RecipesChanged", skillLine)
end

-- Listen for profession windows (and skill changes). Reading waits for the burst of events to settle.
function Professions:Start()
  if self.frame or not C_TradeSkillUI then
    return
  end
  local f = CreateFrame("Frame")
  self.frame = f
  local pending = false
  for _, e in ipairs({
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "NEW_RECIPE_LEARNED",
    "SKILL_LINES_CHANGED",
  }) do
    pcall(f.RegisterEvent, f, e) -- tolerate events a client flavour doesn't have
  end
  f:SetScript("OnEvent", function(_, event, arg)
    if event == "SKILL_LINES_CHANGED" then
      Professions:RecordSpellbook()
      return
    end
    if event == "NEW_RECIPE_LEARNED" then
      Professions:Learned(arg) -- then read the window too, when one is open
    end
    if pending then
      return
    end
    pending = true
    C_Timer.After(Professions.DEBOUNCE, function()
      pending = false
      Professions:Record()
    end)
  end)
  self:RecordSpellbook()
end
