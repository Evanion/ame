-- Core/UI/Parts/Trade.lua: the price ladder (rows, buttons, lines; a click picks) and the buy card (what's on sale
-- now from a data source; Buy runs the game's purchase from the click: price, then Confirm or Cancel).
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("the trade widgets", function()
  local env, ns, Layout, r, ctx, got

  before_each(function()
    env = wow.install()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Settings.lua",
      "Core/ItemCache.lua",
      "Core/Analytics.lua",
      "Core/UI/Tokens.lua",
      "Core/UI/Kit.lua",
      "Core/UI/Layout.lua",
      "Core/UI/Widgets.lua",
      "Core/UI/Help.lua",
      "Core/UI/DataTable.lua",
      "Core/UI/Parts/Primitives.lua",
      "Core/ItemPage.lua",
      "Core/UI/Parts/Trade.lua",
    })
    _G.AME_DB = { settings = {} }
    Layout = ns.Layout
    got = {}
    ctx = Layout.Context({
      pick = function(p)
        got[#got + 1] = { "pick", p }
      end,
      bought = function(p)
        got[#got + 1] = { "bought", p }
      end,
      qty = function(p)
        got[#got + 1] = { "qty", p }
      end,
    }, { sources = {} })
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(300, 300)
    r = Layout.Renderer(root, ctx)
  end)

  after_each(function()
    env:restore()
  end)

  local function draw(type_, props)
    local tree = { id = "w", type = type_, props = props }
    assert.same({}, Layout.Validate(tree))
    r:Render(tree)
    return r:Frame("w")
  end

  local picks = {
    { label = "Quick", when = "<1 h", price = 920 },
    { label = "Normal", when = "sells in ~3 h", price = 931, selected = true },
    { label = "Patient", when = "~1 day", price = 980 },
    { label = "Market", when = "the market price", price = 957, apart = true },
  }

  describe("price ladder", function()
    it("rows: one per pick, the picked one lit, Market set apart", function()
      local f = draw("priceladder", { picks = picks, action = "pick" })
      assert.equals(4, #f.rows)
      assert.is_true(f.rows[2].selected)
      local ys = ns.TradePart.LadderOffsets(picks, "rows")
      assert.equals(26 + 8, ys[2])
      assert.equals(3 * (26 + 8) + 10, ys[4]) -- apart: 10 more
      f.rows[3]:GetScript("OnClick")(f.rows[3])
      assert.same({ "pick", { index = 3 } }, got[1])
    end)

    it("dense rows sit closer", function()
      local _, total = ns.TradePart.LadderOffsets(picks, "rows", true)
      local _, wide = ns.TradePart.LadderOffsets(picks, "rows", false)
      assert.is_true(total < wide)
    end)

    it("lines: a label with its time, the price at the right, the picked one bold", function()
      local f = draw("priceladder", { picks = picks, layout = "lines" })
      assert.equals("Normal · sells in ~3 h", f.rows[2].label:GetText())
      assert.equals(13, f.rows[2].label.kitSize)
      assert.equals(12, f.rows[1].label.kitSize)
      local _, h = Layout.Get("priceladder").size(f)
      assert.equals(4 * 18, h)
    end)

    it("buttons: one line of buttons", function()
      local f = draw("priceladder", { picks = picks, layout = "buttons" })
      assert.matches("^Quick ", f.rows[1].label:GetText())
      local _, h = Layout.Get("priceladder").size(f)
      assert.equals(24, h)
    end)
  end)

  describe("buy card", function()
    local AH

    before_each(function()
      AH = {
        results = {
          [2452] = { commodity = true, rows = { { price = 904, qty = 60 }, { price = 910, qty = 85 } }, at = 0 },
        },
        calls = {},
      }
      function AH:Buy(key, qty)
        self.calls[#self.calls + 1] = { "buy", key, qty }
        self.pending = { key = key, qty = qty, commodity = true }
        return true
      end
      function AH:Confirm()
        self.calls[#self.calls + 1] = { "confirm" }
        self.pending.sent = true
        return true
      end
      function AH:Cancel()
        self.calls[#self.calls + 1] = { "cancel" }
        self.pending = nil
      end
      ns.AHSearch = AH
    end)

    local function card(extra)
      local rows = ns.ItemPage.Listings(AH.results[2452], 100, 0)
      ctx.sources.listings = rows
      local props = {
        summary = "145 on sale · just now",
        listings = "listings",
        qty = "100",
        total = 90640,
        itemKey = 2452,
        action = "bought",
        qtyAction = "qty",
      }
      for k, v in pairs(extra or {}) do
        props[k] = v
      end
      return draw("buycard", props), rows
    end

    it("lists what's on sale, the rows the order takes from picked ('40 of 85')", function()
      local f, rows = card()
      assert.is_true(rows[1].selected)
      assert.equals("40 of 85", rows[2].qty)
      assert.equals(2, #f.listings.source)
      assert.is_true(f.listings.opts.selected(rows[2]))
      assert.equals("Buy", f.buy.label:GetText())
      assert.is_false(f.cancel:IsShown())
    end)

    it("Buy asks the game for the price from the click, then reads Confirm with Cancel; Confirm buys", function()
      local f = card()
      f.buy:GetScript("OnClick")(f.buy)
      assert.same({ "buy", 2452, 100 }, AH.calls[1])
      assert.equals(90640, AH.pending.expected)
      assert.same({ "bought", { itemKey = 2452, qty = 100, step = "price" } }, got[1])
      -- the game answers with the price
      AH.pending.total = 90640
      ns.TradePart.DrawState(f)
      assert.equals("Confirm", f.buy.label:GetText())
      assert.is_true(f.cancel:IsShown())
      f.buy:GetScript("OnClick")(f.buy)
      assert.same({ "confirm" }, AH.calls[2])
      assert.equals("confirm", got[2][2].step)
    end)

    it("a price well over the listings shown asks to confirm anyway", function()
      ns.AHShopping = {
        PriceJump = function(total, expected)
          return total / expected - 1 > 0.1 and total / expected - 1 or nil
        end,
      }
      local f = card()
      f.buy:GetScript("OnClick")(f.buy)
      AH.pending.total = 120000
      ns.TradePart.DrawState(f)
      assert.equals("Confirm anyway", f.buy.label:GetText())
    end)

    it("Cancel drops the priced purchase", function()
      local f = card()
      f.buy:GetScript("OnClick")(f.buy)
      f.cancel:GetScript("OnClick")(f.cancel)
      assert.same({ "cancel" }, AH.calls[2])
      assert.equals("cancel", got[2][2].step)
      assert.equals("Buy", f.buy.label:GetText())
    end)

    it("changing how many reports it", function()
      local f = card()
      f.box:SetText("40")
      f.box:GetScript("OnEnterPressed")(f.box)
      assert.same({ "qty", { text = "40" } }, got[1])
    end)

    it("the narrow window's bar: no table, Market and the signal beside the buttons", function()
      local f = card({ bar = true, market = 957, signal = "sell" })
      assert.is_false(f.tableHolder:IsShown())
      assert.is_true(f.marketText:IsShown())
      local _, h = Layout.Get("buycard").size(f, { bar = true })
      assert.equals(38, h)
    end)
  end)
end)
