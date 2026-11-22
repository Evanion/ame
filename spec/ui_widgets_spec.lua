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
