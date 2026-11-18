-- Pricing (pure): what to post an item at, so it sells within the listing time at the best price - instead of
-- undercutting the cheapest listing by 1c every time.
--
-- Queue model: buyers take the cheapest listings first. At price p you wait behind every unit listed at or below p,
-- plus the undercutters who arrive below you while you wait. With D units sold per hour and U units of undercutting
-- supply arriving per hour, a listing with A units ahead and q of your own sells after about (A + q) / (D - U)
-- hours. Each candidate price gets a chance to sell within the listing time; the suggestion weighs that against the
-- deposit lost when it doesn't sell.
--
-- Adaptive: every item has a profile learned from consecutive scans (sales rate, how fast and how deep it gets
-- undercut, which hours and weekdays it sells in) and from your own listings (did items posted at a suggested
-- chance actually sell? and how fast, against how fast the model expected - Pricing.LearnSpeed). Items with
-- little data borrow their category's behaviour until their own numbers take over (shrinkage), so a new item gets
-- sensible advice and a well-known one gets its own.
--
--   obs     = { t, min, qty, ladder = { units at or below min * (1 + band) for each of BANDS } }   one scan
--   profile = Pricing.NewProfile(), updated by Pricing.Observe(profile, obs) and Pricing.Learn(profile, chance, sold)
--   params  = Pricing.Params(profile, prior, summary)   prior = Pricing.Prior({ profiles of the category })
--   advice  = Pricing.Suggest(book, params, opts)       book = { prices = {...ascending}, qtys = {...} }
local _, ns = ...

local Pricing = {}
ns.Pricing = Pricing

local floor, max, min, exp, log = math.floor, math.max, math.min, math.exp, math.log

Pricing.BANDS = { 0, 0.02, 0.05, 0.10, 0.20 } -- price ladder kept per scan: units within this much of the lowest
Pricing.HALF_LIFE = 72 -- hours: an observation's weight halves this much later (markets change)
Pricing.MIN_GAP, Pricing.MAX_GAP = 0.25, 48 -- hours between two scans to learn rates from
Pricing.SHAPE_RATE = 0.15 -- how fast the hour-of-day / weekday shapes adapt
Pricing.PRIOR_WEIGHT = 5 -- observations before an item's own rates outweigh its category's
Pricing.SHAPE_WEIGHT = 20 -- same for the hour-of-day shape (weekday: half of it)
Pricing.OUTCOME_WEIGHT = 5 -- same for the calibration from your own listings
Pricing.LEARN_RATE = 0.3 -- calibration step per listing outcome
Pricing.SPEED_RATE = 0.3 -- speed step per listing outcome (in log units: 0.3 of the log of predicted / actual hours)
Pricing.SPEED_WEIGHT = 5 -- listing outcomes before an item's own speed outweighs its category's
Pricing.SPEED_LIMIT = 2 -- speed factor kept within e^-2 .. e^2 (about 7x slower .. 7x faster than the scans say)
Pricing.QUICK_HOURS, Pricing.QUICK_CHANCE = 4, 0.85 -- "Quick": sells within this many hours this surely
Pricing.PATIENT_CHANCE = 0.5 -- "Patient": the highest price that still sells within the listing time half the time
Pricing.HOLD_CHANCE = 0.25 -- below this at the best price: advise holding

Pricing.DEFAULT_PRIOR = { comp = 0.5, cut = 0.03, calib = 0, hd = {}, wd = {}, n = 0 }

local function clamp(x, lo, hi)
  return x < lo and lo or x > hi and hi or x
end

local function hourOf(t)
  return floor((t % 86400) / 3600) + 1 -- 1..24
end

local function weekdayOf(t)
  return (floor(t / 86400) + 4) % 7 + 1 -- 1 = Sunday (day 0 of the epoch was a Thursday)
end

function Pricing.NewProfile()
  return {
    n = 0,
    demand = 0,
    inflow = 0,
    cut = 0,
    cuts = 0,
    calib = 0,
    no = 0,
    speed = 0, -- log factor on the sales rate, learned from how fast your listings sold
    sn = 0, -- listing outcomes behind it
    hn = 0,
    wn = 0,
    hd = {},
    wd = {},
  }
end

---------------------------------------------------------------------------------------------------------------------
-- scans

-- Ladder of one item's listings: units listed at or below lowest * (1 + band), per band.
-- units/counts: unit price and units per listing; order: listing indices sorted by unit price
function Pricing.Ladder(units, counts, order)
  local lowest = units[order[1]]
  local out, k, cum = {}, 1, 0
  for b, band in ipairs(Pricing.BANDS) do
    local limit = lowest * (1 + band) + 1e-6
    while order[k] and units[order[k]] <= limit do
      cum = cum + counts[order[k]]
      k = k + 1
    end
    out[b] = cum
  end
  return out
