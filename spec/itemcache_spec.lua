local addon = require("spec.helpers.addon")

describe("ItemCache with random-suffix variants", function()
  local ns, C, saved
  local magicLink = "|cff1eff00|Hitem:15211::::::1234::60:::::|h[Raider Shortsword of Magic]|h|r"

  before_each(function()
    saved = { C_Item = _G.C_Item, CreateFrame = _G.CreateFrame, C_Timer = _G.C_Timer }
    _G.C_Item = {
      GetItemInfo = function(id)
        if id == 15211 then
          return "Raider Shortsword",
            "|cff1eff00|Hitem:15211::::::::60:::::|h[Raider Shortsword]|h|r",
            2,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            135321,
            425
        end
        if type(id) == "number" and id < 1000000 then
          return "Item " .. id, nil, 1, nil, nil, nil, nil, nil, nil, 134400, 5
        end
        return nil -- the client knows nothing by a composite key
      end,
      GetItemInfoInstant = function(id)
        if id == "Linen Cloth" then
          return 2589
        end
        if type(id) == "number" and id < 1000000 then
          return id, "Weapon", "Swords", "", 135321, 2, 7
        end
      end,
    }
    _G.CreateFrame = function()
      return { RegisterEvent = function() end, SetScript = function() end }
    end
    _G.C_Timer = { After = function() end }
    ns = addon.load({ "Core/Init.lua", "Core/ItemCache.lua" })
    C = ns.ItemCache
    C.Init({})
  end)

  after_each(function()
    for k, v in pairs(saved) do
      _G[k] = v
    end
  end)

  it("learns a variant's name from its link, and keeps the base item's facts", function()
    local key = C.Learn(magicLink)
    assert.are.equal(ns.ItemKey(15211, 1234), key)
    local e = C.Get(key)
    assert.are.equal("Raider Shortsword of Magic", e.name)
    assert.are.equal(2, e.classID) -- from the base item
    assert.are.equal(425, e.sellPrice)
    assert.are.equal(2, e.quality)
    assert.are.equal("Raider Shortsword of Magic", C.Name(key))
    local link = C.Link(key)
    assert.truthy(link:find("item:15211::::::1234", 1, true), link)
    assert.truthy(link:find("[Raider Shortsword of Magic]", 1, true), link)
    -- plain items are unchanged
    assert.are.equal(2589, C.Learn("|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r"))
    assert.are.equal("Item 2589", C.Name(2589))
  end)

  it("pairs a Forever link with its auction item key: names the variant and maps the link's bonus", function()
    local forever = "|cff1eff00|Hitem:15211::::::::1:1488:::1:12917::::::|h[Raider Shortsword of Magic]|h|r"
    local key = C.Pair(forever, 15211, 14324)
    assert.are.equal(ns.ItemKey(15211, 14324), key)
    assert.are.equal("Raider Shortsword of Magic", C.Get(key).name)
    assert.are.equal(key, ns.ItemIDFrom(forever)) -- any later link of it (tooltips, chat) finds the variant
    assert.are.equal("item:15211::::::::1:1488:::1:12917::::::", ns.ItemString(key))
  end)

  it("asks the game for a scanned variant's link through its item key's tooltip", function()
    _G.C_TooltipInfo = {
      GetItemKey = function(itemID, _, suffix)
        if itemID == 15211 and suffix == 14324 then
          local link = "|cff1eff00|Hitem:15211::::::::1:1488:::1:12917::::::|h[Raider Shortsword of Magic]|h|r"
          return { lines = { { hyperlink = link } } }
        end
      end,
    }
    local key = ns.ItemKey(15211, 14324)
    assert.are.equal("Raider Shortsword of Magic", C.Get(key).name)
    assert.are.equal(key, C.KeyByName("Raider Shortsword of Magic"))
    _G.C_TooltipInfo = nil
  end)

  it("keys an item location by the auction house's item key for it", function()
    local link = "|cff1eff00|Hitem:15211::::::::1:1488:::1:12917::::::|h[Raider Shortsword of Magic]|h|r"
    _G.C_Item.GetItemLink = function()
      return link
    end
    _G.C_Item.GetItemID = function()
      return 15211
    end
    _G.C_AuctionHouse = {
      GetItemKeyFromItem = function()
        return { itemID = 15211, itemLevel = 25, itemSuffix = 14324 }
      end,
    }
    assert.are.equal(ns.ItemKey(15211, 14324), C.KeyAt({}))
    assert.are.equal(ns.ItemKey(15211, 14324), ns.ItemIDFrom(link)) -- learned on the way
    _G.C_AuctionHouse = nil
  end)

  it("shows the base name until a variant's own name is learned", function()
    local key = ns.ItemKey(15211, 1234)
    assert.are.equal("Raider Shortsword", C.Get(key).name)
    C.Learn(magicLink)
    assert.are.equal("Raider Shortsword of Magic", C.Get(key).name)
  end)

  it("finds a variant by its full name, and keeps learned names across reloads", function()
    local saved_ = {}
    C.Init(saved_)
    local key = C.Learn(magicLink)
    assert.are.equal(key, C.KeyByName("Raider Shortsword of Magic"))
    assert.are.equal(2589, C.KeyByName("Linen Cloth"))
    assert.are.equal(key, C.KeyFor(15211, "Raider Shortsword of Magic"))
    assert.are.equal(15211, C.KeyFor(15211, "Raider Shortsword of the Monkey")) -- not learned: the plain item
    assert.are.equal(2589, C.KeyFor(2589, "Raider Shortsword of Magic")) -- another item's name: ignored
    -- a reload
    ns.ItemCache.info = {}
    C.Init(saved_)
    assert.are.equal(key, C.KeyByName("Raider Shortsword of Magic"))
    assert.are.equal("Raider Shortsword of Magic", C.Get(key).name)
  end)
end)
