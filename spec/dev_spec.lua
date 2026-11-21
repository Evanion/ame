local addon = require("spec.helpers.addon")

describe("Dev profiler helpers", function()
  local Dev
  before_each(function()
    Dev = addon.load({ "Core/Init.lua", "Core/Dev/Profiler.lua" }).Dev
  end)

  it("adds up timed runs per name and ranks them by total time", function()
    local stats = {}
    Dev.Record(stats, "store-full", 5)
    Dev.Record(stats, "store-full", 7)
    Dev.Record(stats, "index", 30)
    Dev.Record(stats, "chart", 1)
    assert.are.same({ ms = 12, n = 2, max = 7 }, stats["store-full"])
    local top = Dev.Top(stats, 2)
    assert.are.same({ "index", "store-full" }, { top[1].name, top[2].name })
  end)

  it("estimates sizes, counting shared tables and strings once", function()
    local shared = { 1, 2, 3 }
    local s = Dev.Size({ a = shared, b = shared, name = "Linen Cloth", n = 5 })
    assert.are.equal(2, s.tables)
    assert.is_true(s.mem > 0 and s.text > 0)
    local big = {}
    for i = 1, 3000 do
      big[i] = { i }
    end
    local steps = 0
    local b = Dev.Size(big, nil, function()
      steps = steps + 1
    end)
    assert.are.equal(3001, b.tables)
    assert.are.equal(3, steps)
    assert.is_true(b.mem > s.mem)
  end)

  it("serializes a report and reads it back without loading any code", function()
    local R = addon.load({ "Core/Init.lua", "Core/Dev/Profiler.lua", "Core/Dev/Report.lua" }).Dev.Report
    local v = { a = 1.5, b = "x|y:z;", list = { 1, 2, { deep = true } }, [7] = false, neg = -3 }
    assert.are.same(v, R.Deserialize(R.Serialize(v)))
    assert.is_nil(R.Deserialize("t" .. string.rep("t", 30)))
    assert.is_nil(R.Deserialize("s99:short"))
  end)
end)
