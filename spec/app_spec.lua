-- Core/UI/App.lua: the redesigned window - chrome around the current screen, tabs, back and forward through what
-- you opened, the auction house's tabs while it's open, and every screen's tree valid.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("the redesigned window", function()
  local env, ns, App

  before_each(function()
    env = wow.install()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Settings.lua",
      "Core/ItemCache.lua",
      "Core/UI/Tokens.lua",
      "Core/UI/Kit.lua",
      "Core/UI/Layout.lua",
      "Core/UI/Widgets.lua",
      "Core/UI/Parts/Primitives.lua",
      "Core/UI/Parts/Chrome.lua",
      "Core/UI/App.lua",
    })
    _G.AME_DB = { settings = {} }
    ns.AME = {
      ahOpen = false,
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
    ns.ShardKey = ns.ShardKey or function(realm, house)
      return realm .. "|" .. house
    end
    App = ns.App
    App.Screen("home", {
      tab = "home",
      Build = function()
        return { id = "home", type = "text", props = { text = "Home" } }
      end,
      Status = function()
        return "home status"
      end,
    })
    App.Screen("market", {
      tab = "market",
      Build = function(_, params)
        return { id = "market", type = "text", props = { text = "Market " .. tostring(params.view) } }
      end,
      actions = {
        view = function(app, p)
          app:Set({ view = p.key })
        end,
      },
    })
  end)

  after_each(function()
    env:restore()
  end)

  local function title()
    return App.renderer:Frame("app.title")
  end

  it("the status row says the same busy news once", function()
    ns.AME.ahOpen = true
    ns.ScanButton = { Progress = function() return "Updating market data..." end }
    ns.UI = { FooterRight = function() return "Updating market data\226\128\166    vdev" end }
    local text = ns.App.StatusRight()
    local _, n = text:gsub("Updating market data", "")
    assert.equals(1, n)
    ns.ScanButton = { Progress = function() return "Reading auctions 40%" end }
    assert.matches("Reading auctions 40%%", ns.App.StatusRight())
    ns.ScanButton, ns.UI, ns.AME.ahOpen = nil, nil, false
  end)

  it("a beta's escape hatch: with a profession taken over, a failing screen offers the game's window", function()
    local used
    ns.CraftingSidecar = {
      TookOver = function()
        return true
      end,
      UseGameWindow = function()
        used = true
      end,
    }
    ns.App.Screen("boom", {
      Build = function()
        error("broken")
      end,
    })
    App:Show()
    App:Go("boom")
    local tree = App:Tree()
    local b = ns.Layout.Find(tree, "error.gamewindow")
    assert.is_not_nil(b)
    App.ctx:Dispatch(b.props.action)
    assert.is_true(used)
    ns.CraftingSidecar = nil
    ns.App.screens.boom = nil
  end)

  it("opens on Home with the chrome around it", function()
    App:Show()
    assert.equals("home", App:Current())
    assert.equals("Home", App.renderer:Frame("home").fs:GetText())
    assert.equals("home status", App.renderer:Frame("app.status").text:GetText())
    assert.matches("Azeroth", title().brand:GetText())
    assert.same({}, ns.Layout.Validate(App:Tree()))
  end)

  it("a tab opens its screen, and back and forward walk what you opened", function()
    App:Show()
    App.ctx:Dispatch("tab", { key = "market" })
    assert.equals("market", App:Current())
    App.ctx:Dispatch("tab", { key = "crafting" })
    assert.equals("crafting", App:Current()) -- not built yet: the placeholder draws it
    assert.is_not_nil(App.renderer:Frame("soon"))
    App.ctx:Dispatch("back")
    assert.equals("market", App:Current())
    App.ctx:Dispatch("back")
    assert.equals("home", App:Current())
    App.ctx:Dispatch("forward")
    assert.equals("market", App:Current())
    assert.is_true(title().props.back)
    assert.is_true(title().props.forward)
  end)

  it("a screen's own action changes its params without a history step", function()
    App:Show()
    App:Go("market")
    App.ctx:Dispatch("view", { key = "overview" })
    assert.equals("Market overview", App.renderer:Frame("market").fs:GetText())
    App.ctx:Dispatch("back")
    assert.equals("home", App:Current())
  end)

  it("the cog opens Settings, and on Settings goes back", function()
    App:Show()
    App:Go("market")
    App.ctx:Dispatch("settings")
    assert.equals("settings", App:Current())
    App.ctx:Dispatch("settings")
    assert.equals("market", App:Current())
  end)

  it("hangs the auction house's tabs under the window while it's open", function()
    App:Show()
    assert.is_false(App.ahFrame:IsShown())
    ns.AME.ahOpen = true
    App:Go("market")
    assert.is_true(App.ahFrame:IsShown())
    assert.equals("buy", App.ahRenderer.top.item.props.active)
    assert.is_true(title().props.ah)
    -- the title bar keeps Full scan; "Use the game's AH" is at the tabs' right end
    assert.is_nil(title().gameAH)
    local tabs = App.ahRenderer:Frame("ah.tabs")
    local swapped
    App.actions.gameAH, App.actions.realGameAH = function()
      swapped = true
    end, App.actions.gameAH
    tabs.gameAH:GetScript("OnClick")(tabs.gameAH)
    App.actions.gameAH = App.actions.realGameAH
    App.actions.realGameAH = nil
    assert.is_true(swapped)
  end)

  it("folds the title bar in a narrow window", function()
    App:Show()
    App.frame:SetSize(800, 500)
    App.frame.scripts.OnSizeChanged(App.frame, 800, 500)
    App:Render()
    assert.equals("AME", title().brand:GetText())
  end)
end)
