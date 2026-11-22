-- Namespace and shared constants. Pure: no WoW API calls (loaded by busted specs too).
local _, ns = ...

ns.VERSION = "dev" -- stamped with the release version by scripts/package.sh

-- Translated text. Core\Locale.lua sets it up in game; specs that load modules directly get the English key back.
ns.L = ns.L or setmetatable({}, {
  __index = function(_, key)
    return key
  end,
})
local L = ns.L

ns.HOUSES = { Alliance = true, Horde = true, Neutral = true }
ns.HOUSE_ORDER = { "Alliance", "Horde", "Neutral" }

-- Text colours by role ("RRGGBB" for |c escapes), shared by the window (ns.Widgets.HEX) and chat lines.
ns.HEX = {
  dim = "999999", -- secondary text
  none = "777777", -- missing values ("-")
  bad = "ff6159", -- losses, errors, SELL
  good = "4dd973", -- gains, on, BUY
  warn = "ffcc00", -- warnings
  hold = "ffcc33", -- HOLD, purchases
  wait = "8fa3b8", -- WAIT
  vendor = "c8a272", -- VENDOR
  disenchant = "b49cff", -- DE (disenchant)
  brand = "33ccff", -- "AME" / "Azeroth" in chat and titles
  gold = "ffd100", -- the gold unit, "Post at"
  link = "8bb8ff", -- actions written as text ("+ New list")
  soft = "cfcdc7", -- quieter lines in a list (subclasses)
  white = "ffffff",
}

-- text in a role's colour: ns.Color("bad", "failed") -> "|cffff6159failed|r"
function ns.Color(key, text)
  return "|cff" .. (ns.HEX[key] or key) .. tostring(text) .. "|r"
end

ns.DAY = 86400
-- day number of a server time (UTC days, as history is stored)
function ns.Today(t)
  return math.floor(t / ns.DAY)
end

-- Item keys. Random-suffix gear ("Raider Shortsword of Magic" vs "... of the Monkey") sells at very different prices,
-- so each suffix is tracked as its own item: key = itemID + SUFFIX_STEP * suffix, where suffix is the auction house's
-- item key suffix (ItemKey.itemSuffix; scans and searches report it). A plain item's key is its item ID. SUFFIX_STEP is
-- a multiple of the store's bucket count, so a variant shares its base item's bucket. Keys can exceed 2^31: format
-- them with tostring, never "%d".
--
-- Item links name the suffix differently: Classic links in their suffix field, WoW Forever's links as bonus IDs (the
-- suffix field is empty). ns.suffixMap (learned by ItemCache from APIs that give both a link and an item key, saved)
-- maps a link's bonus IDs to the auction house's suffix: ["itemID:bonus,bonus"] for that item, ["bonus,bonus"] for any.
ns.SUFFIX_STEP = 1000000
ns.suffixMap = ns.suffixMap or {}

function ns.ItemKey(itemID, suffix)
  if not itemID then
    return nil
  end
  suffix = tonumber(suffix) or 0
  return itemID + ns.SUFFIX_STEP * suffix
end

-- key -> itemID, suffix (0 for a plain item)
function ns.SplitKey(key)
  local id = key % ns.SUFFIX_STEP
  return id, (key - id) / ns.SUFFIX_STEP
end

function ns.BaseID(key)
  return key and key % ns.SUFFIX_STEP
end

function ns.IsVariant(key)
  return key ~= nil and key ~= key % ns.SUFFIX_STEP
end

