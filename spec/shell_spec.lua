-- Shell.lua's layout widgets (cards, side lists, settings cards) on the stubbed client's frames
-- (spec/helpers/wow.lua): what they draw, how much room they take and what a click does.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("shell widgets", function()
  local env, ns, W, UI

  before_each(function()
    env = wow.install()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Settings.lua",
      "Core/ItemCache.lua",
      "Core/UI/Widgets.lua",
      "Core/UI/Help.lua",
      "Core/UI/DataTable.lua",
    })
    W = ns.Widgets
    W.SetTheme("Horde")
    _G.AME_DB = { settings = {} }
    ns.UI = {}
    UI = ns.UI
    addon.load({ "Core/UI/Shell.lua" }, ns)
  end)

  after_each(function()
    env:restore()
  end)

  local function same(a, b)
    for i = 1, 3 do
      if math.abs(a[i] - b[i]) > 1e-6 then
        return false
      end
    end
    return true
  end

  describe("card:SetContent", function()
    local function newCard()
      local col = UI.Stack(UIParent, 0)
      return col:Card(0)
    end

    it("draws a title, label / value rows and a note, and sizes the card to them", function()
      local card = newCard()
      card:SetContent({
        title = "Route",
        rows = { { label = "Buy", copper = 12000 }, { label = "Margin", text = "30%", color = "good" } },
        note = "Prices are a day old.",
      })
      card:Fit(240)
      assert.are.equal("Route", card.parts.title.text)
      assert.are.equal("Buy", card.rows[1].label.text)
      assert.are.equal(W.Money(12000), card.rows[1].value.text)
      assert.are.equal(W.Color("good", "30%"), card.rows[2].value.text)
      assert.are.equal("Prices are a day old.", card.parts.note.text)
      -- pad 8, title 12, 4 before the rows, two 16 px rows, 4 before the note, note 12, pad 8
      assert.are.equal(8 + 12 + 4 + 32 + 4 + 12 + 8, card:GetHeight())
    end)

    it("reuses its rows and their font strings on every call", function()
      local card = newCard()
      card:SetContent({ rows = { { label = "A", text = "1" }, { label = "B", text = "2" } } })
      local row, label, value = card.rows[1], card.rows[1].label, card.rows[1].value
      card:SetContent({ rows = { { label = "C", copper = 5 } } })
      assert.are.equal(row, card.rows[1])
      assert.are.equal(label, card.rows[1].label)
      assert.are.equal(value, card.rows[1].value)
      assert.are.equal("C", label.text)
      assert.is_false(card.rows[2]:IsShown()) -- the row it no longer needs is hidden, not thrown away
    end)

    it("draws a total row with a rule above it and brighter text", function()
      local card = newCard()
      card:SetContent({
        rows = {
          { label = "Sells for", copper = 30000 },
          { label = "You net", copper = 2500, signed = true, total = true },
        },
      })
      local plain, total = card.rows[1], card.rows[2]
      assert.is_false(plain.rule:IsShown())
      assert.is_true(total.rule:IsShown())
      assert.are.equal("GameFontHighlight", total.label._font)
      assert.are.equal(W.SignedMoney(2500, { full = true }), total.value.text)
      assert.is_true(total:GetHeight() > plain:GetHeight())
    end)

    it("draws a big row's value large", function()
      local card = newCard()
      card:SetContent({ rows = { { label = "Now", copper = 904, big = true } } })
      assert.are.equal("GameFontHighlightLarge", card.rows[1].value._font)
    end)

    it("leaves hidden rows and empty pieces out of its height", function()
      local card = newCard()
      card:SetContent({ rows = { { label = "A", text = "1" } } })
      card:Fit(240)
      local h = card:GetHeight()
      card:SetContent({ rows = { { label = "A", text = "1" }, { label = "B", text = "2", hidden = true } } })
      assert.are.equal(h, card:GetHeight())
      assert.is_false(card.rows[2] ~= nil and card.rows[2]:IsShown())
    end)

    it("shows an item title as an item link, and an item on a label as an inline link", function()
      local card = newCard()
      card:SetContent({ item = 2589, count = 4, rows = { { item = 2592, label = "x2", text = "" } } })
      assert.is_true(card.parts.item:IsShown())
      assert.are.equal(2589, card.parts.item.key)
      assert.are.equal("", card.parts.title.text)
      assert.truthy(card.rows[1].label.text:find("|Hitem:2592", 1, true))
      assert.truthy(card.rows[1].mouse) -- hover and clicks reach the link
    end)

    it("explains a row's term on hover, following the row's current term", function()
      local card = newCard()
      card:SetContent({ rows = { { label = "Market", text = "1g", term = "market" } } })
      local row = card.rows[1]
      row.scripts.OnEnter(row)
      assert.are.equal(ns.Help.TERMS.market[1], GameTooltip.text) -- the tooltip's title
      card:SetContent({ rows = { { label = "Lowest", text = "1g", term = "min" } } })
      row.scripts.OnEnter(row)
      assert.are.equal(ns.Help.TERMS.min[1], GameTooltip.text)
    end)
  end)

  describe("UI.SideList", function()
    local function newList(onClick)
      local side = UI.Sidebar(UIParent, 200)
      return UI.SideList(side, { onClick = onClick }), side
    end
    local function entries(n)
      local out = { { heading = "Categories" } }
      for i = 1, n do
        out[#out + 1] = { label = "Line " .. i, count = i * 1000 }
      end
      return out
    end

    it("grows its lines with the sidebar's height, and keeps them as sidebar.lines", function()
      local list, side = newList()
      list:SetEntries(entries(30))
      side.scripts.OnSizeChanged(side, 200, 4 + 4 + 10 * UI.SIDE_LINE_H)
      assert.are.equal(10, list.rows)
      assert.are.equal(list.lines, side.lines)
      assert.is_true(#side.lines >= 10)
      assert.are.equal("Line 9", side.lines[10].text.text)
      side.scripts.OnSizeChanged(side, 200, 4 + 4 + 20 * UI.SIDE_LINE_H)
      assert.are.equal(20, #side.lines)
      assert.are.equal("Line 19", side.lines[20].text.text)
    end)

    it("pages with the mouse wheel, never past the end", function()
      local list, side = newList()
      side.scripts.OnSizeChanged(side, 200, 4 + 4 + 5 * UI.SIDE_LINE_H)
      list:SetEntries(entries(6)) -- 7 entries, 5 lines
      side.scripts.OnMouseWheel(side, -1)
      assert.are.equal(2, list.offset)
      side.scripts.OnMouseWheel(side, -1)
      assert.are.equal(2, list.offset)
      assert.are.equal("Line 6", side.lines[5].text.text)
      side.scripts.OnMouseWheel(side, 5)
      assert.are.equal(0, list.offset)
    end)

    it("draws the selected line tinted and white, links in link blue, counts with separators", function()
      local list, side = newList()
      side.scripts.OnSizeChanged(side, 200, 200)
      list:SetEntries({
        { label = "Potions", count = 1234, selected = true },
        { label = "+ New list", kind = "link" },
        { label = "Raid", count = "done", kind = "done" },
        { label = "Mine", note = "Tyken", indent = 1 },
      })
      local sel, link, done, owned = side.lines[1], side.lines[2], side.lines[3], side.lines[4]
      assert.is_true(sel.sel:IsShown())
      assert.is_true(same(sel.text._textColor, W.RGB("white")))
      assert.is_true(same(sel.sel._color, W.COLORS.rowSelected))
      assert.are.equal("1,234", sel.count.text)
      assert.is_false(link.sel:IsShown())
      assert.is_true(same(link.text._textColor, W.RGB("link")))
      assert.are.equal(W.Color("good", "done"), done.count.text)
      assert.truthy(owned.text.text:find(W.Dim("Tyken"), 1, true))
      assert.are.same({ "LEFT", 6 + UI.SIDE_INDENT, 0 }, owned.text.points[1])
    end)

    it("re-tints the selection when the theme changes", function()
      local list, side = newList()
      list:SetEntries({ { label = "Potions", selected = true } })
      W.SetTheme("Alliance")
      assert.is_true(same(side.lines[1].sel._color, W.COLORS.rowSelected))
    end)

    it("passes a click's entry and button, and ignores headings", function()
      local clicks = {}
      local list, side = newList(function(e, button)
        clicks[#clicks + 1] = { e.key, button }
      end)
      side.scripts.OnSizeChanged(side, 200, 200)
      list:SetEntries({ { heading = "Lists" }, { label = "Potions", key = "s:1" } })
      local head, line = side.lines[1], side.lines[2]
      head.scripts.OnClick(head, "LeftButton")
      line.scripts.OnClick(line, "RightButton")
      assert.are.same({ { "s:1", "RightButton" } }, clicks)
    end)
  end)

  describe("UI.SettingsCard", function()
    local function newCard(rows)
      return UI.SettingsCard(UI.Stack(UIParent, 0), "Window", rows)
    end

    it("binds a check to its setting: ticked from it, and a click saves it", function()
      AME_DB.settings.openWithAH = true
      local changed
      local card = newCard({
        { check = "Open with the auction house", key = "openWithAH" },
        {
          check = "Colour-blind palette",
          key = "colorBlind",
          indent = true,
          onChange = function(on)
            changed = on
          end,
        },
      })
      card:Refresh()
      local open, close = card.controls[1], card.controls[2]
      assert.are.equal("Window", card.title.text)
      assert.is_true(open.checked)
      assert.is_false(close.checked)
      assert.are.equal(UI.SETTINGS_INDENT, close.points[1][2]) -- set in under the one above
      close.scripts.OnClick(close)
      assert.is_true(ns.Settings:Get("colorBlind"))
      assert.is_true(changed)
      open.scripts.OnClick(open)
      assert.is_false(ns.Settings:Get("openWithAH"))
      assert.are.same({ open, close }, card.checks)
    end)

    it("puts a field's control on the right, and passes an input's text to its button", function()
      local picked, sent
      local card = newCard({
        {
          field = "Scale",
          note = "(70-120%)",
          dropdown = {
            80,
            { { 1, "100%" } },
            function(v)
              picked = v
            end,
          },
        },
        {
          input = "Player name",
          button = "Add",
          onClick = function(text)
            sent = text
          end,
        },
        { text = "Shared with your guild." },
      })
      local dd, box, para = card.controls[1], card.controls[2], card.controls[3]
      assert.are.same({ "RIGHT", 0, 0 }, dd.points[#dd.points])
      assert.truthy(card.rowFrames[1].text.text:find("Scale", 1, true))
      box:SetText("Tyken")
      box.button.scripts.OnClick(box.button)
      assert.are.equal("Tyken", sent)
      assert.are.equal("Shared with your guild.", para.text)
      assert.is_nil(picked)
    end)

    it("wraps a row of buttons onto a new line when they don't fit", function()
      local card =
        newCard({ { buttons = { { "Export", nil, width = 90, primary = true }, { "Import", nil, width = 90 } } } })
      local row = card.controls[1]
      row:Fit(400)
      assert.are.equal(22, row:GetHeight())
      row:Fit(150)
      assert.are.equal(22 + 6 + 22, row:GetHeight())
      assert.are.same({ "TOPLEFT", 0, -28 }, row.buttons[2].points[1])
      assert.is_true(same(row.buttons[1]._backdrop, W.COLORS.primary))
      card:Fit(500) -- the card measures the row at its width
      assert.are.equal(22, row:GetHeight())
    end)
  end)

  describe("W.Panel and W.PageHeading", function()
    it("a panel has the panel colour, and an inner frame inset by pad", function()
      local p = W.Panel(UIParent, 8)
      assert.is_true(same(p._backdrop, W.COLORS.panel))
      assert.are.same({ "TOPLEFT", 8, -8 }, p.inner.points[1])
    end)

    it("a page heading has a gold title and a dim subtitle, hidden when empty", function()
      local h = W.PageHeading(UIParent)
      h:Set("Top earners", "what pays most to craft")
      assert.are.equal("GameFontNormal", h.title._font)
      assert.are.equal("what pays most to craft", h.subtitle.text)
      h:Set("Recipes to buy")
      assert.is_false(h.subtitle:IsShown())
    end)
  end)

  describe("W.Menu", function()
    it("draws separators as short lines that don't click, and marks submenus", function()
      local clicked = 0
      local anchor = CreateFrame("Button", nil, UIParent)
      local m = W.Menu(anchor, {
        {
          text = "Open chart",
          func = function()
            clicked = clicked + 1
          end,
        },
        { separator = true },
        { text = "Watchlists...", submenu = true },
      })
      local open, sep, sub = m.items[1], m.items[2], m.items[3]
      assert.is_true(sep.rule:IsShown())
      assert.is_false(open.rule:IsShown())
      assert.is_true(sub.arrow:IsShown())
      assert.is_false(open.arrow:IsShown())
      assert.is_true(sep:GetHeight() < open:GetHeight())
      assert.are.equal(3 + 18 + 9 + 18 + 3, m:GetHeight())
      sep.scripts.OnClick(sep)
      assert.is_true(m:IsShown())
      open.scripts.OnClick(open)
      assert.are.equal(1, clicked)
    end)
  end)
end)
