-- Core/UI/Parts/Composites.lua: widgets made of several parts, drawn from plain data.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("composite widgets", function()
  local env, ns, Layout, r, got

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
      "Core/UI/Parts/Primitives.lua",
      "Core/UI/Parts/Composites.lua",
    })
    _G.AME_DB = { settings = {} }
    Layout = ns.Layout
    got = {}
    local ctx = Layout.Context({
      open = function(p)
        got[#got + 1] = { "open", p }
      end,
    })
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(480, 300)
    r = Layout.Renderer(root, ctx)
  end)

  after_each(function()
    env:restore()
  end)

  describe("kpi", function()
    it("shows a label, an amount with its coloured change after it, and its note", function()
      local tree = {
        id = "k",
        type = "kpi",
        props = { label = "Net worth", copper = 48120000, delta = "+3.1%", deltaTone = "good", note = "this week" },
      }
      assert.same({}, Layout.Validate(tree))
      r:Render(tree)
      local f = r:Frame("k")
      assert.equals("Net worth", f.label:GetText())
      assert.matches("4", f.value:GetText())
      assert.matches("%+3%.1%%", f.delta:GetText()) -- after the value, as the board's KpiCard
      assert.equals("this week", f.note:GetText())
      assert.is_false(f.rise:IsShown())
    end)

    it("draws the breadth bar from rise and fall", function()
      local tree = {
        id = "b",
        type = "kpi",
        props = { label = "Breadth", value = "51%", rise = 2502, fall = 2397, note = "up · down" },
      }
      assert.same({}, Layout.Validate(tree))
      r:Render(tree)
      local f = r:Frame("b")
      assert.is_true(f.rise:IsShown())
      assert.is_true(f.fall:IsShown())
    end)
    it("shows a dash before there is a number", function()
      r:Render({ id = "k", type = "kpi", props = { label = "Market", note = "no prices yet" } })
      assert.matches("—", r:Frame("k").value:GetText())
    end)
  end)

  describe("sidebar", function()
    it("draws headings, entries with counts, a link and the picked one; a click names its key", function()
      local tree = {
        id = "s",
        type = "sidebar",
        props = {
          action = "open",
          entries = {
            { key = "all", label = "All items", count = "7,004" },
            { heading = true, label = "Watchlists" },
            { key = "alchemy", label = "★ Alchemy", count = 8, selected = true },
            { key = "new", label = "+ New list", link = true },
          },
        },
      }
      assert.same({}, Layout.Validate(tree))
      r:Render(tree)
      local f = r:Frame("s")
      assert.equals("7,004", f.rows[1].count:GetText())
      assert.is_nil(f.rows[2].key)
      f.rows[3].scripts.OnClick(f.rows[3])
      f.rows[2].scripts.OnClick(f.rows[2])
      assert.same({ { "open", { key = "alchemy" } } }, got)
    end)
  end)

  describe("actionlist", function()
    local rows = {
      {
        key = "alert",
        pill = "ALERT",
        tone = "warn",
        title = { { item = 13468 }, " dropped to 62", { gold = "g" } },
        sub = "Your alert was at 65g",
        button = "Open",
        action = "open",
        primary = true,
        selected = true,
      },
      { key = "bags", pill = "BAGS", title = "142g in your bags", button = "At the AH", action = "open", off = true },
      { key = "craft", pill = "CRAFT", title = "Refined Deeprock Salt", value = "+65g each", valueTone = "good" },
    }

    it("draws a row per entry: pill, title with links, a dim line, value and button", function()
      local tree = { id = "l", type = "actionlist", props = { title = "To do now", rows = rows } }
      assert.same({}, Layout.Validate(tree))
      r:Render(tree)
      local f = r:Frame("l")
      assert.equals("To do now", f.title:GetText())
      local a = f.rows[1]
      assert.equals("ALERT", a.pill.text:GetText())
      assert.matches("|Hitem:13468", a.title:GetText())
      assert.matches("dropped to 62", a.title:GetText())
      assert.equals("Your alert was at 65g", a.sub:GetText())
      assert.equals("primary", a.button.variant)
      assert.equals("disabled", f.rows[2].button.variant)
      assert.is_false(f.rows[3].button:IsShown())
      assert.matches("%+65g each", f.rows[3].value:GetText())
    end)

    it("a row's button dispatches its action with the row's key; a greyed one doesn't", function()
      r:Render({ id = "l", type = "actionlist", props = { rows = rows } })
      local f = r:Frame("l")
      f.rows[1].button.scripts.OnClick(f.rows[1].button)
      f.rows[2].button.scripts.OnClick(f.rows[2].button)
      assert.same({ { "open", { key = "alert" } } }, got)
    end)

    it("sizes itself to its rows, and hides rows a shorter list drops", function()
      r:Render({ id = "l", type = "actionlist", props = { title = "x", rows = rows } })
      r:Render({ id = "l", type = "actionlist", props = { title = "x", rows = { rows[1] } } })
      local f = r:Frame("l")
      assert.is_false(f.rows[2]:IsShown())
      assert.equals(32 + 46, select(2, Layout.widgets.actionlist.size(f, { rows = { rows[1] } })))
    end)
  end)
end)
