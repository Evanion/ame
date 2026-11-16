-- Plain-language explanations: hover text for columns and stat cards, and the Guide tab.
local _, ns = ...

local W = ns.Widgets
local Help = {}
ns.Help = Help

Help.TERMS = {
  name = { "Item", "Click a row to open its price chart. Click the star to add it to a watchlist." },
  market = {
    "Market price",
    "What the item typically sells for right now. From full listing data it's the average of the cheapest "
      .. "15-30% of the supply on the auction house, which ignores a few cheap or absurd listings. From a "
      .. "browse summary (what many scanners do by default) only the cheapest listing is known, so then it's the "
      .. "lowest price.",
  },
  min = { "Lowest", "The cheapest single listing seen in the latest data." },
  avg = {
    "Average",
    "The average daily market price over the chosen period (Settings > Average period, 7 days by default). Compare "
      .. "it with today's market price to see if the item is cheap or expensive right now.",
  },
  change7 = {
    "7-day change",
    "How much the market price moved compared with 7 days of data ago. Green is up, red is down.",
  },
  vol30 = {
    "Volatility",
    "How much the price jumps from day to day (the spread of daily % changes over 30 days). Low numbers mean a "
      .. "stable, predictable item; high numbers mean risky swings - and bigger opportunities.",
  },
  qty = {
    "Supply",
    "How many are listed in the latest data. On the item page the % next to it is the weekly supply trend: "
      .. "falling supply often comes before rising prices.",
  },
  sellRate = {
    "Sells per day (estimate)",
    "How fast the item moves: units that disappeared between consecutive full scans of this auction house, per "
      .. "day, over the last week. It counts sold, cancelled and expired listings, and new listings hide some "
      .. "sales, so treat it as a rough guide. A cheap item that never sells is a trap; a high number means you "
      .. "can sell a stack quickly. Needs a few full scans on the same day to show.",
  },
  signal = {
    "Signal",
    "BUY: today's price is unusually low for this item - at least 1.5 standard deviations below its own "
      .. "30-day average. SELL: unusually high by the same measure. HOLD: within its normal range - keep it if you "
      .. 'own it, no edge to buy. Needs 7+ days of history ("-" until then). It compares the item with itself, '
      .. "not with other items, and it's a hint, not financial advice.",
  },
  score = {
    "Score",
    "An opportunity ranking from -100 to +100. Higher means the item is further below its usual price, on a "
      .. "stable item, with an upward trend. Around 0 means a normal price; negative means pricier than usual. "
      .. "Sort by it to find bargains quickly.",
  },
  arbBuy = {
    "Buy at",
    "The cheapest listing at the auction house you buy from - what the first units cost you.",
  },
  arbSell = {
    "Sells for",
    "The market price at the auction house you sell at: what the item typically sells for there.",
  },
  arbFee = {
    "AH cut",
    "The selling auction house's cut of the sale: 5% at faction auction houses and 15% at the goblin ones "
      .. "(WoW Forever's rates; adjustable in Settings). The deposit isn't subtracted - you get it back when the "
      .. "item sells.",
  },
  arbProfit = { "Profit", "Per item: what it sells for, minus the AH cut, minus what you paid." },
  arbMargin = { "Margin", "Profit as a share of what you paid. 50% means every 10g spent comes back as 15g." },
  arbSupply = {
    "Supply",
    "Listed at the buy house / at the sell house. Plenty to buy and little to compete with where you sell is ideal; "
      .. "a big gap on one listing at the buy house may be gone fast.",
  },
  arbDeposit = {
    "Deposit",
    "What listing one at the sell house costs up front: a share of the item's vendor price (faction AH 5/20/60% "
      .. "for 2/8/24 hours, goblin AH five times that), at least 1 silver. You get it back when it sells and "
      .. "lose it if it doesn't - so a high deposit on a slow seller is real risk.",
  },
  arbSellRate = {
    "Sells per day at the sell house",
    "Estimated units sold per day where you'd sell. Compare it with how many you plan to buy: if it sells 5 a "
      .. "day, 100 will take weeks.",
  },
  arbAge = {
    "Data",
    "How old the older of the two prices is. Fresh data on both sides makes a route trustworthy - scan both "
      .. "auction houses (alts on this account count) before buying.",
  },
  candles = {
    "Candles",
    "Each candle covers one or more days. It opens at the previous candle's close and closes at the market "
      .. "price; green closed higher, red lower. The thin wick reaches down to the cheapest listing seen.",
  },
}

-- show a term's explanation on hover
function Help.Explain(frame, key)
  local term = Help.TERMS[key]
  if not term then
    return
  end
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(term[1], 1, 1, 1)
    GameTooltip:AddLine(term[2], nil, nil, nil, true)
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

Help.GUIDE = {
  {
    "Where the data comes from",
    "AME listens to the game's own auction house APIs, so every scan and search you run is recorded - from the "
      .. "default auction house window or any scanning addon (it works well with addons like Auctionator). "
      .. "Nothing extra is scanned. History is kept per market (realm or Forever ruleset) and auction house, and "
      .. "guild members running AME share their full scans automatically.",
  },
  {
    "Market tab",
    "A screener over every item with history. Pick a category or watchlist on the left, search by name, filter "
      .. "by quality, price range or signal, and click a column to sort. Hover a column header for what it means. "
      .. "Click a row to open its chart; click the star to watch it.",
  },
  {
    "Arbitrage tab",
    "Items you can buy at one auction house and sell at another for a profit after the AH cut - e.g. your "
      .. "faction's AH and the goblin AH (cross-faction). Each auction house keeps its own history, so scan both "
      .. "(alts on this account count). Hover the columns for details.",
  },
  {
    "Item tab",
    "The price chart: market price, lowest listing, 7-day average and supply. Switch to candles for a trading "
      .. "view. Mouse wheel zooms, drag pans, double-click resets. Alt-click any item in the game (bags, chat, "
      .. "the AH) to open it here.",
  },
  {
    "Watchlists and alerts",
    'Star items to put them on a watchlist; make more lists with "+ New list" in the sidebar (right-click a '
      .. "list to delete it). On an item's page set an alert: below or above a price in gold, or when a buy/sell "
      .. "signal appears. Alerts are checked after every scan and posted in chat with a sound.",
  },
  {
    "Reading the numbers",
    "Signals and score compare an item with its own history, so they need a week or more of data to mean "
      .. "anything. Items that are cheap AND stable (low volatility) score highest. Supply falling while the "
      .. "price is flat is often a good early sign. None of this is advice - markets can stay weird for a while.",
  },
  {
    "Commands",
    "/ame - open the window.   /ame <item link> - chart an item.   /ame status - data and sync status.   "
      .. "/ame config - settings.   /ame selftest - check everything is working.",
  },
}

function Help.CreateGuide(parent, contentArea)
  local v = contentArea(parent)
  local x, y, colW = 0, 0, 470
  for i, section in ipairs(Help.GUIDE) do
    if i == 4 then
      x, y = colW + 20, 0
    end
    local head = W.Text(v, "GameFontNormal")
    head:SetPoint("TOPLEFT", x, y)
    head:SetText(section[1])
    local body = W.Text(v, "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
    body:SetWidth(colW)
    body:SetSpacing(2)
    body:SetText(section[2])
    y = y - 22 - (body:GetStringHeight() or 40) - 18
  end
  return v
end
