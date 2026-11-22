-- Frame widgets from Widgets.lua and DataTable.lua, on the stubbed client's frames (spec/helpers/wow.lua): what
-- they draw and what a click does.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("frame widgets", function()
  local env, ns, W

  before_each(function()
    env = wow.install()
    ns = addon.load({ "Core/Init.lua", "Core/ItemCache.lua", "Core/UI/Widgets.lua", "Core/UI/DataTable.lua" })
    W = ns.Widgets
    W.SetTheme("Horde")
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

  describe("W.Primary", function()
    it("fills the button with the primary shade of the accent and a white label", function()
      local b = W.Primary(W.Button(UIParent, "Post", 80, 22))
      assert.is_true(same(b._backdrop, W.COLORS.primary))
      assert.is_true(same(b.label._textColor, { 1, 1, 1 }))
    end)

    it("is a little lighter under the mouse, and back on leave", function()
      local b = W.Primary(W.Button(UIParent, "Post", 80, 22))
      b.scripts.OnEnter(b)
      assert.is_true(same(b._backdrop, W.COLORS.primaryHover))
      b.scripts.OnLeave(b)
      assert.is_true(same(b._backdrop, W.COLORS.primary))
    end)

    it("draws the selected look when selected, and the primary fill again after", function()
      local b = W.Primary(W.Button(UIParent, "Market", 80, 22))
      b:SetSelected(true)
      assert.is_true(same(b._backdrop, W.COLORS.selected))
      assert.is_true(same(b._border, W.COLORS.accent))
      b:SetSelected(false)
      assert.is_true(same(b._backdrop, W.COLORS.primary))
    end)

    it("follows a theme change", function()
      local b = W.Primary(W.Button(UIParent, "Post", 80, 22))
      local horde = b._backdrop
      W.SetTheme("Alliance")
      assert.is_false(same(b._backdrop, horde))
      assert.is_true(same(b._backdrop, W.COLORS.primary))
    end)

    it("can be switched off again: an ordinary button", function()
      local b = W.Primary(W.Button(UIParent, "Post anyway", 80, 22))
      W.Primary(b, false)
      assert.is_true(same(b._backdrop, W.COLORS.panel))
      assert.is_false(same(b.label._textColor, { 1, 1, 1 }))
    end)
  end)

  describe("item links", function()
    local shown
    before_each(function()
      shown = {}
      ns.UI = {
        ShowItem = function(_, key)
          shown[#shown + 1] = key
        end,
      }
    end)

    it("LinkText is the name as an item hyperlink in its quality colour, with a dim count", function()
      assert.are.equal("|cffffffff|Hitem:2589|hItem 2589|h|r", W.LinkText(2589))
      local text = W.LinkText(2589, 20)
      assert.truthy(text:find("|Hitem:2589|hItem 2589|h", 1, true))
      assert.truthy(text:find(W.Dim("20"), 1, true))
      assert.are.equal(W.NONE, W.LinkText(nil))
    end)

    it("links a variant by its own item string, and finds its key again on a click", function()
      local key = ns.ItemKey(15211, 1234)
      local text = W.LinkText(key)
      local s = text:match("|H(.-)|h")
      assert.are.equal(ns.ItemString(key), s)
      assert.are.equal(key, W.LinkKey(s))
      assert.is_nil(W.LinkKey("command:/ame"))
    end)

    it("in text: Shift-click links the item in chat, a plain click opens it", function()
      local f = W.EnableLinks(CreateFrame("Frame", nil, UIParent))
      env.modified = "CHATLINK"
      f.scripts.OnHyperlinkClick(f, "item:2589", "Item 2589", "LeftButton")
      assert.are.same({ "|Hitem:2589|h" }, env.modifiedLinks)
      assert.are.same({}, shown)
      env.modified = nil
      f.scripts.OnHyperlinkClick(f, "item:2589", "Item 2589", "LeftButton")
      assert.are.same({ 2589 }, shown)
    end)

    it("in text: hovering shows the item's tooltip; other links are left alone", function()
      local f = W.EnableLinks(CreateFrame("Frame", nil, UIParent))
      local tipped
      local tip = _G.GameTooltip -- the stub's, fresh for each test
      tip.SetItemByID = function(_, id)
        tipped = id
      end
      f.scripts.OnHyperlinkEnter(f, "item:2589")
      assert.are.equal(2589, tipped)
      f.scripts.OnHyperlinkClick(f, "command:/ame", "/ame", "LeftButton")
      assert.are.same({}, shown)
    end)

    it("ItemLink draws icon, name, count and confidence, and is as wide as they are", function()
      local link = W.ItemLink(UIParent, { icon = 14 })
      link:SetItem(2589, 20, "high")
      assert.is_true(link:IsShown())
      assert.are.equal(134400, link.icon._texture)
      assert.are.equal("|cffffffffItem 2589|r", link.name:GetText())
      assert.are.equal(W.Dim("20"), link.count:GetText())
      assert.are.equal(W.Confidence("high"), link.conf:GetText())
      local nameW = link.name:GetStringWidth()
      assert.are.equal(14 + W.LINK_GAP + nameW + 4 + link.count:GetStringWidth() + 24, link:GetWidth())
      link:SetItem(nil)
      assert.is_false(link:IsShown())
    end)

    it("ItemLink cuts a long name short to fit maxWidth", function()
      local link = W.ItemLink(UIParent, { icon = 14, maxWidth = 80 })
      link:SetItem(2589)
      assert.are.equal(80, link:GetWidth())
    end)

    it("ItemLink: Shift-click links it, a plain click opens it", function()
      local link = W.ItemLink(UIParent)
      link:SetItem(2589)
      env.modified = "CHATLINK"
      link.scripts.OnClick(link, "LeftButton")
      assert.are.same({ "|Hitem:2589|h" }, env.modifiedLinks)
      env.modified = nil
      link.scripts.OnClick(link, "LeftButton")
      assert.are.same({ 2589 }, shown)
    end)
  end)

  describe("signals", function()
    it("a badge draws the icon and word on its pill; no signal is a dim dash", function()
      local badge = W.SignalBadge(UIParent)
      badge:SetSignal("sell")
      local word, pill = W.SignalBadgeColors("sell")
      assert.truthy(badge.text:GetText():find("SELL", 1, true))
      assert.truthy(badge.text:GetText():find("Signals\\Down", 1, true))
      assert.truthy(badge.text:GetText():find("|cff" .. word, 1, true))
      assert.is_true(same(badge.pill._color, pill))
      assert.is_true(badge.pill:IsShown())
      assert.is_true(badge:GetWidth() > badge.text:GetStringWidth())
      badge:SetSignal("none")
      assert.are.equal(W.NONE, badge.text:GetText())
      assert.is_false(badge.pill:IsShown())
    end)

    it("SignalText is the plain form, SignalGlyph's", function()
      assert.are.equal(W.SignalGlyph("buy"), W.SignalText("buy"))
    end)

    it("a signal filter has a button per signal; short ones are icons only; the picked one inverts", function()
      local picked
      local f = W.SignalFilter(UIParent, {
        onSelect = function(key)
          picked = key
        end,
      })
      assert.are.equal(7, #f.buttons)
      assert.truthy(f.byKey.buy.label:GetText():find("BUY", 1, true))
      local short = W.SignalFilter(UIParent, { signals = { "all", "buy", "sell" }, short = true })
      assert.are.equal(3, #short.buttons)
      assert.is_falsy(short.byKey.buy.label:GetText():find("BUY", 1, true))
      assert.truthy(short.byKey.buy.label:GetText():find("Signals\\Up", 1, true))
      f.byKey.sell.scripts.OnClick(f.byKey.sell)
      assert.are.equal("sell", picked)
      assert.truthy(f.byKey.sell.label:GetText():find(W.INVERTED_TEXT, 1, true))
    end)

    it("a DataTable signal column draws a badge per row", function()
      local t = ns.DataTable.New(UIParent, {
        rows = 2,
        columns = {
          { key = "name", label = "Item", width = 150, item = true },
          { key = "signal", label = "Signal", width = 64, format = "signal" },
        },
        itemID = function(d)
          return d.id
        end,
      })
      t.frame:SetWidth(400)
      t:SetData({ { id = 1, signal = "buy" } })
      t:Render()
      local badge = t.rows[1].badges[2]
      assert.are.equal("buy", badge.signal)
      assert.is_true(badge:IsShown())
      assert.are.equal("", t.rows[1].cells[2]:GetText())
      assert.truthy(t:ExportText():find("BUY", 1, true))
    end)
  end)

  describe("W.Tag", function()
    it("draws its text in its kind's colours, as wide as the text", function()
      local tag = W.Tag(UIParent)
      tag:Set("12 · AH", "ah")
      local c = W.COLORS.tag.ah
      assert.is_true(same(tag.bg._color, c[1]))
      assert.is_true(same(tag.text._textColor, c[2]))
      assert.are.equal(math.ceil(tag.text:GetStringWidth()) + 12, tag:GetWidth())
      tag:Set("odd", "nonsense")
      assert.are.equal("other", tag.kind)
      tag:Set("")
      assert.is_false(tag:IsShown())
    end)

    it("re-tints made tags on a theme change", function()
      local tag = W.Tag(UIParent)
      tag:Set("made", "made")
      W.SetTheme("Alliance")
      assert.is_true(same(tag.bg._color, W.COLORS.tag.made[1]))
    end)

    it("a DataTable tag column draws one per row, and exports its text", function()
      local t = ns.DataTable.New(UIParent, {
        rows = 2,
        columns = {
          { key = "name", label = "Item", width = 150, item = true },
          { key = "from", label = "From", width = 80, format = "tag" },
        },
        itemID = function(d)
          return d.id
        end,
      })
      t.frame:SetWidth(400)
      t:SetData({
        { id = 1, from = { text = "4 · bank", kind = "other" } },
        { id = 2, from = { text = "AH", kind = "ah" } },
      })
      t.headers[2].scripts.OnClick(t.headers[2]) -- sorting by it works on the text
      t:Render()
      local kinds = { t.rows[1].tags[2].kind, t.rows[2].tags[2].kind }
      table.sort(kinds)
      assert.are.same({ "ah", "other" }, kinds)
      assert.truthy(t:ExportText():find("4 · bank", 1, true))
    end)
  end)

  describe("W.KpiCard", function()
    it("colours the change by its kind: up and down in the palette's gain and loss, mute dim", function()
      local c = W.KpiCard(UIParent, "Market index")
      for kind, role in pairs({ up = "good", down = "bad", mute = "dim" }) do
        c:Set({ value = "104.2", delta = "0.9%", deltaKind = kind })
        assert.is_true(same(c.delta._textColor, W.RGB(role)), kind)
      end
      assert.are.equal("104.2", c.value.text)
    end)

    it("draws money, signed money and a second amount", function()
      local c = W.KpiCard(UIParent, "Sold / bought")
      c:Set({ copper = 120000, copper2 = 50000 })
      assert.are.equal(W.BigMoney(120000) .. W.Dim(" / ") .. W.BigMoney(50000), c.value.text)
      c:Set({ copper = -5000, signed = true })
      assert.are.equal(W.SignedMoney(-5000), c.value.text)
    end)

    it("splits the breadth bar by rising and falling", function()
      local c = W.KpiCard(UIParent, "Breadth")
      c:SetWidth(216) -- 200 inside the padding
      c:Set({ value = "60%", rise = 300, fall = 200 })
      assert.are.equal(120, c.rise:GetWidth())
      assert.are.equal(80, c.fall:GetWidth())
      assert.is_true(same(c.rise._color, W.COLORS.up))
      assert.is_true(same(c.fall._color, W.COLORS.down))
      c:Set({ value = "-" })
      assert.is_false(c.rise:IsShown())
      assert.is_false(c.fall:IsShown())
    end)

    it("hides its note when compact, and needs less room", function()
      local c = W.KpiCard(UIParent, "Listed value")
      c:Set({ value = "48.6M g", note = "3,940 items" })
      assert.is_true(c.note:IsShown())
      local tall = c:NeededHeight()
      c:SetCompact(true)
      assert.is_false(c.note:IsShown())
      assert.are.equal("GameFontHighlight", c.value._font)
      assert.is_true(c:NeededHeight() < tall)
      c:SetCompact(false)
      assert.is_true(c.note:IsShown())
    end)

    it("is what a W.CardRow is made of, sharing the row's width", function()
      local row = W.CardRow(UIParent, { { "A" }, { "B" } }, { width = 206 })
      assert.are.equal(2, #row.cards)
      assert.are.equal(100, row.cards[1]:GetWidth())
      assert.is_function(row.cards[2].Set)
      row:SetCompact(true)
      assert.is_true(row.cards[2].compact)
    end)
  end)

  describe("W.Button", function()
    it("colours its label with opts.color, dimmed while disabled", function()
      local b = W.Button(UIParent, "Buy", 60, 20, nil, { color = "good" })
      assert.is_true(same(b.label._textColor, W.RGB(ns.HEX.good)))
      b:SetEnabled(false)
      assert.is_true(same(b.label._textColor, W.COLORS.dim))
      b:SetEnabled(true)
      assert.is_true(same(b.label._textColor, W.RGB("good")))
    end)
  end)
end)
