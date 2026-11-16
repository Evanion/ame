-- Namespace and shared constants. Pure: no WoW API calls (loaded by busted specs too).
local _, ns = ...

ns.VERSION = "0.1.0-beta.1"

ns.HOUSES = { Alliance = true, Horde = true, Neutral = true }

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

-- Shard key: one price history per market (realm, or Forever ruleset) + auction house.
function ns.ShardKey(realm, house)
  assert(type(realm) == "string" and realm ~= "", "realm required")
  assert(ns.HOUSES[house], "house must be Alliance, Horde or Neutral")
  return realm .. "|" .. house
end
