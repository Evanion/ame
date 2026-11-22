-- Shopping lists: buying toward a goal (the reagents for something you'll craft), unlike watchlists, which you keep
-- an eye on for good. Pure: state is a plain table (AME_DB.shopping), holdings and prices are passed in.
--
--   db = {
--     lists = { { name, items = { [itemKey] = { need = n, max = copper? } }, shared = bool?, version = n }, ... },
--     guild = { ["owner/name"] = { owner, name, items = { [itemKey] = { need, max? } }, t } },  -- shared with you
--   }
--
-- What you still need counts down by itself: from what your characters on this market have to use - bags, bank,
-- mailbox and guild banks (Holdings.PLACES.usable), as the craft queue counts it.
local _, ns = ...
local L = ns.L

local Shopping = {}
Shopping.__index = Shopping
ns.Shopping = Shopping

Shopping.MAX_NEED = 100000

function Shopping.New(db)
  db.lists = db.lists or {}
  db.guild = db.guild or {}
  return setmetatable({ db = db }, Shopping)
end

-- tell whoever shows the lists that they changed (Events "ShoppingChanged"; the AH's Shopping tab listens)
local function changed(self)
  ns.Events.Fire("ShoppingChanged", self)
end

local function trim(name)
  return (tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Shopping:Lists()
  return self.db.lists
end

-- returns the new list's index, or nil and why not
function Shopping:AddList(name)
  name = trim(name)
  if name == "" then
    return nil, L["a list needs a name"]
  end
  for _, l in ipairs(self.db.lists) do
    if l.name:lower() == name:lower() then
      return nil, L["a list with that name already exists"]
    end
  end
  self.db.lists[#self.db.lists + 1] = { name = name, items = {}, version = 1 }
  changed(self)
  return #self.db.lists
end

function Shopping:RenameList(i, name)
  local l = self.db.lists[i]
  name = trim(name)
  if not l or name == "" then
    return false
  end
  for j, other in ipairs(self.db.lists) do
    if j ~= i and other.name:lower() == name:lower() then
      return false
    end
  end
  l.name = name
  l.version = (l.version or 0) + 1
  changed(self)
  return true
end

function Shopping:RemoveList(i)
  local gone = table.remove(self.db.lists, i) ~= nil
  changed(self)
  return gone
end

local function touch(l)
  l.version = (l.version or 0) + 1
end

-- set how many of an item the list needs (0 or nil removes it); max: the most you'd pay per unit (copper), false
-- clears it, nil keeps it
function Shopping:SetItem(i, key, need, max)
  local l = self.db.lists[i]
  if not (l and key) then
    return nil
  end
  need = math.floor(tonumber(need) or 0)
  if need <= 0 then
    l.items[key] = nil
    touch(l)
    changed(self)
    return nil
  end
  local e = l.items[key] or {}
  e.need = math.min(need, Shopping.MAX_NEED)
  if max == false then
    e.max = nil
  elseif max then
    e.max = math.floor(max)
  end
  l.items[key] = e
  touch(l)
  changed(self)
  return e
end

-- add n more of an item (a recipe's reagents times how many you'll craft)
function Shopping:AddItem(i, key, n, max)
  local l = self.db.lists[i]
  local cur = l and l.items[key]
  return self:SetItem(i, key, (cur and cur.need or 0) + (n or 1), max)
end

function Shopping:Count(i)
  local n = 0
  for _ in pairs(self.db.lists[i] and self.db.lists[i].items or {}) do
    n = n + 1
  end
  return n
end

-- What a list still needs. held: what you have, as Holdings.Map counts it (Holdings.Of("usable"): what's listed on
-- the AH doesn't count, it's for sale); items: market summaries by key (index.items). Returns rows (missing first,
-- then by cost) and totals { missing = items still short, cost = buying the rest at market, unpriced = items short
-- with no market price, done = nothing missing }.
function Shopping.Progress(items, held, market)
  held = held or {}
  local rows, totals = {}, { missing = 0, cost = 0, unpriced = 0, done = true, items = 0 }
  for key, want in pairs(items or {}) do
    local h = held[key]
    local have = h and h.qty or 0
    local missing = math.max(0, want.need - have)
    local s = market and market[key]
    local price = s and s.market
    local row = {
      itemID = key,
      need = want.need,
      have = math.min(have, want.need),
      held = have,
      missing = missing,
      chars = h and h.chars or {},
      guilds = h and h.guilds or {},
      market = price,
      max = want.max,
      -- at or under your top price right now (on the latest data)
      cheap = want.max and price and price <= want.max or nil,
      cost = price and missing * price or nil,
      signal = s and s.signal,
      signalRank = s and s.signalRank,
    }
    rows[#rows + 1] = row
    totals.items = totals.items + 1
    if missing > 0 then
      totals.done = false
      totals.missing = totals.missing + 1
      if price then
        totals.cost = totals.cost + missing * price
      else
        totals.unpriced = totals.unpriced + 1
      end
    end
  end
  if totals.items == 0 then
    totals.done = false
  end
  table.sort(rows, function(a, b)
    if (a.missing > 0) ~= (b.missing > 0) then
      return a.missing > 0
    end
    if (a.cost or 0) ~= (b.cost or 0) then
      return (a.cost or 0) > (b.cost or 0)
    end
    return a.itemID < b.itemID
  end)
  return rows, totals
end

---------------------------------------------------------------------------------------------------------------------
-- sharing with the guild (like watchlists: sent over sync, newer versions replace older)

function Shopping:SetShared(i, on)
  local l = self.db.lists[i]
  if l then
    l.shared = on or nil
    touch(l)
  end
  return l
end

-- your shared lists as { name, entries = { { key, need, max? }, ... } } (sorted by key)
function Shopping:SharedLists()
  local out = {}
  for _, l in ipairs(self.db.lists) do
    if l.shared then
      local entries = {}
      for key, e in pairs(l.items) do
        entries[#entries + 1] = { key, e.need, e.max }
      end
      table.sort(entries, function(a, b)
        return a[1] < b[1]
      end)
      out[#out + 1] = { name = l.name, entries = entries }
    end
  end
  return out
end

-- a guild member's list arrived: newer versions replace older; an empty list removes it
function Shopping:SetGuildList(owner, name, t, entries)
  local key = owner .. "/" .. name
  local cur = self.db.guild[key]
  if cur and cur.t >= t then
    return false
  end
  if #entries == 0 then
    self.db.guild[key] = nil
    return true
  end
  local items = {}
  for _, e in ipairs(entries) do
    items[e[1]] = { need = e[2], max = e[3] }
  end
  self.db.guild[key] = { owner = owner, name = name, items = items, t = t }
  return true
end

function Shopping:GuildLists()
  local out = {}
  for key, g in pairs(self.db.guild) do
    out[#out + 1] = { key = key, owner = g.owner, name = g.name, items = g.items, t = g.t }
  end
  table.sort(out, function(a, b)
    return a.key:lower() < b.key:lower()
  end)
  return out
end

-- copy a guild member's list into your own; returns its index
function Shopping:CopyGuildList(key)
  local g = self.db.guild[key]
  if not g then
    return nil
  end
  local base = ("%s (%s)"):format(g.name, g.owner)
  local name, n = base, 1
  while true do
    local i = self:AddList(name)
    if i then
      for k, e in pairs(g.items) do
        self.db.lists[i].items[k] = { need = e.need, max = e.max }
      end
      return i
    end
    n = n + 1
    name = base .. " " .. n
  end
end

---------------------------------------------------------------------------------------------------------------------
-- recipes: the reagents of the recipe selected in the open profession window

-- api: { selected = fn() -> index, numReagents = fn(i), reagentLink = fn(i, r), reagentCount = fn(i, r) -> count,
-- name = fn(i) } (the classic GetTradeSkill* / GetCraft* functions). Returns { name, reagents = { { key, count } } }
-- or nil when no recipe is selected.
function Shopping.Recipe(api)
  if not (api and api.selected) then
    return nil
  end
  local i = api.selected()
  if not i or i == 0 then
    return nil
  end
  local out = { name = api.name and api.name(i), reagents = {} }
  for r = 1, api.numReagents(i) or 0 do
    local key = ns.ItemIDFrom(api.reagentLink(i, r) or "")
    local count = api.reagentCount(i, r)
    if key and count and count > 0 then
      out.reagents[#out.reagents + 1] = { key, count }
    end
  end
  return #out.reagents > 0 and out or nil
end
