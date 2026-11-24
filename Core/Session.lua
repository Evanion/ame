-- This session (board SessionTracker), pure: what an outing has put in your bags and the gold it looted, from what
-- your bags and purse held each time they changed. Items gained while you're at a vendor, the bank, the mailbox, the
-- auction house, a trade or a profession window are bought, fetched or made, not gathered: those changes only move
-- the baseline. What you use up or sell takes nothing off what you gathered.
--
--   db = { start, seen, last = { [key] = n }, money, gained = { [key] = n }, looted }  (AME_DB.sessions[character])
--   Session.New(db) -> s
--   s:Start(now, bags, money)                 a new session from what you hold now
--   s:Active(now) -> bool                     there is a session, seen within Session.GAP (a short logout continues it)
--   s:Observe(bags, money, now, busy)         bags { [key] = n } and money as they are now; busy: bought, not gathered
--   s:Summary(worth, now) -> { elapsed, items, money, total, perHour, top = { { key, count, value }, ... } }
--                                              worth(key) -> copper for one (nil: no value)
--   Session.Value(counts, worth) -> copper    what a set of items is worth
--   Session.Duration(seconds) -> "1 h 12 min"
local _, ns = ...
local L = ns.L

local Session = { GAP = 1800, MIN_RATE = 600, TOP = 3 }
Session.__index = Session
ns.Session = Session

function Session.New(db)
  return setmetatable({ db = db }, Session)
end

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do
    out[k] = v
  end
  return out
end

function Session:Start(now, bags, money)
  local db = self.db
  db.start, db.seen = now, now
  db.last, db.money = copy(bags), money or 0
  db.gained, db.looted = {}, 0
end

function Session:Active(now)
  local db = self.db
  return db.start ~= nil and db.seen ~= nil and now - db.seen <= Session.GAP
end

function Session:Observe(bags, money, now, busy)
  local db = self.db
  if not db.start then
    return self:Start(now, bags, money)
  end
  db.gained = db.gained or {}
  if not busy then
    local last = db.last or {}
    for key, n in pairs(bags or {}) do
      local d = n - (last[key] or 0)
      if d > 0 then
        db.gained[key] = (db.gained[key] or 0) + d
      end
    end
    if money and db.money and money > db.money then
      db.looted = (db.looted or 0) + money - db.money
    end
  end
  db.last = copy(bags)
  db.money = money or db.money
  db.seen = now
end

function Session.Value(counts, worth)
  local total = 0
  for key, n in pairs(counts or {}) do
    local each = worth(key)
    if each and each > 0 then
      total = total + each * n
    end
  end
  return total
end

function Session:Summary(worth, now)
  local db = self.db
  local elapsed = db.start and math.max(0, now - db.start) or 0
  local top = {}
  local items = 0
  for key, n in pairs(db.gained or {}) do
    local each = worth(key)
    if each and each > 0 then
      local value = each * n
      items = items + value
      top[#top + 1] = { key = key, count = n, value = value }
    end
  end
  table.sort(top, function(a, b)
    if a.value ~= b.value then
      return a.value > b.value
    end
    return a.key < b.key
  end)
  for i = #top, Session.TOP + 1, -1 do
    top[i] = nil
  end
  local money = db.looted or 0
  local total = items + money
  return {
    elapsed = elapsed,
    items = items,
    money = money,
    total = total,
    -- a rate over the first few minutes means little: it counts at least MIN_RATE seconds
    perHour = math.floor(total * 3600 / math.max(elapsed, Session.MIN_RATE) + 0.5),
    top = top,
  }
end

function Session.Duration(s)
  s = math.max(0, math.floor(s or 0))
  local h, m = math.floor(s / 3600), math.floor((s % 3600) / 60)
  if h > 0 then
    return L["%d h %d min"]:format(h, m)
  end
  return L["%d min"]:format(m)
end
