local addon = require("spec.helpers.addon")

describe("notifications", function()
  local ns, N

  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/Notices.lua" })
    N = ns.Notices.New({})
  end)

  it("keeps what was said, newest first, and counts what you haven't seen", function()
    N:Add({ kind = "alert", text = "dropped to 9s", itemID = 2589 }, 100)
    N:Add({ kind = "request", who = "Ann" }, 200)
    assert.are.equal(2, N:Unread())
    local list = N:List()
    assert.are.equal("request", list[1].kind)
    assert.are.equal(2589, list[2].itemID)
    N:MarkRead(250)
    assert.are.equal(0, N:Unread())
    N:Add({ kind = "alert", text = "rose to 2g", itemID = 2589 }, 300)
    assert.are.equal(1, N:Unread())
    assert.is_true(N:IsUnread(N:List()[1]))
    assert.is_false(N:IsUnread(N:List()[2]))
  end)

  it("the same notice again soon moves up instead of piling up", function()
    N:Add({ kind = "request", who = "Ann" }, 100)
    N:Add({ kind = "alert", text = "x", itemID = 1 }, 150)
    N:Add({ kind = "request", who = "Ann" }, 200)
    assert.are.equal(2, #N:List())
    assert.are.equal("Ann", N:List()[1].who)
    N:Add({ kind = "request", who = "Ann" }, 200 + ns.Notices.REPEAT + 1)
    assert.are.equal(3, #N:List())
  end)

  it("keeps the newest MAX, and clears", function()
    for i = 1, ns.Notices.MAX + 5 do
      N:Add({ kind = "alert", text = tostring(i), itemID = i }, i * 1000)
    end
    local list = N:List()
    assert.are.equal(ns.Notices.MAX, #list)
    assert.are.equal(tostring(ns.Notices.MAX + 5), list[1].text)
    local told = 0
    N:OnChange(function()
      told = told + 1
    end)
    N:Clear()
    assert.are.equal(0, #N:List())
    assert.are.equal(1, told)
  end)
end)
