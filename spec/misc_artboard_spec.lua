-- Small features from the design's artboards, each in the real addon in a stubbed client: the Arbitrage column
-- chooser, the Shopping tab's Time left, the Overview's largest items, and the next announce on the Sharing status.
local wow = require("spec.helpers.wow")

local f = io.open("Libs/LibDeflate/LibDeflate.lua", "r")
local haveLibs = f ~= nil
if f then
  f:close()
end

describe("artboard features", function()
  if not haveLibs then
    pending("Libs missing; run scripts/fetch-libs.sh")
    return
  end

  local env, ns

  local function boot()
    env = wow.install()
    ns = wow.loadAddon("AzerothMercantileExchange.toc", "AzerothMercantileExchange")
    ns.AME.syncTransport = { Register = function() end, Send = function() end } -- sync on, sending nowhere
    env:fire("ADDON_LOADED", "AzerothMercantileExchange")
    env:fire("PLAYER_LOGIN")
  end

  local function drainJobs()
    for _ = 1, 5000 do
      if not ns.AME.jobs:Busy() then
        return
      end
      env:update(1)
    end
    error("jobs did not finish")
  end

  local function fullScan(rows)
    env.ah.rows = rows
    C_AuctionHouse.ReplicateItems()
    for _ = 1, 30 do
      env:fire("REPLICATE_ITEM_LIST_UPDATE")
    end
    drainJobs()
  end

  after_each(function()
    if env then
      env:restore()
    end
  end)

  -- the menu entry whose text has `word`
  local function menuItem(word)
    for _, it in ipairs(ns.Widgets.menu.items) do
      if it:IsShown() and (it.text.text or ""):find(word, 1, true) then
        return it
      end
    end
  end

  it("Arbitrage: a Columns button hides and shows columns, as the screener's does", function()
    boot()
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    fullScan({ { 2589, 1000, 10 } })
    env:fire("AUCTION_HOUSE_CLOSED")
    env.now = env.now + 60
    env.npcFaction = nil
    env:fire("AUCTION_HOUSE_SHOW")
    fullScan({ { 2589, 3000, 10 } })
    env:advance(4)
    drainJobs()
    ns.UI:Toggle()
    ns.UI:ShowTab("arbitrage")
    local v = ns.UI.arbView
    v.scripts.OnShow(v)
    drainJobs()
    local t = v.table
    assert.are.equal(t:ColumnsLabel(), v.columns.label.text) -- counts the ones dropped for room too
    assert.is_true(v.columns:IsShown())
    -- the chooser lists every column but the item; switching one off saves it and hides it
    v.columns.scripts.OnClick(v.columns)
    assert.is_nil(menuItem("Item"))
    local margin = menuItem("Margin")
    assert.is_not_nil(margin)
    margin.scripts.OnClick(margin)
    assert.is_false(AME_DB.settings.arbColumns.margin)
    assert.is_true(ns.DataTable.ChosenHidden(t.opts.columns, "arbColumns").margin)
    local marginIndex
    for c, col in ipairs(t.opts.columns) do
      if col.key == "margin" then
        marginIndex = c
      end
    end
    assert.is_true(t.hiddenColumns[marginIndex])
    assert.truthy(v.columns.label.text:find("hidden", 1, true), v.columns.label.text)
    assert.are.equal(t:ColumnsLabel(), v.columns.label.text)
    -- and back on
    v.columns.scripts.OnClick(v.columns)
    margin = menuItem("Margin")
    margin.scripts.OnClick(margin)
    assert.is_true(AME_DB.settings.arbColumns.margin)
    assert.is_nil(t.hiddenColumns[marginIndex])
    -- the compact toolbar has no room for it
    v:SetCompact(true)
    assert.is_false(v.columns:IsShown())
    v:SetCompact(false)
    assert.is_true(v.columns:IsShown())
    -- the screener's chooser works as before (the same shared menu)
    ns.UI:ShowTab("market")
    local mv = ns.UI.marketView
    ns.UI:ColumnMenu(mv.columns)
    local phase = menuItem("Phase")
    phase.scripts.OnClick(phase)
    assert.is_true(AME_DB.settings.marketColumns.phase)
    assert.is_nil(ns.UI:MarketHiddenColumns().phase)
  end)

  it("Shopping: each listing's time left, from what the game says about it", function()
    boot()
    local S = ns.AHSearch
    -- the game's search results: commodities give seconds, gear a band
    local api = {
      GetNumCommoditySearchResults = function(id)
        return id == 2589 and 2 or 0
      end,
      GetCommoditySearchResultInfo = function(_, i)
        return ({
          { unitPrice = 100, quantity = 5, timeLeftSeconds = 23 * 3600 + 120 },
          { unitPrice = 120, quantity = 3 }, -- the client said nothing
        })[i]
      end,
      MakeItemKey = function(id)
        return { itemID = id }
      end,
      GetNumItemSearchResults = function(key)
        return key.itemID == 4306 and 1 or 0
      end,
      GetItemSearchResultInfo = function()
        return { buyoutAmount = 5000, quantity = 1, auctionID = 7, timeLeft = 2 }
      end,
    }
    local book = S.Book(api, 2589)
    book.at = 1000
    assert.are.equal(23 * 3600 + 120, book.rows[1].timeLeft)
    -- counted from the search: an hour later, an hour less
    assert.are.equal(22 * 3600 + 120, (S.TimeLeft(book, book.rows[1], 1000 + 3600)))
    assert.is_nil(S.TimeLeft(book, book.rows[1], 1000 + 24 * 3600)) -- run out: sold or expired, not known
    local left, band = S.TimeLeft(book, book.rows[2], 1000)
    assert.is_nil(left)
    assert.is_nil(band)
    local gear = S.Book(api, 4306)
    left, band = S.TimeLeft(gear, gear.rows[1], 1000)
    assert.is_nil(left)
    assert.are.equal(2, band)
    -- drawn as the design has it: "23 h", minutes under an hour, the band's range, nothing when not known
    local T = ns.AHShopping
    assert.are.equal("23 h", T.TimeLeftText(23 * 3600 + 120))
    assert.are.equal("40 min", T.TimeLeftText(40 * 60 + 5))
    assert.are.equal("2-12 h", T.TimeLeftText(nil, 2))
    assert.are.equal("under 30 min", T.TimeLeftText(nil, 0))
    assert.are.equal("", T.TimeLeftText(nil, nil))
  end)

end)
