-- Holdings (pure): one answer to "what you have". Every view that adds up your characters' items goes through here,
-- naming which places it counts, so two views can't count differently by accident. (Data core, steps 6 and 10;
-- docs/plans/data-core.md.)
--
--   holdings   = AME_DB.holdings: { [charKey] = { bags = { [key] = n }, bank, auctions, mail (the same) } }
--   guildBanks = AME_DB.guildBanks: { ["<market>:<guild>"] = { tabs = { [tab] = { [key] = n } } } }
--   Holdings.PLACES.usable   bags, bank, mail and guild banks: what you can craft with or still have to buy
--                            (shopping lists, the craft queue, the profession bar, the Crafting tab, Leveling)
--   Holdings.PLACES.owned    those and what's on the auction house: what you own (the portfolio)
--   Holdings.Keep(scope)     a filter on keys: "market" (your characters on this market, the default), "account"
--                            (every character), or one character's key (no guild banks then)
--   Holdings.Map(holdings, places, keep, guildBanks) -> { [key] = { qty, chars = { [charKey] = n },
--                                                       guilds = { [guildKey] = n } } }
--     places: a list of place names (or a preset name); keep(key) -> true to count that character or guild bank
--   Holdings.Totals(holdings, places, keep, guildBanks) -> { [key] = n }
--   Holdings.Of(places, scope)    Map over the saved data (AME_DB), in a scope (Keep)
--   Holdings.Reserve(have) -> r   a stock to draw from (have: { [key] = n } or fn(key) -> n):
--                                 r:Take(key, n) -> taken, r:Left(key) -> what's still there
local _, ns = ...

local Holdings = {}
ns.Holdings = Holdings

Holdings.PLACES = {
  usable = { "bags", "bank", "mail", "guild" },
  owned = { "bags", "bank", "mail", "guild", "auctions" },
}

local function placesOf(places)
  return type(places) == "string" and Holdings.PLACES[places] or places
end

function Holdings.Keep(scope)
  if type(scope) == "function" then
    return scope
  elseif scope == "account" then
    return nil
  elseif scope == nil or scope == "market" then
    local market = ns.AME and ns.AME.MarketRealmName and ns.AME:MarketRealmName()
    if not market then
      return nil
    end
    local prefix = market .. ":"
    return function(key)
      return key:sub(1, #prefix) == prefix
    end
  end
  return function(key)
    return key == scope
  end
end

local function entry(out, key)
  local e = out[key]
  if not e then
    e = { qty = 0, chars = {}, guilds = {} }
    out[key] = e
  end
  return e
end

function Holdings.Map(holdings, places, keep, guildBanks)
  places = placesOf(places)
  local out, guild = {}, false
  for char, h in pairs(holdings or {}) do
    if not keep or keep(char) then
      for _, place in ipairs(places) do
        for key, qty in pairs(h[place] or {}) do
          local e = entry(out, key)
          e.qty = e.qty + qty
          e.chars[char] = (e.chars[char] or 0) + qty
        end
      end
    end
  end
  for _, place in ipairs(places) do
    guild = guild or place == "guild"
  end
  for gkey, g in pairs(guild and guildBanks or {}) do
    if not keep or keep(gkey) then
      for _, items in pairs(g.tabs or {}) do
        for key, qty in pairs(items) do
          local e = entry(out, key)
          e.qty = e.qty + qty
          e.guilds[gkey] = (e.guilds[gkey] or 0) + qty
        end
      end
    end
  end
  return out
end

function Holdings.Totals(holdings, places, keep, guildBanks)
  local out = {}
  for key, e in pairs(Holdings.Map(holdings, places, keep, guildBanks)) do
    out[key] = e.qty
  end
  return out
end

function Holdings.Of(places, scope)
  local db = AME_DB or {}
  return Holdings.Map(db.holdings, places, Holdings.Keep(scope), db.guildBanks)
end

local Reserve = {}
Reserve.__index = Reserve

function Holdings.Reserve(have)
  return setmetatable({ have = have, taken = {} }, Reserve)
end

function Reserve:Left(key)
  local have = self.have
  local n = type(have) == "function" and have(key) or (have and have[key]) or 0
  if type(n) == "table" then
    n = n.qty or 0
  end
  return math.max(0, n - (self.taken[key] or 0))
end

function Reserve:Take(key, n)
  local got = math.min(self:Left(key), math.max(0, n or 0))
  self.taken[key] = (self.taken[key] or 0) + got
  return got
end
