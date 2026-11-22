local addon = require("spec.helpers.addon")

describe("Tooltip.Lines", function()
  local T, W
  before_each(function()
    local ns = addon.load({ "Core/Init.lua", "Core/UI/Widgets.lua", "Core/UI/Tooltip.lua" })
    T, W = ns.Tooltip, ns.Widgets
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
      local mids = {} -- the middle columns, the furthest left first
      local k = 3
      while r[k] ~= nil do
        table.insert(mids, 1, r[k] .. " | ")
        k = k + 1
      end
      out[#out + 1] = r[1] .. " = " .. table.concat(mids) .. (r[2] or "")
    end
    return (table.concat(out, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) -- without colour codes
  end

  local held = {
    total = 43,
    bags = 20,
    bank = 18,
    auctions = 0,
    guildBank = 5,
    chars = {
      { name = "Mainchar", bags = 12, bank = 10, auctions = 0, me = true },
      { name = "Bankalt", bags = 8, bank = 8 },
    },
    guilds = { { name = "Iron Ledger", qty = 5 } },
  }

  it("by default: a header with the auction house and freshness, the market price, context and a Shift hint", function()
    local rows = T.Lines(s, { avgDays = 14, house = "Horde AH", age = "2 hr ago" })
    local t = text(rows)
    assert.truthy(t:find("Horde AH = 2 hr ago", 1, true), t) -- the auction house heads the block, no addon name
    assert.truthy(t:find("Market = 55g 98s", 1, true), t)
    assert.truthy(t:find("-14%", 1, true), t) -- 55g 98s vs 65g
    assert.is_nil(t:find("each")) -- one column: no heads
    assert.truthy(t:find("vs 14-day avg", 1, true), t)
    assert.truthy(t:find("13 listed", 1, true), t)
    assert.truthy(t:find("Hold Shift for more", 1, true), t)
    assert.is_nil(t:find("AME", 1, true)) -- no addon name anywhere in the block
    assert.is_nil(t:find("Lowest"))
    assert.is_nil(t:find("You have"))
    assert.is_nil(t:find("Vendor")) -- nothing owned: the game's sell price says it
  end)

  it("with more than one owned: each and a total for all of yours, the vendor total, and where they are", function()
    local t = text(T.Lines(s, { held = held, vendor = 200, house = "Horde AH" }))
    assert.truthy(t:find("Horde AH = each | your 43", 1, true), t) -- no age: the columns' heads on the header
    t = text(T.Lines(s, { held = held, vendor = 200, house = "Horde AH", age = "now" }))
    assert.truthy(t:find("Horde AH = now", 1, true), t) -- the header on a line of its own
    assert.truthy(t:find("  = each | your 43", 1, true), t) -- then the columns' heads
    assert.truthy(t:find("Market = 55g 98s | 2,407g", 1, true), t) -- each in the middle, all of yours on the right
    assert.truthy(t:find("Vendor = · | 86s", 1, true), t)
    assert.truthy(t:find("You have 43  ·  bags 20 · bank 18 · guild bank 5", 1, true), t)
  end)

  it("leaves out the comparison on the first day (nothing to compare with)", function()
    local young = { market = 100, avg7 = 100, signal = "none", days = 1 }
    assert.is_nil(text(T.Lines(young, {})):find("avg"))
  end)

  it("shows the signal with the Shift hint beside it, and says when the goblin AH pays better", function()
    local buy = setmetatable({ signal = "buy", sellRate = 12 }, { __index = s })
    local t = text(T.Lines(buy, { better = 0.16 }))
    assert.truthy(t:find("BUY = Shift: more", 1, true), t)
    assert.truthy(t:find("~12 sold/day", 1, true), t)
    buy.sellRate = 2.5
    assert.truthy(text(T.Lines(buy, {})):find("~2.5 sold/day", 1, true))
    assert.truthy(t:find("Sells 16% better at the goblin AH, after its cut", 1, true), t)
    local rows = T.Lines(buy, { better = 0.16, house = "Horde AH" })
    assert.are.equal(W.Color("gold", "Horde AH"), rows[1][1]) -- the house in gold
    local notice
    for _, r in ipairs(rows) do
      notice = notice or (r[1]:find("goblin AH, after", 1, true) and r[1])
    end
    assert.are.equal(1, notice:find(W.WARN_ICON, 1, true)) -- the notice leads with the warning icon
  end)

  it("compact (little room): no freshness, holdings or context lines; the goblin AH joins the signal line", function()
    local buy = setmetatable({ signal = "buy" }, { __index = s })
    local rows = T.Lines(buy, { compact = true, held = held, house = "Horde AH", age = "now", better = 0.16 })
    local t = text(rows)
    assert.is_nil(t:find("now", 1, true)) -- no freshness
    assert.is_nil(t:find("You have"))
    assert.is_nil(t:find("listed"))
    assert.truthy(t:find("BUY  ·  goblin AH +16% = Shift: more", 1, true), t)
    assert.are.equal(3, #rows) -- header (with the columns' heads), market, signal
    assert.truthy(t:find("Horde AH = each | your 43", 1, true), t)
  end)

  it("goes compact on a small screen or a UI scaled far up, not at the default scale", function()
    local saved = { _G.UIParent, _G.GetPhysicalScreenSize }
    finally(function()
      _G.UIParent, _G.GetPhysicalScreenSize = saved[1], saved[2]
    end)
    local h, ph = 768, 1080
    _G.UIParent = {
      GetHeight = function()
        return h
      end,
    }
    _G.GetPhysicalScreenSize = function()
      return 1920, ph
    end
    assert.is_false(T.Compact()) -- 1080p, default scale: the UI is 768 units tall
    ph = 768
    assert.is_true(T.Compact()) -- a 768-pixel laptop screen
    ph, h = 1440, 668
    assert.is_true(T.Compact()) -- UI scale 1.15
  end)

  it("gear: the disenchant value, and with Shift what it disenchants into by chance", function()
    local de = {
      value = 9900,
      outcomes = {
        { name = "Strange Dust", chance = 0.75, min = 4, max = 6, price = 1400 },
        { name = "Lesser Astral Essence", chance = 0.2, min = 1, max = 2, price = 12000 },
        { name = "Small Glimmering Shard", chance = 0.05, min = 1, max = 1 },
      },
    }
    local t = text(T.Lines(s, { de = de }))
    assert.truthy(t:find("Disenchant ~ = 99s", 1, true), t)
    t = text(T.Lines(s, { de = de, held = held }))
    assert.truthy(t:find("Disenchant ~ = 99s | 42g 57s", 1, true), t)
    assert.is_nil(t:find("Strange Dust"))
    t = text(T.Lines(s, { de = de, detail = true }))
    assert.truthy(t:find("75%  4-6 Strange Dust = × 14s | 70s", 1, true), t) -- each at market, then that many
    assert.truthy(t:find("20%  1-2 Lesser Astral Essence = × 1g 20s | 1g 80s", 1, true), t)
    assert.truthy(t:find("5%  1 Small Glimmering Shard = -", 1, true), t) -- no price for it
    assert.truthy(t:find("Expected, weighted by chance = 99s", 1, true), t)
  end)

  it(
    "with Shift: yours per character and guild bank, your cost, every auction house after its cut, the details",
    function()
      local t = text(T.Lines(s, {
        detail = true,
        today = 102,
        held = held,
        basis = { units = 10, unit = 500000 },
        houses = {
          { label = "Horde AH", market = 559800, net = 531810, cut = 0.05, mine = true },
          { label = "Goblin AH", market = 700000, net = 595000, cut = 0.15 },
        },
      }))
      assert.truthy(t:find("YOURS  ·  43 on 2 characters = bags | bank | AH", 1, true), t) -- a grid
      assert.truthy(t:find("Mainchar (you) = 12 | 10 | ·", 1, true), t)
      assert.truthy(t:find("Bankalt = 8 | 8 | ·", 1, true), t)
      assert.truthy(t:find("<Iron Ledger> guild bank = 5", 1, true), t)
      assert.truthy(t:find("Average cost = 50g", 1, true), t)
      assert.truthy(t:find("Unrealized = +59g 80s", 1, true), t) -- (55g 98s - 50g) x 10
      assert.truthy(t:find("= market | you get", 1, true), t)
      assert.truthy(t:find("Goblin AH (15%) +12% = 70g | 59g 50s", 1, true), t)
      assert.is_nil(t:find("Horde AH (5%) +", 1, true)) -- yours: no margin against itself
      assert.truthy(t:find("Lowest listing = 55g", 1, true), t)
      assert.truthy(t:find("/week"))
      assert.truthy(t:find("Volatility"))
      assert.truthy(t:find("2 days ago"))
      assert.is_nil(t:find("Hold Shift"))
    end
  )
end)

describe("Tooltip sections", function()
  local wow = require("spec.helpers.wow")
  local env, ns, T, W
  before_each(function()
    env = wow.install()
    ns = addon.load({ "Core/Init.lua", "Core/ItemCache.lua", "Core/UI/Widgets.lua", "Core/UI/Tooltip.lua" })
    T, W = ns.Tooltip, ns.Widgets
  end)
  after_each(function()
    env:restore()
  end)

  local function plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end

  it("a section's heading carries its column heads, and its rows fill the columns left to right", function()
    local rows = T.SectionRows({
      heading = "Yours",
      note = "43 on 3 characters",
      columns = { "bags", "bank" },
      rows = {
        { label = "Mainchar", cells = { 12, false } },
        { label = "Bankalt", note = "(alt)", cells = { "8", "8" } },
      },
    })
    assert.are.equal("YOURS  ·  43 on 3 characters", plain(rows[1][1]))
    assert.are.equal("bank", plain(rows[1][2])) -- the right column's head
    assert.are.equal("bags", plain(rows[1][3])) -- the middle column's head
    assert.are.equal(W.Money(12), rows[2][3]) -- a number is copper
    assert.are.equal("·", plain(rows[2][2])) -- an empty cell
    assert.are.equal("Bankalt (alt)", plain(rows[3][1]))
  end)

  it("draws an item bit as its name in its quality colour, with a dim count", function()
    local left = T.Bits({ { item = 3, count = 4 }, { text = "x", dim = true } })
    assert.truthy(left:find(ITEM_QUALITY_COLORS[1].hex .. "Item 3", 1, true), left)
    assert.truthy(left:find(W.Dim("4"), 1, true), left)
    assert.is_nil(left:find("|H", 1, true)) -- tooltips can't be clicked: a name, not a link
  end)

  it("draws money, warn, confidence and signal bits", function()
    assert.are.equal(W.SignedMoney(-500, { full = true }), T.Bits({ copper = -500, signed = true }))
    assert.are.equal(
      W.WARN_ICON .. " " .. W.Color("warn", "old"),
      T.Bits({ { icon = "warn" }, { text = "old", color = "warn" } })
    )
    assert.are.equal(W.Confidence("high"), T.Bits({ bars = "high" }))
    assert.are.equal(W.SignalText("buy"), T.Bits({ signal = "buy" }))
  end)

  it("Tooltip.Lines puts sections after the signal; detail ones only with Shift", function()
    local s = { market = 100, signal = "buy", qty = 1 }
    local sections = {
      { heading = "Recipe", rows = { { label = "Makes", cells = { 500 } } } },
      { heading = "Made by", detail = true, lines = { "Tyken" } },
    }
    local rows = T.Lines(s, { house = "Horde AH", sections = sections })
    local texts = {}
    for i, r in ipairs(rows) do
      texts[i] = plain(r[1])
    end
    local signalAt, recipeAt
    for i, t in ipairs(texts) do
      signalAt = signalAt or (t:find("BUY", 1, true) and i)
      recipeAt = recipeAt or (t == "RECIPE" and i)
    end
    assert.truthy(signalAt and recipeAt and recipeAt > signalAt, table.concat(texts, " / "))
    assert.is_nil(table.concat(texts, " / "):find("MADE BY", 1, true))
    rows = T.Lines(s, { house = "Horde AH", sections = sections, detail = true })
    local all = {}
    for i, r in ipairs(rows) do
      all[i] = plain(r[1])
    end
    assert.truthy(table.concat(all, " / "):find("MADE BY", 1, true))
  end)
end)

describe("Tooltip.AddRows", function()
  local T
  before_each(function()
    T = addon.load({ "Core/Init.lua", "Core/UI/Widgets.lua", "Core/UI/Tooltip.lua" }).Tooltip
  end)

  -- a game tooltip: numbered left and right texts, font strings of their own, a minimum width
  local function fakeTip()
    local function fs(text)
      local f = { text = text, shown = true }
      function f.SetText(self, t)
        self.text = t
      end
      function f.GetStringWidth(self)
        return #(self.text or "") * 6
      end
      function f.GetFontObject()
        return "font"
      end
      function f.SetFontObject() end
      function f.Show(self)
        self.shown = true
      end
      function f.Hide(self)
        self.shown = false
      end
      function f.ClearAllPoints() end
      function f.SetPoint(self, ...)
        self.point = { ... }
      end
      return f
    end
    local tip = { n = 0, made = {}, hooks = {} }
    function tip.GetName()
      return "FakeTip"
    end
    function tip.NumLines(self)
      return self.n
    end
    function tip.AddDoubleLine(self, l, r)
      self.n = self.n + 1
      _G["FakeTipTextLeft" .. self.n], _G["FakeTipTextRight" .. self.n] = fs(l), fs(r)
    end
    function tip.AddLine(self, l)
      self:AddDoubleLine(l, "")
    end
    function tip.CreateFontString(self)
      local f = fs()
      self.made[#self.made + 1] = f
      return f
    end
    function tip.SetMinimumWidth(self, w)
      self.minWidth = w
    end
    function tip.HookScript(self, event, fn)
      self.hooks[event] = fn
    end
    return tip
  end

  it("puts each in a middle column lined up left of the totals, and widens the tooltip for it", function()
    local tip = fakeTip()
    T.AddRows(
      tip,
      { { "AME", "Horde AH" }, { " ", "your 43", "each" }, { "Market", "2,407g", "55g 98s" }, { "plain" } }
    )
    assert.are.equal(4, tip.n)
    assert.are.equal(2, #tip.made)
    assert.are.equal("each", tip.made[1].text)
    assert.are.equal("55g 98s", tip.made[2].text)
    -- both right-aligned the widest total ("your 43", 42) plus the gap left of the right texts
    assert.are.equal(-(42 + T.GAP), tip.made[2].point[4])
    assert.are.equal(_G.FakeTipTextRight3, tip.made[2].point[2])
    assert.truthy(tip.minWidth > 6 * (#"Market" + #"55g 98s" + #"your 43"))
    tip.hooks.OnTooltipCleared(tip)
    assert.is_false(tip.made[1].shown)
    assert.are.equal(0, tip.minWidth)
  end)

  it("lines up a grid's further columns left of the middle one (bags / bank / AH)", function()
    local tip = fakeTip()
    T.AddRows(tip, { { "Mainchar", "5", "10", "12" }, { "Bankalt", "3", "8", "8" } })
    assert.are.equal(4, #tip.made)
    local bank, bags = tip.made[1], tip.made[2]
    assert.are.equal("10", bank.text)
    assert.are.equal("12", bags.text)
    assert.are.equal(-(6 + T.GAP), bank.point[4]) -- right of it: the widest right text ("5", 6)
    assert.are.equal(-(6 + T.GAP + 12 + T.GAP), bags.point[4]) -- then the middle column ("10", 12)
  end)

  it("puts each beside the total when the game keeps the text widths secret (12.x)", function()
    local tip = fakeTip()
    _G.issecretvalue = function()
      return true
    end
    finally(function()
      _G.issecretvalue = nil
    end)
    T.AddRows(tip, { { "Market", "2,407g", "55g 98s" } })
    assert.is_false(tip.made[1].shown)
    assert.are.equal("55g 98s   2,407g", _G.FakeTipTextRight1.text)
    assert.is_nil(tip.minWidth)
  end)

  it("draws a { section = ... } row as its heading and rows", function()
    local tip = fakeTip()
    T.AddRows(
      tip,
      { { "Last full scan", "Nov 20" }, { section = { heading = "Top buy signals", lines = { "Item" } } } }
    )
    assert.are.equal(3, tip.n)
    assert.truthy(_G.FakeTipTextLeft2.text:find("TOP BUY SIGNALS", 1, true))
    assert.are.equal("Item", _G.FakeTipTextLeft3.text)
  end)
end)
