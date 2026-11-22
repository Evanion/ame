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
      "Core/ItemCache.lua",
      "Core/UI/Widgets.lua",
      "Core/UI/Help.lua",
      "Core/UI/DataTable.lua",
    })
    W = ns.Widgets
    W.SetTheme("Horde")
    ns.UI = {}
    UI = ns.UI
    addon.load({ "Core/UI/Shell.lua" }, ns)
  end)

  after_each(function()
    env:restore()
  end)

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
end)
