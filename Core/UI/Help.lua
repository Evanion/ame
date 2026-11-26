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
  marketDay = {
    L["Market/day"],
    L["What the whole market's daily sales of an item would earn at this recipe's profit: profit per craft times how many sell a day. It's the size of the opportunity, not your income - you'd sell a share of those, after the other sellers, and a recipe with a cooldown (transmutes) only as often as it allows: the sidebar says how often. Use it to compare recipes; a big Market/day with few sellers is the best kind."],
  },
  sellRate = {
    L["Sells per day (estimate)"],
    L["How fast the item moves: units that disappeared between consecutive full scans of this auction house, per day, over the last week - never more than are listed now, since nobody can buy more than that today. Scans can't tell a sale from a listing that expired or was cancelled, so where you or your guildmates have listed the item, only its sell-through's share counts as sold - an item reposted every day that never sells drops to about 0. Items nobody has listed count the market's share: the sell-through of everything that has been (about 40% until there's enough of it), so treat those as estimates. A cheap item that never sells is a trap; a high number means you can sell a stack quickly. Needs a few full scans on the same day to show."],
  },
  sellThrough = {
    L["Sell-through"],
    L["How much of what was listed actually sold, in units: sold / (sold + expired + cancelled). It comes from real auction outcomes - your auction mail and cancels, and your guildmates' (shared automatically) - and recent ones count most. With a few outcomes it takes over from the scans: the sales rate, what a listing nets (VENDOR, DE) and the value of what you hold (worth the market price when it sells, the vendor's price when it doesn't)."],
  },
  syncProtocol = {
    L["Sync protocol"],
    L["How AME shares with your guild. v2 (the default) sends each scan once to the whole guild, in small numbered pieces: a lost piece is sent again on its own, a /reload doesn't start a transfer over, and hours you missed - up to a week back - are filled in from whoever has them, so the 7D chart has a point for every hour someone scanned. v1 is the original: each player asks for each scan separately, over the last 48 hours. Pick v1 if sync seems to slow your game; v2 players keep sharing with you. Trusted players outside the guild always use v1."],
  },
  signal = {
    L["Signal"],
    L["BUY: today's price is unusually low for this item - at least 1.5 standard deviations below its own 30-day average. SELL: unusually high by the same measure. HOLD: within its normal range - keep it if you own it, no edge to buy. WAIT: cheap, but sellers are dumping - wait for the bottom. Needs 7+ days of history (\"-\" until then). The market phase reads the week's price move against supply: shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand or dumping. It compares the item with itself, and it's a hint, not financial advice."]
      .. " "
      .. L["VENDOR: after the AH cut and the listing deposit, the auction house pays less than a vendor would - sell it to a vendor."]
      .. " "
      .. L["When one of your characters knows a recipe that makes it into something worth more (silk cloth into silk bandages, say), the item page says so instead: make that first, then vendor or post it."]
      .. " "
      .. L["DE: the enchanting materials it disenchants into are worth more than listing it nets (and than a vendor pays) - disenchant it, or sell it to an enchanter. Worked out from the classic disenchanting rules and today's material prices."],
  },
  confidence = {
    L["Confidence"],
    L["How much to trust the numbers: 3 green bars = plenty of recent scans, 2 amber = some, 1 red = few or old. More scans of the item (full scans or searches) raise it."],
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
    L["The market price at the auction house you sell at: what the item typically sells for there - never more than a few times its 30-day average, so one fantasy listing doesn't make a route."],
  },
  arbNet = {
    L["Net"],
    L["Per item: what it sells for, minus the AH cut, minus the listing deposit, minus what you paid. The deposit is counted for one post of the units the route pays for (or up to 20), 60% of the vendor price for a 24-hour listing - you get it back when it sells."],
  },
  arbUnits = {
    L["Units"],
    L["How many units at the buy house still pay after the cut, of how many are listed there. The first number needs the item's listings: search it at the buy house (it then stays for 6 hours)."],
  },
  arbMargin = { L["Margin"], L["Profit as a share of what you paid. 50% means every 10g spent comes back as 15g."] },
  arbDeposit = {
    L["Deposit"],
    L["What listing one at the sell house costs up front: a share of the item's vendor price (faction AH 5/20/60% for 2/8/24 hours, goblin AH five times that), at least 1 silver. You get it back when it sells and lose it if it doesn't - so a high deposit on a slow seller is real risk."],
  },
  arbSellRate = {
    L["Sells per day at the sell house"],
    L["Estimated units sold per day where you'd sell, never more than are listed there. Compare it with how many you plan to buy: if it sells 5 a day, 100 will take weeks."],
  },
  arbDepth = {
    L["Depth"],
    L["How many units you can buy at the buy auction house before the route stops paying, and the total profit: every listing priced below what one sells for after the cut. It needs the item's listings, so search the item at the buy house first (the Search button does it) - it then stays for 6 hours. Selling that many still takes time: check Sales/day."],
  },
  arbAge = {
    L["Data"],
    L["How old the older of the two prices is. Fresh data on both sides makes a route trustworthy - scan both auction houses (alts on this account count) before buying."],
  },
  mxIndex = {
    L["Market index"],
    L["How prices across the whole auction house moved, as one number: 100 thirty days ago. Each day it moves by the average price change of steadily listed items - listed on most days, at least 3 at a time - so one-off and fantasy listings can't move it. Above 100: things got more expensive."],
  },
  mxCpi = {
    L["CPI"],
    L["Consumer price index: what playing costs. Only what players use up - consumables, trade goods, reagents, gems, ammo - weighted by how much gold is spent on each (sell rate x price), like a real CPI weighs what households buy. Sell rates need full scans a few hours apart; until there are enough, it weighs by listed value (the status line says which)."],
  },
  mxValue = {
    L["Listed value"],
    L["Everything listed at the last full scan at market price. Each item's price is capped at the outlier limit (Settings, Data) times its 30-day average, so a fantasy listing can't inflate the total. Items too new to have an average can't be capped: Largest by value shows what the total leans on."],
  },
  mxTurnover = {
    L["Turnover (estimate)"],
    L["Gold changing hands per day: each item's sell rate times its price, summed. Sell rates count supply leaving the auction house between full scans, so expired and cancelled auctions count too: read it as an upper bound."],
  },
  mxAuctions = {
    L["Auctions"],
    L["Auctions listed at the last full scan, and the change over the chosen period. Only days with a full scan count: a day of searches sees too few items."],
  },
  mxBreadth = {
    L["Breadth"],
    L["How many steadily listed items rose against how many fell over the chosen period. A rising index with weak breadth means a few items are carrying it."],
  },
  pfValue = {
    L["Holdings value"],
    L["Everything your characters on this realm own - bags, bank, mailbox, guild banks and active auctions - at what selling them nets at your faction's auction house: the market price after the cut and the listing deposit (lost as often as listings fail, by the item's sell-through), or a vendor's price when that's more. Soulbound items (they can't be sold) and items you hid are left out. Bank items and auctions are counted as of the last time you opened the bank / auction house."],
  },
  pfCost = {
    L["Average cost"],
    L["What you paid per unit for the units you bought on the auction house (oldest purchases are sold first). Items you looted or crafted have no cost."],
  },
  pfUnrealized = {
    L["Unrealized profit"],
    L["For units you bought on the auction house: what they're worth now (what selling them nets) minus what you paid. It becomes real profit when you sell."],
  },
  pfProfit = {
    L["Realized profit"],
    L["From your auction sales: what you received after the AH cut, minus what you paid for those units (oldest purchases first). Sales of looted or crafted items count fully."],
  },
  pfFlow = {
    L["Sold / bought"],
    L["Gold received from auction sales (after the cut) and gold spent on auction purchases in the chosen period."],
  },
  pfDays = {
    L["Days to sell"],
    L["How long selling everything you hold would take at the item's current sell rate (estimate)."],
  },
  candles = {
    L["Candles"],
    L["Each candle covers one time slot, from 15 minutes up depending on the zoom. It opens at the previous candle's close and closes at the market price; green closed higher, red lower. The thin wick reaches down to the cheapest listing seen."],
  },
  posting = {
    L["Posting price"],
    L["What to post at so it sells within the listing time - instead of undercutting the cheapest listing by 1c. Buyers take the cheapest listings first, so AME counts the units ahead of you at each price, how fast the item sells, and how often new listings undercut you, and weighs the chance of selling against the deposit you lose if it doesn't. How far the item's price swings in a day - from your scans of it, else its 30-day volatility - sets the choices apart: Quick goes under where the cheapest listing usually dips within a few hours, Normal is the best price for the chance, Patient waits for the usual peak within the listing time (nothing above it is suggested). Quick only shows when it's cheaper than Normal. It learns every item's pattern from your scans (busy hours, weekdays, how hard sellers compete) and from your own posts: if items keep expiring at its prices it gets more careful for that item. With little data it borrows from similar items; the bars show how much it knows."],
  },
}

