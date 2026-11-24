-- Core/UI/Parts/Chart.lua: the chart widget - an item's history (line and candles, the legend, its layers), the
-- price index and the small spark line, each fed by a data source and drawn with LibAMEChart-1.0.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("the chart widget", function()
  local env, ns, Layout, r, ctx, got

  local DAY = 86400
  local now = 100 * DAY

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
      "Core/UI/Parts/Chart.lua",
    })
    _G.AME_DB = { settings = {} }
    Layout = ns.Layout
    got = {}
    ctx = Layout.Context({
      layer = function(p)
        got[#got + 1] = p
      end,
    }, { sources = {} })
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(700, 400)
    r = Layout.Renderer(root, ctx)
  end)

  after_each(function()
    env:restore()
  end)

  -- ten days of daily points, with the 7-day average at each
  local function points(n)
    local out = {}
    for i = 1, n do
      out[i] = { x = (90 + i) * DAY + DAY / 2, market = 900 + i * 10, min = 880 + i * 10, qty = 100 + i, avg = 900 + i * 5 }
    end
    return out
  end

  local function draw(props, data)
    ctx.sources.c = data
    local p = { source = "c" }
    for k, v in pairs(props) do
      p[k] = v
    end
    local tree = { id = "ch", type = "chart", props = p }
    assert.same({}, Layout.Validate(tree))
    r:Render(tree)
    return r:Frame("ch")
  end

  it("draws an item's history as lines: market, lowest, the 7-day average, supply; and says so in the legend", function()
    local f = draw({ kind = "item", range = "30D" }, { points = points(10), now = now })
    local c = f.charts.item
    assert.is_not_nil(c.series.market)
    assert.is_not_nil(c.series.min)
    assert.is_not_nil(c.series.sma)
    assert.is_not_nil(c.series.qty)
    assert.is_nil(c.series.candles)
    local labels = {}
    for _, e in ipairs(f.legend) do
      labels[#labels + 1] = e[2] or e.note
    end
    assert.equals("Market", labels[1])
    assert.equals("Lowest", labels[2])
    assert.is_true(f.legendBox:IsShown())
  end)

  it("candles in place of the lines when the style says so", function()
    local f = draw({ kind = "item", style = "candles" }, { points = points(10), now = now })
    local c = f.charts.item
    assert.is_not_nil(c.series.candles)
    assert.is_nil(c.series.market)
    assert.equals("Up", f.legend[1][2])
  end)

  it("leaves out the layers switched off, and a legend row click reports its layer", function()
    local f = draw({ kind = "item", hidden = { min = true }, action = "layer" }, { points = points(10), now = now })
    assert.is_nil(f.charts.item.series.min)
    f.legendBox.rows[2]:GetScript("OnClick")(f.legendBox.rows[2])
    assert.same({ key = "min" }, got[1])
  end)

  it("your trades are dots, a vendor price near the prices a dashed line", function()
    local f = draw({ kind = "item" }, {
      points = points(10),
      now = now,
      vendor = 800,
      trades = { { x = 95 * DAY, y = 950, kind = "buy" }, { x = 97 * DAY, y = 990, kind = "sale" } },
    })
    local c = f.charts.item
    assert.equals(2, #c.series.trades.xs)
    assert.is_not_nil(c.series.vendor)
  end)

  it("no points: the source's message", function()
    local f = draw({ kind = "item" }, { points = {}, message = "Loading history..." })
    assert.equals("Loading history...", f.charts.item.message:GetText())
    assert.is_false(f.legendBox:IsShown())
  end)

  it("folds the legend into a button in the narrow window", function()
    local f = draw({ kind = "item", compact = true }, { points = points(10), now = now })
    assert.is_true(f.legendToggle:IsShown())
    assert.is_false(f.legendBox:IsShown())
    f.legendToggle:GetScript("OnClick")(f.legendToggle)
    assert.is_true(f.legendBox:IsShown())
  end)

  it("the slot size follows the span: a day for daily history, finer for scans", function()
    assert.equals(DAY, ns.ChartPart.SlotSize({ points = points(10) }))
    local scans = {}
    for i = 1, 40 do
      scans[i] = { x = now - 2 * DAY + i * 3600, market = 100 }
    end
    assert.is_true(ns.ChartPart.SlotSize({ points = scans, intraday = true }) < DAY)
  end)

  it("draws the price index as an area with its base level", function()
    local xs, ys = {}, {}
    for i = 1, 30 do
      xs[i], ys[i] = (70 + i) * DAY, 100 + i * 0.1
    end
    local f = draw({ kind = "index", format = "level" }, { xs = xs, ys = ys, base = 100, label = "Price index" })
    local c = f.charts.index
    assert.equals("area", c.series.y.kind)
    assert.is_not_nil(c.series.base)
    assert.equals("104.2", f.format(104.2))
    assert.is_false(f.legendBox:IsShown())
  end)

  it("a spark line with its dashed average", function()
    local f = draw({ kind = "spark" }, { xs = { 1, 2, 3 }, ys = { 5, 6, 7 }, avg = { 5, 5.5, 6 } })
    assert.is_not_nil(f.charts.spark.series.y)
    assert.is_not_nil(f.charts.spark.series.avg)
  end)

  it("too few days for the index: says so", function()
    local f = draw({ kind = "index" }, { xs = { 1 }, ys = { 100 } })
    assert.matches("Not enough days", f.charts.index.message:GetText())
  end)
end)
