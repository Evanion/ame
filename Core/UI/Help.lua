-- Plain-language explanations: hover text for columns and stat cards, and the Guide tab.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local Help = {}
ns.Help = Help

Help.TERMS = {
  name = {
    L["Item"],
    L["Click a row to open its price chart. Click the star to add it to a watchlist. The bars after the name show how much to trust the numbers: 3 green = plenty of recent scans, 2 amber = some, 1 red = few or old."],
  },
  market = {
    L["Market price"],
    L["What the item typically sells for right now. From full listing data it's the average of the cheapest 15-30% of the supply on the auction house, which ignores a few cheap or absurd listings. From a browse summary (what many scanners do by default) only the cheapest listing is known, so then it's the lowest price."],
  },
  min = { L["Lowest"], L["The cheapest single listing seen in the latest data."] },
  avg = {
    L["Average"],
    L["The average daily market price over the chosen period (Settings > Average period, 7 days by default). Compare it with today's market price to see if the item is cheap or expensive right now."],
  },
  change7 = {
    L["7-day change"],
    L["How much the market price moved compared with 7 days of data ago. Green is up, red is down."],
  },
  vol30 = {
    L["Volatility"],
    L["How much the price jumps from day to day (the spread of daily % changes over 30 days). Low numbers mean a stable, predictable item; high numbers mean risky swings - and bigger opportunities."],
  },
  qty = {
    L["Supply"],
    L["How many are listed in the latest data. On the item page the % next to it is the weekly supply trend: falling supply often comes before rising prices."],
  },
  sellRate = {
    L["Sells per day (estimate)"],
    L["How fast the item moves: units that disappeared between consecutive full scans of this auction house, per day, over the last week. It counts sold, cancelled and expired listings, and new listings hide some sales, so treat it as a rough guide. A cheap item that never sells is a trap; a high number means you can sell a stack quickly. Needs a few full scans on the same day to show."],
  },
  signal = {
    L["Signal"],
    L["BUY: today's price is unusually low for this item - at least 1.5 standard deviations below its own 30-day average. SELL: unusually high by the same measure. HOLD: within its normal range - keep it if you own it, no edge to buy. WAIT: cheap, but sellers are dumping - wait for the bottom. Needs 7+ days of history (\"-\" until then). The market phase reads the week's price move against supply: shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand or dumping. It compares the item with itself, and it's a hint, not financial advice."]
      .. " "
      .. L["VENDOR: after the AH cut and the listing deposit, the auction house pays less than a vendor would - sell it to a vendor."],
  },
  vsAvg = {
    L["vs average"],
    L["Today's market price against the average over the chosen period (Settings > Average period). -20% means 20% cheaper than usual."],
  },
  age = {
    L["Data age"],
    L["How old the latest price for this item is. Rows older than 3 days fade: scan again (or let a guildmate's scan arrive) before trusting them."],
  },
  phase = {
    L["Market phase"],
    L["The week's price move read against supply: shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand or dumping."],
  },
  score = {
    L["Score"],
    L["An opportunity ranking from -100 to +100. Higher means the item is further below its usual price, on a stable item, with an upward trend. Around 0 means a normal price; negative means pricier than usual. Sort by it to find bargains quickly."],
  },
  arbBuy = {
    L["Buy at"],
    L["The cheapest listing at the auction house you buy from - what the first units cost you."],
  },
  arbSell = {
    L["Sells for"],
    L["The market price at the auction house you sell at: what the item typically sells for there."],
  },
  arbProfit = { L["Profit"], L["Per item: what it sells for, minus the AH cut, minus what you paid."] },
  arbNet = {
    L["Net"],
    L["Per item: what it sells for, minus the AH cut, minus the listing deposit, minus what you paid. The deposit is counted for one post of the units the route pays for (or up to 20), at least 1 silver per post - you get it back when it sells."],
  },
  arbMargin = { L["Margin"], L["Profit as a share of what you paid. 50% means every 10g spent comes back as 15g."] },
  arbSupply = {
    L["Supply"],
    L["Listed at the buy house / at the sell house. Plenty to buy and little to compete with where you sell is ideal; a big gap on one listing at the buy house may be gone fast."],
  },
  arbDeposit = {
    L["Deposit"],
    L["What listing one at the sell house costs up front: a share of the item's vendor price (faction AH 5/20/60% for 2/8/24 hours, goblin AH five times that), at least 1 silver. You get it back when it sells and lose it if it doesn't - so a high deposit on a slow seller is real risk."],
  },
  arbSellRate = {
    L["Sells per day at the sell house"],
    L["Estimated units sold per day where you'd sell. Compare it with how many you plan to buy: if it sells 5 a day, 100 will take weeks."],
  },
  arbDepth = {
    L["Depth"],
    L["How many units you can buy at the buy auction house before the route stops paying, and the total profit: every listing priced below what one sells for after the cut. It needs the item's listings, so search the item at the buy house first (the Search button does it) - it then stays for 6 hours. Selling that many still takes time: check Sells/d."],
  },
  arbAge = {
    L["Data"],
    L["How old the older of the two prices is. Fresh data on both sides makes a route trustworthy - scan both auction houses (alts on this account count) before buying."],
  },
  pfValue = {
    L["Holdings value"],
    L["Everything your characters hold - bags, bank and active auctions - at your faction auction house's market price. Bank items and auctions are counted as of the last time you opened the bank / auction house."],
  },
  pfCost = {
    L["Average cost"],
    L["What you paid per unit for the units you bought on the auction house (oldest purchases are sold first). Items you looted or crafted have no cost."],
  },
  pfUnrealized = {
    L["Unrealized profit"],
    L["For units you bought on the auction house: what they're worth now at market price minus what you paid. It becomes real profit when you sell."],
  },
  pfProfit = {
    L["Realized profit"],
    L["From your auction sales: what you received after the AH cut, minus what you paid for those units (oldest purchases first). Sales of looted or crafted items count fully."],
  },
  pfFlow = {
    L["Sold / bought"],
    L["Gold received from auction sales (after the cut) and gold spent on auction purchases in the last 30 days."],
  },
  pfDays = {
    L["Days to sell"],
    L["How long selling everything you hold would take at the item's current sell rate (estimate)."],
  },
  candles = {
    L["Candles"],
    L["Each candle covers one or more days. It opens at the previous candle's close and closes at the market price; green closed higher, red lower. The thin wick reaches down to the cheapest listing seen."],
  },
  posting = {
    L["Posting price"],
    L["What to post at so it sells within the listing time - instead of undercutting the cheapest listing by 1c. Buyers take the cheapest listings first, so AME counts the units ahead of you at each price, how fast the item sells, and how often new listings undercut you, and weighs the chance of selling against the deposit you lose if it doesn't. Quick sells within a few hours almost surely, Normal is the best price for the chance, Patient is the highest price that still sells about half the time. It learns every item's pattern from your scans (busy hours, weekdays, how hard sellers compete) and from your own posts: if items keep expiring at its prices it gets more careful for that item. With little data it borrows from similar items; the bars show how much it knows."],
  },
}

