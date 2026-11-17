-- Trading.Pattern turns the game's own message formats (localized) into patterns for its system messages.
local addon = require("spec.helpers.addon")

describe("Trading.Pattern", function()
  local Trading
  before_each(function()
    Trading = addon.load({ "Core/Init.lua", "Core/Trading.lua" }).Trading
  end)

  it("captures the item name from the game's message", function()
    local p = Trading.Pattern("A buyer has been found for your auction of %s.", "unused")
    assert.are.equal("Linen Cloth", ("A buyer has been found for your auction of Linen Cloth."):match(p))
    assert.is_nil(("A buyer has been found for your auction of Linen Cloth"):match(p)) -- whole message only
  end)

  it("falls back when the client has no such format string", function()
    local p = Trading.Pattern(nil, "Your auction of %s has expired.")
    assert.are.equal("Silk", ("Your auction of Silk has expired."):match(p))
  end)

  it("escapes magic characters and handles other languages, numbered placeholders included", function()
    local de = Trading.Pattern("Für Eure Auktion von %s wurde ein Käufer gefunden.", "")
    assert.are.equal("Leinenstoff", ("Für Eure Auktion von Leinenstoff wurde ein Käufer gefunden."):match(de))
    local numbered = Trading.Pattern("Auction (%1$s) sold - 100%% done?", "")
    assert.are.equal("Elixir [Rare]", ("Auction (Elixir [Rare]) sold - 100% done?"):match(numbered))
    local zh = Trading.Pattern("你拍卖的%s已经找到买家。", "")
    assert.are.equal("亚麻布", ("你拍卖的亚麻布已经找到买家。"):match(zh))
  end)
end)
