-- Sell-through (pure): how much of what gets listed actually sells, from real auction outcomes - yours (auction mail
-- and cancels) and your guildmates' (shared over sync) - instead of from scans, which can't tell a sale from a listing
-- that expired or was cancelled. An item reposted every day that never sells looks like thousands sold a day in
-- scans; its sell-through says 0%.
--
--   record = { s = units sold, e = units expired, c = units cancelled, n = outcomes (listings), t = as of (time) }
--
-- Counts fade (HALF_LIFE): what sold a month ago says less about today. Sell-through = sold / (sold + expired +
-- cancelled), in units, as TradeSkillMaster counts it. It only takes over from the scan-based numbers with data:
-- weight = outcomes / (outcomes + WEIGHT).
local _, ns = ...

local SellThrough = {}
ns.SellThrough = SellThrough

local floor, min = math.floor, math.min

SellThrough.HALF_LIFE = 21 * 86400 -- seconds: an outcome's weight halves this much later
SellThrough.WEIGHT = 3 -- outcomes before an item's own sell-through outweighs the scan-based assumption
SellThrough.PEER_AGE = 30 * 86400 -- a guildmate's shared numbers are dropped this long after they last sent them
SellThrough.MAX_ITEMS = 300 -- items shared per message (the ones with the most outcomes)
SellThrough.MAX_UNITS = 100000 -- per item and kind, in shared numbers (anything above is junk)
SellThrough.MAX_OUTCOMES = 1000
-- Items nobody has listed: the scans' rate counts expired and cancelled listings as sold, so only a share of it is.
-- That share is the market's own sell-through (every item with outcomes, by how many it has), starting from
-- DEFAULT_SHARE until there are PRIOR_WEIGHT outcomes to go on.
SellThrough.DEFAULT_SHARE = 0.4
SellThrough.PRIOR_WEIGHT = 20
SellThrough.MIN_SHARE = 0.05

local FIELD = { sold = "s", expired = "e", cancelled = "c" }

function SellThrough.New(t)
  return { s = 0, e = 0, c = 0, n = 0, t = t or 0 }
end

-- fade a record's counts to time t
function SellThrough.Decay(r, t)
  if r.t and r.t > 0 and t and t > r.t then
    local f = 0.5 ^ ((t - r.t) / SellThrough.HALF_LIFE)
    r.s, r.e, r.c, r.n = r.s * f, r.e * f, r.c * f, r.n * f
  end
  if t and t > (r.t or 0) then
    r.t = t
  end
  return r
end

-- one listing's outcome: kind "sold" / "expired" / "cancelled", units of it, at time t
function SellThrough.Add(r, kind, units, t)
  local f = FIELD[kind]
  if not f or not units or units <= 0 then
    return false
  end
  SellThrough.Decay(r, t)
  r[f] = r[f] + units
  r.n = r.n + 1
  return true
end

local function num(x)
  if x == floor(x) then
    return tostring(x)
  end
  return ("%.3g"):format(x)
end

function SellThrough.Encode(r)
  return table.concat({ num(r.s), num(r.e), num(r.c), num(r.n), num(r.t or 0) }, ",")
end

