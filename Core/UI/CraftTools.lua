-- The tools a recipe needs, and how to get them (the Crafting tab's Top earners sidebar, its Tools section): each tool
-- the profession window named (Professions: recipe.tools, item IDs in recipe.toolIDs), whether one of your characters
-- has it, and the ways to get one - make it (a recipe of yours; else the pattern that teaches it, with its price and
-- where it's sold), buy it from a vendor (who and where, as seen; else "vendors" and the shipped price), or the
-- auction house. A place to make it ("at an Anvil": recipe.at) is shown too.
--
--   UI.CraftTools(recipe, env) -> { tools = { tool, ... }, at = { name, ... } } or nil (no tool, no place)
--     tool = { id, name, held = { total, chars = { name, ... } }, ways = { way, ... } }
--     way  = { kind = "known", who, profession }                           a character of yours makes it
--          | { kind = "make", profession, skill, patterns = { { item, price, source }, ... } }
--          | { kind = "vendor", npc, zone, price } | { kind = "vendors", price } | { kind = "ah", price }
--   env: what it reads, injectable for tests - market(id), held(id), recipesFor(id), producers(id), recipe(id),
--        taughtBy(spell), vendorPrice(id), sources(id), profession(skillLine), keyByName(name)
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

local function charName(key)
  return key and key:match("[^:]+$") or key
end

-- the game's own data and AME's, read in game
function UI.CraftToolsEnv()
  local index = ns.AME and ns.AME.FactionIndex and ns.AME:FactionIndex()
  local db = AME_DB and AME_DB.crafting or {}
  return {
    market = function(id)
      local s = index and index.items[id]
      return s and s.market
    end,
    held = function(id)
      return ns.Trading and ns.Trading.Held and ns.Trading.Held(id)
    end,
    recipesFor = function(id)
      return ns.Crafters and ns.Crafters.RecipesFor and ns.Crafters.RecipesFor(id) or {}
    end,
    producers = function(id)
      return ns.Recipes.Producers(id)
    end,
    recipe = function(id)
      return ns.Recipes.Get(id)
    end,
    taughtBy = function(spell)
      return ns.Recipes.TaughtBy(spell)
    end,
    vendorPrice = function(id)
      return ns.CraftingData and ns.CraftingData.VendorPrice and ns.CraftingData:VendorPrice(id)
    end,
    sources = function(id)
      return ns.RecipeSources and ns.RecipeSources.DB and ns.RecipeSources.DB()[id]
    end,
    profession = function(skillLine)
      local c = db.catalog and db.catalog[skillLine]
      if c and c.name then
        return c.name
      end
      for _, ch in pairs(ns.Professions:Characters()) do
        local p = ch.professions and ch.professions[skillLine]
        if p and p.name then
          return p.name
        end
      end
      return nil
    end,
    keyByName = function(name)
      return ns.ItemCache.KeyByName and ns.ItemCache.KeyByName(name)
    end,
  }
end

-- where something is sold, from what AME has seen: the first vendor sighting
local function vendorOf(env, id)
  for _, s in ipairs(env.sources(id) or {}) do
    if s.kind == "vendor" then
      return s
    end
  end
end

function UI.CraftTools(recipe, env)
  if not recipe or not ((recipe.tools and #recipe.tools > 0) or (recipe.at and #recipe.at > 0)) then
    return nil
  end
  env = env or UI.CraftToolsEnv()
  local out = { tools = {}, at = recipe.at }
  for _, name in ipairs(recipe.tools or {}) do
    local id = recipe.toolIDs and recipe.toolIDs[name] or env.keyByName(name)
    local tool = { id = id, name = name, ways = {} }
    if id then
      -- yours: who has one
      local h = env.held(id)
      if h and (h.total or 0) > 0 then
        local names = {}
        for key, n in pairs(h.chars or {}) do
          if n > 0 then
            names[#names + 1] = charName(key)
          end
        end
        table.sort(names)
        tool.held = { total = h.total, chars = names }
      end
      -- make it: a character of yours who knows a recipe for it, else the pattern that teaches one
      local known = env.producers(id)
      if known[1] and known[1].crafters and known[1].crafters[1] then
        local r = env.recipe(known[1].recipe)
        tool.ways[#tool.ways + 1] = {
          kind = "known",
          who = charName(known[1].crafters[1]),
          profession = r and env.profession(r.profession),
        }
      else
        local spell = env.recipesFor(id)[1] -- one recipe is enough to say how
        if spell then
          local r = env.recipe(spell)
          local way = { kind = "make", profession = r and env.profession(r.profession), patterns = {} }
          for _, t in ipairs(env.taughtBy(spell)) do
            way.skill = way.skill or t.rank
            local v = vendorOf(env, t.item)
            way.patterns[#way.patterns + 1] = {
              item = t.item,
              price = env.market(t.item),
              source = v and { npc = v.npc, zone = v.zone, price = v.price },
            }
          end
          way.skill = way.skill or (r and r.yellow)
          tool.ways[#tool.ways + 1] = way
        end
      end
      -- buy it: a vendor seen selling it, else the shipped vendor price; the auction house
      local v = vendorOf(env, id)
      if v then
        tool.ways[#tool.ways + 1] = { kind = "vendor", npc = v.npc, zone = v.zone, price = v.price }
      elseif env.vendorPrice(id) then
        tool.ways[#tool.ways + 1] = { kind = "vendors", price = env.vendorPrice(id) }
      end
      local ah = env.market(id)
      if ah then
        tool.ways[#tool.ways + 1] = { kind = "ah", price = ah }
      end
    end
    out.tools[#out.tools + 1] = tool
  end
  return out
end

-- the Tools section's blocks for UI:LayoutCraftingDetail: a heading, a card per tool (the tool a link; whether yours
-- has one; each way to get one as a row, a pattern as a link with its price and where it's sold), and the place to
-- make it
function UI.CraftToolBlocks(t)
  if not t then
    return {}
  end
  local blocks = { { heading = L["Tools"] } }
  for _, tool in ipairs(t.tools) do
    local have = tool.held and W.Color("good", L["%s has one"]:format(table.concat(tool.held.chars, ", ")))
      or W.Color("warn", L["none of yours has one"])
    local rows = {}
    for _, w in ipairs(tool.ways) do
      if w.kind == "known" then
        rows[#rows + 1] = {
          label = L["Make it: %s knows it"]:format(w.who)
            .. (w.profession and W.Dim(" (" .. w.profession .. ")") or ""),
        }
      elseif w.kind == "make" then
        local what = w.profession and (w.skill and ("%s %d"):format(w.profession, w.skill) or w.profession)
        rows[#rows + 1] = {
          label = L["Make it: %s"]:format(what or L["a recipe"]) .. " " .. W.Dim(L["(none of yours knows it)"]),
        }
        for _, p in ipairs(w.patterns) do
          rows[#rows + 1] = {
            item = p.item,
            label = "",
            copper = p.price,
            text = not p.price and W.Dim(L["not on the AH"]) or nil,
          }
          if p.source then
            local where = p.source.npc .. (p.source.zone and (", " .. p.source.zone) or "")
            rows[#rows + 1] = { label = "   " .. W.Dim(L["Sold by %s"]:format(where)), copper = p.source.price }
          end
        end
      elseif w.kind == "vendor" then
        local where = w.npc .. (w.zone and (", " .. w.zone) or "")
        rows[#rows + 1] = { label = L["Sold by %s"]:format(where), copper = w.price }
      elseif w.kind == "vendors" then
        rows[#rows + 1] = { label = L["Sold by vendors"], copper = w.price }
      elseif w.kind == "ah" then
        rows[#rows + 1] = { label = L["On the auction house"], copper = w.price }
      end
    end
    if #rows == 0 and not tool.held then
      rows[1] = { label = W.Dim(L["AME doesn't know where to get one yet."]) }
    end
    blocks[#blocks + 1] = {
      card = {
        item = tool.id,
        title = not tool.id and tool.name or nil,
        subtitle = have,
        rows = rows,
      },
    }
  end
  if t.at and #t.at > 0 then
    -- where it's made, in the game's words ("Requires Anvil")
    blocks[#blocks + 1] = { card = { title = L["Requires %s"]:format(table.concat(t.at, ", ")) } }
  end
  return blocks
end
