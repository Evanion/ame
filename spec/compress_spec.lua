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

  it("compresses big texts in pieces, pausing between them, and reads both forms", function()
    local c = ns.Compress.New(LibDeflate)
    local parts = {}
    for i = 1, 6000 do
      parts[i] = ns.Codec.ToBase36(i * 7919 % 100003)
    end
    local text = table.concat(parts, ",") -- ~30 KB: more than one piece
    assert.is_true(#text > ns.Compress.CHUNK)
    local pauses = 0
    local function pause()
      pauses = pauses + 1
    end
    local packed = ns.Codec.Pack(text, c, pause)
    assert.are.equal("#2,", packed:sub(1, 3))
    assert.is_true(pauses >= 2)
    pauses = 0
    assert.are.equal(text, ns.Codec.Unpack(packed, c, pause))
    assert.is_true(pauses >= 2)
    -- small texts keep the old single-piece form (older versions read them), and the old form still reads
    local small = string.rep("a,b,", 100)
    local old = ns.Codec.Pack(small, c)
    assert.are_not.equal("#2,", old:sub(1, 3))
    assert.are.equal(small, ns.Codec.Unpack(old, c))
    -- a damaged piece fails cleanly
    assert.has_error(function()
      ns.Codec.Unpack(packed:sub(1, #packed - 40) .. "!!", c)
    end)
  end)

  it("fails cleanly on garbage", function()
    local c = ns.Compress.New(LibDeflate)
    assert.has_error(function()
      ns.Codec.Unpack("not a packed string!!", c)
    end)
  end)
end)
