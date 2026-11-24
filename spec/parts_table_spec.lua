-- Core/UI/Parts/Table.lua: the table widget - columns as data, rows from a data source (never in the layout), and
-- row clicks and row buttons as named actions.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("the table widget", function()
  local env, ns, Layout, r, ctx, got

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
      "Core/UI/Help.lua",
      "Core/UI/DataTable.lua",
      "Core/UI/Parts/Primitives.lua",
      "Core/UI/Parts/Table.lua",
    })
    _G.AME_DB = { settings = {} }
    Layout = ns.Layout
    got = {}
    ctx = Layout.Context({
      open = function(p)
        got[#got + 1] = { "open", p }
      end,
      queue = function(p)
        got[#got + 1] = { "queue", p }
      end,
    }, { sources = {} })
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(600, 300)
    r = Layout.Renderer(root, ctx)
  end)

  after_each(function()
    env:restore()
  end)

  local columns = {
    { key = "name", label = "Recipe", width = 160, item = true },
    { key = "profit", label = "Profit", width = 70, format = "signedMoney" },
    { key = "ready", label = "Ready", width = 120, align = "LEFT" },
    { key = "queue", label = "", width = 50, button = { label = "Queue", action = "queue" } },
  }

  local function draw(rows, extra)
    ctx.sources.recipes = rows
    local props = { source = "recipes", columns = columns, action = "open", selected = "b" }
    for k, v in pairs(extra or {}) do
      props[k] = v
    end
    local tree = { id = "t", type = "table", props = props }
    assert.same({}, Layout.Validate(tree))
    r:Render(tree)
    return r:Frame("t").dt
  end

  it("draws the rows its source gives, never from the layout", function()
    local dt = draw({
      { key = "a", item = 13444, profit = 3400, ready = { text = "ready ×3", color = "good" } },
      { key = "b", item = 13443, profit = -500, ready = "missing 1 Firebloom", queue = false },
    })
    assert.equals(2, #dt.source)
    local col = dt.opts.columns[3]
    assert.matches("ready ×3", col.text(dt.source[1]))
    assert.equals("missing 1 Firebloom", col.text(dt.source[2]))
    assert.is_true(dt.opts.selected(dt.source[2]))
    assert.is_false(dt.opts.columns[4].button.shown(dt.source[2]))
  end)

  it("reports a row click and a row button as actions with the row's key", function()
    local dt = draw({ { key = "a", item = 13444, profit = 1 } })
    dt.opts.onClick(dt.source[1], "LeftButton")
    dt.opts.columns[4].button.onClick(dt.source[1])
    assert.same({ "open", { key = "a", item = 13444, button = "LeftButton" } }, got[1])
    assert.same({ "queue", { key = "a", item = 13444 } }, got[2])
  end)

  it("keeps its table across draws with the same columns, and says when there's nothing", function()
    local dt = draw({ { key = "a" } })
    local again = draw({}, { empty = "Nothing ready" })
    assert.equals(dt, again)
    assert.equals("Nothing ready", again.message:GetText())
  end)
end)
