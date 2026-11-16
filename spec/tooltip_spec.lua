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

  it("is compact by default: market with 7d change, the chosen average, a Shift hint", function()
    local rows = T.Lines(s, { avgDays = 14 })
    assert.are.equal(3, #rows)
    local t = text(rows)
    assert.truthy(t:find("market"))
    assert.truthy(t:find("7d"))
    assert.truthy(t:find("14%-day average"))
    assert.truthy(t:find("65g"))
    assert.truthy(t:find("Hold Shift"))
  end)

  it("leaves out the 7d change when it isn't known yet (no dangling '7d')", function()
    local young = { market = 100, avg7 = 100, signal = "none" }
    assert.is_nil(text(T.Lines(young, {})):find("7d"))
  end)

  it("shows the signal even when compact", function()
    local buy = setmetatable({ signal = "buy" }, { __index = s })
    assert.truthy(text(T.Lines(buy, {})):find("BUY"))
  end)

  it("adds supply, volatility, score, other auction houses and data age in detail", function()
    local goblin = { market = 800000 }
    local t = text(T.Lines(s, { detail = true, today = 102, others = { { "Neutral", goblin } } }))
    assert.truthy(t:find("lowest"))
    assert.truthy(t:find("13"))
    assert.truthy(t:find("/week"))
    assert.truthy(t:find("volatility"))
    assert.truthy(t:find("score"))
    assert.truthy(t:find("Goblin AH = 80g"))
    assert.truthy(t:find("2 days ago"))
    assert.is_nil(t:find("Hold Shift"))
  end)
end)
