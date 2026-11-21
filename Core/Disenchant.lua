-- Disenchanting: what an item is expected to give, for valuing crafted gear you'd disenchant instead of selling
-- (leveling guides, M16). Pure.
--
-- Written by hand from the community-documented classic rules (warcraft.wiki.gg "Disenchanting", cross-checked with
-- published player logs): bands of item level; uncommon armor gives mostly dust, uncommon weapons mostly essence,
-- with a small chance of a shard; rare gives a shard; epic gives shards, then Nexus Crystals from item level 56.
-- Counts in a range (1-2) are equally likely. Forever's client has the same item-level bands as Classic Era
-- (ItemDisenchantLoot) plus rare bands from item level 5, which use the lowest shard here. Not copied from any
-- database; the chances are the documented ones and may differ slightly in game.
local _, ns = ...

local Disenchant = {}
ns.Disenchant = Disenchant

-- materials
local STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
local LMAGIC, GMAGIC, LASTRAL, GASTRAL = 10938, 10939, 10998, 11082
local LMYSTIC, GMYSTIC, LNETHER, GNETHER, LETERNAL, GETERNAL = 11134, 11135, 11174, 11175, 16202, 16203
local SGLIMMER, LGLIMMER, SGLOW, LGLOW, SRADIANT, LRADIANT = 10978, 11084, 11138, 11139, 11177, 11178
local SBRILLIANT, LBRILLIANT, NEXUS = 14343, 14344, 20725

-- uncommon (green) bands: max item level, dust {id, min, max}, essence {id, min, max}, shard id (or nil)
local UNCOMMON = {
  { 15, { STRANGE, 1, 2 }, { LMAGIC, 1, 2 }, nil },
  { 20, { STRANGE, 2, 3 }, { GMAGIC, 1, 2 }, SGLIMMER },
  { 25, { STRANGE, 4, 6 }, { LASTRAL, 1, 2 }, SGLIMMER },
  { 30, { SOUL, 1, 2 }, { GASTRAL, 1, 2 }, LGLIMMER },
  { 35, { SOUL, 2, 5 }, { LMYSTIC, 1, 2 }, SGLOW },
  { 40, { VISION, 1, 2 }, { GMYSTIC, 1, 2 }, LGLOW },
  { 45, { VISION, 2, 5 }, { LNETHER, 1, 2 }, SRADIANT },
  { 50, { DREAM, 1, 2 }, { GNETHER, 1, 2 }, LRADIANT },
  { 55, { DREAM, 2, 5 }, { LETERNAL, 1, 2 }, SBRILLIANT },
  { 60, { ILLUSION, 1, 2 }, { GETERNAL, 1, 2 }, LBRILLIANT },
  { 99, { ILLUSION, 2, 5 }, { GETERNAL, 2, 3 }, LBRILLIANT },
}
-- rare (blue): one shard by max item level
local RARE = {
  { 25, SGLIMMER },
  { 30, LGLIMMER },
  { 35, SGLOW },
  { 40, LGLOW },
  { 45, SRADIANT },
  { 50, LRADIANT },
  { 55, SBRILLIANT },
  { 99, LBRILLIANT },
}
-- epic (purple): { max item level, id, min, max }
local EPIC = {
  { 45, SRADIANT, 2, 4 },
  { 50, LRADIANT, 2, 4 },
  { 55, SBRILLIANT, 2, 4 },
  { 60, NEXUS, 1, 1 },
  { 99, NEXUS, 1, 2 },
}

local function band(list, level)
  for _, b in ipairs(list) do
    if level <= b[1] then
      return b
    end
  end
end

local function avg(lo, hi)
  return (lo + hi) / 2
end

-- What one disenchant can give: { { itemID, chance (0-1), min, max }, ... } (one of them, by chance), or nil when
-- the item can't be disenchanted (not armor / weapon, below uncommon, or too low). classID: 2 weapon, 4 armor;
-- quality: 2 / 3 / 4.
function Disenchant.Outcomes(itemLevel, quality, classID)
  if not itemLevel or itemLevel < 5 or (classID ~= 2 and classID ~= 4) then
    return nil
  end
  if quality == 2 then
    local b = band(UNCOMMON, itemLevel)
    if not b then
      return nil
    end
    local dustShare, essenceShare = 0.75, 0.20
    if classID == 2 then -- weapons: the other way round
      dustShare, essenceShare = 0.20, 0.75
    end
    if not b[4] then -- the lowest band has no shard: dust and essence share it all
      dustShare, essenceShare = dustShare / 0.95, essenceShare / 0.95
    end
    local out = {
      { b[2][1], dustShare, b[2][2], b[2][3] },
      { b[3][1], essenceShare, b[3][2], b[3][3] },
    }
    if b[4] then
      out[#out + 1] = { b[4], 0.05, 1, 1 }
    end
    return out
  elseif quality == 3 then
    local b = band(RARE, itemLevel)
    return b and { { b[2], 1, 1, 1 } } or nil
  elseif quality == 4 then
    local b = band(EPIC, itemLevel)
    return b and { { b[2], 1, b[3], b[4] } } or nil
  end
end

-- Expected materials from one disenchant: { { itemID, expected count }, ... }, or nil (see Outcomes)
function Disenchant.Expected(itemLevel, quality, classID)
  local outcomes = Disenchant.Outcomes(itemLevel, quality, classID)
  if not outcomes then
    return nil
  end
  local out = {}
  for i, o in ipairs(outcomes) do
    out[i] = { o[1], o[2] * avg(o[3], o[4]) }
  end
  return out
end

-- What disenchanting an item is worth: the expected materials at price(itemID) (what selling them would net).
-- nil when it can't be disenchanted or a material has no price.
function Disenchant.Value(itemLevel, quality, classID, price)
  local mats = Disenchant.Expected(itemLevel, quality, classID)
  if not mats then
    return nil
  end
  local total = 0
  for _, m in ipairs(mats) do
    local p = price(m[1])
    if not p then
      return nil
    end
    total = total + p * m[2]
  end
  return total
end
