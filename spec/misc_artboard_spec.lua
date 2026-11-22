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

end)
