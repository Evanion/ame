-- Events: the one change signal Core fires and views subscribe to.
local addon = require("spec.helpers.addon")

describe("Events", function()
  local E
  before_each(function()
    E = addon.load({ "Core/Init.lua" }).Events
  end)

  it("calls every subscriber with what was fired, in the order they subscribed", function()
    local got = {}
    E.On("IndexReady", function(shard)
      got[#got + 1] = "a:" .. shard
    end)
    E.On("IndexReady", function(shard)
      got[#got + 1] = "b:" .. shard
    end)
    E.On("SyncChanged", function()
      got[#got + 1] = "other"
    end)
    E.Fire("IndexReady", "PvP|Horde")
    assert.are.same({ "a:PvP|Horde", "b:PvP|Horde" }, got)
  end)

  it("stops calling a handle once it's off, and fires nothing for names nobody listens to", function()
    local n = 0
    local h = E.On("RecipesChanged", function()
      n = n + 1
    end)
    E.Fire("RecipesChanged", 171)
    E.Off(h)
    E.Fire("RecipesChanged", 171)
    E.Fire("NobodyListens")
    assert.are.equal(1, n)
  end)

  it("lets a subscriber unsubscribe itself while it runs", function()
    local n, h = 0, nil
    h = E.On("ShoppingChanged", function()
      n = n + 1
      E.Off(h)
    end)
    E.On("ShoppingChanged", function()
      n = n + 10
    end)
    E.Fire("ShoppingChanged")
    E.Fire("ShoppingChanged")
    assert.are.equal(21, n)
  end)
end)
