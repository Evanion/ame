-- Compact text encoding for columnar price data. Pure: no WoW API calls.
--
-- Snapshot wire format v1:  "1|<n>|<ids>|<min>|<market>|<median>|<qty>|<auctions>"
--   each column: n comma-separated base-36 integers; ids are sorted ascending and delta-encoded.
-- Integers must be exact in a double (|x| < 2^53). Base 36 is parsed by hand: Lua 5.1's tonumber(s, 36) uses C
-- unsigned long, which is 32-bit on Windows, so it would overflow in the WoW client for prices above ~429k gold.
--
-- Pack/Unpack wrap a string with an injected compressor { Compress = fn(self, s), Decompress = fn(self, s) }, so the
-- codec is testable without LibDeflate. Decompress must return nil on failure.
local _, ns = ...

local floor = math.floor
local byte, char, sub, concat = string.byte, string.char, string.sub, table.concat

local Codec = {}
ns.Codec = Codec

Codec.VERSION = "1"
Codec.SNAPSHOT_FIELDS = { "ids", "min", "market", "median", "qty", "auctions" }
-- an hourly point (Store's hours tier): plain items only, prices to 3 significant figures (see Codec.Round3)
Codec.HOUR_FIELDS = { "ids", "min", "market", "qty", "auctions", "median" } -- median: added later (may be missing)

-- a price (copper) to 3 significant figures: 123456 -> 123000. Charts and trends don't need the last copper, and
-- rounded points compress far better (hourly points go out over sync).
function Codec.Round3(v)
  if v < 1000 then
    return v
  end
  local p = 1
  while v >= 1000 * p do
    p = p * 10
  end
  return math.floor(v / p + 0.5) * p
end

local MAX_SAFE = 2 ^ 53

local DIGITS = {}
local VALUES = {}
for i = 0, 35 do
  local c = i < 10 and char(48 + i) or char(87 + i) -- 0-9, a-z
  DIGITS[i] = c
  VALUES[byte(c)] = i
end

function Codec.ToBase36(x)
  if type(x) ~= "number" or x ~= floor(x) or x >= MAX_SAFE or x <= -MAX_SAFE then
    error("Codec: not an exact integer: " .. tostring(x), 2)
  end
  if x == 0 then
    return "0"
  end
  local neg = x < 0
  if neg then
    x = -x
  end
  local out, n = {}, 0
  while x > 0 do
    local r = x % 36
    n = n + 1
    out[n] = DIGITS[r]
    x = (x - r) / 36 -- exact: x - r is a multiple of 36
  end
  -- reverse
  for i = 1, floor(n / 2) do
    out[i], out[n - i + 1] = out[n - i + 1], out[i]
  end
  return (neg and "-" or "") .. concat(out)
end

function Codec.FromBase36(s)
  local len = #s
  local i, neg = 1, false
  if byte(s, 1) == 45 then -- "-"
    neg, i = true, 2
  end
  if i > len then
    error("Codec: empty number", 2)
  end
  local x = 0
  for k = i, len do
    local v = VALUES[byte(s, k)]
    if not v then
      error("Codec: bad digit in " .. s, 2)
    end
    x = x * 36 + v
  end
  if x >= MAX_SAFE then
    error("Codec: number out of range: " .. s, 2)
  end
  return neg and -x or x
end

-- split keeping empty fields
local function split(s, sep)
  local out, n, start = {}, 0, 1
  while true do
    local at = s:find(sep, start, true)
    n = n + 1
    if not at then
      out[n] = sub(s, start)
      return out, n
    end
    out[n] = sub(s, start, at - 1)
    start = at + 1
  end
end

local function encodeColumn(values, n, delta)
  local parts, prev = {}, 0
  for i = 1, n do
    local v = values[i]
    if delta then
      if v < prev then
        error("Codec: ids must be sorted ascending", 3)
      end
      v, prev = v - prev, v
    end
    parts[i] = Codec.ToBase36(v)
  end
  return concat(parts, ",")
end

local function decodeColumn(text, n, delta, yield)
  local values = {}
  if n == 0 then
    if text ~= "" then
      error("Codec: column length mismatch", 3)
    end
    return values
  end
  local parts, count = split(text, ",")
  if count ~= n then
    error("Codec: column length mismatch", 3)
  end
  local prev = 0
  for i = 1, n do
    local v = Codec.FromBase36(parts[i])
    if delta then
      v = prev + v
      prev = v
    end
    values[i] = v
    if yield and i % 500 == 0 then -- a column of 25k values is ~45 ms
      yield()
    end
  end
  return values
end

-- Generic columnar table: fieldNames[1] is the key column (sorted ascending, delta-encoded); all columns have the
-- same length. Used for scan snapshots and for daily/weekly point segments.
function Codec.Encode(fieldNames, cols)
  local n = #cols[fieldNames[1]]
  local out = { Codec.VERSION, Codec.ToBase36(n) }
  for f, name in ipairs(fieldNames) do
    local col = cols[name]
    if not col then
      error("Codec: missing column " .. name, 2)
    end
    out[f + 2] = encodeColumn(col, n, f == 1)
  end
  return concat(out, "|")
end

-- allowMissing: text written before trailing fields were added decodes with those columns nil
-- yield (optional): called between columns (a full scan's columns take ~8 ms each), and every 500 values in them
-- init (optional): where the encoded table starts in text (a saved market index has a header before it)
-- The columns are cut out one at a time, as they're decoded: an 8 MB index split up front allocated twice its size
-- in one step, and the garbage collector made the next frames pay for it.
function Codec.Decode(fieldNames, text, allowMissing, yield, init)
  local starts, pos = {}, init or 1
  while true do
    starts[#starts + 1] = pos
    local at = text:find("|", pos, true)
    if not at then
      break
    end
    pos = at + 1
  end
  local count = #starts
  local function field(i)
    local e = starts[i + 1] and starts[i + 1] - 2 or #text
    return sub(text, starts[i], e)
  end
  if field(1) ~= Codec.VERSION then
    error("Codec: unsupported version " .. tostring(field(1)), 2)
  end
  if count ~= #fieldNames + 2 and not (allowMissing and count >= 3 and count < #fieldNames + 2) then
    error("Codec: wrong field count", 2)
  end
  local n = Codec.FromBase36(field(2))
  local cols = {}
  for f, name in ipairs(fieldNames) do
    if f + 2 <= count then
      cols[name] = decodeColumn(field(f + 2), n, f == 1, yield)
      if yield then
        yield()
      end
    end
  end
  return cols
end

function Codec.EncodeSnapshot(snap)
  return Codec.Encode(Codec.SNAPSHOT_FIELDS, snap)
end

function Codec.DecodeSnapshot(text, yield)
  return Codec.Decode(Codec.SNAPSHOT_FIELDS, text, nil, yield)
end

-- yield (optional): passed to the compressor, which pauses between the pieces of a big text
function Codec.Pack(text, compressor, yield)
  return compressor:Compress(text, yield)
end

function Codec.Unpack(packed, compressor, yield)
  local text = compressor:Decompress(packed, yield)
  if not text then
    error("Codec: decompression failed", 2)
  end
  return text
end
