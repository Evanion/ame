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
      .. "15-30% of the supply on the auction house, which ignores a few cheap or absurd listings. From "
      .. "Auctionator's default summary scan only the cheapest listing is known, so then it's the lowest price.",
  },
  min = { "Lowest", "The cheapest single listing seen in the latest data." },
  avg30 = {
    "30-day average",
    "The average daily market price over the last 30 days with data. Compare it with today's market price to "
      .. "see if the item is cheap or expensive right now.",
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
  signal = {
    "Signal",
    "BUY: today's price is unusually low for this item - at least 1.5 standard deviations below its own "
      .. "30-day average. SELL: unusually high by the same measure. Needs 7+ days of history. It compares the "
      .. "item with itself, not with other items, and it's a hint, not financial advice.",
  },
  score = {
    "Score",
    "An opportunity ranking from -100 to +100. Higher means the item is further below its usual price, on a "
      .. "stable item, with an upward trend. Around 0 means a normal price; negative means pricier than usual. "
      .. "Sort by it to find bargains quickly.",
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
    "AME records every auction house scan you (or Auctionator, or AHDB) run - full scans and the searches you "
      .. "do while buying and selling. Nothing extra is scanned. History is kept per market (realm or Forever "
      .. "ruleset) and auction house, and guild members running AME share their full scans automatically.",
  },
  {
    "Market tab",
    "A screener over every item with history. Pick a category or watchlist on the left, search by name, filter "
      .. "by quality, price range or signal, and click a column to sort. Hover a column header for what it means. "
      .. "Click a row to open its chart; click the star to watch it.",
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
