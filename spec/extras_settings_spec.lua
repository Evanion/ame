-- Settings behind the cog (Core/UI/Screens/Settings.lua) and the settingscard widget (Core/UI/Parts/Settings.lua):
-- the board's cards, what a change saves and does, LibSharedMedia's lists, and a valid tree for every section.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("Settings screen", function()
  local env, ns, S, App

  local function fakeLSM(lists)
    local media = { registered = {} }
    function media:List(kind)
      return lists[kind] or {}
    end
    function media:Register(kind, name, data)
      self.registered[#self.registered + 1] = { kind, name, data }
      lists[kind] = lists[kind] or {}
      table.insert(lists[kind], name)
    end
    function media:IsValid(kind, name)
      for _, n in ipairs(lists[kind] or {}) do
        if n == name then
          return true
        end
      end
      return false
    end
    function media:Fetch(kind, name)
      return "path/" .. kind .. "/" .. name
    end
    return media
  end

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
      "Core/UI/Help.lua",
      "Core/UI/DataTable.lua",
      "Core/UI/Parts/Primitives.lua",
      "Core/UI/Parts/Chrome.lua",
      "Core/UI/Parts/Composites.lua",
      "Core/UI/Parts/Settings.lua",
      "Core/Sound.lua",
      "Core/UI/App.lua",
      "Core/UI/Screens/Settings.lua",
    })
    _G.AME_DB = { settings = { minimap = { hide = false } } }
    S, App = ns.SettingsScreen, ns.App
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
    ns.ShardKey = ns.ShardKey or function(r, h)
      return r .. "|" .. h
    end
  end)

  after_each(function()
    env:restore()
    _G.LibStub = nil
  end)

  local function rowByKey(cards, key)
    for _, c in ipairs(cards) do
      for _, r in ipairs(c.rows) do
        if r.key == key then
          return r, c
        end
      end
    end
  end

  it("General has the board's four cards, in order, with the new keys' defaults", function()
    local cards = S.Cards("general", { sounds = { "AME (default)" }, sound = "AME (default)", minimapLib = true })
    assert.same({ "Window", "Fonts and bars", "Notifications", "Other addons" }, {
      cards[1].title,
      cards[2].title,
      cards[3].title,
      cards[4].title,
    })
    assert.equals("ame", rowByKey(cards, "ahMode").value)
    assert.is_true(rowByKey(cards, "openWithAH").off) -- only with the game's window
    assert.is_true(rowByKey(cards, "queueTracker").checked)
    assert.is_true(rowByKey(cards, "pendingMark").checked)
    assert.is_false(rowByKey(cards, "soundAuction").checked)
    assert.is_true(rowByKey(cards, "minimap").checked)
    assert.equals("", rowByKey(cards, "fontText").value)
    assert.equals("Arial Narrow (AME)", rowByKey(cards, "fontText").options[1].label)
  end)

  it("the minimap check says what it needs when LibDBIcon is missing", function()
    local r = rowByKey(S.Cards("general", {}), "minimap")
    assert.is_true(r.off)
    assert.matches("LibDBIcon", r.check)
  end)

  it("fonts, bars and sounds come from LibSharedMedia, AME's own first", function()
    local lists = { font = { "Friz Quadrata TT", "Expressway" }, statusbar = { "Blizzard" }, sound = { "None", "Bell" } }
    local media = fakeLSM(lists)
    _G.LibStub = function(name)
      return name == "LibSharedMedia-3.0" and media or nil
    end
    local sounds = ns.Sound.List()
    assert.equals("AME (default)", sounds[1])
    assert.equals(3, #media.registered) -- AME's own, by file ID
    assert.equals("number", type(media.registered[1][3]))
    local cards = S.Cards("general", { sounds = sounds, sound = ns.Sound.Chosen() })
    local font = rowByKey(cards, "fontText")
    assert.equals("Expressway", font.options[3].label)
    assert.equals("Blizzard", rowByKey(cards, "barTexture").options[2].value)
    ns.Settings:Set("fontText", "Expressway")
    assert.equals("path/font/Expressway", S.FontPath("text"))
    assert.is_nil(S.FontPath("heading"))
  end)

  it("a change is saved and does what it does; a bad cut is refused", function()
    local played
    ns.Sound.Preview = function(name)
      played = name
    end
    assert.is_true(S.Apply("ahMode", "game"))
    assert.equals("game", ns.Settings:Get("ahMode"))
    assert.is_true(S.Apply("notifySound", "Bell"))
    assert.equals("Bell", played)
    assert.is_true(S.Apply("cutFaction", "7"))
    assert.equals(7, ns.Settings:Get("cutFaction"))
    assert.is_false(S.Apply("cutFaction", "200"))
    assert.equals(7, ns.Settings:Get("cutFaction"))
    assert.is_true(S.Apply("outlierFactor", false))
    assert.is_false(ns.Settings:Get("outlierFactor"))
    assert.is_true(S.Apply("notifySound", ns.Sound.DEFAULT))
    assert.equals("", ns.Settings:Get("notifySound"))
  end)

  it("the other sections have their cards", function()
    assert.equals("Tooltips", S.Cards("display", { hidden = 2 })[1].title)
    assert.is_false(S.Cards("display", { hidden = 2 })[3].rows[2].buttons[1].off)
    assert.equals("Selling", S.Cards("selling")[1].title)
    assert.equals("%", S.Cards("selling")[1].rows[1].suffix)
    assert.equals("Data", S.Cards("data", { summary = "x" })[1].title)
  end)

  describe("the settingscard widget", function()
    local r, got
    before_each(function()
      got = {}
      local ctx = ns.Layout.Context({
        setting = function(p)
          got[#got + 1] = p
        end,
      })
      local root = CreateFrame("Frame", nil, UIParent)
      root:SetSize(560, 400)
      r = ns.Layout.Renderer(root, ctx)
    end)

    it("draws every kind of row and dispatches the setting a check changes", function()
      local tree = {
        id = "c",
        type = "settingscard",
        props = {
          title = "Window",
          width = 560,
          rows = {
            { check = "Show minimap button", key = "minimap", checked = true },
            { field = "Scale", key = "windowScale", value = 1, options = { { value = 1, label = "100%" } } },
            { text = "Some words." },
            { input = "", label = "Cut", key = "cutFaction", value = "5", suffix = "%", numeric = true },
            { name = "Yuki", note = "asks to share", buttons = { "Approve", "Decline" } },
            { buttons = { { label = "Rebuild", action = "rebuild" } } },
          },
        },
      }
      assert.same({}, ns.Layout.Validate(tree))
      r:Render(tree)
      local f = r:Frame("c")
      assert.is_true(f.natural > 100)
      local check = f.pool.check[1].check
      check:GetScript("OnClick")(check)
      assert.same({ key = "minimap", value = false }, got[1])
      assert.equals("100%", f.pool.field[1].button.label:GetText())
    end)

    it("a faded row does nothing", function()
      r:Render({ id = "c", type = "settingscard", props = { rows = { { check = "x", key = "k", off = true } } } })
      local check = r:Frame("c").pool.check[1].check
      check:GetScript("OnClick")(check)
      assert.equals(0, #got)
    end)
  end)

  describe("the screen", function()
    for _, section in ipairs({ "general", "display", "selling", "data", "sharing" }) do
      it("draws a valid tree for " .. section, function()
        App:Show()
        App:Go("settings", { section = section })
        assert.same({}, ns.Layout.Validate(App:Tree()))
        assert.is_not_nil(App.renderer:Frame("settings.card1"))
      end)
    end

    it("a section is picked without a history step; a setting redraws", function()
      App:Show()
      App:Go("home")
      App:Go("settings")
      local steps = #App.back
      App.ctx:Dispatch("section", { key = "selling" })
      local id, params = App:Current()
      assert.equals("settings", id)
      assert.equals("selling", params.section)
      assert.equals(steps, #App.back)
      App.ctx:Dispatch("setting", { key = "listingHours", value = 8 })
      assert.equals(8, ns.Settings:Get("listingHours"))
    end)
  end)
end)
