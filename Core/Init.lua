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
  local realm, house = tostring(shard):match("^(.*)|(%a+)$")
  if not realm then
    return (tostring(shard):gsub("|", "/"))
  end
  return realm .. " · " .. (ns.HOUSE_LABEL[house] or house)
end

-- Shard key: one price history per market (realm, or Forever ruleset) + auction house.
function ns.ShardKey(realm, house)
  assert(type(realm) == "string" and realm ~= "", "realm required")
  assert(ns.HOUSES[house], "house must be Alliance, Horde or Neutral")
  return realm .. "|" .. house
end
