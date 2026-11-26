local addon = require("spec.helpers.addon")

describe("Codec", function()
  local Codec

  before_each(function()
    Codec = addon.load({ "Core/Init.lua", "Core/Codec.lua" }).Codec
  end)

  local function snap(ids, extra)
    local s = { ids = ids, min = {}, market = {}, median = {}, qty = {}, auctions = {} }
    for i = 1, #ids do
      s.min[i], s.market[i], s.median[i], s.qty[i], s.auctions[i] = 100 * i, 110 * i, 120 * i, i, 1
    end
    for k, v in pairs(extra or {}) do
      s[k] = v
    end
    return s
  end

  local function strip(s)
    return {
      ids = s.ids,
      min = s.min,
      market = s.market,
      median = s.median,
      qty = s.qty,
      auctions = s.auctions,
    }
  end

  describe("base36", function()
    it("round-trips 0, small, negative and 2^53-range integers", function()
      for _, v in ipairs({ 0, 1, 35, 36, 1295, -1, -12345, 2 ^ 31, 3 * 2 ^ 31, 2 ^ 53 - 1 }) do
        assert.are.equal(v, Codec.FromBase36(Codec.ToBase36(v)))
      end
    end)

    it("rejects non-integers", function()
      assert.has_error(function()
        Codec.ToBase36(1.5)
      end)
    end)
  end)

  describe("snapshot", function()
    it("round-trips a snapshot", function()
      local s = snap({ 2589, 2592, 4306, 190000 })
      assert.are.same(strip(s), strip(Codec.DecodeSnapshot(Codec.EncodeSnapshot(s))))
    end)

    it("round-trips an empty snapshot", function()
      local s = snap({})
      assert.are.same(strip(s), strip(Codec.DecodeSnapshot(Codec.EncodeSnapshot(s))))
    end)

    it("round-trips prices above 2^31 copper", function()
      local s = snap({ 1 })
      s.min[1], s.market[1], s.median[1] = 3 * 2 ^ 31, 2 ^ 40, 2 ^ 53 - 1
      assert.are.same(strip(s), strip(Codec.DecodeSnapshot(Codec.EncodeSnapshot(s))))
    end)

    it("delta-encodes the sorted id column", function()
      local enc = Codec.EncodeSnapshot(snap({ 1000, 1001, 1005 }))
      -- 1000 = "rs" in base36, then deltas 1 and 4
      assert.truthy(enc:find("rs,1,4", 1, true), enc)
    end)

    it("is versioned", function()
      local enc = Codec.EncodeSnapshot(snap({ 1 }))
      assert.are.equal("1|", enc:sub(1, 2))
      assert.has_error(function()
        Codec.DecodeSnapshot("9" .. enc:sub(2))
      end)
    end)

    it("errors on corrupted input instead of returning garbage", function()
      local enc = Codec.EncodeSnapshot(snap({ 1, 2, 3 }))
      assert.has_error(function()
        Codec.DecodeSnapshot(enc:sub(1, #enc - 4))
      end)
      assert.has_error(function()
        Codec.DecodeSnapshot(enc:gsub("|", "#", 1))
      end)
      assert.has_error(function()
        Codec.DecodeSnapshot("1|3|!!")
      end)
      -- read off the text without splitting it: every malformed number still errors
      local F = { "ids", "v" }
      assert.are.same({ ids = { 1, 3 }, v = { -5, 71 } }, Codec.Decode(F, "1|2|1,2|-5,1z"))
      for _, bad in ipairs({
        "1|2|1,2|5,",
        "1|2|1,2|-,1",
        "1|2|1,2|5,1-2",
        "1|2|1,2|5,6,7",
        "1|2|1,2|5",
        "1|2|1,,2|5,6",
      }) do
        assert.is_false((pcall(Codec.Decode, F, bad)), bad)
      end
    end)

    it("DecodeRow reads one row, as Decode would cut it down to that row", function()
      local F = { "ids", "a", "b", "c" }
      local cols = { ids = { 3, 8, 9, 40, 1000 }, a = { -1, 2, 3, 4, 5 }, b = { 0, 0, 77, 0, 2 ^ 40 }, c = {} }
      for i = 1, 5 do
        cols.c[i] = i * 1000
      end
      local text = Codec.Encode(F, cols)
      for i, id in ipairs(cols.ids) do
        assert.are.same(
          { ids = { id }, a = { cols.a[i] }, b = { cols.b[i] }, c = { cols.c[i] } },
          Codec.DecodeRow(F, text, id)
        )
      end
      for _, id in ipairs({ 1, 4, 41, 5000 }) do
        assert.is_nil(Codec.DecodeRow(F, text, id))
      end
      assert.is_nil(Codec.DecodeRow(F, "1|0||||", 3))
      -- text written before the trailing columns existed
      local older = Codec.Encode({ "ids", "a" }, cols)
      assert.are.same({ ids = { 40 }, a = { 4 } }, Codec.DecodeRow(F, older, 40, true))
      assert.has_error(function()
        Codec.DecodeRow(F, older, 40)
      end)
    end)

    it("DecodeRow errors on malformed text", function()
      local F = { "ids", "v" }
      for _, bad in ipairs({
        "9|2|1,2|5,6",
        "1|2|1,2|5,6|7",
        "1|2|1,2|5",
        "1|2|1,2|5,",
        "1|2|1,2|5,!",
        "1|2|1,!|5,6",
        "1|2|1|5,6",
      }) do
        assert.is_false((pcall(Codec.DecodeRow, F, bad, 3)), bad)
      end
    end)

    it("rejects unsorted ids", function()
      assert.has_error(function()
        Codec.EncodeSnapshot(snap({ 5, 3 }))
      end)
    end)
  end)

  describe("pack", function()
    local reverse = {
      Compress = function(_, s)
        return s:reverse()
      end,
      Decompress = function(_, s)
        return s:reverse()
      end,
    }
    local broken = {
      Compress = function(_, s)
        return s
      end,
      Decompress = function()
        return nil
      end,
    }

    it("passes through the injected compressor", function()
      local packed = Codec.Pack("hello", reverse)
      assert.are.equal("olleh", packed)
      assert.are.equal("hello", Codec.Unpack(packed, reverse))
    end)

    it("errors when decompression fails", function()
      assert.has_error(function()
        Codec.Unpack("x", broken)
      end)
    end)
  end)
end)
