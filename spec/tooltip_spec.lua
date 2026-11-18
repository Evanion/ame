local addon = require("spec.helpers.addon")

describe("Tooltip.Lines", function()
  local T
  before_each(function()
    T = addon.load({ "Core/Init.lua", "Core/UI/Widgets.lua", "Core/UI/Tooltip.lua" }).Tooltip
  end)

  local s = {
    market = 559800,
    min = 550000,
    change7 = 0.032,
    avg3 = 560000,
    avg7 = 600000,
    avg14 = 650000,
    avg30 = 693700,
    qty = 13,
    supplyTrend30 = -0.03,
    vol30 = 0.24,
    score = 12,
    signal = "none",
    day = 100,
  }

  local function text(rows)
    local out = {}
    for _, r in ipairs(rows) do
      out[#out + 1] = r[1] .. " = " .. (r[2] or "")
    end
    return (table.concat(out, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) -- without colour codes
  end

  it("is three lines by default: market vs the chosen average, supply and sells/day, a Shift hint", function()
    local rows = T.Lines(s, { avgDays = 14 })
    assert.are.equal(3, #rows)
    local t = text(rows)
    assert.truthy(t:find("market"))
    assert.truthy(t:find("vs 14d avg"))
    assert.truthy(t:find("-13.9%", 1, true)) -- 55g 98s vs 65g
    assert.truthy(t:find("supply = 13 listed"))
    assert.truthy(t:find("Hold Shift"))
    assert.is_nil(t:find("lowest"))
  end)

  it("leaves out the comparison on the first day (nothing to compare with)", function()
    local young = { market = 100, avg7 = 100, signal = "none", days = 1 }
    assert.is_nil(text(T.Lines(young, {})):find("avg"))
  end)

  it("shows the signal as the third line, with the Shift hint beside it", function()
    local buy = setmetatable({ signal = "buy", sellRate = 12 }, { __index = s })
    local rows = T.Lines(buy, {})
    assert.are.equal(3, #rows)
    local t = text(rows)
    assert.truthy(t:find("BUY"))
    assert.truthy(t:find("Shift: more"))
    assert.truthy(t:find("~12/d"))
  end)

  it("adds supply, volatility, score and data age in detail - never other auction houses", function()
    local t = text(T.Lines(s, { detail = true, today = 102 }))
    assert.truthy(t:find("lowest"))
    assert.truthy(t:find("13"))
    assert.truthy(t:find("/week"))
    assert.truthy(t:find("volatility"))
    assert.truthy(t:find("score"))
    assert.is_nil(t:find("AH"))
    assert.truthy(t:find("2 days ago"))
    assert.is_nil(t:find("Hold Shift"))
  end)
end)
