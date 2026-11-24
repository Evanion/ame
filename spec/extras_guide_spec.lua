-- The Guide screen (Core/UI/Screens/Guide.lua): the articles in the board's order, search, the open buttons and See
-- also, and a valid tree for an article, the auction house article, a glossary term and a search.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("Guide screen", function()
  local env, ns, Guide, App

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
      "Core/UI/App.lua",
      "Core/UI/Screens/Guide.lua",
    })
    _G.AME_DB = { settings = {} }
    Guide, App = ns.GuideScreen, ns.App
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
  end)

  it("orders the articles as the board does, with the auction house article and the glossary last", function()
    local groups = Guide.Groups()
    assert.equals("start", groups[1].articles[1].key)
    assert.equals("Tabs", groups[2].title)
    local keys = {}
    for _, a in ipairs(groups[2].articles) do
      keys[#keys + 1] = a.key
    end
    assert.equals("tabMarket", keys[1])
    local ah
    for i, k in ipairs(keys) do
      if k == "ah" then
        ah = i
      end
    end
    assert.is_not_nil(ah)
    assert.equals("tabItem", keys[ah - 1])
    assert.equals("glossary", groups[#groups].articles[1].key)
    assert.is_true(#groups[#groups].terms > 20)
  end)

  it("the sidebar picks the shown article; a term lights the glossary; a search narrows it", function()
    local groups = Guide.Groups()
    local entries = Guide.Entries(groups, "tabItem")
    local picked
    for _, e in ipairs(entries) do
      if e.selected then
        picked = e.key
      end
    end
    assert.equals("tabItem", picked)
    assert.matches("Glossary · %d+ terms", entries[#entries - 1].label)
    picked = nil
    for _, e in ipairs(Guide.Entries(groups, "candles")) do
      if e.selected then
        picked = e.key
      end
    end
    assert.equals("glossary", picked)
    local found = Guide.Entries(groups, nil, "candles")
    local keys = {}
    for _, e in ipairs(found) do
      if e.key then
        keys[e.key] = true
      end
    end
    assert.is_true(keys.candles) -- the term itself, while searching
    assert.is_true(keys.tabItem)
    assert.is_nil(keys.commands)
    assert.equals("No articles match", Guide.Entries(groups, nil, "zzqqxx")[1].label)
  end)

  it("an article opens its screen and links the ones to read next", function()
    local groups = Guide.Groups()
    local byKey = Guide.Index(groups)
    local blocks = Guide.Blocks(byKey.tabItem, byKey)
    assert.equals("Open the Item tab", blocks[1].buttons[1].label)
    assert.equals("item", blocks[1].buttons[1].payload.screen)
    local last = blocks[#blocks]
    assert.equals("ah", last.links[1].key)
    assert.equals("See also", blocks[#blocks - 1].h)
    local ex = false
    for _, b in ipairs(blocks) do
      ex = ex or b.example == "candleAnatomy"
    end
    assert.is_true(ex)
  end)

  describe("the screen", function()
    for _, case in ipairs({
      { "an article", { article = "tabItem" } },
      { "the auction house", { article = "ah" } },
      { "a glossary term", { article = "candles" } },
      { "a search", { search = "scan" } },
      { "nothing picked", {} },
    }) do
      it("draws a valid tree for " .. case[1], function()
        App:Show()
        App:Go("guide", case[2])
        assert.same({}, ns.Layout.Validate(App:Tree()))
        assert.is_not_nil(App.renderer:Frame("guide.article"))
      end)
    end

    it("an article link is a step in the history; the search keeps to what matches", function()
      App:Show()
      App:Go("guide", { article = "tabItem" })
      App.ctx:Dispatch("article", { key = "ah" })
      local id, params = App:Current()
      assert.equals("guide", id)
      assert.equals("ah", params.article)
      App.ctx:Dispatch("guideSearch", { text = "candles" })
      params = select(2, App:Current())
      assert.equals("candles", params.search)
      assert.is_true(Guide.Matches(Guide.Index(Guide.Groups())[params.article], "candles"))
      App.ctx:Dispatch("openScreen", { screen = "item" })
      assert.equals("item", (App:Current()))
    end)
  end)
end)