-- A variant's item string, with the bonus that gives it its suffix and stats: its own, learned from a link; else
-- built from another item's with the same suffix (a suffix is the same bonus on every item: "of the Bear" is 12917
-- wherever it rolls); else from the bonus ns.suffixMap learned for that suffix. nil when AME knows none.
function ns.VariantString(key)
  local known = ns.itemStrings and ns.itemStrings[key]
  if known or not ns.IsVariant(key) then
    return known
  end
  local id, suffix = ns.SplitKey(key)
  for other, s in pairs(ns.itemStrings or {}) do
    if
      other ~= key
      and other % ns.SUFFIX_STEP ~= other
      and (other - other % ns.SUFFIX_STEP) / ns.SUFFIX_STEP == suffix
    then
      local built = s:gsub("^item:%d+", "item:" .. id, 1)
      return built
    end
  end
  for bonuses, s in pairs(ns.suffixMap or {}) do
    if s == suffix and not tostring(bonuses):find(":", 1, true) then
      local list = {}
      for b in tostring(bonuses):gmatch("[^,]+") do
        list[#list + 1] = b
      end
      return "item:" .. id .. "::::::::::::" .. #list .. ":" .. table.concat(list, ":")
    end
  end
end

-- an item string the client's item APIs and tooltips accept: a variant's own (see VariantString) when known, else
-- "item:2207" / the Classic form "item:2207::::::1234"
function ns.ItemString(key)
  local known = ns.VariantString(key)
  if known then
    return known
  end
  local id, suffix = ns.SplitKey(key)
  if suffix == 0 then
    return "item:" .. id
  end
  return "item:" .. id .. "::::::" .. tostring(suffix)
end

-- Fields of an item link or item string: itemID, the suffix field (0 if empty), the bonus IDs as "a,b" (nil if none),
-- and the item string itself. item:itemID:enchant:gem1:gem2:gem3:gem4:suffix:unique:linkLevel:spec:modifiersMask:
-- context:numBonusIDs:bonusID...
function ns.ParseItemString(text)
  if type(text) ~= "string" then
    return nil
  end
  local fields = text:match("item:([%-:%d]+)")
  if not fields then
    return nil
  end
  local parts, n = {}, 0
  for f in (fields .. ":"):gmatch("([^:]*):") do
    n = n + 1
    parts[n] = f
  end
  local id = tonumber(parts[1])
  if not id then
    return nil
  end
  local bonuses
  local count = tonumber(parts[13]) or 0
  if count > 0 then
    local list = {}
    for k = 1, count do
      list[k] = parts[13 + k] or ""
    end
    bonuses = table.concat(list, ",")
  end
  return id, tonumber(parts[7]) or 0, bonuses, "item:" .. fields
end

-- item key from an item link or item string, or from text that is just a number; nil otherwise. A Forever link's
-- variant resolves once its bonus IDs are in ns.suffixMap (until then: the plain item ID).
function ns.ItemIDFrom(text)
  if type(text) ~= "string" or text == "" then
    return nil
  end
  local id, suffix, bonuses = ns.ParseItemString(text)
  if id then
    if suffix == 0 and bonuses then
      suffix = ns.suffixMap[id .. ":" .. bonuses] or ns.suffixMap[bonuses] or 0
    end
    return ns.ItemKey(id, suffix)
  end
  return tonumber(text:match("^%s*(%d+)%s*$"))
end

-- the addon's icon (also used for the minimap / broker launcher and the window title)
ns.ICON = "Interface\\AddOns\\AzerothMercantileExchange\\media\\Icon"

-- WoW Forever runs one layered mega-realm per ruleset; its internal realm names (e.g. "CAMWOWEU5Realm6PvP") differ
-- per region/layer but share the economy. There the market is identified by the ruleset alone.
local RULESETS = { "RPPvP", "RPPvE", "RP", "PvP", "PvE", "HC", "Normal" }

-- rules (optional): the ruleset from the game's rules API (see AME:MarketRealmName); wins when present
function ns.MarketRealm(realm, rules)
  if rules then
    return rules
  end
  if type(realm) == "string" and realm:match("^CAMWOW") then
    for _, name in ipairs(RULESETS) do
      if realm:sub(-#name) == name then
        return name
      end
    end
    return "Forever"
  end
  return realm
end

ns.HOUSE_LABEL = { Alliance = L["Alliance AH"], Horde = L["Horde AH"], Neutral = L["Goblin AH"] }

-- Human-readable market name: "PvP · Goblin AH". Never show raw shard keys: WoW treats "|N" (as in "|Neutral")
-- and other "|x" pairs in displayed text as escape codes.
function ns.ShardLabel(shard)
  local realm, house = ns.SplitShard(shard)
  if not realm then
    return (tostring(shard):gsub("|", "/"))
  end
  return realm .. " · " .. (ns.HOUSE_LABEL[house] or house)
end

-- Shard key: one price history per market (realm, or Forever ruleset) + auction house.
-- realm, house of a shard key (nil when it isn't one)
function ns.SplitShard(shard)
  return tostring(shard):match("^(.*)|(%a+)$")
end

function ns.ShardKey(realm, house)
  assert(type(realm) == "string" and realm ~= "", "realm required")
  assert(ns.HOUSES[house], "house must be Alliance, Horde or Neutral")
  return realm .. "|" .. house
end

---------------------------------------------------------------------------------------------------------------------
-- money typed into a box: "12" or "1.5" (gold), "12g", "9s 50c", "1g20s", "150c", "1g 50" (a bare number after a
-- unit is the next one down). The game's own coin letters count too (GOLD_AMOUNT_SYMBOL...: "k" for copper in
-- German, 金/银/铜 in Chinese). Returns copper, or nil when empty or unreadable.

local function coinUnits()
  local units = { g = 10000, gold = 10000, s = 100, silver = 100, c = 1, copper = 1 }
  for sym, value in pairs({
    [GOLD_AMOUNT_SYMBOL or "g"] = 10000,
    [SILVER_AMOUNT_SYMBOL or "s"] = 100,
    [COPPER_AMOUNT_SYMBOL or "c"] = 1,
  }) do
    units[sym:lower()] = value
  end
  return units
end

function ns.ParseMoney(text)
  text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    return nil
  end
  local plain = tonumber((text:gsub(",", ".")))
  if plain then
    return plain >= 0 and math.floor(plain * 10000 + 0.5) or nil
  end
  local units = coinUnits()
  local total, last, pos = 0, nil, 1
  while pos <= #text do
    local s, e, num, unit = text:find("^%s*(%d*[%.,]?%d+)%s*([^%d%s%.,]*)", pos)
    if not s then
      return nil
    end
    local value
    if unit == "" then -- "1g 50": the unit after the last one
      value = last == 10000 and 100 or last == 100 and 1 or nil
    else
      value = units[unit]
    end
    if not value or (last and value >= last) then
      return nil -- unknown unit, or out of order ("5c 2g")
    end
    total = total + tonumber((num:gsub(",", "."))) * value
    last, pos = value, e + 1
  end
  return math.floor(total + 0.5)
end

-- copper as it's typed: "12g", "9s 50c", "1g 20s 5c" (in the game's coin letters)
function ns.MoneyInputText(copper)
  copper = math.floor((copper or 0) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if g > 0 then
    parts[#parts + 1] = g .. (GOLD_AMOUNT_SYMBOL or "g")
  end
  if s > 0 then
    parts[#parts + 1] = s .. (SILVER_AMOUNT_SYMBOL or "s")
  end
  if c > 0 or #parts == 0 then
    parts[#parts + 1] = c .. (COPPER_AMOUNT_SYMBOL or "c")
  end
  return table.concat(parts, " ")
end
