-- Compressor adapter for Codec.Pack/Unpack, backed by LibDeflate. Output is print-safe (EncodeForPrint), so it can
-- live in SavedVariables. Pure apart from the injected library.
local _, ns = ...

local Compress = {}
ns.Compress = Compress

Compress.LEVEL = 5

function Compress.New(LibDeflate)
  assert(LibDeflate, "LibDeflate required")
  local config = { level = Compress.LEVEL }
  return {
    Compress = function(_, s)
      return LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(s, config))
    end,
    Decompress = function(_, s)
      local raw = LibDeflate:DecodeForPrint(s)
      if not raw then
        return nil
      end
      return LibDeflate:DecompressDeflate(raw)
    end,
  }
end
