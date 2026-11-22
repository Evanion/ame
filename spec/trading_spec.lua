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

  it("skips system messages the game hands over as secret values (dungeons, raids)", function()
    local secret = setmetatable({}, {
      __index = function()
        error("attempt to index a secret string value")
      end,
    })
    _G.issecretvalue = function(v)
      return v == secret
    end
    assert.has_no.errors(function()
      Trading:OnSystemMessage(secret)
    end)
    _G.issecretvalue = nil
  end)
end)

describe("Trading.BankBags", function()
  local Trading
  before_each(function()
    Trading = addon.load({ "Core/Init.lua", "Core/Trading.lua" }).Trading
  end)

  it("reads the character bank's tabs where the game has them", function()
    local tabs = { Bank = -1, ReagentBag = 5, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8 }
    assert.are.same({ 6, 7, 8 }, Trading.BankBags(tabs))
  end)

  it("else the bank, the reagent bank and the bank bags, never the reagent bag", function()
    local B = { Bank = -1, Reagentbank = -3, ReagentBag = 5 }
    assert.are.same({ -1, -3, 6, 7, 8, 9, 10, 11, 12 }, Trading.BankBags(B))
    assert.are.same({ -1, 5, 6, 7, 8, 9, 10, 11 }, Trading.BankBags({ Bank = -1 })) -- classic: no reagent bag
  end)
end)

describe("Trading.WonFrom", function()
  local Trading
  before_each(function()
    Trading = addon.load({ "Core/Init.lua", "Core/Trading.lua" }).Trading
  end)

  it("reads a won auction's item and count from the game's message", function()
    local name, n = Trading.WonFrom("You won an auction for Murloc Eye (x40)", "You won an auction for %s")
    assert.are.equal("Murloc Eye", name)
    assert.are.equal(40, n)
    name, n = Trading.WonFrom("You won an auction for Mirah's Song", "You won an auction for %s")
    assert.are.equal("Mirah's Song", name)
    assert.are.equal(1, n)
    assert.is_nil(Trading.WonFrom("Your auction of Silk has expired.", "You won an auction for %s"))
  end)
end)
