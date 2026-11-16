local addon = require("spec.helpers.addon")

-- Uses the real LibDeflate from Libs/ (run scripts/fetch-libs.sh first). Skipped when it isn't present.
local libPath = "Libs/LibDeflate/LibDeflate.lua"
local f = io.open(libPath, "r")
local LibDeflate
if f then
  f:close()
  LibDeflate = dofile(libPath)
end

describe("Compress (LibDeflate adapter)", function()
  if not LibDeflate then
    pending("Libs/LibDeflate missing; run scripts/fetch-libs.sh")
    return
  end

  local ns
  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/Compress.lua" })
  end)

  it("round-trips through Codec.Pack/Unpack and stays print-safe", function()
    local c = ns.Compress.New(LibDeflate)
    local text = string.rep("1|3|rs,1,4|2s,5k,9z|", 200)
    local packed = ns.Codec.Pack(text, c)
    assert.is_nil(packed:find("[%z\1-\31\127-\255]"), "packed string has unprintable bytes")
    assert.is_true(#packed < #text)
    assert.are.equal(text, ns.Codec.Unpack(packed, c))
  end)

  it("fails cleanly on garbage", function()
    local c = ns.Compress.New(LibDeflate)
    assert.has_error(function()
      ns.Codec.Unpack("not a packed string!!", c)
    end)
  end)
end)
