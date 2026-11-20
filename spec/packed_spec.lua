local addon = require("spec.helpers.addon")

describe("Packed", function()
  local Packed

  before_each(function()
    Packed = addon.load({ "Core/Init.lua", "Core/Packed.lua" }).Packed
  end)

  it("round-trips number and string keys (item keys with suffixes too)", function()
    local t = { [2589] = "1;2;3", [14473015985] = "Raider Shortsword of the Monkey", name = "x", [7] = "" }
    local text = Packed.Pack(t)
    assert.are.equal("string", type(text))
    assert.are.same(t, Packed.Unpack(text))
  end)

  it("leaves out what it can't carry: tabs or newlines, values that aren't strings", function()
    local back = Packed.Unpack(Packed.Pack({ [1] = "a\tb", [2] = "c\nd", [3] = 5, [4] = "ok" }))
    assert.are.same({ [4] = "ok" }, back)
  end)

  it("unpacks later into a table, keeping entries it got meanwhile, and Ready finishes it at once", function()
    local src = {}
    for i = 1, 5000 do
      src[i] = "v" .. i
    end
    local into, seen, done = { [3] = "newer" }, 0, false
    Packed.Later("names", Packed.Pack(src), into, function()
      seen = seen + 1
    end, function()
      done = true
    end)
    assert.is_true(Packed.Pending("names"))
    assert.is_nil(into[10])
    Packed.Ready("names")
    assert.is_false(Packed.Pending("names"))
    assert.is_true(done)
    assert.are.equal("newer", into[3]) -- learned since: not overwritten
    assert.are.equal("v10", into[10])
    assert.are.equal(4999, seen)
    Packed.Ready("names") -- nothing left: fine
  end)

  it("several texts under one name all unpack; nothing packed is done at once", function()
    local a, b = {}, {}
    Packed.Later("pricing", Packed.Pack({ [1] = "x" }), a)
    Packed.Later("pricing", Packed.Pack({ [2] = "y" }), b)
    local called = false
    Packed.Later("empty", nil, {}, nil, function()
      called = true
    end)
    assert.is_true(called)
    assert.is_false(Packed.Pending("empty"))
    Packed.ReadyAll()
    assert.are.same({ [1] = "x" }, a)
    assert.are.same({ [2] = "y" }, b)
  end)
end)
