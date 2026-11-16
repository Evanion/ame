-- Watchlists and price alerts. Pure: state lives in a plain table (AME_DB.watch), no WoW API calls.
--
--   db = {
--     lists  = { { name = "Watchlist", items = { [itemID] = true } }, ... },   -- account-wide, any shard
--     alerts = { [itemID] = { below = copper?, above = copper?, signal = bool?, state = {} } },
--   }
--
-- Alerts fire once when their condition becomes true and re-arm when it stops being true (with a little hysteresis
-- on price levels), so a price hovering around a threshold doesn't spam.
local _, ns = ...

local Watch = {}
Watch.__index = Watch
ns.Watch = Watch

Watch.REARM = 0.02 -- a price alert re-arms once the price moves 2% back past the threshold
Watch.DEFAULT_NAME = "Watchlist"

function Watch.New(db)
  db.lists = db.lists or {}
  db.alerts = db.alerts or {}
  if #db.lists == 0 then
    db.lists[1] = { name = Watch.DEFAULT_NAME, items = {} }
  end
  return setmetatable({ db = db }, Watch)
end

---------------------------------------------------------------------------------------------------------------------
-- lists

function Watch:Lists()
  return self.db.lists
end

function Watch:AddList(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    return nil, "a list needs a name"
  end
  for _, l in ipairs(self.db.lists) do
    if l.name:lower() == name:lower() then
      return nil, "a list with that name already exists"
    end
  end
  local list = { name = name, items = {} }
  self.db.lists[#self.db.lists + 1] = list
  return #self.db.lists, list
end

-- the last list can't be removed (there's always somewhere to put a star)
function Watch:RemoveList(i)
  if #self.db.lists <= 1 or not self.db.lists[i] then
    return false
  end
  table.remove(self.db.lists, i)
  return true
end

function Watch:Count(i)
  local n = 0
  for _ in pairs(self.db.lists[i] and self.db.lists[i].items or {}) do
    n = n + 1
  end
  return n
end

function Watch:Has(i, itemID)
  local l = self.db.lists[i]
  return l and l.items[itemID] == true or false
end

-- toggles membership; returns the new state
function Watch:Toggle(i, itemID)
  local l = self.db.lists[i]
  if not l then
    return false
  end
  l.items[itemID] = not l.items[itemID] or nil
  return l.items[itemID] == true
end

-- watched in any list?
function Watch:Watched(itemID)
  for _, l in ipairs(self.db.lists) do
    if l.items[itemID] then
      return true
    end
  end
  return self.db.alerts[itemID] ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- alerts

function Watch:Alert(itemID)
  return self.db.alerts[itemID]
end

-- fields: below, above (copper or nil), signal (bool). Clearing all fields removes the alert.
function Watch:SetAlert(itemID, fields)
  local a = self.db.alerts[itemID] or { state = {} }
  for _, k in ipairs({ "below", "above", "signal" }) do
    if fields[k] ~= nil then
      a[k] = fields[k] or nil
    end
  end
  a.state = {} -- changed thresholds re-arm everything
  if not a.below and not a.above and not a.signal then
    self.db.alerts[itemID] = nil
  else
    self.db.alerts[itemID] = a
  end
  return self.db.alerts[itemID]
end

-- Check every alert against market summaries (index.items: itemID -> { market, signal, ... }).
-- Returns triggered alerts: { { itemID, kind = "below"|"above"|"buy"|"sell", market, threshold }, ... }
function Watch:Check(items)
  local fired = {}
  for itemID, a in pairs(self.db.alerts) do
    local s = items[itemID]
    local st = a.state
    if s and s.market then
      local m = s.market
      if a.below then
        if m <= a.below and not st.below then
          st.below = true
          fired[#fired + 1] = { itemID = itemID, kind = "below", market = m, threshold = a.below }
        elseif m > a.below * (1 + Watch.REARM) then
          st.below = nil
        end
      end
      if a.above then
        if m >= a.above and not st.above then
          st.above = true
          fired[#fired + 1] = { itemID = itemID, kind = "above", market = m, threshold = a.above }
        elseif m < a.above * (1 - Watch.REARM) then
          st.above = nil
        end
      end
      if a.signal then
        local sig = s.signal ~= "none" and s.signal or nil
        if sig and st.signal ~= sig then
          fired[#fired + 1] = { itemID = itemID, kind = sig, market = m }
        end
        st.signal = sig
      end
    end
  end
  table.sort(fired, function(x, y)
    return x.itemID < y.itemID
  end)
  return fired
end
