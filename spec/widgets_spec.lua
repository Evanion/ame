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

  describe("inverted signal buttons", function()
    it("keep their word readable: near-black on every signal colour, in both palettes (WCAG AA, 4.5:1)", function()
      assert.are.equal(21, math.floor(W.Contrast("000000", "ffffff") + 0.5))
      for name, palette in pairs(W.PALETTES) do
        local roles = { good = palette.good, bad = palette.bad }
        for _, role in ipairs({ "hold", "wait", "vendor" }) do
          roles[role] = W.HEX[role]
        end
        for role, hex in pairs(roles) do
          local ratio = W.Contrast(hex, W.INVERTED_TEXT)
          assert.is_true(ratio >= 6, ("%s %s: %.2f:1"):format(name, role, ratio))
        end
      end
    end)
  end)

  describe("selected buttons", function()
    it("keep white labels readable on every faction theme's fill (the accent at half strength, WCAG AA)", function()
      for house, c in pairs(W.THEMES) do
        local fill = ""
        for i = 1, 3 do
          fill = fill .. ("%02x"):format(math.floor(c[i] * W.SELECTED_SHADE * 255 + 0.5))
        end
        local ratio = W.Contrast(fill, "ffffff")
        assert.is_true(ratio >= 4.5, ("%s: %.2f:1"):format(house, ratio))
      end
    end)
  end)

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

    it("colours each unit, number and letter, in its coin's colour", function()
      assert.are.equal("|cffffd10012g|r |cffc7c7cf34s|r", W.Money(123456))
      assert.are.equal("|cffeda55f7c|r", W.Money(7))
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

  it("abbreviates large quantities", function()
    assert.are.equal("950", W.Count(950))
    assert.are.equal("1k", W.Count(1000))
    assert.are.equal("4.5k", W.Count(4520))
    assert.are.equal("12k", W.Count(12400))
    assert.are.equal("1.2M", W.Count(1234567))
    assert.are.equal("-", plain(W.Count(nil)))
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
