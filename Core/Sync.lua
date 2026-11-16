-- Sync protocol core (pure). Peers share FULL scans from their raw tier (last 48 h):
--
--   announce  "1|A|<shard>|<t36>:<src>;<t36>:<src>;..."   newest full scans this peer holds (GUILD broadcast)
--   request   "1|R|<shard>|<t36>|<src>"                     whisper to the announcer
--   scan      "1|S|<shard>|<t36>|<src>|<kind>|<packed>"     whisper reply; packed = the raw entry's compressed string
--   hello     "1|H|<shard>"                                   whisper: "I'd like to share prices with you" (trust)
--   accept    "1|K|<shard>"                                   whisper: "I trust you too"
--
-- Transport (chunking + pacing at BULK priority) is AceComm/ChatThrottleLib in the WoW glue. Received scans are
-- merged with Store:AddScan, whose dedupe makes repeats harmless; announcements repeat, so dropped whispers retry
-- naturally. Plausible() guards against poisoned data before merging.
local _, ns = ...

local Codec = ns.Codec

local Sync = {}
ns.Sync = Sync

Sync.PROTO = "1"
Sync.MAX_ANNOUNCE = 8
Sync.WINDOW = 48 * 3600
Sync.OUTLIER_FACTOR = 5 -- a price 5x above or below ours counts as "off"
Sync.MAX_OFF_SHARE = 0.3 -- reject a scan when more than 30% of comparable items are off
Sync.MIN_COMPARABLE = 3

local function split(s, sep)
  local out, start = {}, 1
  while true do
    local at = s:find(sep, start, true)
    if not at then
      out[#out + 1] = s:sub(start)
      return out
    end
    out[#out + 1] = s:sub(start, at - 1)
    start = at + 1
  end
end

-- full scans in a raw tier, newest first
function Sync.Inventory(raw, limit)
  local out = {}
  for i = #raw, 1, -1 do
    local e = raw[i]
    if (e.k or "full") == "full" then
      out[#out + 1] = { t = e.t, src = e.src, entry = e }
      if #out >= (limit or Sync.MAX_ANNOUNCE) then
        break
      end
    end
  end
  return out
end

local function clean(s)
  return (tostring(s):gsub("[|;:]", ""))
end

function Sync.EncodeAnnounce(shard, inventory)
  local parts = {}
  for i, s in ipairs(inventory) do
    parts[i] = Codec.ToBase36(s.t) .. ":" .. clean(s.src)
  end
  return table.concat({ Sync.PROTO, "A", shard, table.concat(parts, ";") }, "|")
end

function Sync.EncodeRequest(shard, t, src)
  return table.concat({ Sync.PROTO, "R", shard, Codec.ToBase36(t), clean(src) }, "|")
end

function Sync.EncodeScan(shard, entry)
  return table.concat(
    { Sync.PROTO, "S", shard, Codec.ToBase36(entry.t), clean(entry.src), entry.k or "full", entry.s },
    "|"
  )
end

function Sync.EncodeHello(shard)
  return table.concat({ Sync.PROTO, "H", shard }, "|")
end

function Sync.EncodeAccept(shard)
  return table.concat({ Sync.PROTO, "K", shard }, "|")
end

-- shard keys contain "|" (realm|house), so fields are counted from the known layout
function Sync.Decode(msg)
  if type(msg) ~= "string" or msg:sub(1, 2) ~= Sync.PROTO .. "|" then
    return nil
  end
  local ok, result = pcall(function()
    local f = split(msg, "|")
    local kind = f[2]
    local shard = f[3] and f[4] and (f[3] .. "|" .. f[4])
    if kind == "A" and #f == 5 then
      local scans = {}
      if f[5] ~= "" then
        for _, item in ipairs(split(f[5], ";")) do
          local t, src = item:match("^([%w]+):(.+)$")
          if t then
            scans[#scans + 1] = { t = Codec.FromBase36(t), src = src }
          end
        end
      end
      return { type = "announce", shard = shard, scans = scans }
    elseif kind == "H" and #f == 4 then
      return { type = "hello", shard = shard }
    elseif kind == "K" and #f == 4 then
      return { type = "accept", shard = shard }
    elseif kind == "R" and #f == 6 then
      return { type = "request", shard = shard, t = Codec.FromBase36(f[5]), src = f[6] }
    elseif kind == "S" and #f >= 8 then
      -- packed payload is print-safe and contains no "|", but join defensively
      local packed = table.concat(f, "|", 8)
      return { type = "scan", shard = shard, t = Codec.FromBase36(f[5]), src = f[6], kind = f[7], packed = packed }
    end
  end)
  return ok and result or nil
end

-- scans in an announcement that we don't hold, for our shard, still inside the sync window
function Sync.Wanted(announce, myShard, myRaw, now, window)
  local want = {}
  if not announce or announce.shard ~= myShard then
    return want
  end
  local have = {}
  for _, e in ipairs(myRaw) do
    have[e.t .. ":" .. clean(e.src)] = true
  end
  for _, s in ipairs(announce.scans) do
    if s.t >= now - (window or Sync.WINDOW) and not have[s.t .. ":" .. s.src] then
      want[#want + 1] = s
    end
  end
  return want
end

-- Compare a received snapshot's market prices with ours (reference: itemID -> { market = }). Returns ok, reason.
function Sync.Plausible(snap, reference)
  local comparable, off = 0, 0
  for i, id in ipairs(snap.ids) do
    local ref = reference[id]
    local p = snap.market[i]
    if ref and ref.market and ref.market > 0 and p and p > 0 then
      comparable = comparable + 1
      local ratio = p / ref.market
      if ratio > Sync.OUTLIER_FACTOR or ratio < 1 / Sync.OUTLIER_FACTOR then
        off = off + 1
      end
    end
  end
  if comparable < Sync.MIN_COMPARABLE then
    return true
  end
  if off / comparable > Sync.MAX_OFF_SHARE then
    return false, ("%d of %d known prices differ more than %dx from ours"):format(off, comparable, Sync.OUTLIER_FACTOR)
  end
  return true
end
