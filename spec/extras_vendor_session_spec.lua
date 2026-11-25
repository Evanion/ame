-- The vendor panel (Core/UI/Vendor.lua) and the session tracker (Core/Session.lua, Core/UI/SessionTracker.lua):
-- what to sell here, what a click sells, what an outing gathered, and both frames' trees.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("frames outside the window", function()
  local env, ns

  before_each(function()
    env = wow.install()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Settings.lua",
      "Core/ItemCache.lua",
      "Core/UI/Tokens.lua",
      "Core/UI/Kit.lua",
      "Core/UI/Layout.lua",
      "Core/UI/Widgets.lua",
      "Core/UI/DataTable.lua",
      "Core/UI/Parts/Primitives.lua",
      "Core/UI/Parts/Chrome.lua",
      "Core/UI/Parts/Table.lua",
      "Core/UI/Parts/Composites.lua",
      "Core/Session.lua",
      "Core/UI/Vendor.lua",
      "Core/UI/SessionTracker.lua",
    })
    _G.AME_DB = { settings = {} }
  end)

  after_each(function()
    env:restore()
  end)

  describe("the vendor panel", function()
    local V
    before_each(function()
      V = ns.Vendor
    end)

    -- 1: a vendor pays more than the AH nets; 2: the AH pays more; 3: no AH price; 0-quality junk; 5: kept
    local function worth(key)
      if key == 1 then
        return 500, "vendor", true
      elseif key == 2 then
        return 900, "ah", true
      elseif key == 3 then
        return 100, "vendor", false
      end
      return 10, "vendor", false
    end
    local slots = {
      { key = 1, count = 8, quality = 1, sellPrice = 500, bag = 0, slot = 1 },
      { key = 1, count = 2, quality = 1, sellPrice = 500, bag = 0, slot = 2 },
      { key = 2, count = 1, quality = 2, sellPrice = 400, bag = 0, slot = 3 },
      { key = 3, count = 5, quality = 1, sellPrice = 100, bag = 0, slot = 4 },
      { key = 4, count = 3, quality = 0, sellPrice = 1800, bag = 1, slot = 1 },
      { key = 5, count = 1, quality = 0, sellPrice = 50, bag = 1, slot = 2 },
      { key = 6, count = 1, quality = 0, sellPrice = 0, bag = 1, slot = 3 },
    }

    it(
      "lists what a vendor pays more for, then junk; never what the auction house pays more for or has no price for",
      function()
        local rows = V.Rows(slots, worth, { keep = { [5] = true } })
        assert.equals(2, #rows)
        assert.same({ 1, "vendor", 10, 5000 }, { rows[1].key, rows[1].why, rows[1].count, rows[1].pays })
        assert.equals(2, #rows[1].slots)
        assert.same({ 4, "junk", 5400 }, { rows[2].key, rows[2].why, rows[2].pays })
      end
    )

    it("the button sells junk only with Junk too, and no more than the buyback holds", function()
      local rows = V.Rows(slots, worth)
      assert.equals(3, #V.Selling(rows, true)) -- the vendor row, the junk and the cheap junk
      assert.equals(1, #V.Selling(rows, false))
      local many = { { why = "vendor", slots = {} } }
      for i = 1, 20 do
        many[1].slots[i] = { bag = 0, slot = i }
      end
      assert.equals(12, #V.Plan(many))
    end)

    it("draws a valid tree; a right-click keeps an item", function()
      local rows = V.Rows(slots, worth)
      local tree = V.Tree(rows, 10400, 2, true)
      assert.same({}, ns.Layout.Validate(tree))
      local root = CreateFrame("Frame", nil, UIParent)
      root:SetSize(360, 440)
      local ctx = ns.Layout.Context({}, { sources = { vendor = V.TableRows(rows) } })
      local r = ns.Layout.Renderer(root, ctx)
      r:Render(tree)
      assert.is_not_nil(r:Frame("vendor.table"))
      assert.equals("Vendor", V.TableRows(rows)[1].why.text)
    end)
  end)

  describe("the session", function()
    local S
    before_each(function()
      S = ns.Session
    end)

    it("counts what you gathered and the gold you looted, not what you bought or used", function()
      local db = {}
      local s = S.New(db)
      s:Start(0, { [1] = 5 }, 1000)
      s:Observe({ [1] = 9, [2] = 2 }, 1500, 600, false) -- looted 4 + 2 and 500 copper
      s:Observe({ [1] = 9, [2] = 2, [3] = 20 }, 900, 700, true) -- at a vendor: bought 20 for 600
      s:Observe({ [1] = 3, [2] = 2, [3] = 20 }, 900, 800, false) -- used 6
      s:Observe({ [1] = 4, [2] = 2, [3] = 20 }, 950, 3600, false) -- one more, 50 copper
      local prices = { [1] = 100, [2] = 1000, [3] = 5 }
      local sum = s:Summary(function(k)
        return prices[k]
      end, 3600)
      assert.equals(5 * 100 + 2 * 1000, sum.items)
      assert.equals(550, sum.money)
      assert.equals(3050, sum.total)
      assert.equals(3050, sum.perHour)
      assert.same({ 2, 1 }, { sum.top[1].key, sum.top[2].key })
    end)

    it("a short break continues the session; a long one doesn't", function()
      local s = S.New({})
      assert.is_false(s:Active(0))
      s:Start(0, {}, 0)
      assert.is_true(s:Active(S.GAP))
      assert.is_false(s:Active(S.GAP + 1))
    end)

    it("an early rate counts at least ten minutes", function()
      local s = S.New({})
      s:Start(0, {}, 0)
      s:Observe({}, 1000, 60, false)
      assert.equals(6000, s:Summary(function() end, 60).perHour)
      assert.equals("1 h 12 min", S.Duration(4320))
      assert.equals("8 min", S.Duration(480))
    end)

    it("the tracker's tree is valid with finds and without", function()
      local T = ns.SessionTracker
      local sum =
        { elapsed = 4320, total = 382000, perHour = 318000, top = { { key = 13463, count = 40, value = 196000 } } }
      assert.same({}, ns.Layout.Validate(T.Tree(sum, { value = 1420000, free = 9 })))
      assert.same({}, ns.Layout.Validate(T.Tree({ elapsed = 0, total = 0, perHour = 0, top = {} }, {})))
      local root = CreateFrame("Frame", nil, UIParent)
      root:SetSize(280, 214)
      local r = ns.Layout.Renderer(root, ns.Layout.Context({}))
      r:Render(T.Tree(sum, { value = 1420000, free = 9 }))
      assert.is_not_nil(r:Frame("session.top1"))
    end)
  end)
end)
