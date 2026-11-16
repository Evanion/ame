-- Guards the test environment itself: WoW runs Lua 5.1, so the pure-logic modules must be tested on 5.1.
describe("toolchain", function()
  it("runs on Lua 5.1 like the WoW client", function()
    assert.are.equal("Lua 5.1", _VERSION)
  end)

  it("has 5.1 integer/float semantics (no integer subtype)", function()
    assert.are.equal("number", type(1))
    assert.are.equal(0.5, 1 / 2)
  end)
end)
