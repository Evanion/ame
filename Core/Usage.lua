-- What you use up (pure, with its event frame at the end): the consumables, reagents and ammo that leave a
-- character's bags while nothing else explains it, counted per day, so Home can suggest stocking up on what you use
-- when it's cheap (Home's Stock up rows). A drop in a bag count is "used" unless you're at a vendor, the bank, the
-- mailbox, the auction house, a trade, a profession window or a quest giver, or just deleted something: those move
-- items without using them, so they only move the baseline.
--
--   db = { since, last = { [itemID] = n }, days = { [itemID] = { [day] = n } } }   (AME_DB.usage[character])
--   Usage.New(db) -> u
--   u:Observe(bags, now, busy, counts)   bags { [itemID] = n } as they are now; busy: moved, not used;
--                                         counts(itemID) -> true for the items whose use is counted (Usage.Counts)
--   u:Rebase(bags, counts)               a new baseline without counting (a login: what changed offline isn't use)
--   u:Used(now) -> { [itemID] = { n, days, on, perDay } }   the last Usage.WINDOW days: how many, on how many days
--                                         (on: those days as a set), and the rate a day (over at least
--                                         Usage.MIN_SPAN days, however new the record)
--   Usage.Rates(dbs, now) -> { [itemID] = perDay }   every character's (dbs: { [charKey] = db }), added up; only
--                                         items used at least Usage.MIN_USED times on Usage.MIN_DAYS days
--   Usage.Counts(classID) -> bool        consumables, reagents and ammo
local _, ns = ...

local Usage = { WINDOW = 28, MIN_SPAN = 7, MIN_USED = 4, MIN_DAYS = 2 }
Usage.__index = Usage
ns.Usage = Usage

local DAY = 86400

-- item classes (Enum.ItemClass): Consumable, Reagent, Projectile (ammo)
Usage.CLASSES = { [0] = true, [5] = true, [6] = true }

function Usage.Counts(classID)
  return classID ~= nil and Usage.CLASSES[classID] == true
end

function Usage.New(db)
  db.last = db.last or {}
  db.days = db.days or {}
  return setmetatable({ db = db }, Usage)
end

local function only(bags, counts)
  local out = {}
  for id, n in pairs(bags or {}) do
    if n > 0 and counts(id) then
      out[id] = n
    end
  end
  return out
end

function Usage:Rebase(bags, counts)
  self.db.last = only(bags, counts)
end

-- days older than the window go
local function prune(db, today)
  for id, days in pairs(db.days) do
    for day in pairs(days) do
      if day <= today - Usage.WINDOW then
        days[day] = nil
      end
    end
    if next(days) == nil then
      db.days[id] = nil
    end
  end
end

function Usage:Observe(bags, now, busy, counts)
  local db = self.db
  db.since = db.since or now
  local today = math.floor(now / DAY)
  if not busy then
    for id, was in pairs(db.last) do
      local d = was - (bags[id] or 0)
      if d > 0 then
        local days = db.days[id] or {}
        db.days[id] = days
        days[today] = (days[today] or 0) + d
      end
    end
  end
  db.last = only(bags, counts)
  if db.pruned ~= today then
    db.pruned = today
    prune(db, today)
  end
end

function Usage:Used(now)
  local db = self.db
  local today = math.floor(now / DAY)
  -- the rate is over the days recorded, at least MIN_SPAN: a first day's few potions aren't a habit yet
  local span = Usage.WINDOW
  if db.since then
    span = math.min(Usage.WINDOW, math.floor((now - db.since) / DAY) + 1)
  end
  span = math.max(span, Usage.MIN_SPAN)
  local out = {}
  for id, days in pairs(db.days or {}) do
    local n, k, on = 0, 0, {}
    for day, c in pairs(days) do
      if day > today - Usage.WINDOW then
        n, k, on[day] = n + c, k + 1, true
      end
    end
    if n > 0 then
      out[id] = { n = n, days = k, on = on, perDay = n / span }
    end
  end
  return out
end

function Usage.Rates(dbs, now)
  local total = {}
  for _, db in pairs(dbs or {}) do
    for id, u in pairs(Usage.New(db):Used(now)) do
      local t = total[id] or { n = 0, days = 0, on = {}, perDay = 0 }
      total[id] = t
      t.n, t.perDay = t.n + u.n, t.perDay + u.perDay
      for day in pairs(u.on) do -- the days any of your characters used it
        if not t.on[day] then
          t.on[day], t.days = true, t.days + 1
        end
      end
    end
  end
  local out = {}
  for id, t in pairs(total) do
    if t.n >= Usage.MIN_USED and t.days >= Usage.MIN_DAYS then
      out[id] = t.perDay
    end
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ in game

if CreateFrame then
  local function counts(id)
    local info = ns.ItemCache and ns.ItemCache.Get(id)
    return info ~= nil and Usage.Counts(info.classID)
  end

  local function now()
    return GetServerTime and GetServerTime() or 0
  end

  local function mine()
    if not AME_DB then
      return nil
    end
    AME_DB.usage = AME_DB.usage or {}
    local me = ns.Trading and ns.Trading.CharKey and ns.Trading.CharKey()
    if not me then
      return nil
    end
    AME_DB.usage[me] = AME_DB.usage[me] or {}
    return Usage.New(AME_DB.usage[me])
  end

  -- what moves items without using them (as the session tracker sees it), and a short quiet after each
  local BUSY = {
    MERCHANT_SHOW = "merchant",
    BANKFRAME_OPENED = "bank",
    GUILDBANKFRAME_OPENED = "guildbank",
    MAIL_SHOW = "mail",
    AUCTION_HOUSE_SHOW = "ah",
    TRADE_SHOW = "trade",
    TRADE_SKILL_SHOW = "craft",
    CRAFT_SHOW = "enchant",
    QUEST_PROGRESS = "quest",
    QUEST_COMPLETE = "quest",
  }
  local DONE = {
    MERCHANT_CLOSED = "merchant",
    BANKFRAME_CLOSED = "bank",
    GUILDBANKFRAME_CLOSED = "guildbank",
    MAIL_CLOSED = "mail",
    AUCTION_HOUSE_CLOSED = "ah",
    TRADE_CLOSED = "trade",
    TRADE_SKILL_CLOSE = "craft",
    CRAFT_CLOSE = "enchant",
    QUEST_FINISHED = "quest",
  }
  local busy, quietUntil, ready = {}, 0, false
  local function quiet(seconds)
    quietUntil = math.max(quietUntil, (GetTime and GetTime() or 0) + seconds)
  end
  -- a stack split onto the cursor leaves its slot short until it's put down: not used either
  local function isBusy()
    if CursorHasItem and CursorHasItem() then
      return true
    end
    return next(busy) ~= nil or (GetTime and GetTime() or 0) < quietUntil
  end

  local function read()
    local T = ns.SessionTracker
    local bags = T and T.ReadBags and T.ReadBags() or {}
    return bags, next(bags) ~= nil
  end

  -- deleting an item isn't using it
  if hooksecurefunc then
    for _, name in ipairs({ "DeleteCursorItem" }) do
      if _G[name] then
        hooksecurefunc(name, function()
          quiet(2)
        end)
      end
    end
  end

  local events = CreateFrame("Frame")
  local all = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED" }
  for e in pairs(BUSY) do
    all[#all + 1] = e
  end
  for e in pairs(DONE) do
    all[#all + 1] = e
  end
  for _, e in ipairs(all) do
    pcall(events.RegisterEvent, events, e)
  end
  events:SetScript("OnEvent", function(_, event)
    local u = mine()
    if not u then
      return
    end
    local bags, any = read()
    if event == "PLAYER_ENTERING_WORLD" then
      -- a login or a loading screen: what changed meanwhile isn't counted; the bags may not be read yet
      ready = any
      if any then
        u:Rebase(bags, counts)
      end
      return
    end
    if not any then -- bags not loaded (or truly empty): nothing to compare
      return
    end
    if not ready then
      ready = true
      return u:Rebase(bags, counts)
    end
    if BUSY[event] then
      u:Observe(bags, now(), isBusy(), counts) -- what was used up to here counts, then the baseline holds
      busy[BUSY[event]] = true
    elseif DONE[event] then
      busy[DONE[event]] = nil
      quiet(2) -- purchases and mail still landing
      u:Rebase(bags, counts)
    else
      u:Observe(bags, now(), isBusy(), counts)
    end
  end)
end
