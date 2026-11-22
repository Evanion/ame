-- Who can make it: the recipes your guildmates' and trusted players' characters know, shared over sync, and your own
-- characters' (recorded when their profession windows open). Recipe IDs only - names come from the client.
--
--   AME_DB.crafters = { [charName] = { owner = sender, t,
--                       profs = { [skillLine] = { skill, ids = { [recipeID] = true } } } } }
--
-- Crafters.Encode / Decode are the message body (pure); Crafters.New(db) keeps what arrived. Who knows a recipe:
-- Crafters:Who(recipeID, mine) -> { { name, owner, skill, t, mine, online } } (yours first, then online, then latest).
-- Crafters:Players(): how many players (senders) the recipes came from.
local _, ns = ...
local Codec = ns.Codec

local Crafters = {}
Crafters.__index = Crafters
ns.Crafters = Crafters

Crafters.MAX_AGE = 30 * 86400 -- a crafter not heard from in 30 days drops off
Crafters.MAX_IDS = 2000 -- per character, all professions (a sanity cap on what's taken in)

-- one character's professions as text: "<skillLine36>.<skill36>.<id36>,<id36>,...;..." (ids sorted)
function Crafters.Encode(profs)
  local lines, order = {}, {}
  for skillLine in pairs(profs or {}) do
    order[#order + 1] = skillLine
  end
  table.sort(order)
  for _, skillLine in ipairs(order) do
    local p = profs[skillLine]
    local ids = {}
    for id in pairs(p.ids or {}) do
      ids[#ids + 1] = id
    end
    table.sort(ids)
    for i, id in ipairs(ids) do
      ids[i] = Codec.ToBase36(id)
    end
    if #ids > 0 then
      lines[#lines + 1] = Codec.ToBase36(skillLine)
        .. "."
        .. Codec.ToBase36(p.skill or 0)
        .. "."
        .. table.concat(ids, ",")
    end
  end
  return table.concat(lines, ";")
end

function Crafters.Decode(text)
  local profs, n = {}, 0
  for line in tostring(text or ""):gmatch("[^;]+") do
    local skillLine, skill, ids = line:match("^(%w+)%.(%w+)%.([%w,]+)$")
    if skillLine then
      local p = { skill = Codec.FromBase36(skill), ids = {} }
      for id in ids:gmatch("[^,]+") do
        n = n + 1
        if n > Crafters.MAX_IDS then
          break
        end
        p.ids[Codec.FromBase36(id)] = true
      end
      profs[Codec.FromBase36(skillLine)] = p
    end
  end
  return profs
end

function Crafters.New(db)
  return setmetatable({ db = db }, Crafters)
end

-- what guildmates and trusted players shared (AME_DB.crafters), pruned once a session
function Crafters.Shared()
  if not AME_DB then
    return nil
  end
  AME_DB.crafters = AME_DB.crafters or {}
  if not Crafters.shared or Crafters.shared.db ~= AME_DB.crafters then
    Crafters.shared = Crafters.New(AME_DB.crafters)
    Crafters.shared:Prune(GetServerTime())
  end
  return Crafters.shared
end

-- what a sender says one of their characters knows (newer replaces older)
function Crafters:Set(owner, char, t, profs)
  local cur = self.db[char]
  if cur and cur.owner ~= owner and cur.t and t and cur.t > t then
    return false -- someone else claimed this name more recently
  end
  if cur and cur.owner == owner and cur.t and t and cur.t >= t then
    return false
  end
  self.db[char] = { owner = owner, t = t, profs = profs }
  return true
end

function Crafters:Prune(now)
  for name, c in pairs(self.db) do
    if not c.t or now - c.t > Crafters.MAX_AGE then
      self.db[name] = nil
    end
  end
end

-- who knows a recipe. mine: { [charName] = { skill } } your own characters that know it; online(name) -> true/false
function Crafters:Who(recipeID, mine, online)
  local out, seen = {}, {}
  for name, m in pairs(mine or {}) do
    out[#out + 1] = { name = name, skill = m.skill, mine = true, online = true }
    seen[name] = true
  end
  for name, c in pairs(self.db) do
    if not seen[name] then
      for _, p in pairs(c.profs or {}) do
        if p.ids and p.ids[recipeID] then
          out[#out + 1] =
            { name = name, owner = c.owner, skill = p.skill, t = c.t, online = online and online(name) or false }
          break
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.mine ~= b.mine then
      return a.mine
    end
    if a.online ~= b.online then
      return a.online
    end
    if (a.t or 0) ~= (b.t or 0) then
      return (a.t or 0) > (b.t or 0)
    end
    return a.name < b.name
  end)
  return out
end

-- how many players the recipes came from: the senders (one player's characters count once)
function Crafters:Players()
  local owners, n = {}, 0
  for name, c in pairs(self.db) do
    local who = c.owner or name
    if not owners[who] then
      owners[who], n = true, n + 1
    end
  end
  return n
end

-- every recipe anyone in the list knows: { [recipeID] = true }
function Crafters:Known()
  local out = {}
  for _, c in pairs(self.db) do
    for _, p in pairs(c.profs or {}) do
      for id in pairs(p.ids or {}) do
        out[id] = true
      end
    end
  end
  return out
end

---------------------------------------------------------------------------------------------------------------------
-- in game: your own characters, names, and who's online

local function market()
  return ns.AME:MarketRealmName() .. ":"
end

-- your characters on this market and what they know: { [charName] = { profs = { [skillLine] = { skill, ids } } } }
function Crafters.Mine()
  local out, prefix = {}, market()
  for key, ch in pairs(AME_DB.crafting and AME_DB.crafting.chars or {}) do
    if key:sub(1, #prefix) == prefix then
      local profs = {}
      for skillLine, p in pairs(ch.professions or {}) do
        profs[skillLine] = { skill = p.skill, ids = p.learned or {} }
      end
      out[key:sub(#prefix + 1)] = { profs = profs }
    end
  end
  return out
end

local function mineFor(recipeID)
  local out = {}
  for name, c in pairs(Crafters.Mine()) do
    for _, p in pairs(c.profs) do
      if p.ids[recipeID] then
        out[name] = { skill = p.skill }
      end
    end
  end
  return out
end

-- guildmates online right now (the guild roster)
local onlineCache, onlineAt
local function online(name)
  local now = GetTime and GetTime() or 0
  if not onlineCache or now - (onlineAt or 0) > 30 then
    onlineCache, onlineAt = {}, now
    local count = _G.GetNumGuildMembers and _G.GetNumGuildMembers() or 0
    for i = 1, count do
      local full, _, _, _, _, _, _, _, isOnline = _G.GetGuildRosterInfo(i)
      if full and isOnline then
        onlineCache[full] = true
        onlineCache[(full:gsub("%-.*$", ""))] = true
      end
    end
  end
  return onlineCache[name] or false
end

function Crafters:WhoKnows(recipeID)
  return self:Who(recipeID, mineFor(recipeID), online)
end

-- a recipe's name: its spell's (enchants and crafts alike), else what it makes
local function recipeName(recipeID)
  local spell = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID))
    or (_G.GetSpellInfo and (_G.GetSpellInfo(recipeID)))
  if spell then
    return spell
  end
  local r = ns.Recipes.Get(recipeID)
  return r and r.product and ns.ItemCache.Name(r.product) or nil
end
Crafters.RecipeName = recipeName

-- the recipes that make an item (your characters' recorded windows, and the shipped data when it's loaded)
local shippedBy -- product itemID -> { recipe spell, ... } from the shipped data (built once it's loaded)
function Crafters.RecipesFor(itemID)
  local out, seen = {}, {}
  for _, p in ipairs(ns.Recipes.Producers(itemID)) do
    out[#out + 1], seen[p.recipe] = p.recipe, true
  end
  local data = ns.CraftingData
  if data and data.data then
    if not shippedBy then
      shippedBy = {}
      for spell in pairs(data.data.recipes or {}) do
        local r = data:Recipe(spell)
        if r and r.product then
          shippedBy[r.product] = shippedBy[r.product] or {}
          table.insert(shippedBy[r.product], spell)
        end
      end
    end
    for _, spell in ipairs(shippedBy[itemID] or {}) do
      if not seen[spell] then
        out[#out + 1], seen[spell] = spell, true
      end
    end
  end
  return out
end

-- recipes whose name has the text in it, with who knows each: { { recipe, name, who = {...} } }, most crafters first
function Crafters:Search(text)
  text = tostring(text or ""):lower()
  if text == "" then
    return {}
  end
  local ids = self:Known()
  for _, c in pairs(Crafters.Mine()) do
    for _, p in pairs(c.profs) do
      for id in pairs(p.ids) do
        ids[id] = true
      end
    end
  end
  local out = {}
  for id in pairs(ids) do
    local n = recipeName(id)
    if n and n:lower():find(text, 1, true) then
      out[#out + 1] = { recipe = id, name = n, who = self:WhoKnows(id) }
    end
  end
  table.sort(out, function(a, b)
    if #a.who ~= #b.who then
      return #a.who > #b.who
    end
    return a.name < b.name
  end)
  return out
end
