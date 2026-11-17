-- The text formatters in Widgets.lua: they decide what every number in the UI looks like.
local addon = require("spec.helpers.addon")

describe("Widgets formatters", function()
  local W
  before_each(function()
    W = addon.load({ "Core/Init.lua", "Core/UI/Widgets.lua" }).Widgets
  end)

  -- strip WoW colour codes: "|cffffd100g|r" -> "g"
  local function plain(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end

  describe("Money", function()
    it("shows gold, silver and copper, leaving out zero units", function()
      assert.are.equal("12g 34s", plain(W.Money(123456)))
      assert.are.equal("12g", plain(W.Money(120000)))
      assert.are.equal("18s", plain(W.Money(1800)))
      assert.are.equal("18s 5c", plain(W.Money(1805)))
      assert.are.equal("7c", plain(W.Money(7)))
      assert.are.equal("0c", plain(W.Money(0)))
      assert.are.equal("-", plain(W.Money(nil)))
    end)

    it("rounds to whole copper", function()
      assert.are.equal("2c", plain(W.Money(1.6)))
    end)

    it("keeps silver below 100g in short mode, and rounds gold from there", function()
      assert.are.equal("2g 98s", plain(W.Money(29835, true)))
      assert.are.equal("171g", plain(W.Money(1706000, true))) -- 170g 60s rounds up
      assert.are.equal("1,235g", plain(W.Money(12345678))) -- 1000g+: gold only, with separators
    end)
  end)

  it("formats percentages with a sign, and dashes for nothing", function()
    assert.are.equal("+59.6%", plain(W.Percent(0.596)))
    assert.are.equal("-42.7%", plain(W.Percent(-0.427)))
    assert.are.equal("+0.0%", plain(W.Percent(0)))
    assert.are.equal("+60%", plain(W.Percent(0.6, 0)))
    assert.are.equal("-", plain(W.Percent(nil)))
  end)

  it("formats sell rates, with ~0 for items that don't move", function()
    assert.are.equal("~350/d", W.Rate(349.6))
    assert.are.equal("~4.5/d", W.Rate(4.5))
    assert.are.equal("~0/d", W.Rate(0.01))
    assert.are.equal("-", plain(W.Rate(nil)))
  end)

  it("formats expected selling times", function()
    assert.are.equal("<1h", W.Hours(0.4))
    assert.are.equal("~5h", W.Hours(5.2))
    assert.are.equal("~2 days", W.Hours(47))
    assert.are.equal("a week+", W.Hours(nil))
  end)

  it("says how long ago something happened", function()
    local now = 100000
    assert.are.equal("never", W.Ago(nil, now))
    assert.are.equal("just now", W.Ago(now - 30, now))
    assert.are.equal("5 min ago", W.Ago(now - 300, now))
    assert.are.equal("3 h ago", W.Ago(now - 3 * 3600, now))
    assert.are.equal("2 days ago", W.Ago(now - 2 * 86400, now))
    assert.are.equal("today", W.DaysAgo(10, 10))
    assert.are.equal("yesterday", W.DaysAgo(9, 10))
    assert.are.equal("4 days ago", W.DaysAgo(6, 10))
    assert.is_nil(W.DaysAgo(nil, 10))
  end)
end)