end

-- Units listed at or below price x in a scan (interpolated within the ladder's bands; without a ladder all supply
-- counts as sitting at the lowest price).
function Pricing.Below(obs, x)
  if not obs.min or x < obs.min then
    return 0
  end
  local l = obs.ladder
  if not l then
    return obs.qty or 0
  end
  local prevEdge, prevCum = obs.min, l[1]
  for b = 2, #Pricing.BANDS do
    local edge = obs.min * (1 + Pricing.BANDS[b])
    if x <= edge then
      return prevCum + (l[b] - prevCum) * (x - prevEdge) / (edge - prevEdge)
    end
    prevEdge, prevCum = edge, l[b]
  end
  local total, top = max(obs.qty or prevCum, prevCum), obs.min * 2
  if x >= top then
    return total
  end
  return prevCum + (total - prevCum) * (x - prevEdge) / (top - prevEdge)
end

-- An order book (price tiers) from a scan's ladder, for when there's no fresh search of the item.
function Pricing.BookFromObs(obs)
  local book = { prices = {}, qtys = {} }
  if not (obs and obs.min) then
    return book
  end
  local l = obs.ladder or { obs.qty or 0 }
  local prev = 0
  for b, cum in ipairs(l) do
    if cum > prev then
      book.prices[#book.prices + 1] = floor(obs.min * (1 + Pricing.BANDS[b]) + 0.5)
      book.qtys[#book.qtys + 1] = cum - prev
      prev = cum
    end
  end
  if (obs.qty or 0) > prev then -- the rest, somewhere above the ladder
    book.prices[#book.prices + 1] = floor(obs.min * 1.35 + 0.5)
    book.qtys[#book.qtys + 1] = obs.qty - prev
  end
  return book
end

-- Learn from the next scan of the item. Returns true when the pair of scans taught something.
--   sold: units gone from the cheap end of the book (cancellations look the same - an overestimate, as for sellRate)
--   undercutting supply: units newly listed below the previous lowest price
function Pricing.Observe(p, obs)
  local last = p.last
  p.last = { t = obs.t, min = obs.min, qty = obs.qty, ladder = obs.ladder }
  if not (last and last.t and last.min and obs.t and obs.min) then
    return false
  end
  local dt = (obs.t - last.t) / 3600
  if dt < Pricing.MIN_GAP or dt > Pricing.MAX_GAP then
    return false
  end
  local undercut = obs.min < last.min
  local newBelow = 0
  if undercut then
    newBelow = obs.ladder and max(1, Pricing.Below(obs, last.min - 1)) or 1
  end
  local sold
  if last.ladder and obs.ladder then
    local x = last.min * 1.05
    sold = max(0, Pricing.Below(last, x) - Pricing.Below(obs, x) + newBelow)
  else
    sold = max(0, (last.qty or 0) - (obs.qty or 0) + newBelow)
  end
  local d, u, c = sold / dt, newBelow / dt, (undercut and 1 or 0) / dt

  -- when (hour, weekday) it sells, relative to the item's usual rate
  local mid = (last.t + obs.t) / 2
  if p.n > 0 and p.demand > 0 then
    local r = clamp(d / p.demand, 0.1, 5)
    if dt <= 6 then
      local h = hourOf(mid)
      p.hd[h] = (p.hd[h] or 1) + Pricing.SHAPE_RATE * (r - (p.hd[h] or 1))
      p.hn = p.hn + 1
    end
    if dt <= 24 then
      local w = weekdayOf(mid)
      p.wd[w] = (p.wd[w] or 1) + Pricing.SHAPE_RATE * (r - (p.wd[w] or 1))
      p.wn = p.wn + 1
    end
  end

  if p.n == 0 then
    p.demand, p.inflow, p.cuts = d, u, c
  else
    local a = 1 - 0.5 ^ (dt / Pricing.HALF_LIFE)
    p.demand = p.demand + a * (d - p.demand)
    p.inflow = p.inflow + a * (u - p.inflow)
    p.cuts = p.cuts + a * (c - p.cuts)
  end
  if undercut then
    local size = (last.min - obs.min) / last.min
    p.cut = p.cut == 0 and size or p.cut + 0.2 * (size - p.cut)
  end
  p.n = p.n + 1
  return true
end

-- One of your listings ended: sold or expired. chance: what the model gave it when you posted.
function Pricing.Learn(p, chance, sold)
  if not chance then
    return
  end
  p.calib = clamp(p.calib + Pricing.LEARN_RATE * ((sold and 1 or 0) - chance), -2, 2)
  p.no = p.no + 1
end

-- How fast one of your listings sold, against how fast the model expected (hours to sell, predicted when posting):
--   kind "exact":   it sold after `hours` (the game said so while you were online)
--   kind "within":  it sold within `hours` (learned from the auction mail later: the exact time is unknown)
--   kind "expired": it didn't sell within its `hours` of listing time
-- The item's speed moves toward what happened, as a factor on its sales rate: sold twice as fast as predicted, a
-- few times over, and its sales rate (and so every "sells in" and the posting prices) doubles. A bound only
-- teaches when the prediction was on the wrong side of it.
function Pricing.LearnSpeed(p, expected, kind, hours)
  if not (expected and expected > 0 and hours) then
    return false
  end
  hours = max(hours, 0.05)
  local r
  if kind == "exact" then
    r = log(expected / hours)
  elseif kind == "within" then
    if expected <= hours then
      return false -- it sold in time, as predicted: no news
    end
    r = log(expected / hours) -- faster than predicted, at least this much
  elseif kind == "expired" then
    if expected >= hours then
      return false -- predicted not to sell in time: no news
    end
    r = log(expected / hours) -- slower than predicted, at least this much (negative)
  else
    return false
  end
  r = clamp(r, -log(8), log(8))
  p.speed = clamp((p.speed or 0) + Pricing.SPEED_RATE * r, -Pricing.SPEED_LIMIT, Pricing.SPEED_LIMIT)
  p.sn = (p.sn or 0) + 1
  return true
end

---------------------------------------------------------------------------------------------------------------------
-- category behaviour and the blend

-- What items of a category typically do (from those with enough data): competition (undercutting supply per unit
-- sold), undercut size, calibration, and hour / weekday shapes.
function Pricing.Prior(profiles)
  local comp, cw, cut, kw, calib, no = 0, 0, 0, 0, 0, 0
  local speed, sn = 0, 0
  local hd, hw, wd, ww = {}, 0, {}, 0
  for _, p in ipairs(profiles) do
    if p.n >= 3 and p.demand > 0 then
      comp, cw = comp + min(p.inflow / p.demand, 3), cw + 1
    end
    if p.cut > 0 then
      cut, kw = cut + p.cut, kw + 1
    end
    if p.no > 0 then
      calib, no = calib + p.calib * p.no, no + p.no
    end
    if (p.sn or 0) > 0 then
      speed, sn = speed + p.speed * p.sn, sn + p.sn
    end
    if p.hn >= 5 then
      for h = 1, 24 do
        hd[h] = (hd[h] or 0) + (p.hd[h] or 1)
      end
      hw = hw + 1
    end
    if p.wn >= 5 then
      for w = 1, 7 do
        wd[w] = (wd[w] or 0) + (p.wd[w] or 1)
      end
      ww = ww + 1
    end
  end
  local d = Pricing.DEFAULT_PRIOR
  local prior = {
    comp = cw > 0 and comp / cw or d.comp,
    cut = kw > 0 and cut / kw or d.cut,
    calib = no > 0 and calib / no or d.calib,
    speed = sn > 0 and speed / sn or 0,
    hd = {},
    wd = {},
    n = cw,
  }
  for h = 1, 24 do
    prior.hd[h] = hw > 0 and hd[h] / hw or 1
  end
  for w = 1, 7 do
    prior.wd[w] = ww > 0 and wd[w] / ww or 1
  end
  return prior
end

-- The numbers the queue model runs on: the item's own, blended with its category's by how much data it has.
-- summary (optional): the market index summary; its sellRate (from daily history) anchors the sales rate.
function Pricing.Params(p, prior, summary)
  p = p or Pricing.NewProfile()
  prior = prior or Pricing.DEFAULT_PRIOR
  local w = p.n / (p.n + Pricing.PRIOR_WEIGHT)
  local longRun = summary and summary.sellRate and summary.sellRate / 24
  local demand
  if p.n > 0 and longRun then
    demand = w * p.demand + (1 - w) * longRun
  elseif p.n > 0 then
    demand = p.demand
  else
    demand = longRun or 0
  end
  -- how fast your own listings sold against the model's expectation (the item's own, blended with its category's)
  local sw = (p.sn or 0) / ((p.sn or 0) + Pricing.SPEED_WEIGHT)
  local speed = sw * (p.speed or 0) + (1 - sw) * (prior.speed or 0)
  demand = demand * exp(speed)
  local comp = prior.comp
  if p.n > 0 and p.demand > 0 then
    comp = w * min(p.inflow / p.demand, 3) + (1 - w) * prior.comp
  end
  local params = {
    demand = demand,
    inflow = comp * demand,
    cut = p.cut > 0 and (w * p.cut + (1 - w) * prior.cut) or prior.cut,
    cuts = p.cuts,
    speed = speed,
    hd = {},
    wd = {},
    n = p.n,
  }
  local hw, ww = p.hn / (p.hn + Pricing.SHAPE_WEIGHT), p.wn / (p.wn + Pricing.SHAPE_WEIGHT / 2)
  for h = 1, 24 do
    params.hd[h] = hw * (p.hd[h] or 1) + (1 - hw) * (prior.hd[h] or 1)
  end
  for d = 1, 7 do
    params.wd[d] = ww * (p.wd[d] or 1) + (1 - ww) * (prior.wd[d] or 1)
  end
  local ow = p.no / (p.no + Pricing.OUTCOME_WEIGHT)
  params.calib = ow * p.calib + (1 - ow) * (prior.calib or 0)
  if p.n >= 20 and longRun then
    params.confidence, params.spread = "high", 0.5
  elseif p.n >= 5 or longRun then
    params.confidence, params.spread = "medium", 0.8
  else
    params.confidence, params.spread = "low", 1.2
  end
  return params
end

---------------------------------------------------------------------------------------------------------------------
-- the queue

-- units that sell (net of undercutting supply arriving in front of you) over the next `hours` from `now`
function Pricing.Capacity(params, hours, now)
  local net = max(params.demand - params.inflow, params.demand * 0.1)
  local cap, t, left = 0, now, hours
  while left > 0 do
    local step = min(1, left)
    cap = cap + net * params.hd[hourOf(t)] * params.wd[weekdayOf(t)] * step
    t, left = t + step * 3600, left - step
  end
  return cap
end

-- chance that the last of `need` units (those ahead plus yours) sells within `hours`
function Pricing.Chance(params, need, hours, now)
  if need <= 0 then
    return 0.99
  end
  local cap = Pricing.Capacity(params, hours, now)
  if cap <= 0 then
    return 0.01
  end
  local z = log(cap / need) / params.spread + params.calib
  return clamp(1 / (1 + exp(-z)), 0.01, 0.99)
end

-- expected hours until `need` units have sold (nil: not within `limit` hours, default a week)
function Pricing.Hours(params, need, now, limit)
  local net = max(params.demand - params.inflow, params.demand * 0.1)
  if net <= 0 then
    return nil
  end
  local cap, t = 0, now
  for h = 1, limit or 168 do
    local rate = net * params.hd[hourOf(t)] * params.wd[weekdayOf(t)]
    if cap + rate >= need then
      return h - 1 + (need - cap) / rate
    end
    cap, t = cap + rate, t + 3600
  end
  return nil
end

-- units in the book at or below price p (a listing at the same price was there first)
function Pricing.Ahead(book, p)
  local n = 0
  for i, price in ipairs(book.prices) do
    if price > p then
      break
    end
    n = n + book.qtys[i]
  end
  return n
end

-- Suggest posting prices.
--   book: current listings (fresh search, or Pricing.BookFromObs); params: Pricing.Params
--   opts: qty (units you post, default 1), hours (listing time, default 24), now, cut (AH cut fraction),
--         deposit (copper for the whole post, lost when it doesn't sell), vendor (vendor price per unit: never
--         suggest below it), reference (usual price, e.g. the 7-day average), ceiling (highest sensible price)
-- returns { quick, normal, patient = { price, chance, hours, ahead, ev }, hold = bool, cheap = bool,
--           confidence, demand, inflow, cut, cuts }  or nil when there's nothing to go on
function Pricing.Suggest(book, params, opts)
  opts = opts or {}
  local qty, hours, now = opts.qty or 1, opts.hours or 24, opts.now or 0
  local cut, deposit = opts.cut or 0, opts.deposit or 0
  local lo = max(1, (opts.vendor or 0) + 1)
  local ref = opts.reference
  local hi = opts.ceiling or (ref and ref * 1.5) or math.huge

  local seen, cands = {}, {}
  local function add(p)
    p = floor(p + 0.5)
    if p >= lo and p <= hi and not seen[p] then
      seen[p] = true
      cands[#cands + 1] = p
    end
  end
  local prices = book.prices
  for _, price in ipairs(prices) do
    add(price - 1) -- in front of this tier
    add(price) -- behind it
  end
  local top = prices[#prices] or ref
  if not top then
    return nil
  end
  for _, f in ipairs({ 1.05, 1.1, 1.2, 1.35, 1.5 }) do
    add(top * f)
  end
  if ref then
    for _, f in ipairs({ 0.9, 1, 1.1, 1.2 }) do
      add(ref * f)
    end
  end
  if #cands == 0 then -- nothing sensible above the vendor price: the vendor floor is all there is
    cands[1] = lo
  end
  table.sort(cands)

  local rows = {}
  for i, p in ipairs(cands) do
    local ahead = Pricing.Ahead(book, p)
    local need = ahead + qty
    local chance = Pricing.Chance(params, need, hours, now)
    rows[i] = {
      price = p,
      ahead = ahead,
      chance = chance,
      quickChance = Pricing.Chance(params, need, min(hours, Pricing.QUICK_HOURS), now),
      hours = Pricing.Hours(params, need, now),
      ev = chance * p * qty * (1 - cut) - (1 - chance) * deposit,
    }
  end

  local normal = rows[1]
  for _, r in ipairs(rows) do
    if r.ev > normal.ev or (r.ev == normal.ev and r.chance > normal.chance) then
      normal = r
    end
  end
  local quick, patient = rows[1], normal
  for _, r in ipairs(rows) do
    if r.quickChance >= Pricing.QUICK_CHANCE and r.price <= normal.price then
      quick = r
    end
    if r.chance >= Pricing.PATIENT_CHANCE and r.price > patient.price then
      patient = r
    end
  end
  return {
    quick = quick,
    normal = normal,
    patient = patient,
    hold = normal.chance < Pricing.HOLD_CHANCE,
    cheap = ref ~= nil and normal.price < ref * 0.7,
    confidence = params.confidence,
    demand = params.demand,
    inflow = params.inflow,
    cut = params.cut,
    cuts = params.cuts,
  }
end

---------------------------------------------------------------------------------------------------------------------
-- storage: one compact string per item

local function num(x)
  x = x or 0
  if x == floor(x) then
    return tostring(x)
  end
  return ("%.4g"):format(x)
end

local function list(t, n, default)
  local out = {}
  for i = 1, n do
    out[i] = num(t[i] or default)
  end
  return table.concat(out, ",")
end

function Pricing.Encode(p)
  local l = p.last or {}
  return table.concat({
    table.concat({
      num(p.n),
      num(p.demand),
      num(p.inflow),
      num(p.cut),
      num(p.cuts),
      num(p.calib),
      num(p.no),
      num(p.speed),
      num(p.sn),
    }, ","),
    table.concat({ num(l.t), num(l.min), num(l.qty) }, ","),
    l.ladder and list(l.ladder, #Pricing.BANDS, 0) or "",
    p.hn > 0 and (num(p.hn) .. "," .. list(p.hd, 24, 1)) or "",
    p.wn > 0 and (num(p.wn) .. "," .. list(p.wd, 7, 1)) or "",
  }, ";")
end

local function numbers(s)
  local out = {}
  for v in (s or ""):gmatch("[^,]+") do
    out[#out + 1] = tonumber(v)
  end
  return out
end

-- quick reads of a stored profile without decoding it all (pruning and category averages skim thousands)
function Pricing.Samples(s) -- scan pairs learned from
  return tonumber(s:match("^(%d+)")) or 0
end

function Pricing.LastSeen(s) -- server time of the last scan that saw the item (nil if never)
  local t = tonumber(s:match("^[^;]*;([^,;]*)"))
  return t and t > 0 and t or nil
end

function Pricing.Decode(s)
  local parts = {}
  for part in (s .. ";"):gmatch("([^;]*);") do
    parts[#parts + 1] = part
  end
  local a, l, ladder, hd, wd =
    numbers(parts[1]), numbers(parts[2]), numbers(parts[3]), numbers(parts[4]), numbers(parts[5])
  local p = Pricing.NewProfile()
  p.n, p.demand, p.inflow, p.cut, p.cuts, p.calib, p.no =
    a[1] or 0, a[2] or 0, a[3] or 0, a[4] or 0, a[5] or 0, a[6] or 0, a[7] or 0
  p.speed, p.sn = a[8] or 0, a[9] or 0
  if l[1] and l[1] > 0 then
    p.last = { t = l[1], min = l[2], qty = l[3], ladder = #ladder > 0 and ladder or nil }
  end
  if hd[1] then
    p.hn = hd[1]
    for h = 1, 24 do
      p.hd[h] = hd[h + 1]
    end
  end
  if wd[1] then
    p.wn = wd[1]
    for w = 1, 7 do
      p.wd[w] = wd[w + 1]
    end
  end
  return p
end