function SellThrough.Decode(text)
  local v = {}
  for x in (text or ""):gmatch("[^,]+") do
    v[#v + 1] = tonumber(x) or 0
  end
  return { s = v[1] or 0, e = v[2] or 0, c = v[3] or 0, n = v[4] or 0, t = v[5] or 0 }
end

---------------------------------------------------------------------------------------------------------------------
-- combining yours with your guildmates'

-- Totals for one item at time t: own (record or nil) plus peers ({ { t = when sent, r = record }, ... }).
-- Returns { s, e, c, n, peers = guildmates with data } or nil when nobody has any.
function SellThrough.Combine(own, peers, t)
  local tot = { s = 0, e = 0, c = 0, n = 0, peers = 0 }
  local function add(r, at)
    local f = at and t and t > at and 0.5 ^ ((t - at) / SellThrough.HALF_LIFE) or 1
    tot.s, tot.e, tot.c, tot.n = tot.s + r.s * f, tot.e + r.e * f, tot.c + r.c * f, tot.n + r.n * f
  end
  if own and own.n > 0 then
    add(own, own.t)
  end
  for _, p in ipairs(peers or {}) do
    if p.r and p.r.n > 0 then
      add(p.r, p.t)
      tot.peers = tot.peers + 1
    end
  end
  if tot.n <= 0 or tot.s + tot.e + tot.c <= 0 then
    return nil
  end
  return tot
end

-- sell-through (0..1) and how much it counts (0..1), from Combine's totals
function SellThrough.Rate(tot)
  if not tot then
    return nil
  end
  local ended = tot.s + tot.e + tot.c
  if ended <= 0 or tot.n <= 0 then
    return nil
  end
  return tot.s / ended, tot.n / (tot.n + SellThrough.WEIGHT)
end

-- The share of the scans' rate that sells, for items without outcomes of their own: the market's sell-through
-- (through = { [item] = Combine totals }), weighed by outcomes and pulled toward DEFAULT_SHARE while there are few.
function SellThrough.Prior(through)
  local sum, n = 0, 0
  for _, tot in pairs(through or {}) do
    local p = SellThrough.Rate(tot)
    if p then
      sum, n = sum + p * tot.n, n + tot.n
    end
  end
  local k = SellThrough.PRIOR_WEIGHT
  local share = (sum + SellThrough.DEFAULT_SHARE * k) / (n + k)
  return math.max(SellThrough.MIN_SHARE, math.min(1, share))
end

-- An item without outcomes: its sales rate is the scans' rate times the market's share (Prior). stPrior marks the
-- rate as estimated that way; churnRate keeps the scans' own.
function SellThrough.Estimate(s, prior)
  if s.sellRate and prior and prior < 1 then
    s.churnRate = s.sellRate
    s.sellRate = s.sellRate * prior
    s.stPrior = prior
  end
end

-- Fold an item's sell-through into its market summary (Analytics.Summarize):
--   sellThrough, stWeight     the rate and how much it counts
--   stSold, stEnded, stPeers  units sold, units whose listing ended, guildmates who contributed
--   churnRate                 the scans' rate (units leaving the AH a day: sold, expired or cancelled)
--   sellRate                  scaled to the share of those that sold (while its outcomes are few, partly the
--                             market's share: prior, from Prior; 1 when not given)
--   value                     what one is worth to you: the market price when it sells, else the vendor's
-- vendor: the vendor price (copper, or nil). Returns true when the item has data.
function SellThrough.Apply(s, tot, vendor, prior)
  local p, w = SellThrough.Rate(tot)
  if not p then
    return false
  end
  s.sellThrough, s.stWeight = p, w
  s.stSold, s.stEnded, s.stPeers = tot.s, tot.s + tot.e + tot.c, tot.peers
  if s.sellRate then
    s.churnRate = s.sellRate
    s.sellRate = s.sellRate * (w * p + (1 - w) * (prior or 1))
  end
  if s.market then
    s.value = w * (p * s.market + (1 - p) * (vendor or 0)) + (1 - w) * s.market
  end
  return true
end

-- What one listing nets at the auction house: market after the cut, less the deposit. Without sell-through the
-- deposit counts as lost (the cautious view); with it, a sale earns the market price and keeps the deposit, a listing
-- that doesn't sell loses it - weighed by the sell-through, as much as it counts.
function SellThrough.Net(s, cut, deposit)
  local m = s.market * (1 - (cut or 0))
  local net = m - (deposit or 0)
  local p, w = s.sellThrough, s.stWeight
  if p and w then
    net = w * (p * m - (1 - p) * (deposit or 0)) + (1 - w) * net
  end
  return net
end

---------------------------------------------------------------------------------------------------------------------
-- sharing: your own numbers per item, plus what your listings taught the posting model (calibration and speed, see
-- Pricing.Learn / LearnSpeed), so guildmates' posting advice learns from everyone's listings

-- item entries -> "key36:s:e:c:n:calib:no:speed:sn;..." (counts x10, calibration and speed x100: whole numbers)
--   entries = { { key, record, calib, no, speed, sn }, ... }
function SellThrough.EncodeItems(entries)
  local B = ns.Codec.ToBase36
  local parts = {}
  for i = 1, min(#entries, SellThrough.MAX_ITEMS) do
    local e = entries[i]
    local r = e[2]
    local function x(v, k)
      return B(floor((v or 0) * k + 0.5))
    end
    parts[i] = table.concat({
      B(e[1]),
      x(r.s, 10),
      x(r.e, 10),
      x(r.c, 10),
      x(r.n, 10),
      x(e[3], 100),
      x(e[4], 1),
      x(e[5], 100),
      x(e[6], 1),
    }, ":")
  end
  return table.concat(parts, ";")
end

local function clamp(x, lo, hi)
  return x < lo and lo or x > hi and hi or x
end

-- the reverse, with junk clamped away: { [key] = { r = record, calib, no, speed, sn } }
function SellThrough.DecodeItems(text, t)
  local F = ns.Codec.FromBase36
  local out, count = {}, 0
  for item in (text or ""):gmatch("[^;]+") do
    local f = {}
    for v in item:gmatch("[^:]+") do
      f[#f + 1] = v
    end
    if #f == 9 then
      local ok, v = pcall(function()
        local r = {}
        for i = 1, 9 do
          r[i] = F(f[i])
        end
        return r
      end)
      if ok then
        local U, N = SellThrough.MAX_UNITS, SellThrough.MAX_OUTCOMES
        out[v[1]] = {
          r = {
            s = clamp(v[2] / 10, 0, U),
            e = clamp(v[3] / 10, 0, U),
            c = clamp(v[4] / 10, 0, U),
            n = clamp(v[5] / 10, 0, N),
            t = t or 0,
          },
          calib = clamp(v[6] / 100, -2, 2),
          no = clamp(v[7], 0, N),
          speed = clamp(v[8] / 100, -2, 2),
          sn = clamp(v[9], 0, N),
        }
        count = count + 1
        if count >= SellThrough.MAX_ITEMS then
          break
        end
      end
    end
  end
  return out
end

-- A pricing profile with guildmates' listing outcomes folded in: calibration and speed become the outcome-weighted
-- averages of yours and theirs (p is not changed; a copy is returned when there's anything to add).
--   shared = { { calib, no, speed, sn }, ... }
function SellThrough.MergeProfile(p, shared)
  if not shared or #shared == 0 then
    return p
  end
  local calib, no = (p.calib or 0) * (p.no or 0), p.no or 0
  local speed, sn = (p.speed or 0) * (p.sn or 0), p.sn or 0
  for _, o in ipairs(shared) do
    calib, no = calib + o.calib * o.no, no + o.no
    speed, sn = speed + o.speed * o.sn, sn + o.sn
  end
  local q = {}
  for k, v in pairs(p) do
    q[k] = v
  end
  q.calib, q.no = no > 0 and calib / no or 0, no
  q.speed, q.sn = sn > 0 and speed / sn or 0, sn
  return q
end