-- show a term's explanation on hover. key: a term, or function(frame) -> term for a reused frame whose term changes
-- (a card's pooled rows); no term, no tooltip
function Help.Explain(frame, key)
  local dynamic = type(key) == "function"
  if not dynamic and not Help.TERMS[key] then
    return
  end
  local function keyOf(self)
    if dynamic then
      return key(self)
    end
    return key
  end
  W.Tooltip(frame, function(tip, self)
    local term = Help.TERMS[keyOf(self) or ""]
    if not term then
      return false
    end
    W.TipText(tip, term[1], term[2])
    tip:AddLine(W.Dim(L["Right-click: open it in the Guide's glossary"]))
  end, "ANCHOR_TOP")
  -- right-click: the term's glossary entry on the Guide tab
  frame:HookScript("OnMouseUp", function(self, button)
    local k = keyOf(self)
    if button == "RightButton" and Help.TERMS[k or ""] then
      local app = ns.App
      if app and app.Enabled and app.Enabled() and app.frame and app.frame:IsShown() then
        app:Go("guide", { article = k }) -- the new window's Guide
      elseif ns.UI and ns.UI.ShowGuide then
        ns.UI:ShowGuide(k)
      end
    end
  end)
end

-- the glossary at the end of the Guide: every explained term, in this order
Help.GLOSSARY = {
  "mxIndex",
  "mxCpi",
  "mxValue",
  "mxTurnover",
  "mxAuctions",
  "mxBreadth",
  "market",
  "min",
  "avg",
  "vsAvg",
  "change7",
  "vol30",
  "qty",
  "sellRate",
  "sellThrough",
  "syncProtocol",
  "signal",
  "score",
  "phase",
  "age",
  "name",
  "confidence",
  "posting",
  "marketDay",
  "candles",
  "arbBuy",
  "arbSell",
  "arbNet",
  "arbUnits",
  "arbMargin",
  "arbDeposit",
  "arbDepth",
  "arbSellRate",
  "arbAge",
  "pfValue",
  "pfCost",
  "pfUnrealized",
  "pfProfit",
  "pfFlow",
  "pfDays",
}

Help.GUIDE = {
  {
    L["Where the data comes from"],
    L["AME listens to the game's own auction house APIs, so every scan and search you run is recorded - from the default auction house window or any scanning addon (it works well with addons like Auctionator). Nothing extra is scanned. History is kept per market (realm or Forever ruleset) and auction house, and guild members running AME share their full scans automatically."],
  },
  {
    L["Market tab"],
    L["Auctions lists every item with history. Pick a category or watchlist on the left, search by name, filter by quality (each in its colour), price range or signal, and click a column to sort. Filters narrows it by required level, item level (ranges like 20-30, 40 or 40-) and Usable by you: items your character's level allows and, for weapons, armour and recipes, whose tooltip shows nothing in red (a weapon or armour type you can't use, a skill you lack, a recipe you know). At the auction house the same filters go with your search, beside the auction house's own category and Exact name. A watchlist shows every item on it, whatever the filters say; the name search still narrows it. Double-click the search box to clear the search and every filter. Hover a column header for what it means. Click a row to open its chart; click the star to watch it. Right-click a row for more: search the auction house, watchlists, an alert, a chat link, or hiding items you don't trade (they move to Hidden in the sidebar, where you can unhide them)."],
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
    L["The price chart: market price, lowest listing, two averages (MA 20 and the 7-day average) and supply. Switch to candles for a trading view. Mouse wheel zooms, drag pans, double-click resets. To chart an item, type its name in the search box above the chart (Enter opens the best match), Shift-click it anywhere (bags, chat, the AH) while the Item tab is showing, or pick a modifier click under Settings, Tooltips & charts that charts it from anywhere."],
  },
  {
    L["Watchlists and alerts"],
    L["Star items to put them on a watchlist; make more lists with \"+ New list\" in the sidebar (right-click a list to share it with your guild or delete it; guild members' shared lists appear below yours). On an item's page set an alert: when its cheapest listing goes below or above a price (12 or 12g is gold; 9s 50c works too), or when a buy/sell signal appears. Alerts are checked after every scan and posted in chat with a sound; the bell left of the tabs keeps them, with a count of the ones you haven't seen."],
  },
  {
    L["Reading the numbers"],
    L["Signals and score compare an item with its own history, so they need a week or more of data to mean anything. Items that are cheap AND stable (low volatility) score highest. Supply falling while the price is flat is often a good early sign. None of this is advice - markets can stay weird for a while."],
  },
  {
    L["Commands"],
    L["/ame - open the window.   /ame <item link> - chart an item.   /ame item <item link> - its history in chat.   /ame scan - a full scan of the open auction house.   /ame status - data and sharing status.   /ame config - settings.   /ame sync - sharing settings.   /ame backfill - import Auctionator's history now.   /ame selftest - check everything is working.   /ame help - the commands in chat."],
  },
}

-- The Guide's articles, grouped like a documentation site. Each article: key, title, label (optional: a shorter
-- name in the sidebar, e.g. "Market" under "Tabs"; the title otherwise), body (paragraphs). The glossary group is
-- built from Help.TERMS (Help.GLOSSARY order), so every hover explanation has its own page.
local function guideText(i)
  return Help.GUIDE[i][2]
end

-- An article's body is a list of blocks: a string is a paragraph, { h = text } a section heading, and
-- { example = name } one of AME's own elements drawn live (Help.EXAMPLES), so the text sits next to the thing it
-- talks about.
local H = function(text)
  return { h = text }
end
local EX = function(name)
  return { example = name }
end

