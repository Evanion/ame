-- Where a recipe comes from, for the recipe item's tooltip ("Sold by Kulwia, Stonetalon · 1g 20s", "Drops from ...").
-- The game's client data doesn't say who sells or drops a pattern, so AME learns it as you play, and your guild shares
-- what it learned:
--   - the profession window: the game's own source text for each recipe you haven't learned (Professions records it
--     in the catalog: recipe.src)
--   - a merchant: the recipe items it sells, with the NPC, the zone and the price
--   - loot: a recipe item you loot, with what dropped it and where
--
--   AME_DB.recipeSources = { [itemID] = { { kind = "vendor" | "drop", npc, zone, price, t, by }, ... } }
-- Add / Lines are pure; Encode / Decode are the sync message's body.
local _, ns = ...
local L = ns.L
local Codec = ns.Codec

local RS = {}
ns.RecipeSources = RS

RS.MAX_PER_ITEM = 4
RS.MAX_SHARE = 300 -- sources in one message

-- The game hands out some text as secret values (a unit's name in combat, say): addons may pass them on but not read
-- them, so they can't be kept, compared or sent. plain(s): s when it's a readable string, else nil.
local function plain(s)
  local secret = _G.issecretvalue
  if s == nil or (secret and secret(s)) or type(s) ~= "string" or s == "" then
    return nil
  end
  return s
end
RS.Plain = plain

local function clean(s)
  return ((plain(s) or ""):gsub("[|;:~]", ""):sub(1, 48))
end

-- add a source (the same NPC and zone once: a newer sighting updates its price and time)
function RS.Add(db, itemID, src)
  src.npc, src.zone = plain(src.npc), plain(src.zone)
  if not src.npc then
    return false -- who sells or drops it is the point
  end
  local list = db[itemID] or {}
  db[itemID] = list
  for _, e in ipairs(list) do
    if e.kind == src.kind and e.npc == src.npc and e.zone == src.zone then
      if (src.t or 0) > (e.t or 0) then
        e.price, e.t = src.price or e.price, src.t
      end
      return false
    end
  end
  list[#list + 1] = src
  table.sort(list, function(a, b)
    if a.kind ~= b.kind then
      return a.kind == "vendor"
    end
    return (a.t or 0) > (b.t or 0)
  end)
  while #list > RS.MAX_PER_ITEM do
    table.remove(list)
  end
  return true
end

-- the tooltip's lines for a recipe item: { text, ... } (vendors first, then drops, then the game's own text)
function RS.Lines(list, gameText, money)
  local out = {}
  for _, e in ipairs(list or {}) do
    if e.kind == "vendor" then
      local where = e.zone and e.zone ~= "" and (", " .. e.zone) or ""
      out[#out + 1] = L["Sold by %s"]:format(e.npc or "?") .. where .. (e.price and ("  ·  " .. money(e.price)) or "")
    elseif e.kind == "drop" then
      out[#out + 1] = L["Drops from %s"]:format(e.npc or "?") .. (e.zone and e.zone ~= "" and (", " .. e.zone) or "")
    end
  end
  if #out == 0 and gameText and gameText ~= "" then
    -- the game's text: "Vendor: X|nZone: Y|nCost: Z", colour codes and all, on one line
    local text = gameText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "  ·  "):gsub("\n", "  ·  ")
    text = text:gsub("|T.-|t", "")
    out[#out + 1] = text
  end
  return out
end

-- the sync message's body: "<item36>~<kind v|d>~<npc>~<zone>~<price36>;..."
function RS.Encode(db, since)
  local parts = {}
  for itemID, list in pairs(db) do
    for _, e in ipairs(list) do
      if plain(e.npc) and (not since or (e.t or 0) >= since) then
        parts[#parts + 1] = table.concat({
          Codec.ToBase36(itemID),
          e.kind == "vendor" and "v" or "d",
          clean(e.npc),
          clean(e.zone),
          e.price and Codec.ToBase36(e.price) or "",
        }, "~")
        if #parts >= RS.MAX_SHARE then
          return table.concat(parts, ";")
        end
      end
    end
  end
  return table.concat(parts, ";")
end

function RS.Decode(text, t, by)
  local out = {}
  for part in tostring(text or ""):gmatch("[^;]+") do
    local id, kind, npc, zone, price = part:match("^(%w+)~([vd])~([^~]*)~([^~]*)~(%w*)$")
    if id then
      out[#out + 1] = {
        item = Codec.FromBase36(id),
        src = {
          kind = kind == "v" and "vendor" or "drop",
          npc = npc ~= "" and npc or nil,
          zone = zone ~= "" and zone or nil,
          price = price ~= "" and Codec.FromBase36(price) or nil,
          t = t,
          by = by,
        },
      }
    end
  end
  return out
end

---------------------------------------------------------------------------------------------------------------------
-- in game

local cleaned = false
local function db()
  AME_DB.recipeSources = AME_DB.recipeSources or {}
  if not cleaned then
    -- sources an older version recorded from secret text: dropped (they can't be read, shown or shared)
    cleaned = true
    for itemID, list in pairs(AME_DB.recipeSources) do
      for i = #list, 1, -1 do
        if not plain(list[i].npc) then
          table.remove(list, i)
        elseif list[i].zone ~= nil and not plain(list[i].zone) then
          list[i].zone = nil
        end
      end
      if #list == 0 then
        AME_DB.recipeSources[itemID] = nil
      end
    end
  end
  return AME_DB.recipeSources
end
RS.DB = db

local function isRecipe(itemID)
  local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
  if not (instant and itemID) then
    return false
  end
  local classID = select(6, instant(itemID))
  return classID == 9 -- Enum.ItemClass.Recipe
end
RS.IsRecipe = isRecipe

-- a tool some recorded recipe needs (Professions: recipe.toolIDs): merchants selling one are noted too, so the
-- Crafting tab's Tools section can say where to buy it. Built once per catalog change (RS.CatalogChanged).
local toolSet
function RS.IsTool(itemID)
  if not toolSet then
    toolSet = {}
    for _, c in pairs(AME_DB and AME_DB.crafting and AME_DB.crafting.catalog or {}) do
      for _, r in pairs(c.recipes or {}) do
        for _, id in pairs(r.toolIDs or {}) do
          toolSet[id] = true
        end
      end
    end
  end
  return itemID ~= nil and toolSet[itemID] == true
end

local function zone()
  return (_G.GetRealZoneText and _G.GetRealZoneText()) or (_G.GetZoneText and _G.GetZoneText()) or nil
end

-- a merchant's window: the recipe items it sells, and tools recipes need
function RS:RecordMerchant()
  local n = _G.GetMerchantNumItems and _G.GetMerchantNumItems() or 0
  local npc = UnitName and UnitName("npc")
  if n == 0 or not npc then
    return
  end
  local now, any = GetServerTime(), false
  for i = 1, n do
    local link = _G.GetMerchantItemLink and _G.GetMerchantItemLink(i)
    local id = link and ns.ItemCache.Learn(link)
    if id and (RS.IsRecipe(id) or RS.IsTool(id)) then
      local price
      local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(i)
      if type(info) == "table" then
        price = info.price
      elseif _G.GetMerchantItemInfo then
        price = select(3, _G.GetMerchantItemInfo(i))
      end
      any = RS.Add(db(), id, { kind = "vendor", npc = npc, zone = zone(), price = price, t = now }) or any
    end
  end
  if any then
    self.changed = true
  end
end

-- loot: recipe items, and what dropped them (the target you killed, where you are)
function RS:RecordLoot()
  local n = _G.GetNumLootItems and _G.GetNumLootItems() or 0
  local now = GetServerTime()
  for i = 1, n do
    local link = _G.GetLootSlotLink and _G.GetLootSlotLink(i)
    local id = link and ns.ItemCache.Learn(link)
    if id and RS.IsRecipe(id) then
      local npc = UnitName and UnitIsDead and UnitIsDead("target") and UnitName("target") or nil
      if npc and RS.Add(db(), id, { kind = "drop", npc = npc, zone = zone(), t = now }) then
        self.changed = true
      end
    end
  end
end

-- the recipe an item teaches: the shipped data, else by name ("Plans: Heavy Mithril Gauntlet" -> the recipe whose
-- spell is "Heavy Mithril Gauntlet", among the ones your profession windows recorded)
local byName
local function recipeOf(itemID)
  local data = ns.CraftingData
  local t = data and data.data and data:Teaches(itemID)
  if t and t.spells and t.spells[1] then
    return t.spells[1]
  end
  local name = ns.ItemCache.Name(itemID)
  local bare = name and name:match("^[^:]+:%s*(.+)$")
  if not bare then
    return nil
  end
  if not byName then
    byName = {}
    for _, c in pairs(AME_DB.crafting and AME_DB.crafting.catalog or {}) do
      for id in pairs(c.recipes or {}) do
        local n = ns.Crafters and ns.Crafters.RecipeName(id)
        if n then
          byName[n] = id
        end
      end
    end
  end
  return byName[bare]
end

function RS.CatalogChanged()
  byName, toolSet = nil, nil
end

-- the game's own source text for the recipe an item teaches (recorded from a profession window), or nil
local function gameText(itemID)
  local recipe = recipeOf(itemID)
  if not recipe then
    return nil
  end
  for _, c in pairs(AME_DB.crafting and AME_DB.crafting.catalog or {}) do
    local r = c.recipes and c.recipes[recipe]
    if r and r.src then
      return r.src
    end
  end
end

-- the recipe item's tooltip lines (nil when it isn't a recipe or nothing is known)
function RS.TooltipLines(itemID)
  if not (AME_DB and RS.IsRecipe(itemID)) then
    return nil
  end
  local lines = RS.Lines(db()[itemID], gameText(itemID), function(c)
    return ns.Widgets.Money(c)
  end)
  return #lines > 0 and lines or nil
end

-- what arrived from a guildmate
function RS:Merge(text, t, by)
  local any = false
  for _, e in ipairs(RS.Decode(text, t, by)) do
    any = RS.Add(db(), e.item, e.src) or any
  end
  return any
end

function RS:Start()
  if self.frame or not CreateFrame then
    return
  end
  local f = CreateFrame("Frame")
  self.frame = f
  pcall(f.RegisterEvent, f, "MERCHANT_SHOW")
  pcall(f.RegisterEvent, f, "LOOT_OPENED")
  f:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
      C_Timer.After(0.5, function() -- the merchant's items load a moment after it opens
        RS:RecordMerchant()
      end)
    else
      RS:RecordLoot()
    end
  end)
end
