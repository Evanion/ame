-- Namespace and shared constants. Pure: no WoW API calls (loaded by busted specs too).
local _, ns = ...

ns.VERSION = "0.2.0-beta.2"

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

-- item ID from an item link, or from text that is just a number; nil otherwise
function ns.ItemIDFrom(text)
  if type(text) ~= "string" or text == "" then
    return nil
  end
  return tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
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
