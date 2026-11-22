-- The item tooltip's artboard features (TooltipTrade / TooltipGear and their Shift views): the signal's reason, what
-- to post at with its sell chance and the deposit on gear, the goblin AH's sales and data age, and "alt there".
local addon = require("spec.helpers.addon")
local wow = require("spec.helpers.wow")

local function text(rows)
  local out = {}
  for _, r in ipairs(rows) do
    local mids = {}
    local k = 3
    while r[k] ~= nil do
      table.insert(mids, 1, r[k] .. " | ")
      k = k + 1
    end
    out[#out + 1] = (r[1] or "") .. " = " .. table.concat(mids) .. (r[2] or "")
  end
  return (table.concat(out, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

describe("Tooltip artboard features", function()
  local T
  before_each(function()
    local ns = addon.load({ "Core/Init.lua", "Core/UI/Widgets.lua", "Core/UI/Tooltip.lua" })
    T = ns.Tooltip
  end)

  local s = { market = 12000, min = 11400, avg7 = 11100, avg30 = 11000, qty = 140, score = 12, day = 100 }
  local function with(fields)
    return setmetatable(fields, { __index = s })
  end

  it("gives the signal its reason: the market phase in words", function()
    local t = text(T.Lines(with({ signal = "buy", phase = "tightening" }), {}))
    assert.truthy(t:find("BUY  supply falling, price steady = Shift: more", 1, true), t)
    t = text(T.Lines(with({ signal = "sell", phase = "shortage" }), {}))
    assert.truthy(t:find("SELL  supply falling, price rising", 1, true), t)
  end)

  it("says how much disenchanting or a vendor beats listing by", function()
    local t = text(T.Lines(with({ signal = "disenchant", deValue = 9900, vendorNet = 6500, phase = "weak" }), {}))
    assert.truthy(t:find("disenchanting beats listing by 34s", 1, true), t)
    assert.is_nil(t:find("price falling", 1, true)) -- the DE reason, not the phase
    t = text(T.Lines(with({ signal = "vendor", vendorPrice = 500, vendorNet = 380 }), {}))
    assert.truthy(t:find("a vendor beats listing by 1s 20c", 1, true), t)
  end)

  it("compact: the goblin AH takes the reason's place when it pays better", function()
    local buy = with({ signal = "buy", phase = "tightening" })
    local t = text(T.Lines(buy, { compact = true, better = 0.16 }))
    assert.truthy(t:find("BUY  ·  goblin AH +16% = Shift: more", 1, true), t)
    assert.is_nil(t:find("supply falling", 1, true))
    assert.truthy(text(T.Lines(buy, { compact = true })):find("BUY  supply falling, price steady", 1, true))
  end)

  it("with Shift: Post at (Normal), how soon it sells and its chance; the deposit only when given (gear)", function()
    local post = { label = "Normal", price = 11800, chance = 0.71, hours = 6 }
    local t = text(T.Lines(s, { detail = true, post = post }))
    assert.truthy(t:find("Post at (Normal) = 1g 18s", 1, true), t)
    assert.truthy(t:find("sells in ~6h · 71% chance = \n", 1, true), t) -- nothing on the right
    assert.is_nil(t:find("deposit", 1, true))
    post.deposit = 800
    t = text(T.Lines(s, { detail = true, post = post }))
    assert.truthy(t:find("sells in ~6h · 71% chance = deposit 8s", 1, true), t)
    assert.is_nil(text(T.Lines(s, { detail = true })):find("Post at", 1, true)) -- too little data: no row
    assert.is_nil(text(T.Lines(s, { post = post })):find("Post at", 1, true)) -- only with Shift
  end)

  it("lists the lowest listing first, then the average", function()
    local t = text(T.Lines(s, { detail = true, avgDays = 7 }))
    local lowest, avg = t:find("Lowest listing", 1, true), t:find("7-day average", 1, true)
    assert.truthy(lowest and avg and lowest < avg, t)
  end)

  local houses = {
    { house = "Horde", label = "Horde AH", market = 12000, net = 11400, cut = 0.05, mine = true },
    { house = "Neutral", label = "Goblin AH", market = 15500, net = 13200, cut = 0.15, sold = 30, age = "6 h ago" },
    { house = "Alliance", label = "Alliance AH", market = 10500, net = 10000, cut = 0.05, alt = true },
  }

  it("marks the other faction's house where one of your characters is, and the goblin AH's sales and age", function()
    local t = text(T.Lines(s, { detail = true, houses = houses }))
    assert.truthy(t:find("Horde AH (5%) = 1g 20s | 1g 14s", 1, true), t)
    assert.truthy(t:find("Goblin AH (15%) +16% = 1g 55s | 1g 32s", 1, true), t)
    assert.truthy(t:find("Alliance AH (alt there) = 1g 5s | 1g", 1, true), t)
    assert.truthy(t:find("Goblin AH sells 30/day, scanned 6 h ago", 1, true), t)
    assert.truthy(t:find("PRICE", 1, true), t) -- several houses: the price has its own section
  end)

  it("says what it knows of the goblin AH: its rate, its age, or no data", function()
    local only = {
      houses[1],
      { house = "Neutral", label = "Goblin AH", market = 15500, net = 13200, cut = 0.15, age = "today" },
    }
    local t = text(T.Lines(s, { detail = true, houses = only }))
    assert.truthy(t:find("Goblin AH scanned today", 1, true), t)
    only[2] = { house = "Neutral", label = "Goblin AH", market = 15500, net = 13200, cut = 0.15, sold = 0.4 }
    assert.truthy(text(T.Lines(s, { detail = true, houses = only })):find("Goblin AH sells 0.4/day", 1, true))
    -- your house and the other faction's only: the goblin AH row says no data
    t = text(T.Lines(s, { detail = true, houses = { houses[1], houses[3] }, noGoblin = true }))
    assert.truthy(t:find("Goblin AH = no data", 1, true), t)
  end)

  it("one house priced: its section is Auction houses, naming it, with the goblin AH's no data", function()
    local t = text(T.Lines(s, { detail = true, house = "Horde AH", houses = { houses[1] }, noGoblin = true }))
    assert.truthy(t:find("AUCTION HOUSES = ", 1, true), t)
    assert.is_nil(t:find("PRICE", 1, true))
    assert.truthy(t:find("Lowest listing (Horde AH) = 1g 14s", 1, true), t)
    assert.truthy(t:find("Goblin AH = no data", 1, true), t)
    assert.is_nil(t:find("after each one's cut", 1, true))
  end)
end)

describe("Holdings.Factions", function()
  it("names the factions of your characters that have logged in", function()
    local H = addon.load({ "Core/Init.lua" }).Holdings
    local holdings = {
      ["PvP:Mainchar"] = { faction = "Horde", bags = {} },
      ["PvP:Bankalt"] = { faction = "Alliance" },
      ["PvP:Crafter"] = { bags = {} }, -- not logged in since factions were recorded
      ["PvE:Other"] = { faction = "Alliance" },
    }
    assert.are.same({ Horde = true, Alliance = true }, H.Factions(holdings))
    local pvp = function(key)
      return key:sub(1, 4) == "PvP:"
    end
    assert.are.same({ Horde = true, Alliance = true }, H.Factions(holdings, pvp))
    holdings["PvP:Bankalt"] = nil
    assert.are.same({ Horde = true }, H.Factions(holdings, pvp))
    assert.are.same({}, H.Factions(nil))
  end)
end)

describe("Tooltip.Gather in a stubbed client", function()
  local f = io.open("Libs/LibDeflate/LibDeflate.lua", "r")
  if not f then
    pending("Libs missing; run scripts/fetch-libs.sh")
    return
  end
  f:close()

  local env, ns
  after_each(function()
    if env then
      env:restore()
    end
  end)

  local function drainJobs()
    for _ = 1, 5000 do
      if not ns.AME.jobs:Busy() then
        return
      end
      env:update(1)
    end
    error("jobs did not finish")
  end

  local function scanAt(faction, rows)
    env.npcFaction = faction
    env:fire("AUCTION_HOUSE_SHOW")
    env.ah.rows = rows
    C_AuctionHouse.ReplicateItems()
    for _ = 1, 30 do
      env:fire("REPLICATE_ITEM_LIST_UPDATE")
    end
    drainJobs()
    env:fire("AUCTION_HOUSE_CLOSED")
  end

  it("gathers the goblin AH's rate and age, alt there, what to post at, and records your faction", function()
    env = wow.install()
    ns = wow.loadAddon("AzerothMercantileExchange.toc", "AzerothMercantileExchange")
    env:fire("ADDON_LOADED", "AzerothMercantileExchange")
    env:fire("PLAYER_LOGIN")
    env.sellPrices[2589] = 10
    scanAt("Horde", { { 2589, 1000, 10 } })
    scanAt(nil, { { 2589, 1200, 10 } })
    scanAt("Alliance", { { 2589, 900, 10 } })
    env:advance(4)
    drainJobs()
    ns.Trading:ScanBags()
    assert.are.equal("Horde", AME_DB.holdings[ns.Trading.CharKey()].faction) -- yours, as you log in

    local _, opts = ns.Tooltip.Gather(2589, true)
    local by = {}
    for _, h in ipairs(opts.houses) do
      by[h.house] = h
    end
    assert.is_nil(by.Alliance.alt) -- no Alliance character yet
    assert.is_truthy(by.Neutral.age)
    assert.is_false(opts.noGoblin)

    AME_DB.holdings[ns.AME:MarketRealmName() .. ":Bankalt"] = { faction = "Alliance" }
    _, opts = ns.Tooltip.Gather(2589, true)
    for _, h in ipairs(opts.houses) do
      by[h.house] = h
    end
    assert.is_true(by.Alliance.alt)
    assert.is_nil(by.Neutral.alt) -- anyone can sell at the goblin AH
    assert.is_nil(by.Horde.alt) -- yours
    assert.truthy(opts.post and opts.post.price, "a Normal price to post at")
    assert.are.equal("Normal", opts.post.label)
    assert.is_nil(opts.post.deposit) -- trade goods: no deposit line

    local _, plain = ns.Tooltip.Gather(2589, false)
    assert.is_nil(plain.post) -- only with Shift
  end)
end)
