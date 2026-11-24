-- Core/UI/Layout.lua: layouts as data, the validator, the renderer (frames kept by id, pooled by type) and the four
-- layout widgets (row, column, grid, fill), on the stubbed client's frames.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("layout", function()
  local env, ns, Layout

  before_each(function()
    env = wow.install()
    ns = addon.load({ "Core/Init.lua", "Core/UI/Layout.lua" })
    Layout = ns.Layout
    for k in pairs(Layout.warned) do
      Layout.warned[k] = nil
    end
    Layout.Register("label", {
      props = { text = "string", tone = "string?" },
      create = function(parent)
        return CreateFrame("Frame", nil, parent)
      end,
      update = function(f, props)
        f.text = props.text
        f.updates = (rawget(f, "updates") or 0) + 1
      end,
      size = function(_, props)
        return #props.text * 10, 20
      end,
    })
    Layout.Register("clicker", {
      props = { action = "string", payload = "any?" },
      create = function(parent, ctx)
        local f = CreateFrame("Button", nil, parent)
        f:SetScript("OnClick", function()
          ctx:Dispatch(f.action, f.payload)
        end)
        return f
      end,
      update = function(f, props)
        f.action, f.payload = props.action, props.payload
      end,
    })
  end)

  after_each(function()
    env:restore()
  end)

  local function root(w, h)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(w, h)
    return f
  end

  local function pos(frame)
    local p = frame.points[#frame.points]
    return p[4], -p[5]
  end

  describe("Validate", function()
    it("accepts a well-formed tree", function()
      local tree = {
        id = "top",
        type = "row",
        props = { gap = 4 },
        children = {
          { id = "a", type = "label", props = { text = "Hi" }, meta = { w = 50 } },
          { id = "b", type = "label", props = { text = "There", tone = "dim" }, meta = { grow = 1 } },
        },
      }
      assert.same({}, Layout.Validate(tree))
    end)

    it("lists every problem and never errors", function()
      local tree = {
        id = "top",
        type = "column",
        children = {
          { id = "a", type = "label", props = {} },
          { id = "a", type = "label", props = { text = 3 } },
          { type = "nope" },
          { id = "c", type = "label", props = { text = "x", bogus = true }, meta = { wide = 1 } },
          { id = "d", type = "label", props = { text = "x" }, children = {} },
          { id = "e", type = "clicker", props = { action = function() end } },
        },
      }
      local text = table.concat(Layout.Validate(tree), "\n")
      assert.matches("missing prop text", text)
      assert.matches("duplicate id a", text)
      assert.matches("prop text is number, not string", text)
      assert.matches("no id", text)
      assert.matches("unknown type nope", text)
      assert.matches("unknown prop bogus", text)
      assert.matches("unknown meta wide", text)
      assert.matches("children on label", text)
      assert.matches("is a function", text)
      assert.same({ ": not an item" }, Layout.Validate(42))
    end)
  end)

  describe("Split", function()
    it("gives fixed sizes first and shares the rest by weight", function()
      local s = Layout.Split(200, { { size = 50 }, { grow = 1 }, { grow = 3 } }, 10)
      assert.same({ { 0, 50 }, { 60, 33 }, { 103, 98 } }, s)
    end)
    it("never shares less than nothing", function()
      local s = Layout.Split(40, { { size = 50 }, { grow = 1, min = 5 } }, 0)
      assert.same({ 0, 50 }, s[1])
      assert.same({ 50, 5 }, s[2])
    end)
  end)

  describe("Renderer", function()
    it("makes a frame per id, places a row by meta and natural size", function()
      local r = Layout.Renderer(root(300, 40))
      r:Render({
        id = "top",
        type = "row",
        props = { gap = 10, pad = 5 },
        children = {
          { id = "a", type = "label", props = { text = "abc" } }, -- natural: 30 wide
          { id = "b", type = "label", props = { text = "x" }, meta = { grow = 1 } },
          { id = "c", type = "label", props = { text = "y" }, meta = { w = 60, h = 20 } },
        },
      })
      local a, b, c = r:Frame("a"), r:Frame("b"), r:Frame("c")
      assert.same({ 5, 5 }, { pos(a) })
      assert.same({ 30, 30 }, { a:GetWidth(), a:GetHeight() })
      assert.same({ 45, 5 }, { pos(b) })
      assert.equals(300 - 10 - 30 - 60 - 20, b:GetWidth())
      assert.same({ 300 - 5 - 60, 5 }, { pos(c) })
      assert.equals(20, c:GetHeight())
      assert.equals("x", b.text)
    end)

    it("stacks a column and nests containers, sizes handed down", function()
      local r = Layout.Renderer(root(200, 300))
      r:Render({
        id = "top",
        type = "column",
        props = { gap = 4 },
        children = {
          { id = "head", type = "label", props = { text = "h" }, meta = { h = 40 } },
          {
            id = "body",
            type = "row",
            meta = { grow = 1 },
            children = {
              { id = "l", type = "label", props = { text = "l" }, meta = { w = 50 } },
              { id = "m", type = "label", props = { text = "m" }, meta = { grow = 1 } },
            },
          },
        },
      })
      assert.same({ 200, 40 }, { r:Frame("head"):GetWidth(), r:Frame("head"):GetHeight() })
      assert.same({ 0, 44 }, { pos(r:Frame("body")) })
      assert.equals(256, r:Frame("body"):GetHeight())
      assert.same({ 150, 256 }, { r:Frame("m"):GetWidth(), r:Frame("m"):GetHeight() })
    end)

    it("flows a grid and lets an item span columns", function()
      local r = Layout.Renderer(root(310, 200))
      r:Render({
        id = "g",
        type = "grid",
        props = { cols = 3, gap = 5, rowH = 30 },
        children = {
          { id = "a", type = "label", props = { text = "a" } },
          { id = "b", type = "label", props = { text = "b" }, meta = { span = 2 } },
          { id = "c", type = "label", props = { text = "c" } },
        },
      })
      assert.same({ 0, 0 }, { pos(r:Frame("a")) })
      assert.equals(100, r:Frame("a"):GetWidth())
      assert.same({ 105, 0 }, { pos(r:Frame("b")) })
      assert.equals(205, r:Frame("b"):GetWidth())
      assert.same({ 0, 35 }, { pos(r:Frame("c")) })
    end)

    it("keeps frames across renders, hides dropped ids and reuses them by type", function()
      local r = Layout.Renderer(root(100, 100))
      local function tree(ids)
        local kids = {}
        for i, id in ipairs(ids) do
          kids[i] = { id = id, type = "label", props = { text = id }, meta = { h = 10 } }
        end
        return { id = "top", type = "column", children = kids }
      end
      r:Render(tree({ "a", "b" }))
      local a, b = r:Frame("a"), r:Frame("b")
      r:Render(tree({ "a" }))
      assert.equals(a, r:Frame("a"))
      assert.is_nil(r:Frame("b"))
      assert.is_false(b:IsShown())
      r:Render(tree({ "a", "c" }))
      assert.equals(b, r:Frame("c")) -- b's frame, pooled, now draws c
      assert.is_true(b:IsShown())
      assert.equals("c", b.text)
    end)

    it("skips an unknown type with one warning and draws the rest", function()
      local r = Layout.Renderer(root(100, 100))
      r:Render({
        id = "top",
        type = "column",
        children = { { id = "x", type = "mystery" }, { id = "a", type = "label", props = { text = "a" } } },
      })
      assert.is_nil(r:Frame("x"))
      assert.is_not_nil(r:Frame("a"))
      assert.matches("unknown widget type mystery", Layout.lastWarning)
    end)

    it("updates one item's props in place", function()
      local r = Layout.Renderer(root(100, 100))
      r:Render({ id = "a", type = "label", props = { text = "one" } })
      local f = r:Frame("a")
      local n = f.updates
      assert.is_true(r:Set("a", { text = "two" }))
      assert.equals("two", f.text)
      assert.equals(n + 1, f.updates)
      assert.is_false(r:Set("nope", {}))
    end)

    it("places again when the root changes size", function()
      local top = root(100, 50)
      local r = Layout.Renderer(top)
      r:Render({ id = "a", type = "label", props = { text = "a" } })
      top:SetSize(240, 50)
      top.scripts.OnSizeChanged(top)
      assert.equals(240, r:Frame("a"):GetWidth())
    end)
  end)

  describe("actions", function()
    it("a widget dispatches a named action and the view's handler gets the payload", function()
      local got
      local ctx = Layout.Context({
        queue = function(payload)
          got = payload
        end,
      })
      local r = Layout.Renderer(root(100, 100), ctx)
      r:Render({ id = "b", type = "clicker", props = { action = "queue", payload = { recipe = 7 } } })
      r:Frame("b").scripts.OnClick()
      assert.same({ recipe = 7 }, got)
      assert.is_false(ctx:Dispatch("nothing"))
      assert.matches("no handler for action nothing", Layout.lastWarning)
    end)
  end)
end)
