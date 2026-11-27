-- Core/Usage.lua: what you use up, from drops in your bags that nothing else explains, and the rate a day Home's
-- Stock up rows are sized by; then its event frame, which tells use from vendors, mail, the bank and the cursor.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

local DAY = 86400

describe("Usage", function()
  local env, ns, Usage
  local POTION, HERB, ARROW = 13446, 13465, 2512
  local CLASS = { [POTION] = 0, [HERB] = 7, [ARROW] = 6 }
  local function counts(id)
    return Usage.Counts(CLASS[id])
  end

  before_each(function()
    env = wow.install()
    ns = addon.load({ "Core/Init.lua", "Core/Usage.lua" })
    Usage = ns.Usage
  end)

  after_each(function()
    env:restore()
  end)

  it("counts consumables, reagents and ammo; not trade goods or gear", function()
    assert.is_true(Usage.Counts(0))
    assert.is_true(Usage.Counts(5))
    assert.is_true(Usage.Counts(6))
    assert.is_false(Usage.Counts(7))
    assert.is_false(Usage.Counts(2))
    assert.is_false(Usage.Counts(nil))
  end)

  it("a drop is use; a rise, a busy drop and items it doesn't count are not", function()
    local db = {}
    local u = Usage.New(db)
    local t = 100 * DAY
    u:Rebase({ [POTION] = 10, [HERB] = 20, [ARROW] = 200 }, counts)
    assert.is_nil(db.last[HERB])
    u:Observe({ [POTION] = 8, [HERB] = 5, [ARROW] = 150 }, t, false, counts)
    u:Observe({ [POTION] = 20, [ARROW] = 150 }, t + 60, false, counts) -- bought more
    u:Observe({ [POTION] = 15, [ARROW] = 150 }, t + 120, true, counts) -- sold at a vendor
    u:Observe({ [POTION] = 14, [ARROW] = 100 }, t + 180, false, counts)
    local used = u:Used(t + 200)
    assert.equals(3, used[POTION].n)
    assert.equals(100, used[ARROW].n)
    assert.is_nil(used[HERB])
    assert.equals(1, used[POTION].days)
  end)

  it("the rate is over the days recorded, at least a week, and the window drops old days", function()
    local db = {}
    local u = Usage.New(db)
    local t0 = 100 * DAY
    u:Rebase({ [POTION] = 50 }, counts)
    u:Observe({ [POTION] = 43 }, t0, false, counts)
    assert.near(1, u:Used(t0)[POTION].perDay, 1e-9) -- 7 used, spread over the first week
    u:Observe({ [POTION] = 29 }, t0 + 13 * DAY, false, counts)
    local used = u:Used(t0 + 13 * DAY)
    assert.equals(21, used[POTION].n)
    assert.equals(2, used[POTION].days)
    assert.near(21 / 14, used[POTION].perDay, 1e-9)
    -- four weeks on, the first day has gone
    u:Observe({ [POTION] = 29 }, t0 + 30 * DAY, false, counts)
    assert.equals(14, u:Used(t0 + 30 * DAY)[POTION].n)
    assert.is_nil(db.days[POTION][100])
  end)

  it("Rates adds your characters up, and leaves out what you've barely used", function()
    local t0 = 100 * DAY
    local a, b = {}, {}
    local ua, ub = Usage.New(a), Usage.New(b)
    ua:Rebase({ [POTION] = 20, [ARROW] = 10 }, counts)
    ub:Rebase({ [POTION] = 20 }, counts)
    ua:Observe({ [POTION] = 17, [ARROW] = 9 }, t0, false, counts)
    ub:Observe({ [POTION] = 16 }, t0 + DAY, false, counts)
    ua:Observe({ [POTION] = 17, [ARROW] = 8 }, t0 + DAY, false, counts)
    local rates = Usage.Rates({ ["R:A"] = a, ["R:B"] = b }, t0 + DAY)
    assert.near(7 / 7, rates[POTION], 1e-9) -- 3 + 4, over a week
    assert.is_nil(rates[ARROW]) -- 2 used: not a habit yet
  end)

  describe("in game", function()
    local bags, cursor

    before_each(function()
      bags = {}
      cursor = false
      _G.CursorHasItem = function()
        return cursor
      end
      _G.DeleteCursorItem = function() end
      ns = addon.load({ "Core/Init.lua", "Core/Usage.lua" })
      ns.SessionTracker = {
        ReadBags = function()
          return bags
        end,
      }
      ns.Trading = {
        CharKey = function()
          return "TestRealm:Tyken"
        end,
      }
      ns.ItemCache = {
        Get = function(id)
          return { classID = CLASS[id] }
        end,
      }
      _G.AME_DB = {}
    end)

    after_each(function()
      _G.CursorHasItem, _G.DeleteCursorItem = nil, nil
    end)

    local function used()
      local u = ns.Usage.New(AME_DB.usage["TestRealm:Tyken"]):Used(env.now)
      return u[POTION] and u[POTION].n or 0
    end

    it("counts drops out of every window that moves items, and none while it's open", function()
      bags = { [POTION] = 10 }
      env:fire("PLAYER_ENTERING_WORLD")
      bags = { [POTION] = 9 }
      env:fire("BAG_UPDATE_DELAYED")
      assert.equals(1, used())
      env:fire("MERCHANT_SHOW")
      bags = { [POTION] = 4 }
      env:fire("BAG_UPDATE_DELAYED")
      env:fire("MERCHANT_CLOSED")
      bags = { [POTION] = 3 } -- still in the quiet after it
      env:fire("BAG_UPDATE_DELAYED")
      assert.equals(1, used())
      env.now = env.now + 5
      bags = { [POTION] = 2 }
      env:fire("BAG_UPDATE_DELAYED")
      assert.equals(2, used())
    end)

    it("a split on the cursor, a deleted stack and a login are not use", function()
      bags = { [POTION] = 10 }
      env:fire("PLAYER_ENTERING_WORLD")
      cursor = true
      bags = { [POTION] = 5 }
      env:fire("BAG_UPDATE_DELAYED")
      cursor = false
      bags = { [POTION] = 10 }
      env:fire("BAG_UPDATE_DELAYED")
      _G.DeleteCursorItem()
      bags = { [POTION] = 6 }
      env:fire("BAG_UPDATE_DELAYED")
      assert.equals(0, used())
      env.now = env.now + 5
      bags = { [POTION] = 1 } -- changed while logged out
      env:fire("PLAYER_ENTERING_WORLD")
      bags = {}
      env:fire("BAG_UPDATE_DELAYED") -- bags read empty: nothing to compare
      assert.equals(0, used())
    end)
  end)
end)
