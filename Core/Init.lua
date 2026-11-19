-- Namespace and shared constants. Pure: no WoW API calls (loaded by busted specs too).
local _, ns = ...

ns.VERSION = "0.2.0-beta.4"

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

-- an item string the client's item APIs and tooltips accept: the variant's own (learned from a link) when known, else
-- "item:2207" / the Classic form "item:2207::::::1234"
function ns.ItemString(key)
  local known = ns.itemStrings and ns.itemStrings[key]
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
