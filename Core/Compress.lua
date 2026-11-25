-- Compressor adapter for Codec.Pack/Unpack, backed by LibDeflate. Output is print-safe (EncodeForPrint), so it can
-- live in SavedVariables. Pure apart from the injected library.
local _, ns = ...

local Compress = {}
ns.Compress = Compress

Compress.LEVEL = 5
-- Big texts (full scans: ~450 KB) are compressed in pieces of this size, with yield() between them: LibDeflate does
-- a whole string in one call (~430 ms for a full scan, ~95 ms to decompress), which froze the game for a moment
-- when storing a scan or receiving one over sync. Chunked text is "#2," followed by the pieces joined with ","
-- (both outside EncodeForPrint's alphabet). Texts up to CHUNK stay in the old single-piece form, readable by older
-- versions; both forms decompress. 8 KB: one piece takes ~9 ms, which can't pause inside LibDeflate (16 KB took
-- ~16 ms, a stutter when storing a guildmate's scan); the pieces compress ~1.5% worse. Any piece size reads back.
Compress.CHUNK = 8192
Compress.CHUNKED = "#2,"

function Compress.New(LibDeflate)
  assert(LibDeflate, "LibDeflate required")
  local config = { level = Compress.LEVEL }
  local function one(s)
    return LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(s, config))
  end
  local function unone(s)
    local raw = LibDeflate:DecodeForPrint(s)
    return raw and LibDeflate:DecompressDeflate(raw) or nil
  end
  return {
    -- yield (optional): called between pieces, so a background job can pause there
    Compress = function(_, s, yield)
      if #s <= Compress.CHUNK then
        return one(s)
      end
      local parts = {}
      for i = 1, #s, Compress.CHUNK do
        parts[#parts + 1] = one(s:sub(i, i + Compress.CHUNK - 1))
        if yield then
          yield()
        end
      end
      return Compress.CHUNKED .. table.concat(parts, ",")
    end,
    Decompress = function(_, s, yield)
      if s:sub(1, #Compress.CHUNKED) ~= Compress.CHUNKED then
        return unone(s)
      end
      local out = {}
      for part in s:sub(#Compress.CHUNKED + 1):gmatch("[^,]+") do
        local text = unone(part)
        if not text then
          return nil
        end
        out[#out + 1] = text
        if yield then
          yield()
        end
      end
      return table.concat(out)
    end,
    -- For sync v2's addon messages (any byte but NUL): a stored (print-safe) string compressed once more and encoded
    -- for the addon channel - print encoding spends 8 bits per 6, so this takes ~25% off the airtime. In pieces of
    -- CHUNK, each "<length36>:<bytes>", with yield() between them.
    Wire = function(_, s, yield)
      local out = {}
      for i = 1, math.max(#s, 1), Compress.CHUNK do
        local p =
          LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(s:sub(i, i + Compress.CHUNK - 1), config))
        out[#out + 1] = ns.Codec.ToBase36(#p) .. ":" .. p
        if yield then
          yield()
        end
      end
      return table.concat(out)
    end,
    Unwire = function(_, s, yield)
      local out, at = {}, 1
      while at <= #s do
        local len, start = s:match("^(%w+):()", at)
        len = len and ns.Codec.FromBase36(len)
        if not len then
          return nil
        end
        local raw = LibDeflate:DecodeForWoWAddonChannel(s:sub(start, start + len - 1))
        local text = raw and LibDeflate:DecompressDeflate(raw)
        if not text then
          return nil
        end
        out[#out + 1] = text
        at = start + len
        if yield then
          yield()
        end
      end
      return table.concat(out)
    end,
  }
end
