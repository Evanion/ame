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

local function decodeColumn(text, n, delta)
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
  end
  return values
end

function Codec.EncodeSnapshot(snap)
  local n = #snap.ids
  local out = { Codec.VERSION, Codec.ToBase36(n) }
  for f, name in ipairs(Codec.SNAPSHOT_FIELDS) do
    out[f + 2] = encodeColumn(snap[name], n, f == 1)
  end
  return concat(out, "|")
end

function Codec.DecodeSnapshot(text)
  local fields, count = split(text, "|")
  if fields[1] ~= Codec.VERSION then
    error("Codec: unsupported version " .. tostring(fields[1]), 2)
  end
  if count ~= #Codec.SNAPSHOT_FIELDS + 2 then
    error("Codec: wrong field count", 2)
  end
  local n = Codec.FromBase36(fields[2])
  local snap = {}
  for f, name in ipairs(Codec.SNAPSHOT_FIELDS) do
    snap[name] = decodeColumn(fields[f + 2], n, f == 1)
  end
  return snap
end

function Codec.Pack(text, compressor)
  return compressor:Compress(text)
end

function Codec.Unpack(packed, compressor)
  local text = compressor:Decompress(packed)
  if not text then
    error("Codec: decompression failed", 2)
  end
  return text
end
