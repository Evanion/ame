-- Holdings (pure): one answer to "what you have". Every view that adds up your characters' items goes through here,
-- naming which places it counts, so two views can't count differently by accident. (Data core, step 6: today's scopes,
-- passed explicitly by each caller; docs/plans/data-core.md. Step 10 gives them one "usable" scope.)
--
--   holdings = AME_DB.holdings: { [charKey] = { bags = { [key] = n }, bank = {...}, auctions = {...}, mail = {...} } }
--   Holdings.PLACES.<preset>            lists of places
--   Holdings.Map(holdings, places, keep) -> { [key] = { qty, chars = { [charKey] = n } } }
--     places: a list of place names (or a preset name); keep(charKey) -> true to count that character (default: all)
--   Holdings.Totals(holdings, places, keep) -> { [key] = n }
local _, ns = ...

local Holdings = {}
ns.Holdings = Holdings

Holdings.PLACES = {
  stored = { "bags", "bank" }, -- shopping lists, the Crafting tab, Leveling
  listed = { "bags", "bank", "auctions" }, -- the portfolio: what you own, on sale or not
}

local function placesOf(places)
  return type(places) == "string" and Holdings.PLACES[places] or places
end

function Holdings.Map(holdings, places, keep)
  places = placesOf(places)
  local out = {}
  for char, h in pairs(holdings or {}) do
    if not keep or keep(char) then
      for _, place in ipairs(places) do
        for key, qty in pairs(h[place] or {}) do
          local e = out[key]
          if not e then
            e = { qty = 0, chars = {} }
            out[key] = e
          end
          e.qty = e.qty + qty
          e.chars[char] = (e.chars[char] or 0) + qty
        end
      end
    end
  end
  return out
end

function Holdings.Totals(holdings, places, keep)
  local out = {}
  for key, e in pairs(Holdings.Map(holdings, places, keep)) do
    out[key] = e.qty
  end
  return out
end
