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
