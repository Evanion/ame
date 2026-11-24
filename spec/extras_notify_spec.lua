-- The bell's notifications (Core/UI/Screens/Notifications.lua), what waits outside the window (Core/UI/Pending.lua)
-- and the notification sound (Core/Sound.lua).
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("notifications", function()
  local env, ns, Notify, App, notices

  before_each(function()
    env = wow.install()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Settings.lua",
      "Core/ItemCache.lua",
      "Core/Notices.lua",
      "Core/UI/Tokens.lua",
      "Core/UI/Kit.lua",
      "Core/UI/Layout.lua",
      "Core/UI/Widgets.lua",
      "Core/UI/Help.lua",
      "Core/UI/DataTable.lua",
      "Core/UI/Parts/Primitives.lua",
      "Core/UI/Parts/Chrome.lua",
      "Core/UI/Parts/Composites.lua",
      "Core/UI/Parts/Settings.lua",
      "Core/Sound.lua",
      "Core/UI/App.lua",
      "Core/UI/Screens/Notifications.lua",
      "Core/UI/Pending.lua",
    })
    _G.AME_DB = { settings = {} }
    Notify, App = ns.NotifyScreen, ns.App
    notices = ns.Notices.New({})
    ns.AME = {
      ahOpen = false,
      notices = notices,
      CurrentHouse = function()
        return "Horde"
      end,
      MarketRealmName = function()
        return "Forever"
      end,
      HasData = function()
        return true
      end,
    }
    ns.ShardKey = ns.ShardKey or function(r, h)
      return r .. "|" .. h
    end
  end)

  after_each(function()
    env:restore()
    _G.LibStub = nil
  end)

  describe("rows", function()
    it("each kind has its pill and tone; the item is a link; the age closes the sub line", function()
      local now = 10000
      local alert = Notify.Row({ kind = "alert", text = "dropped to 62g", itemID = 13468, at = now - 720 }, now, true)
      assert.equals("ALERT", alert.pill)
      assert.equals("warn", alert.tone)
      assert.equals(13468, alert.title[1].item)
      assert.is_true(alert.selected)
      assert.matches("12 min", alert.sub)
      local req = Notify.Row({ kind = "request", who = "Ann", at = now }, now, false)
      assert.equals("SHARING", req.pill)
      assert.is_nil(req.selected)
      local craft = Notify.Row({ kind = "craft", who = "Zakzu", text = "asks for 5", itemID = 13444, at = now }, now)
      assert.equals("REQUEST", craft.pill)
      assert.equals(13444, craft.title[2].item)
      assert.equals("NOTE", Notify.Row({ kind = "?", text = "x", at = now }, now).pill)
    end)

    it("newest first, as many as fit, and says how many more", function()
      for i = 1, 5 do
        notices:Add({ kind = "alert", text = "t" .. i, itemID = i }, i * 1000)
      end
      local rows, older = Notify.Rows(notices:List(), 6000, function(e)
        return e.at > 3000
      end, 3)
      assert.equals(3, #rows)
      assert.equals(2, older)
      assert.equals(5, rows[1].title[1].item)
      assert.is_true(rows[1].selected)
      assert.is_nil(rows[3].selected)
    end)

    it("a click opens what it is about", function()
      assert.same({ "item", { item = 7 } }, { Notify.Target({ kind = "alert", itemID = 7 }) })
      assert.equals("sharing", (Notify.Target({ kind = "request" })))
      assert.equals("auctions", (Notify.Target({ kind = "undercut", itemID = 3 })))
      assert.equals("requests", (Notify.Target({ kind = "craft" })))
      assert.is_nil(Notify.Target({ kind = "scan" }))
    end)
  end)

  describe("the screen", function()
    it("opening marks them read and keeps the unread ones lit; a valid tree with and without notices", function()
      App:Show()
      App:Go("notifications")
      assert.same({}, ns.Layout.Validate(App:Tree()))
      env:advance(120)
      notices:Add({ kind = "alert", text = "dropped", itemID = 2589 }, GetServerTime()) -- after that look
      App:Go("home")
      App:Go("notifications")
      local tree = App:Tree()
      assert.same({}, ns.Layout.Validate(tree))
      assert.equals(0, notices:Unread())
      local list = ns.Layout.Find(tree, "notify.list")
      assert.is_true(list.props.rows[1].selected)
      assert.is_not_nil(App.renderer:Frame("notify.list"))
    end)

    it("a row click opens its item; Clear all empties; the bell goes back", function()
      notices:Add({ kind = "alert", text = "dropped", itemID = 2589 }, GetServerTime() - 60)
      App:Show()
      App:Go("home")
      App:Go("notifications")
      local key = Notify.Key(notices:List()[1])
      App.ctx:Dispatch("openNotice", { key = key })
      local id, params = App:Current()
      assert.equals("item", id)
      assert.equals(2589, params.item)
      App:Go("notifications")
      App.ctx:Dispatch("clearAll")
      assert.equals(0, #notices:List())
      App.ctx:Dispatch("bell")
      assert.equals("item", (App:Current()))
    end)

    it("the list's rows are clickable", function()
      notices:Add({ kind = "alert", text = "dropped", itemID = 2589 }, GetServerTime() - 60)
      App:Show()
      App:Go("home")
      App:Go("notifications")
      local f = App.renderer:Frame("notify.list")
      f.rows[1]:GetScript("OnClick")(f.rows[1])
      assert.equals("item", (App:Current()))
    end)
  end)

  describe("waiting outside the window", function()
    it("counts what the bell counts, unless the mark is off", function()
      notices:Add({ kind = "alert", text = "a", itemID = 1 }, 100)
      notices:Add({ kind = "craft", who = "Zakzu", text = "asks for 5", itemID = 2 }, 200)
      assert.equals(2, ns.Pending.Count())
      assert.equals("AME", ns.Pending.Text(0))
      assert.matches("AME .*2", ns.Pending.Text(2))
      ns.Settings:Set("pendingMark", false)
      assert.equals(0, ns.Pending.Count())
    end)

    it("the tooltip lists what waits, the net worth and how old the prices are", function()
      notices:Add({ kind = "alert", text = "dropped to 62g", itemID = 1 }, 100)
      local rows = ns.Pending.TooltipRows(notices:List(), 1, 820, { worth = 48120000, pricesAt = 100 })
      assert.matches("Azeroth Mercantile Exchange", rows[1][1])
      assert.matches("1 waiting on you", rows[2][1])
      assert.matches("dropped to 62g", rows[3][1])
      assert.matches("alert · 12 min ago", rows[3][1])
      assert.matches("Net worth", rows[4][1])
      assert.matches("Left%-click", rows[#rows][1])
      assert.is_nil(ns.Pending.TooltipRows({}, 0, 820))
    end)

    it("updates the broker's text and the minimap mark", function()
      local obj = {}
      local button = CreateFrame("Button", nil, UIParent)
      _G.LibStub = function(name)
        if name == "LibDataBroker-1.1" then
          return {
            GetDataObjectByName = function()
              return obj
            end,
          }
        elseif name == "LibDBIcon-1.0" then
          return {
            GetMinimapButton = function()
              return button
            end,
          }
        end
      end
      ns.Pending.Attach()
      assert.equals("AME", obj.text)
      notices:Add({ kind = "alert", text = "a", itemID = 1 }, 100)
      assert.matches("1", obj.text)
      assert.is_true(button.ameBadge:IsShown())
      notices:MarkRead(200)
      assert.equals("AME", obj.text)
      assert.is_false(button.ameBadge:IsShown())
    end)
  end)

  describe("the sound", function()
    local played
    before_each(function()
      played = {}
      _G.PlaySound = function(kit)
        played[#played + 1] = kit
        return true
      end
    end)
    after_each(function()
      _G.PlaySound = nil
    end)

    it("plays AME's own for the kinds that are on, once for a burst", function()
      assert.is_true(ns.Sound.Play("alert", 10))
      assert.is_false(ns.Sound.Play("craft", 11)) -- within the gap
      assert.is_true(ns.Sound.Play("craft", 20))
      assert.is_false(ns.Sound.Play("auction", 30)) -- off by default
      assert.equals(2, #played)
      ns.Settings:Set("alertSound", false)
      assert.is_false(ns.Sound.Play("alert", 40))
    end)

    it("a picked sound from a pack that is gone falls back to AME's", function()
      ns.Settings:Set("notifySound", "Gone")
      assert.equals(ns.Sound.DEFAULT, ns.Sound.Chosen())
    end)
  end)
end)