-- show a term's explanation on hover
function Help.Explain(frame, key)
  local term = Help.TERMS[key]
  if not term then
    return
  end
  W.Tooltip(frame, function(tip)
    W.TipText(tip, term[1], term[2])
  end, "ANCHOR_TOP")
end

Help.GUIDE = {
  {
    L["Where the data comes from"],
    L["AME listens to the game's own auction house APIs, so every scan and search you run is recorded - from the default auction house window or any scanning addon (it works well with addons like Auctionator). Nothing extra is scanned. History is kept per market (realm or Forever ruleset) and auction house, and guild members running AME share their full scans automatically."],
  },
  {
    L["Market tab"],
    L["A screener over every item with history. Pick a category or watchlist on the left, search by name, filter by quality, price range or signal, and click a column to sort. Hover a column header for what it means. Click a row to open its chart; click the star to watch it."],
  },
  {
    L["Arbitrage tab"],
    L["Items you can buy at one auction house and sell at another for a profit after the AH cut - e.g. your faction's AH and the goblin AH (cross-faction). Each auction house keeps its own history, so scan both (alts on this account count). Hover the columns for details."],
  },
  {
    L["Portfolio tab"],
    L["What all your characters hold, valued at your faction's market, with cost and unrealized profit for what you bought on the AH, the Buy/Hold/Sell signal and how long it would take to sell. The ledger lists your AH sales and purchases - recorded from auction mail when you open your mailbox."],
  },
  {
    L["Item tab"],
    L["The price chart: market price, lowest listing, 7-day average and supply. Switch to candles for a trading view. Mouse wheel zooms, drag pans, double-click resets. Shift-click any item (bags, chat, the AH) while this window is open to chart it, or set a modifier click in Settings."],
  },
  {
    L["Watchlists and alerts"],
    L["Star items to put them on a watchlist; make more lists with \"+ New list\" in the sidebar (right-click a list to share it with your guild or delete it; guild members' shared lists appear below yours). On an item's page set an alert: below or above a price in gold, or when a buy/sell signal appears. Alerts are checked after every scan and posted in chat with a sound."],
  },
  {
    L["Reading the numbers"],
    L["Signals and score compare an item with its own history, so they need a week or more of data to mean anything. Items that are cheap AND stable (low volatility) score highest. Supply falling while the price is flat is often a good early sign. None of this is advice - markets can stay weird for a while."],
  },
  {
    L["Commands"],
    L["/ame - open the window.   /ame <item link> - chart an item.   /ame status - data and sync status.   /ame config - settings.   /ame selftest - check everything is working."],
  },
}