function Help.Articles()
  local groups = {
    {
      L["Getting started"],
      {
        {
          key = "start",
          title = L["Getting started"],
          body = {
            L["AME records the auction house while you use it and turns it into price history, charts, signals and posting prices. There's nothing to set up: open the auction house and run a full scan, and AME records it - with your scanning addon, or, without one, with the Full scan button over the auction house window (or /ame scan). The game allows one full scan every 15 minutes."],
            H(L["After your first scan"]),
            L["After one scan you can browse the Market tab and see posting prices. Signals, trends and sell rates need history: they get better with a scan a day, and mean the most after a week."],
            H(L["Opening AME"]),
            L["Open the window with /ame, the minimap button, or set it to open with the auction house (Settings > Window)."],
            L["Right-click the minimap button for Settings; hover it for the last full scan and the top buy signals."],
          },
        },
        {
          key = "tooltips",
          title = L["Item tooltips"],
          body = {
            L["Every item tooltip in the game gets AME's block: which auction house the prices come from and how fresh they are, the market price, and for gear what disenchanting it is worth (its materials at what selling them nets, as the DE signal counts them). Own more than one? Each price shows per item and, on the right, for all of yours - with what a vendor pays for them all. Under that: how many you have and where (bags, bank, mailbox, guild banks), how many you have up for sale on the AH, what the ones in your bags and bank are worth at the market price (handy for knowing when you've farmed enough), how it trades against its average, and the signal with its reason: what price and supply are doing, or for DE and VENDOR how much disenchanting or a vendor beats listing it."],
            L["Prices are your own faction's auction house. When the goblin auction house pays clearly more, even after its bigger cut, a line says so."],
            L["Hold Shift for more: what gear disenchants into (each result with its chance and value), yours per character and guild bank with your average cost, every auction house you have prices for and what a listing there nets after its cut and deposit (alt there marks the other faction's when one of your characters on this market is of it; each counts once it has logged in), how much the goblin auction house sells a day and how fresh its prices are, then the lowest listing, the average, what to post at (the sell window's Normal price) with how soon it should sell and its chance to, and for gear the deposit it risks, the supply trend, volatility, the score and how much data it rests on. Always show details keeps it open."],
            L["Guild banks count as AME last saw them: open the guild bank once (each tab) to count it. On a small screen with a large UI scale, tooltips leave out the freshness, holdings and context lines on their own. Turn tooltips off, or change the average they compare with, under Settings, Tooltips & charts."],
            H(L["Recipes"]),
            L["A recipe's tooltip (pattern, plans, formula...) also shows what it makes at today's market price, and what one craft earns after the reagents and the auction house's cut and deposit - red when it loses money. It prices as the Crafting tab and the profession window do: each reagent bought at market, from a vendor or crafted by a recipe you know, whichever is cheapest, and an item searched in the last hour at its cheapest listing. Only the Crafting tab also counts the reagents you hold."],
          },
        },
        {
          key = "data",
          title = Help.GUIDE[1][1],
          body = {
            guideText(1),
            H(L["Quick scans and full scans"]),
            L["Auctionator's Full Scan button runs a quick scan by default: it reads only each item's cheapest listing. AME then sets the market price from how far above the cheapest that item usually sells, learned from scans that see every listing - /ame scan (or the Full scan button without a scanning addon), Auctionator's replicate full scan, and your searches. Run a detailed scan now and then and quick scans stay accurate; candles keep their wicks."],
            L["AME's own full scan (the Full scan button, /ame scan) is detailed by default: every listing, once per 15 minutes. Settings, Data can make it fast instead: each item's cheapest listing, any time."],
            H(L["Other auction houses"]),
            L["The button next to AME's title picks which auction house you're looking at: yours, the other faction's or the goblin AH. Each keeps its own history; scan there (any character on this account counts) to fill it."],
            H(L["Importing from Auctionator"]),
            L["If Auctionator is installed, AME imports its recent daily prices for days it has no data for, once, when you open the auction house - your faction's only. The Import button under Settings, Data does it again."],
            H(L["Random-suffix gear"]),
            L['Gear with a random suffix ("of the Monkey", "of Magic") is tracked per suffix, since each sells at its own price. Charts, tooltips and your portfolio use the suffix of the item in hand.'],
            H(L["What really sells"]),
            L["Scans see listings disappear, but not why: sold, expired or cancelled look the same. So AME also counts real outcomes - sales and expired items from your auction mail, and auctions you cancel - and shares them with your guild. That sell-through corrects the sales rate, the VENDOR and DE signals and your portfolio's value for every item someone has listed."],
            H(L["How long history is kept"]),
            L["Every scan is kept for 2 days (the 2D chart), a point per hour for 7 days (the 7D chart), a point per day for 60 days, then a point per week for a year. Your ledger keeps 90 days."],
            H(L["Backing up your history"]),
            L["AME keeps everything in two files in your game folder, under WTF, Account, your account's name, SavedVariables: AzerothMercantileExchange.lua (settings, ledger, lists, alerts) and AzerothMercantileExchange_History.lua (every auction house's price history). The game writes them when you log out or /reload, so copy both with the game closed to back them up, and put them back the same way to restore. They're shared by every character on the account."],
          },
        },
        {
          key = "window",
          title = L["The window"],
          body = {
            H(L["Moving and resizing"]),
            L["Drag the title bar to move the window and the bottom-right corner to resize it. AME remembers the size, and where you put it with and without the auction house open. When the auction house opens and there's room beside it, AME docks next to it (Settings > Window)."],
            H(L["Narrow windows"]),
            L["On a narrow window the tabs switch to a compact layout: sidebars become a dropdown or a Details button. Window scale changes AME's size without touching the rest of your UI."],
            H(L["The status row"]),
            L["The status row at the bottom says where the numbers come from, how old they are, and when a scan is being read or market data is being updated."],
          },
        },
      },
    },
    {
      L["Tabs"],
      {
        {
          key = "tabMarket",
          title = Help.GUIDE[2][1],
          label = L["Market"],
          body = {
            guideText(2),
            L["With the Market overview switched on (Settings, General), the toolbar's first buttons switch the Market tab between Auctions (this list) and the Overview: indexes and totals for the whole auction house (see Market overview)."],
            H(L["Filtering by signal"]),
            EX("signalFilter"),
            L["Pick a signal to see only those items. Active filters show as chips under the toolbar: click one to remove it, or Clear all."],
            H(L["Views and columns"]),
            L["Views saves the filters you use often and brings them back in one click. Columns picks which columns show; the button says how many are hidden."],
            H(L["Shift-clicks"]),
            L["With the auction house open, Shift-click a row to search for it there. While the search box has focus, Shift-click an item link anywhere to search for it by name."],
            L["Every item name in AME is a link: with a chat box open, Shift-click one to put its link in chat, as you would from your bags. Faded rows have data older than three days; hover a row for the reasons behind its signal."],
            H(L["The item menu"]),
            L["Right-click any item in a list - Market, Arbitrage or Portfolio - for what you can do with it: open its chart, search the auction house for it (while the auction house is open), add it to a watchlist or a shopping list, see who can make it, set a price alert, or put its link in the chat box."],
            H(L["Hiding items"]),
            L["Items you never trade can be hidden - drinks you buy from a vendor, for example: right-click one in the Market, Arbitrage or Portfolio list and pick Hide from lists, or use the button on its item page. Hidden items leave those lists and their totals, on every auction house and character (Portfolio says how many it left out and what they're worth), but AME keeps recording their prices, your ledger keeps every sale and purchase, and their tooltips still work. They're listed under Hidden in the Market sidebar: right-click one there to unhide it, or unhide them all under Settings, Tooltips & charts."],
          },
        },
        {
          key = "marketOverview",
          title = L["Market overview"],
          label = L["Overview"],
          body = {
            L["The Overview is the whole auction house at a glance, like a stock exchange's indexes: is the market getting dearer or cheaper, how much is listed, and where the gold is. It's off by default: switch it on under Settings, General, and Overview appears next to Auctions on the Market tab's toolbar. Market data takes a little longer to update while it's on."],
            H(L["The cards"]),
            L["Market index and CPI start at 100 thirty days ago. The market index follows every steadily listed item; the CPI only what players use up, weighted by what's spent on it. Listed value, Turnover and Auctions are the totals at the last full scan; Breadth is the share of items that rose. Each card's change is over the period picked on the right of the toolbar. Hover a card for how it's worked out."],
            H(L["Fair numbers"]),
            L["Only items listed at least 3 at a time on most days count for the indexes, risers and fallers, so one item reposted every day can't move them. Listed value caps each price at the outlier limit (Settings, Data) times its 30-day average. Totals come only from days with a full scan."],
            H(L["Categories and movers"]),
            L["Categories shows each item class's share of the listed value: click one to open it in the screener. Biggest risers and fallers are steadily listed items, leaving out gray items and white weapons and armour; click one for its chart. Largest by value lists the items the total leans on most: how many are listed, the price each is counted at and what they come to. When an item's price was capped at the outlier limit, it says what its listings came to before the cap (capped from ...)."],
          },
        },
        {
          key = "crafting",
          title = L["Crafting"],
          label = L["Crafting"],
          body = {
            L["The Crafting tab is everything about professions: your characters' professions, who can make what, the craft queue, what your recipes earn at today's prices, and how to level up. Pick a page in the sidebar; the character, profession and search filters on the toolbar stay as you switch pages. AME learns your recipes from your profession windows: open each profession once on every character. Recipe data comes with AME in the AME Crafting Data addon, loaded only when you use the tab; Recipes to buy and Leveling need it."],
            H(L["Your professions"]),
            L["Every profession your characters have recorded: skill, recipes known, cooldowns, and the recipe that earns the most at today's prices. Click a row and the button plans leveling that profession."],
            L["Faded rows are what isn't recorded yet: a profession a character has whose window hasn't been opened there (open it once), and a character AME has seen on this realm with nothing recorded (log in there and open each profession once)."],
            H(L["Find a crafter"]),
            L["Search an item or an enchant to see what makes it: one row per recipe, with how many can make it. Click a recipe for everyone who can make it, online first, and under them the recipe item that teaches it with its price on the auction house; Whisper on a crafter's row opens a chat to them with the recipe linked. Only players who run AME share what they craft."],
            H(L["Craft queue"]),
            L["What you've queued - from a profession window, Top earners, Sell or refine or Leveling - worked out into steps, parts first, with its profit and what's to buy in the heading. A part's Buy buys it instead of making it (Make on its material makes it again); x takes a queued craft off the queue, and Clear empties it. To do lists what to do in order: what to buy, what to fetch from the bank, the mailbox or your other characters, then what to craft and on whom. Missing to shopping list puts everything still missing on the Craft queue shopping list."],
            H(L["Top earners"]),
            L["Every recipe your characters know, most profit per craft first; Market/day is profit per craft times how many the whole market takes a day - the size of the opportunity, not what you'd earn (that's your share of the sales, after the other sellers'). Click a column to sort by it. Reagents count at the cheapest way to get them - bought at market price, from a vendor, crafted from cheaper materials, or, for what you already hold, at what selling it would net (listing costs the AH cut, buying doesn't). Signal is the product's market signal, as the Market screener shows it. Click a row for the breakdown: how it's made, its reagents, and what it sells for. A recipe that requires a tool (a Salt Shaker, a Blacksmith Hammer) or a place (an anvil, a forge) gets a Tools section: whether one of your characters has the tool, and how to get one - make it (or the pattern that teaches it, with its price and who sells it), buy it from a vendor, or the auction house. (Open the profession window once so AME knows what each recipe requires.) Queue puts one craft on the craft queue, and Reagents to a list puts one craft's reagents on a shopping list."],
            H(L["Sell or refine"]),
            L["For the materials your characters hold: sell them as they are, or craft them into something worth more and sell that. Takes says how long the market needs to absorb what you'd list. When crafting it is the best use, the button queues those crafts (Queue the smelt for ore)."],
            L["Click a material for each way to craft it, line by line: the products sold, the other reagents at what getting them costs (bought, from a vendor or crafted), and any of the material left over, sold raw. The lines add up to what it nets."],
            H(L["Recipes to buy"]),
            L["Recipes on the auction house that one of your characters could learn and none knows yet, by profit per craft. Click one for when it pays back: the recipe's price divided by its Market/day - at best, if you sold all the market takes; with other sellers it takes longer. Recipes that need more skill are listed after the ones you can learn now."],
            L["Network says how many in your guild and trusted players already know it. Only what nobody has keeps the gaps: recipes nobody you know can craft yet. Usable only keeps what the character you're on can learn right away: its profession, enough skill, and not known yet. Players who don't run AME aren't counted."],
            H(L["Leveling"]),
            L["The cheapest way to raise a profession from where a character is to the skill you pick, recalculated from today's prices. For every skill point AME picks the recipe with the lowest expected cost per point: how many crafts a point takes (always one while a recipe is orange, more as it turns yellow and green) times what a craft costs, minus what its result gets back."],
            L["Pick a goal: Cheapest counts only what you spend; Best recovery subtracts what the results sell for (only as many as the market takes in about three days; the rest go to a vendor, or are disenchanted if one of your characters has Enchanting); Fewest crafts saves time; My materials uses what the character holds first. Results a later step needs are kept for it, and big reagent buys are priced along the listings when AME has recorded them."],
            L["Steps can need a recipe: one on the auction house (its price is added) or one taught by a trainer. The game data has no training level for most trainer recipes, so those steps say the level is estimated. Click a step for its skill colors and reagents. Queue the steps puts the whole path's crafts on the craft queue, and Reagents to a list puts its reagents on a shopping list. The search box narrows the steps to the recipes whose name has the text."],
          },
        },
        {
          key = "tabItem",
          title = Help.GUIDE[5][1],
          label = L["Item"],
          body = {
            guideText(5),
            H(L["The verdict"]),
            EX("verdict"),
            L["The sidebar opens with the call and why, in plain words: the price against its average, what supply is doing, how fast it sells and how much data it rests on."],
            H(L["The chart"]),
            EX("legend"),
            L["Market price, the lowest listing, the 7-day average, supply, and your own buys and sales as dots. A dashed line marks what a vendor pays for one when that's near the prices - where selling to a vendor can beat the auction house; when it's far below, the legend just says it."],
            H(L["The averages: MA 20 and the 7-day average"]),
            L["Two averages, as on a trading chart: MA 20 is the simple moving average of the last 20 time slots' closes, so its span follows the zoom - about 20 hours on 2D, 60 hours on 7D, 20 days on 30D. The 7-day average is a fixed reference line. The verdict compares the price with the average period set in Settings (7 days unless you change it), and signals with the 30-day average. Click any line in the legend to hide it or show it again; AME remembers."],
            L["Hover the item's name or icon at the top for the game's own tooltip, with its stats."],
            H(L["Reading candles"]),
            L["Switch the chart from Line to Candles for a trading view. Each candle sums up one time slot - an hour on the 2D range, 3 hours on 7D, a day or more on longer ranges, smaller as you zoom in (about 60 across the chart) - in four prices:"],
            EX("candleAnatomy"),
            L["Green: the price closed higher than it opened. Red: lower. The body is the move; the wicks are how far the price strayed. AME's candles open where the previous one closed, so they join up without gaps, and the lower wick is the cheapest listing anyone posted - which is why it's often long: a cheap copy or two shows up long before the market price follows. Hover a candle for its exact open, high, low and close."],
            L["A few shapes worth knowing:"],
            EX("candlePatterns"),
            L["Read candles together with the supply bars underneath: a price move on rising supply means sellers are piling in; on falling supply, it's buyers clearing the shelf. The verdict in the sidebar does that reading for you."],
            H(L["Ranges"]),
            L["2D shows the scans from the last two days. 7D adds a point per hour before that (the newest full scan of each hour). The longer ranges show a point per day, and per week beyond 60 days. On every range the chart merges the points into time slots, about 60 across what's on screen and smaller as you zoom in; every line, candle and bar has one value per slot, so hovering a slot reads them all."],
            H(L["Following the auction house"]),
            L["While the Item tab is showing, it follows the item you pick at the auction house: a row you click, or a name you type into the search box (the item named exactly that, or the only one listed). Put an item up for sale and AME switches to the Item tab for it, wherever it was (Settings, General: Switch to the Item tab for what you put up for sale)."],
            H(L["Post at"]),
            L["The sidebar's Post at card gives the same choices as the sell bar - Normal, Quick and Patient - with how long each takes to sell and what you net after the cut."],
          },
        },
        {
          key = "tabArbitrage",
          title = Help.GUIDE[3][1],
          label = L["Arbitrage"],
          body = {
            guideText(3),
            H(L["A route, broken down"]),
            EX("route"),
            L["Select a route to see what it pays after the cut and the deposit, and how fresh each side's price is. Routes paying over 2000% are gold transfers between factions, not trades: they're hidden and counted."],
            H(L["Filters and actions"]),
            L["Swap turns the route around. Minimum profit, margin and data age narrow the list. At the buy auction house, Search (or Shift-clicking a row) searches the item there, which also fills in how many units still pay; Chart opens it on the Item tab."],
            L["Columns picks which columns show, as on the Market tab; the button says how many are hidden, counting the ones a narrow window has no room for."],
          },
        },
        {
          key = "tabPortfolio",
          title = Help.GUIDE[4][1],
          label = L["Portfolio"],
          body = {
            guideText(4),
            H(L["Five views"]),
            L["Positions is what you hold. Ledger lists your auction sales and purchases. Auctions is what's listed right now on every character. Customers and Suppliers rank who you trade with most - only when your auction mail names the other player (on some clients the auction house keeps them anonymous)."],
            H(L["Whose, and since when"]),
            L["Pick All characters (Account on a wide window: your characters on this market) or This character, and a period - Today, 7 days, 30 days or All time - for the ledger, the counterparties and the profit cards."],
            H(L["How sales get recorded"]),
            L["A sale shows up in the ledger as soon as the game says a buyer was found (awaiting mail), and is settled with the exact amount when its auction mail arrives - open your mailbox to catch it. Soulbound items aren't counted: they can't be sold."],
            H(L["Export"]),
            L["Export copies the list you're looking at, as a spreadsheet (paste it into Excel or Google Sheets) or as CSV."],
          },
        },
        {
          key = "tabSettings",
          title = L["Settings tab"],
          label = L["Settings"],
          body = {
            L["Open Settings with the cog at the top right of the window, left of the notification bell (or /ame config)."],
            L["Pick a section on the left: General (the window and notifications), Tooltips & charts, Selling, Sharing and Data (importing from Auctionator, rebuilding market data, the self-test, and how outrageous prices are ignored)."],
            L["The auction house cuts and the listing length under Selling count everywhere money is worked out: deposits, VENDOR calls, posting prices and arbitrage."],
            L["Full scans, under Data, picks what AME's own full scan reads (the Full scan button and /ame scan): Detailed reads every listing, once per 15 minutes; Fast reads each item's cheapest listing, any time. See Quick scans and full scans under Where the data comes from."],
          },
        },
        {
          key = "tabSync",
          title = L["Sharing prices"],
          label = L["Sharing"],
          body = {
            L["Sharing is a section of the Settings tab."],
            L["Guild members running AME share their full scans automatically, so everyone's prices stay fresh. Players outside your guild can share too: add them under Trusted players; they get a request to approve."],
            L["Sharing happens on its own every 10 minutes. Sync now (on the Sync activity card) does it right away: it sends what you have and asks your guild and trusted players to send theirs, so scans you're missing arrive within a minute or two."],
            H(L["Sync activity"]),
            L["The Sync activity card at the top of Sharing shows when the next announce is due, and what's being sent and received right now, each with a progress bar and the time it has left. A transfer that isn't moving says why and for how long: waiting its turn (the sender is sending other data first, a full day of prices can take half an hour) or stalled (nothing from the sender lately: offline, or they reloaded). Retry asks the sender again for what's missing; Cancel stops it, and it's asked for again later from whoever has it. Missing here lists what the players you share with announced that you don't have yet, per player and auction house: a newer full scan (Their scan says when it was taken), hours and days, its size, how long it takes to arrive (Takes), and whether it's on its way. Sizes are learned from what was sent before, so they are estimates until a transfer starts; players send at the same time, so catching up takes as long as the slowest of them."],
            H(L["Versions"]),
            L["AME tells the players you share with which version you run, and the player lists show theirs. When someone has a newer version than yours, AME says so once in chat and in the notification center, and the window's footer recommends updating until you do."],
            H(L["Sync protocol"]),
            L["With v2 (the default), every scan goes to the whole guild at once, and hours you missed in the last week are filled in from whoever has them - a point per hour for the 7D chart, and whole days for days you have nothing of. It's paced at about one message a second, so a full scan takes several minutes to arrive, in the background. If sync seems to slow your game, pick v1 (lighter) under Guild sharing: you still get scans, the original way. Guild sharing shows how many of the week's hours you have."],
            H(L["Sell-through"]),
            L["AME also shares how your auctions went - per item, how many units sold, expired or were cancelled, and what that taught the posting prices - no prices, gold or buyers. Everyone's outcomes add up: an item that never sells is found out after a few guildmates tried it, and posting advice learns from everyone's listings."],
            H(L["Keeping data honest"]),
            L["Scans that disagree wildly with your own prices are rejected, and you can block players. Guild officers can block players for the whole guild with a line in the guild info. The cards at the top show how fresh each auction house's data is and who scanned it."],
            L["The guild info line looks like this: AME block: Name, Name (any line, several allowed)."],
          },
        },
      },
    },
    {
      L["Trading"],
      {
        {
          key = "selling",
          title = L["Selling: posting prices"],
          body = {
            H(L["The bar under the sell window"]),
            EX("sellBar"),
            L["Quick goes under where the price usually dips within a few hours, so it sells soon even if the price slides. Normal weighs the price against the chance it sells. Patient waits for the price to swing back up to where it usually peaks within the listing time. Quick only shows when it's cheaper than Normal. Market is the item's market price. Click one to put it in the price box; you still click Post."],
            H(L["How the price is worked out"]),
            Help.TERMS.posting[2],
            H(L["It learns from your sales"]),
            L["AME remembers each listing you post and how fast it sold - or that it expired - and adjusts its estimates for that item. Items you sell often get advice of their own; others borrow from similar items."],
          },
        },
        {
          key = "numbers",
          title = Help.GUIDE[7][1],
          body = {
            guideText(7),
            H(L["Signals"]),
            EX("signals"),
            H(L["How much to trust a number"]),
            EX("confidence"),
            H(L["Market phases"]),
            L["The week's price move read against supply: shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand or dumping. It shows beside the signal."],
          },
        },
        {
          key = "watch",
          title = Help.GUIDE[6][1],
          body = {
            guideText(6),
            L["An alert fires once when its condition comes true, and again only after the price has moved back past its line. Alerts are checked after scans, after prices arrive from guild members and at login, and show on screen as well as in chat; the sound can be turned off under Settings, General. Signal alerts fire on Buy and Sell."],
            H(L["Notifications"]),
            L["The bell at the right end of the title bar is the notification center: it keeps the alerts that fired, players asking to share prices with you and news of a newer AME, newest first, with a red count of the ones you haven't seen. Click one to open its item (or, for a request or a new version, Settings, Sharing); Clear all empties it."],
            L['Using an info bar addon (Titan Panel, ChocolateBar, Bazooka and others that read LibDataBroker)? Add its "Notifications" entry: it shows how many you haven\'t seen, the newest on hover, and opens the list on a click.'],
            L["Right-click a guild member's shared list to copy it into your own watchlists."],
          },
        },
        {
          key = "shopping",
          title = L["Shopping lists"],
          body = {
            L["A shopping list is for buying toward something - the reagents for a robe you're about to craft - while a watchlist is for items you keep an eye on for good. Make one with \"+ New shopping list\" in the Market sidebar, from any item's right-click menu (Add to shopping list...), or from a recipe: open your profession window, pick the recipe, set how many you'll make and click Add to shopping list."],
            H(L["What's left to buy"]),
            L["Pick a list in the Market sidebar to see each item: how many you need, how many your characters on this realm have to use - bags, bank, mailbox and guild banks, as the craft queue counts them (hover a row for who holds what), how many are still to buy, the market price and what the rest costs. It counts down by itself as you buy or gather; the sidebar shows how many items are still short, and done once everything is covered."],
            H(L["Top prices and searching"]),
            L["Right-click an item on the list to change the quantity, set the most you'd pay for one (a star marks items at or under it right now) or remove it. Search the AH searches the open auction house for everything still needed - all at once with Auctionator."],
            H(L["The Shopping tab"]),
            L["Without Auctionator, the auction house window gets a Shopping tab next to Buy, Sell and Auctions. Pick a list on the left and click Search all: AME searches each item in turn, as fast as the game allows, and shows how many you still need, the cheapest listing, your top price, and what the rest costs. The sidebar shows how many items are still short on each list. Click an item for its listings, cheapest first, with how long each has left (for gear the game often gives only a range, such as 2-12 h); scroll for more. Buy asks the game for the price, then Confirm buys it - the game wants a click for each purchase - or Cancel backs out. Confirm only ever buys the item on screen: picking another item drops a purchase that wasn't confirmed. Clicking an item while Search all runs searches it first, then Search all goes on. The list counts down as you buy. Shift-click an item (in your bags, in chat) to search for it there, and Search the AH on AME's pages searches this tab too."],
            L["Search the auction house from its box at the top: a name, and under Filters a category, required level, item level, lowest quality, highest price each, exact name or only what you can use. Each result shows its cheapest listing against the market price, and the signal. Your recent searches stay on the left with their filters: click one to run it again, right-click to remove it."],
            H(L["At a vendor"]),
            L["When a vendor sells something one of your shopping lists still needs (thread, vials, flux...), a For your lists panel opens beside the merchant window: how many you need, what that buys in the vendor's stacks, and the cost. Buy takes one row, Buy all everything you can afford. The rows count down as the items reach your bags, and the panel isn't there at vendors with nothing you need."],
            H(L["The Selling tab"]),
            L["Next to it, Selling lists what in your bags can be listed, worth the most first (what each nets after the cut and deposit, or a vendor's price when that's more), with a tip for each: Sell (list it), Arbitrate (make something worth more from it first), DE or vendor - click the Tip heading to sort by it. Click one for AME's Quick, Normal and Patient prices and its market price, how many, how long and the deposit, then Post (the game's own posting, a click per post). What's on sale now shows beside it, yours marked: click a listing to price just under it. The AME window beside the auction house shows the item's chart. The game's Sell tab is still there, and right-clicking an item in your bags still fills it."],
            H(L["Sharing"]),
            L["Right-click a list to add a recipe's reagents, rename it, share it with your guild or delete it. Guild members' shared lists appear under yours: right-click one to copy it into your own."],
          },
        },
        {
          key = "professions",
          title = L["Profession window"],
          body = {
            L["Open a profession and AME adds what each recipe earns: on every recipe in the list, its profit after the auction house's cut, priced as the Crafting tab does: each reagent at market, from a vendor or crafted by a recipe you know, whichever is cheapest, and a bind-on-pickup product as one you can't sell. A recipe whose item or a reagent has no price yet says no price; hover a recipe for the breakdown. Under the window, a bar shows the picked recipe's cost to craft, what it sells for and the profit, and on the right how many of the item sell a day (Sells/day) and its market signal, as the Market tab shows it. Type how many to make for the batch's profit and what you'd actually spend - only the reagents you don't have."],
            L["Queue adds the batch to the craft queue, Add to shopping list puts its reagents on a list (pick one or make a new one), and at the auction house Search AH looks up the item and every reagent."],
            L["With the new window on, opening a profession opens AME's Crafting tab on it. Use the game's window, at the right of its toolbar, swaps to the game's own profession window with AME's frame beside it, and Open in AME on that frame swaps back; AME remembers which you used. If the Crafting tab ever shows Something went wrong, the same button is on it."],
            H(L["The craft queue"]),
            L["The queue opens beside the profession window (Show queue under the window opens and closes it). Parts come first: queue gauntlets and the bars they need are smelted ahead of them, when one of your characters can smelt them. Where buying the bars is cheaper, the line says so (Buy or Make on the line switches it). Each material shows its source in a fixed order: your bags, your bank, your other characters, a guild bank, a vendor, a step of the queue, and the auction house for the rest."],
            L["Craft next crafts the next step this character can make right now. A step only another character knows says whose it is: log over to craft it there. Missing to shopping list puts what's left to buy on the Craft queue shopping list."],
            L["When that step belongs to another of this character's professions, Craft next opens that profession's window on it: click Craft next again to craft it."],
            H(L["Who can make it"]),
            L["Looking for someone to craft something? /ame who (or Who can make it in an item's right-click menu) searches the recipes your guildmates, trusted players and your own characters know, by name - enchants too. Under a recipe taught by a recipe item (a formula, plans, a pattern), that item and its price on the auction house, should you rather learn it yourself; the top line says how many players the recipes came from. Crafters online now come first; Whisper opens the chat box to them with the item linked, for you to send. Hold Shift on a craftable item's tooltip to see who can make it."],
            L["Each AME shares what its characters can craft (recipe IDs only) along with the guild's sync - open each of your professions once so yours count. Turn it off under Settings, Sharing: Share what my characters can craft."],
            H(L["Where to get a recipe"]),
            L["A recipe item's tooltip (pattern, plans, formula...) says where it comes from: which vendor sells it, where and for how much, or what drops it. AME learns this as you and your guild play - from merchants you open and recipes you loot - and shares it over sync. Until someone has seen it, the tooltip shows the game's own source text for recipes your profession window lists but you haven't learned."],
          },
        },
        {
          key = "otherAddons",
          title = L["Other addons"],
          body = {
            H(L["Baganator"]),
            L["With Baganator, AME adds three icon corners and a sort. In Baganator's settings, under Icons, place AME: signal (the item's market signal as its icon: BUY or SELL, and HOLD and WAIT if you ask for them), AME: tip (what to do with it, as the Selling tab's Tip says: Arb, DE or Vend, and Sell if you ask for it) and AME: value (what it's worth, in the coin's colour) in a corner; pick AME: worth as the sort to put the most valuable stacks first. The tip only marks a slot: what's junk is Baganator's own. Settings, General, Other addons says what the tip and value corners show, or turns it all off."],
            H(L["Launchers"]),
            L["AME's launcher works with the minimap button, info bar addons that read LibDataBroker, and the game's addon menu by the minimap: left-click opens the window, right-click the settings."],
            H(L["For addon authors"]),
            L["AzerothMercantileExchange.API.v1 gives other addons and WeakAuras AME's numbers for an item at your faction's auction house: GetMarketPrice, GetWorth, GetSignal, GetItemInfo and GetPostingPrice (item ID or link; copper), and RegisterForUpdates to hear when new prices are in. Core/API.lua describes each."],
          },
        },
        {
          key = "commands",
          title = Help.GUIDE[8][1],
          body = {
            guideText(8),
            L["Also: /ame who <item> - who in your guild (or of your characters) can make it.   /ame scan runs a detailed or fast full scan, as Settings, Data says."],
            L["Helping test AME, or is it slowing your game? /amedev on starts measuring what AME costs (and every fight, quietly), until /amedev off. Play a while, then /amedev send: it sends what was measured to AME's developer in the background. /amedev help lists the rest."],
            L["Not getting prices from your guild? /amedev sync shows what decides it here: whether sharing is on, the market AME thinks you're on, who it has heard from, and why anything that came in was turned down. /amedev send sends that to AME's developer too."],
          },
        },
      },
    },
  }
  local glossary = {}
  for _, key in ipairs(Help.GLOSSARY) do
    local term = Help.TERMS[key]
    if term then
      glossary[#glossary + 1] = { key = key, title = term[1], body = { term[2] } }
    end
  end
  groups[#groups + 1] = { L["Glossary"], glossary }
  return groups
end

-- Slash commands in article text become links: coloured like code, and a click puts the command in the chat box
-- (the player presses Enter; addons can't run slash commands for them). Commands aren't translated, so they're
-- found in any language's text: "/ame", or "/ame" and one of its words.
Help.CODE_COLOR = "8fd0ff"
local SUBCOMMANDS = {
  status = true,
  config = true,
  selftest = true,
  backfill = true,
  help = true,
  item = true,
  sync = true,
  scan = true,
  who = true,
}
function Help.CommandLink(cmd)
  return ("|Hamecmd:%s|h|cff%s%s|r|h"):format(cmd, Help.CODE_COLOR, cmd)
end
function Help.LinkCommands(text)
  return (
    text:gsub("/ame( ?)(%a*)", function(space, word)
      if space == " " and SUBCOMMANDS[word:lower()] then
        return Help.CommandLink("/ame " .. word)
      end
      return Help.CommandLink("/ame") .. space .. word
    end)
  )
end
-- the command in a link (nil for other links)
function Help.LinkedCommand(link)
  return type(link) == "string" and link:match("^amecmd:(.+)$") or nil
end
-- put a command in the chat box, ready to send
function Help.PrefillChat(cmd)
  if ChatFrame_OpenChat then
    ChatFrame_OpenChat(cmd)
  end
end

-- the text of a block (for search)
function Help.BlockText(b)
  if type(b) == "string" then
    return b
  end
  return b.h or ""
end

---------------------------------------------------------------------------------------------------------------------
-- examples: AME's own elements, drawn in an article. Each builder makes a frame in `parent` and returns it with
-- its height set (width: the article's width).

local function row(parent, y, left, right, leftW)
  local a = W.Text(parent, "GameFontHighlightSmall")
  a:SetPoint("TOPLEFT", 10, y)
  a:SetWidth(leftW or 120)
  a:SetText(left)
  local b = W.Text(parent, "GameFontHighlightSmall")
  b:SetPoint("TOPLEFT", 10 + (leftW or 120) + 8, y)
  b:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
  b:SetWordWrap(true)
  b:SetText(right)
  return a, b
end

local function panel(parent, height)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Skin(f, W.COLORS.panel)
  f:SetHeight(height)
  return f
end

-- a label / value line like the sidebar cards
local function pair(parent, y, label, value)
  local a = W.Text(parent, "GameFontDisableSmall")
  a:SetPoint("TOPLEFT", 10, y)
  a:SetText(label)
  local b = W.Text(parent, "GameFontHighlightSmall", "RIGHT")
  b:SetPoint("TOPRIGHT", -10, y)
  b:SetText(value)
end

-- Candles drawn the way the Item chart draws them (a 1 px wick from low to high, a body from open to close; green
-- closed higher, red lower), from made-up prices, into box (x, y from the top-left of f, w by h).
--   data: { { open, high, low, close }, ... }; lo, hi: the price range the box spans (default: the data's).
-- Returns yOf(price) and xOf(i) for annotations.
local function drawCandles(f, x, y, w, h, data, lo, hi, maxBody)
  if not lo then
    lo, hi = math.huge, -math.huge
    for _, c in ipairs(data) do
      lo, hi = math.min(lo, c[3]), math.max(hi, c[2])
    end
    local pad = (hi - lo) * 0.08
    lo, hi = lo - pad, hi + pad
  end
  local function yOf(p)
    return y + (hi - p) / (hi - lo) * h
  end
  local slot = w / #data
  local bw = math.max(3, math.min(maxBody or 12, math.floor(slot * 0.6)))
  local function xOf(i)
    return math.floor(x + (i - 0.5) * slot)
  end
  for i, c in ipairs(data) do
    local col = c[4] >= c[1] and W.COLORS.up or W.COLORS.down
    local wick = f:CreateTexture(nil, "ARTWORK")
    wick:SetColorTexture(col[1], col[2], col[3], 0.8)
    wick:SetSize(1, math.max(1, yOf(c[3]) - yOf(c[2])))
    wick:SetPoint("TOP", f, "TOPLEFT", xOf(i) + 0.5, -yOf(c[2]))
    local body = f:CreateTexture(nil, "OVERLAY")
    body:SetColorTexture(col[1], col[2], col[3], 1)
    body:SetSize(bw, math.max(1, yOf(math.min(c[1], c[4])) - yOf(math.max(c[1], c[4]))))
    body:SetPoint("TOP", f, "TOPLEFT", xOf(i) + 0.5, -yOf(math.max(c[1], c[4])))
  end
  return yOf, xOf, bw
end

-- candles from closing prices, the way AME builds them: each opens where the last one closed. Optional per-candle
-- extras: lows[i] / highs[i] (how far the wick reaches beyond the body).
local function chain(closes, lows, highs)
  local out, prev = {}, closes[1]
  for i, c in ipairs(closes) do
    local o = i == 1 and c - 2 or prev
    out[i] = {
      o,
      math.max(o, c) + ((highs and highs[i]) or 2),
      math.min(o, c) - ((lows and lows[i]) or 3),
      c,
    }
    prev = c
  end
  return out
end

Help.EXAMPLES = {
  -- one green and one red candle, the green one's four prices labelled
  candleAnatomy = function(parent)
    local f = panel(parent, 176)
    local data = { { 100, 141, 70, 128 }, { 128, 133, 98, 112 } }
    local yOf, xOf, bw = drawCandles(f, 16, 14, 110, 140, data, 62, 146, 18)
    local labels = {
      { 141, L["High: the highest price seen"] },
      { 128, L["Close: the market price at the end"] },
      { 100, L["Open: where the previous candle closed"] },
      { 70, L["Low: the cheapest listing seen (the wick)"] },
    }
    for _, l in ipairs(labels) do
      local y = math.floor(yOf(l[1]))
      local line = f:CreateTexture(nil, "ARTWORK")
      W.Fill(line, W.COLORS.border)
      line:SetHeight(1)
      line:SetPoint("TOPLEFT", f, "TOPLEFT", xOf(1) + bw / 2 + 3, -y)
      line:SetPoint("RIGHT", f, "TOPLEFT", 150, 0)
      local t = W.Text(f, "GameFontHighlightSmall")
      t:SetPoint("LEFT", f, "TOPLEFT", 156, -y)
      t:SetPoint("RIGHT", f, "RIGHT", -10, 0)
      t:SetText(l[2])
    end
    for i, word in ipairs({ W.Color("good", L["Up"]), W.Color("bad", L["Down"]) }) do
      local t = W.Text(f, "GameFontDisableSmall", "CENTER")
      t:SetPoint("TOP", f, "TOPLEFT", xOf(i), -158)
      t:SetText(word)
    end
    return f
  end,
  -- five shapes worth knowing, each a small chart beside what it means
  candlePatterns = function(parent)
    local patterns = {
      {
        chain({ 100, 104, 103, 109, 114, 120, 126, 131 }),
        L["Climbing: green candles, each closing higher. Buyers take listings faster than sellers replace them."],
      },
      {
        chain({ 100, 101, 99, 100, 102, 101, 100, 101 }, { 3, 24, 4, 28, 3, 22, 4, 26 }),
        L["Long lower wicks, steady bodies: someone keeps listing far below the market, and those sell before the price moves. Cheap copies are worth watching for."],
      },
      {
        chain({ 100, 102, 101, 103, 102, 104, 103, 104 }, nil, { 2, 2, 2, 34, 2, 2, 2, 2 }),
        L["A tall upper wick: the price jumped once - often a scan with nothing cheap up - and didn't hold. Don't price off the spike."],
      },
      {
        chain({ 100, 103, 106, 108, 110, 93, 86, 84 }),
        L["A big red candle after a climb: sellers piled in and undercut each other. Check the supply bars below the candles before buying into it."],
      },
      {
        chain({ 100, 101, 100, 101, 100, 100, 101, 100 }, { 1, 1, 1, 1, 1, 1, 1, 1 }, { 1, 1, 1, 1, 1, 1, 1, 1 }),
        L["Small bodies, short wicks: a quiet, steady market. Its market price is a safe guide."],
      },
    }
    local ROW = 62
    local f = panel(parent, #patterns * ROW + 8)
    for k, p in ipairs(patterns) do
      local top = 8 + (k - 1) * ROW
      local box = f:CreateTexture(nil, "BACKGROUND", nil, 1)
      W.Fill(box, W.COLORS.chart.bg)
      box:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -top)
      box:SetSize(140, ROW - 8)
      drawCandles(f, 14, top + 4, 132, ROW - 16, p[1])
      local t = W.Text(f, "GameFontHighlightSmall")
      t:SetPoint("TOPLEFT", f, "TOPLEFT", 162, -top - 4)
      t:SetPoint("RIGHT", f, "RIGHT", -10, 0)
      t:SetWordWrap(true)
      t:SetText(p[2])
    end
    return f
  end,
  signals = function(parent)
    local f = panel(parent, 6 * 22 + 12)
    local rows = {
      { "buy", L["Unusually cheap for this item, given how much its price usually moves"] },
      { "hold", L["Within its usual range"] },
      { "sell", L["Unusually expensive for this item, given how much its price usually moves"] },
      { "wait", L["Cheap, but sellers are dumping: wait for the bottom"] },
      { "vendor", L["A vendor pays more than the auction house nets after the cut and the deposit"] },
      { "disenchant", L["Its enchanting materials are worth more than it sells for: disenchant it"] },
    }
    for k, r in ipairs(rows) do
      row(f, -8 - (k - 1) * 22, W.SignalGlyph(r[1]), W.Dim(r[2]), 90)
    end
    return f
  end,
  confidence = function(parent)
    local f = panel(parent, 3 * 22 + 12)
    local rows = {
      { "high", L["plenty of recent scans"] },
      { "medium", L["some recent scans"] },
      { "low", L["few or old scans: treat with care"] },
    }
    for k, r in ipairs(rows) do
      row(f, -8 - (k - 1) * 22, W.Confidence(r[1]), W.Dim(r[2]), 40)
    end
    return f
  end,
  sellBar = function(parent)
    local f = panel(parent, 50)
    -- as the bar draws itself (SellAssist): the accent line on top, the price large, the confidence by the buttons
    local edge = f:CreateTexture(nil, "OVERLAY")
    edge:SetHeight(2)
    edge:SetPoint("TOPLEFT", 1, -1)
    edge:SetPoint("TOPRIGHT", -1, -1)
    W.Fill(edge, W.COLORS.accent)
    local title = W.Text(f, "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetText(L["Post at %s"]:format(W.Money(18700)))
    local unit = W.Text(f, "GameFontDisableSmall")
    unit:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)
    unit:SetText(L["per unit"])
    local info = W.Text(f, "GameFontDisableSmall")
    info:SetPoint("BOTTOMLEFT", 12, 8)
    info:SetPoint("RIGHT", -10, 0)
    info:SetWordWrap(false)
    info:SetText(
      L["Just under %d listed at %s"]:format(20, W.Money(19100))
        .. "  ·  "
        .. L["sells in %s"]:format(W.Hours(5))
        .. "  ·  "
        .. L["you net %s after the %d%% cut"]:format(W.Money(17765), 5)
    )
    local prev
    for i, b in ipairs({
      { L["Market %s"]:format(W.Money(16400)) },
      { L["Patient %s"]:format(W.Money(20900)) },
      { L["Normal %s"]:format(W.Money(18700)), true },
      { L["Quick %s"]:format(W.Money(13800)) },
    }) do
      local btn = W.Button(f, b[1], 80, 22)
      btn:SetWidth(math.ceil(btn.label:GetStringWidth() or 60) + 20)
      if i == 1 then
        W.Primary(btn) -- Market, the bar's main action
      end
      btn:SetSelected(b[2] or false)
      if prev then
        btn:SetPoint("RIGHT", prev, "LEFT", -6, 0)
      else
        btn:SetPoint("TOPRIGHT", -10, -5)
      end
      prev = btn
    end
    local conf = W.Text(f, "GameFontDisableSmall")
    conf:SetPoint("RIGHT", prev, "LEFT", -12, 0)
    conf:SetText(L["Confidence"] .. " " .. W.Confidence("high"))
    return f
  end,
  verdict = function(parent)
    local f = panel(parent, 96)
    pair(f, -8, L["Verdict"], W.SignalGlyph("sell"))
    local head = W.Text(f, "GameFontHighlight")
    head:SetPoint("TOPLEFT", 10, -28)
    head:SetText(L["Pricier than usual"])
    local why = W.Text(f, "GameFontHighlightSmall")
    why:SetPoint("TOPLEFT", 10, -48)
    why:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    why:SetWordWrap(true)
    why:SetText(
      L["%d%% above its %d-day average (%s)"]:format(56, 7, W.Money(61300))
        .. L["; it usually moves ~%d%% a day"]:format(8)
        .. ". "
        .. L["Good time to post."]
    )
    return f
  end,
  legend = function(parent)
    local c = W.COLORS.chart -- the chart's own colours
    local rows = {
      { c.market, L["Market"], 12, 3 },
      { c.lowest, L["Lowest"], 12, 3 },
      { c.average, L["7-day average"], 12, 3 },
      { c.fast, L["MA %d (%s)"]:format(20, L["%d days"]:format(5)), 12, 3 },
      { c.supply, L["Supply"], 8, 8 },
      { c.bought, L["You bought"], 8, 8 },
      { c.sold, L["You sold"], 8, 8 },
    }
    local f = panel(parent, #rows * 16 + 12)
    for k, r in ipairs(rows) do
      local sw = f:CreateTexture(nil, "OVERLAY")
      sw:SetSize(r[3], r[4])
      sw:SetPoint("LEFT", f, "TOPLEFT", 12, -14 - (k - 1) * 16)
      sw:SetColorTexture(r[1][1], r[1][2], r[1][3], 1)
      local t = W.Text(f, "GameFontHighlightSmall")
      t:SetPoint("LEFT", f, "TOPLEFT", 30, -14 - (k - 1) * 16)
      t:SetText(r[2])
    end
    return f
  end,
  route = function(parent)
    local f = panel(parent, 5 * 18 + 22)
    pair(f, -8, L["Buy at the %s"]:format(L["Horde AH"]), W.Money(57500))
    pair(f, -26, L["Sells at the %s"]:format(L["Goblin AH"]), W.Money(78500))
    pair(f, -44, L["%d%% cut"]:format(15), W.Color("bad", "- " .. W.Plain(W.Money(11775))))
    pair(f, -62, L["Deposit if unsold"], W.Money(10000))
    pair(f, -86, L["You net"], W.Color("good", "+" .. W.Plain(W.Money(-0 + 9225))))
    return f
  end,
  signalFilter = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(24)
    local items = { { "all", L["All"] } }
    for _, key in ipairs({ "buy", "hold", "sell", "wait", "vendor", "disenchant" }) do
      items[#items + 1] = { key, W.SignalGlyph(key), W.SignalTone(key) }
    end
    local seg = W.Segmented(f, items, { minWidth = 40 })
    seg:SetPoint("LEFT", 0, 0)
    seg:Select("buy", true)
    return f
  end,
}

-- The Guide: a side menu of articles by group (UI.SideList, filtered by the search box) and the article on a panel on
-- the right, scrolling when long. Narrow window: the sidebar becomes a dropdown next to the search box.
Help.ARTICLE_WIDTH = 640 -- longest comfortable line

function Help.CreateGuide(parent, contentArea)
  local UI = ns.UI
  local v = contentArea(parent)
  local slots = UI.Slots(v, { toolbar = 22, left = ns.UI.SIDEBAR_W, status = true })
  v.slots = slots
  slots.status:SetText(
    L["Created by Tyken Evanion  ·  PvP Horde, WoW Forever"] -- the name is in the title bar, the version on the right
  )
  local groups = Help.Articles()
  v.byKey, v.order, v.shownArticle = {}, {}, false
  for _, g in ipairs(groups) do
    for _, a in ipairs(g[2]) do
      a.group = g[1]
      v.byKey[a.key] = a
      v.order[#v.order + 1] = a
    end
  end

  -- sidebar: the articles under their group headings, the shared side menu (the glossary's heading counts its terms)
  local total = 0
  for _, g in ipairs(groups) do
    total = total + 1 + #g[2]
  end
  v.nav = UI.SideList(slots.left, {
    rows = total,
    onClick = function(e)
      v:ShowArticle(e.key)
    end,
  })
  -- the menu's entries for the articles that match, the shown one selected and paged into view
  function v:RenderNav()
    local entries, at = {}, nil
    for _, e in ipairs(self.navEntries or {}) do
      if e.article then
        e.selected = e.article == self.shownArticle
        at = e.selected and #entries + 1 or at
      end
      entries[#entries + 1] = e
    end
    local nav = self.nav
    if at and (at <= nav.offset or at > nav.offset + nav.rows) then
      nav.offset = math.max(0, at - math.floor(nav.rows / 2))
    end
    nav:SetEntries(entries)
  end

  -- lay the sidebar out, showing only articles matching the search (a group's heading when any of it matches)
  local function matches(a, text)
    if not text or text == "" then
      return true
    end
    if a.title:lower():find(text, 1, true) or (a.label and a.label:lower():find(text, 1, true)) then
      return true
    end
    for _, b in ipairs(a.body) do
      if Help.BlockText(b):lower():find(text, 1, true) then
        return true
      end
    end
    return false
  end
  function v:Filter(text)
    text = text and text:lower() or nil
    self.matches, self.navEntries = {}, {}
    for _, g in ipairs(groups) do
      local shown = {}
      for _, a in ipairs(g[2]) do
        if matches(a, text) then
          shown[#shown + 1] = a
        end
      end
      if #shown > 0 then
        local glossary = g[1] == L["Glossary"]
        self.navEntries[#self.navEntries + 1] =
          { heading = g[1], note = glossary and L["%d terms"]:format(#g[2]) or nil }
        for _, a in ipairs(shown) do
          -- the sidebar's short name; the article keeps its full title
          self.navEntries[#self.navEntries + 1] = { label = a.label or a.title, key = a.key, article = a }
          self.matches[#self.matches + 1] = a
        end
      end
    end
    self.nav.offset = 0
    self:RenderNav()
    -- the compact dropdown lists the same articles
    local options = {}
    for i, a in ipairs(self.matches) do
      options[i] = { a.key, a.label or a.title }
    end
    if #options == 0 then
      options[1] = { false, L["No articles match"] }
    end
    self.pick:SetOptions(options)
    if self.shownArticle then
      self.pick:SetValue(self.shownArticle.key)
    end
  end

  -- toolbar: search, and (compact) the article dropdown
  v.search = W.Input(slots.toolbar, {
    width = ns.UI.SIDEBAR_W, -- lines up with the sidebar under it
    hint = L["Search the guide..."],
    onChange = function(text)
      v:Filter(text)
      if v.matches[1] and text ~= "" then
        local still = false
        for _, a in ipairs(v.matches) do
          still = still or a == v.shownArticle
        end
        if not still then
          v:ShowArticle(v.matches[1].key)
        end
      end
    end,
    clearOnEscape = true,
  })
  v.search:SetPoint("LEFT", 0, 0)
  v.pick = W.Dropdown(slots.toolbar, 220, { { "start", "" } }, function(key)
    if key then
      v:ShowArticle(key)
    end
  end, { neutral = true })
  v.pick:SetPoint("LEFT", v.search, "RIGHT", 8, 0)

  -- the article, on a panel of its own
  v.article = W.Panel(slots.main)
  v.article:SetAllPoints()
  local pane = W.ScrollPane(v.article)
  local page = pane.content
  v.pane = pane
  v.title = W.Text(page, "GameFontNormalLarge")
  v.title:SetPoint("TOPLEFT", 16, -10)
  -- slash commands in paragraphs are links (Help.LinkCommands): hover tells what a click does
  if page.SetHyperlinksEnabled then
    page:SetHyperlinksEnabled(true)
  end
  page:SetScript("OnHyperlinkClick", function(_, href)
    local cmd = Help.LinkedCommand(href)
    if cmd then
      Help.PrefillChat(cmd)
    end
  end)
  page:SetScript("OnHyperlinkEnter", function(self, href)
    local cmd = Help.LinkedCommand(href)
    if cmd then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      GameTooltip:SetText(cmd, 1, 1, 1)
      GameTooltip:AddLine(L["Click to put it in your chat box"], nil, nil, nil, true)
      GameTooltip:Show()
    end
  end)
  page:SetScript("OnHyperlinkLeave", function()
    GameTooltip:Hide()
  end)
  v.crumb = W.Text(page, "GameFontDisableSmall")
  v.crumb:SetPoint("BOTTOMLEFT", v.title, "TOPLEFT", 0, 2)
  -- paragraphs and headings come from pools; examples are built once per article and kept
  v.paras, v.heads, v.examples, v.blocks = {}, {}, {}, {}
  local function para(i)
    local p = v.paras[i]
    if not p then
      p = W.Text(page, "GameFontHighlight")
      p:SetJustifyH("LEFT")
      p:SetWordWrap(true)
      p:SetSpacing(4)
      v.paras[i] = p
    end
    return p
  end
  local function sectionHeading(i)
    local h = v.heads[i]
    if not h then
      h = W.Text(page, "GameFontNormal")
      h:SetJustifyH("LEFT")
      v.heads[i] = h
    end
    return h
  end
  local function example(key, index, name)
    local id = key .. ":" .. index
    local e = v.examples[id]
    if not e and Help.EXAMPLES[name] then
      e = Help.EXAMPLES[name](page)
      v.examples[id] = e
    end
    return e
  end
  v.related = W.Text(page, "GameFontDisableSmall")
  local function width()
    local w = (slots.main:GetWidth() or 0) - 40
    if w <= 0 then
      w = Help.ARTICLE_WIDTH
    end
    return math.min(w, Help.ARTICLE_WIDTH)
  end
  function v:LayoutArticle()
    local w = width()
    self.title:SetWidth(w)
    for _, p in ipairs(self.paras) do
      p:SetWidth(w)
    end
    for _, e in pairs(self.examples) do
      e:SetWidth(w)
    end
    pane:Measure()
  end
  slots.main:SetScript("OnSizeChanged", function()
    v:LayoutArticle()
  end)

  function v:ShowArticle(key)
    local a = self.byKey[key] or self.order[1]
    self.shownArticle, self.term = a, a.key
    self.crumb:SetText(a.group)
    self.title:SetText(a.title)
    -- lay the blocks out top to bottom: paragraphs, section headings, and live examples
    for _, p in ipairs(self.paras) do
      p:Hide()
    end
    for _, h in ipairs(self.heads) do
      h:Hide()
    end
    for _, e in pairs(self.examples) do
      e:Hide()
    end
    local prev, np, nh = self.title, 0, 0
    for i, b in ipairs(a.body) do
      local obj, gap
      if type(b) == "string" then
        np = np + 1
        obj, gap = para(np), 10
        obj:SetText(Help.LinkCommands(b))
      elseif b.h then
        nh = nh + 1
        obj, gap = sectionHeading(nh), 16
        obj:SetText(b.h)
      elseif b.example then
        obj, gap = example(a.key, i, b.example), 8
      end
      if obj then
        obj:ClearAllPoints()
        obj:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, prev == self.title and -12 or -gap)
        obj:Show()
        prev = obj
      end
    end
    self:RenderNav()
    self.pick:SetValue(a.key)
    pane:SetScroll(0)
    self:LayoutArticle()
  end
  -- a glossary term (right-click on an explained header or number)
  function v:ShowTerm(key)
    self:ShowArticle(key)
  end

  function v:SetCompact(on)
    slots:SetCompact(on)
    self.pick:SetShown(on)
  end
  v:SetCompact(slots.compact)
  v:Filter(nil)
  v:ShowArticle("start")
  v:HookScript("OnShow", function(self)
    self:LayoutArticle()
  end)
  return v
end
