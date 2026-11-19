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
-- versions; both forms decompress.
Compress.CHUNK = 16384
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
  }
end