-- The Guide: sections in two columns (each goes to the shorter one), scrolled with the mouse wheel when they don't
-- fit (translations run long). Laid out when shown: text heights are only known once the client has drawn it.
Help.GUIDE_COLUMN, Help.GUIDE_GAP = 460, 24

function Help.CreateGuide(parent, contentArea)
  local v = contentArea(parent)
  local scroll = CreateFrame("ScrollFrame", nil, v)
  scroll:SetPoint("TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", -12, 0)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(2 * Help.GUIDE_COLUMN + Help.GUIDE_GAP, 1)
  scroll:SetScrollChild(content)
  v.scroll, v.content, v.sections = scroll, content, {}
  for _, section in ipairs(Help.GUIDE) do
    local head = W.Text(content, "GameFontNormal")
    head:SetText(section[1])
    local body = W.Text(content, "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
    body:SetWidth(Help.GUIDE_COLUMN)
    body:SetJustifyH("LEFT")
    body:SetSpacing(2)
    body:SetText(section[2])
    v.sections[#v.sections + 1] = { head = head, body = body }
  end
  v.credits = W.Text(content, "GameFontDisableSmall")
  v.credits:SetText(
    L["Azeroth Mercantile Exchange %s  ·  created by Tyken Evanion  ·  PvP Horde, WoW Forever"]:format(ns.VERSION)
  )

  -- a thin bar on the right shows where you are when it scrolls
  local bar = v:CreateTexture(nil, "OVERLAY")
  bar:SetColorTexture(1, 1, 1, 0.25)
  bar:SetWidth(4)
  bar:Hide()

  local function range()
    return math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
  end
  local function setScroll(y)
    y = math.max(0, math.min(range(), y))
    scroll:SetVerticalScroll(y)
    local max, viewH = range(), scroll:GetHeight() or 0
    bar:SetShown(max > 0)
    if max > 0 then
      local total = viewH + max
      local h = math.max(20, viewH * viewH / total)
      bar:SetHeight(h)
      bar:ClearAllPoints()
      bar:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, -(viewH - h) * y / max)
    end
  end

  function v:Layout()
    local cols = { 0, 0 } -- heights so far
    for _, s in ipairs(self.sections) do
      local c = cols[2] < cols[1] and 2 or 1
      s.head:ClearAllPoints()
      s.head:SetPoint("TOPLEFT", (c - 1) * (Help.GUIDE_COLUMN + Help.GUIDE_GAP), -cols[c])
      cols[c] = cols[c] + (s.head:GetStringHeight() or 14) + 4 + (s.body:GetStringHeight() or 40) + 18
    end
    local bottom = math.max(cols[1], cols[2])
    self.credits:ClearAllPoints()
    self.credits:SetPoint("TOPLEFT", 0, -bottom - 4)
    content:SetHeight(bottom + 24)
    setScroll(scroll:GetVerticalScroll() or 0)
  end
  v:HookScript("OnShow", function(self)
    self:Layout()
  end)
  v:EnableMouseWheel(true)
  v:SetScript("OnMouseWheel", function(_, delta)
    setScroll((scroll:GetVerticalScroll() or 0) - delta * 40)
  end)
  return v
end
