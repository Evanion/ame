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
    L["Market sales per day (estimate)"],
    L["How fast the item moves: units that disappeared between consecutive full scans of this auction house, per day, over the last week. It counts sold, cancelled and expired listings, and new listings hide some sales, so treat it as a rough guide. A cheap item that never sells is a trap; a high number means you can sell a stack quickly. Needs a few full scans on the same day to show."],
  },
  signal = {
    L["Signal"],
    L["BUY: today's price is unusually low for this item - at least 1.5 standard deviations below its own 30-day average. SELL: unusually high by the same measure. HOLD: within its normal range - keep it if you own it, no edge to buy. WAIT: cheap, but sellers are dumping - wait for the bottom. Needs 7+ days of history (\"-\" until then). The market phase reads the week's price move against supply: shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand or dumping. It compares the item with itself, and it's a hint, not financial advice."]
      .. " "
      .. L["VENDOR: after the AH cut and the listing deposit, the auction house pays less than a vendor would - sell it to a vendor."],
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
    L["The market price at the auction house you sell at: what the item typically sells for there."],
  },
  arbNet = {
    L["Net"],
    L["Per item: what it sells for, minus the AH cut, minus the listing deposit, minus what you paid. The deposit is counted for one post of the units the route pays for (or up to 20), at least 1 silver per post - you get it back when it sells."],
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
    L["Market sales per day at the sell house"],
    L["Estimated units sold per day where you'd sell. Compare it with how many you plan to buy: if it sells 5 a day, 100 will take weeks."],
  },
  arbDepth = {
    L["Depth"],
    L["How many units you can buy at the buy auction house before the route stops paying, and the total profit: every listing priced below what one sells for after the cut. It needs the item's listings, so search the item at the buy house first (the Search button does it) - it then stays for 6 hours. Selling that many still takes time: check Sales/day."],
  },
  arbAge = {
    L["Data"],
    L["How old the older of the two prices is. Fresh data on both sides makes a route trustworthy - scan both auction houses (alts on this account count) before buying."],
  },
  pfValue = {
    L["Holdings value"],
    L["Everything your characters hold - bags, bank and active auctions - at your faction auction house's market price, except soulbound items (they can't be sold) and items you hid. Bank items and auctions are counted as of the last time you opened the bank / auction house."],
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
    L["Gold received from auction sales (after the cut) and gold spent on auction purchases in the chosen period."],
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
    tip:AddLine(L["Right-click: open it in the Guide's glossary"], 0.5, 0.5, 0.5)
  end, "ANCHOR_TOP")
  -- right-click: the term's glossary entry on the Guide tab
  frame:HookScript("OnMouseUp", function(_, button)
    if button == "RightButton" and ns.UI and ns.UI.ShowGuide then
      ns.UI:ShowGuide(key)
    end
  end)
end

-- the glossary at the end of the Guide: every explained term, in this order
Help.GLOSSARY = {
  "market",
  "min",
  "avg",
  "vsAvg",
  "change7",
  "vol30",
  "qty",
  "sellRate",
  "signal",
  "score",
  "phase",
  "age",
  "name",
  "confidence",
  "posting",
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
    L["A screener over every item with history. Pick a category or watchlist on the left, search by name, filter by quality, price range or signal, and click a column to sort. Hover a column header for what it means. Click a row to open its chart; click the star to watch it. Right-click a row for more: search the auction house, watchlists, an alert, a chat link, or hiding items you don't trade (they move to Hidden in the sidebar, where you can unhide them)."],
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
    L["The price chart: market price, lowest listing, 7-day average and supply. Switch to candles for a trading view. Mouse wheel zooms, drag pans, double-click resets. To chart an item, type its name in the search box above the chart (Enter opens the best match), Shift-click it anywhere (bags, chat, the AH) while the Item tab is showing, or pick a modifier click under Settings, Tooltips & charts that charts it from anywhere."],
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
    L["/ame - open the window.   /ame <item link> - chart an item.   /ame item <item link> - its history in chat.   /ame status - data, sharing and price check status.   /ame config - settings.   /ame sync - sharing settings.   /ame backfill - import Auctionator's history now.   /ame selftest - check everything is working.   /ame help - the commands in chat."],
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
            L["AME records the auction house while you use it and turns it into price history, charts, signals and posting prices. There's nothing to set up: open the auction house and run a full scan (Auctionator's, or the game's own), and AME records it."],
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
            L["Every item tooltip in the game gets AME's lines: the market price against its average, how many are listed and how many sell a day, and the signal with the market phase. Hold Shift for more - the average, the lowest listing, the 7-day change, the supply trend, volatility, the score and how much data it rests on - or show it all the time with Always show details."],
            L["Tooltips show your own faction's auction house. Turn them off, or change the average they compare with, under Settings, Tooltips & charts."],
          },
        },
        {
          key = "data",
          title = Help.GUIDE[1][1],
          body = {
            guideText(1),
            H(L["Other auction houses"]),
            L["The button next to AME's title picks which auction house you're looking at: yours, the other faction's or the goblin AH. Each keeps its own history; scan there (any character on this account counts) to fill it."],
            H(L["Importing from Auctionator"]),
            L["If Auctionator is installed, AME imports its recent daily prices for days it has no data for, once, when you open the auction house - your faction's only. The Import button under Settings, Data does it again."],
            H(L["Random-suffix gear"]),
            L['Gear with a random suffix ("of the Monkey", "of Magic") is tracked per suffix, since each sells at its own price. Charts, tooltips and your portfolio use the suffix of the item in hand.'],
            H(L["How long history is kept"]),
            L["Every scan is kept for 2 days (the 2D chart), a point per day for 60 days, then a point per week for a year. Your ledger keeps 90 days."],
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
            H(L["Filtering by signal"]),
            EX("signalFilter"),
            L["Pick a signal to see only those items. Active filters show as chips under the toolbar: click one to remove it, or Clear all."],
            H(L["Views and columns"]),
            L["Views saves the filters you use often and brings them back in one click. Columns picks which columns show; the button says how many are hidden."],
            H(L["Shift-clicks"]),
            L["With the auction house open, Shift-click a row to search for it there. While the search box has focus, Shift-click an item link anywhere to search for it by name."],
            H(L["The item menu"]),
            L["Right-click any item in a list - Market, Arbitrage or Portfolio - for what you can do with it: open its chart, search the auction house for it (while the auction house is open), add it to a watchlist, set a price alert, or put its link in the chat box."],
            H(L["Hiding items"]),
            L["Items you never trade can be hidden - drinks you buy from a vendor, for example: right-click one in the Market, Arbitrage or Portfolio list and pick Hide from lists, or use the button on its item page. Hidden items leave those lists and their totals, on every auction house and character (Portfolio says how many it left out and what they're worth), but AME keeps recording their prices, your ledger keeps every sale and purchase, and their tooltips still work. They're listed under Hidden in the Market sidebar: right-click one there to unhide it, or unhide them all under Settings, Tooltips & charts."],
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
            L["Market price, the lowest listing, the 7-day average, supply, and your own buys and sales as dots."],
            L["Hover the item's name or icon at the top for the game's own tooltip, with its stats."],
            H(L["Ranges"]),
            L["2D shows every scan from the last two days, with 2-hour candles. The longer ranges show a point per day, and per week beyond 60 days."],
            H(L["Following the auction house"]),
            L["While the Item tab is showing, it follows the item you search at the auction house. Put an item up for sale and AME switches to the Item tab for it, wherever it was (Settings, General: Switch to the Item tab for what you put up for sale)."],
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
            L["Pick All characters or This character, and a period - Today, 7 days, 30 days or All time - for the ledger, the counterparties and the profit cards."],
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
            L["Pick a section on the left: General (the window and notifications), Tooltips & charts, Selling, Sharing and Data (importing from Auctionator, rebuilding market data, the self-test, and how outrageous prices are ignored)."],
            L["The auction house cuts and the listing length under Selling count everywhere money is worked out: deposits, VENDOR calls, posting prices and arbitrage."],
          },
        },
        {
          key = "tabSync",
          title = L["Sharing prices"],
          label = L["Sharing"],
          body = {
            L["Sharing is a section of the Settings tab."],
            L["Guild members running AME share their full scans automatically, so everyone's prices stay fresh. Players outside your guild can share too: add them under Trusted players; they get a request to approve."],
            H(L["Price checks"]),
            L["Turn on Price checks and anyone who types !pc and an item in guild, party or raid chat gets its prices from you - market, lowest and 7-day average at your faction's auction house, and how old they are. When several players run AME, they agree among themselves and only one answers. Whispers can be answered too, for guild members, friends, your party or raid, and trusted players - never strangers. You answer at most once every 5 seconds - change it under Settings, Sharing - so nobody can make you flood the chat; while you wait, another AME player answers instead."],
            L["Your own !pc is always answered, in the channel you asked in, even with Price checks off: ask in party and everyone sees the answer. A request takes an item link or the item's exact name. Inside dungeons, raids and boss encounters the game hides chat from addons, so price checks can't be answered there."],
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
            L["Quick sells within a few hours almost surely. Normal weighs the price against the chance it sells. Patient is the highest price that still sells about half the time. Market is the item's market price. Click one to put it in the price box; you still click Post."],
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
            L["Right-click a guild member's shared list to copy it into your own watchlists."],
          },
        },
        { key = "commands", title = Help.GUIDE[8][1], body = { guideText(8) } },
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
local SUBCOMMANDS =
  { status = true, config = true, selftest = true, backfill = true, help = true, item = true, sync = true }
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

Help.EXAMPLES = {
  signals = function(parent)
    local f = panel(parent, 5 * 22 + 12)
    local rows = {
      { "buy", L["Unusually cheap for this item, given how much its price usually moves"] },
      { "hold", L["Within its usual range"] },
      { "sell", L["Unusually expensive for this item, given how much its price usually moves"] },
      { "wait", L["Cheap, but sellers are dumping: wait for the bottom"] },
      { "vendor", L["A vendor pays more than the auction house nets after the cut and the deposit"] },
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
    local tag = W.Text(f, "GameFontNormal")
    tag:SetPoint("TOPLEFT", 12, -9)
    tag:SetText("AME")
    local title = W.Text(f, "GameFontHighlight")
    title:SetPoint("LEFT", tag, "RIGHT", 12, 0)
    title:SetText(L["Post at %s"]:format(W.Money(18700)) .. " " .. W.Dim(L["per unit"]) .. "  " .. W.Confidence("high"))
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
    for _, b in ipairs({
      { L["Market %s"]:format(W.Money(16400)) },
      { L["Patient %s"]:format(W.Money(20900)) },
      { L["Normal %s"]:format(W.Money(18700)), true },
      { L["Quick %s"]:format(W.Money(13800)) },
    }) do
      local btn = W.Button(f, b[1], 80, 22)
      btn:SetWidth(math.ceil(btn.label:GetStringWidth() or 60) + 20)
      btn:SetSelected(b[2] or false)
      if prev then
        btn:SetPoint("RIGHT", prev, "LEFT", -6, 0)
      else
        btn:SetPoint("TOPRIGHT", -10, -5)
      end
      prev = btn
    end
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
    local rows = {
      { { 0.2, 0.8, 1 }, L["Market"], 12, 3 },
      { { 0.4, 0.87, 0.47 }, L["Lowest"], 12, 3 },
      { { 1, 0.67, 0.2 }, L["7-day average"], 12, 3 },
      { { 0.53, 0.53, 0.67 }, L["Supply"], 8, 8 },
      { ns.UI and ns.UI.TRADE_COLORS and ns.UI.TRADE_COLORS.buy or { 0.35, 0.65, 1 }, L["You bought"], 8, 8 },
      { ns.UI and ns.UI.TRADE_COLORS and ns.UI.TRADE_COLORS.sale or { 1, 0.45, 0.85 }, L["You sold"], 8, 8 },
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
    for _, key in ipairs({ "buy", "hold", "sell", "wait", "vendor" }) do
      items[#items + 1] = { key, W.SignalGlyph(key), W.SignalTone(key) }
    end
    local seg = W.Segmented(f, items, { minWidth = 40 })
    seg:SetPoint("LEFT", 0, 0)
    seg:Select("buy", true)
    return f
  end,
}

-- The Guide: a sidebar of articles by group (filtered by the search box) and the article on the right, scrolling
-- when long. Narrow window: the sidebar becomes a dropdown next to the search box.
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

  -- sidebar: group headings and article links
  local list = slots.left.content
  v.links = {}
  local function heading(text)
    local h = W.Text(list, "GameFontDisableSmall")
    h:SetText(text:upper())
    return { heading = true, frame = h, group = text }
  end
  local function link(a)
    local b = CreateFrame("Button", nil, list)
    b:SetHeight(18)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    W.Fill(b.sel, W.COLORS.rowSelected)
    b.sel:Hide()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    W.Fill(b.hl, W.COLORS.rowHover)
    b.text = W.Text(b, "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 8, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetWordWrap(false)
    b.text:SetText(a.label or a.title) -- the sidebar's short name; the article keeps its full title
    b:SetScript("OnClick", function()
      v:ShowArticle(a.key)
    end)
    b.article = a
    return { frame = b, article = a }
  end
  for _, g in ipairs(groups) do
    v.links[#v.links + 1] = heading(g[1])
    for _, a in ipairs(g[2]) do
      local l = link(a)
      v.links[#v.links + 1] = l
      a.link = l.frame
    end
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
    local y, shown = -8, {}
    for _, l in ipairs(self.links) do
      if not l.heading then
        shown[l.article.group] = shown[l.article.group] or matches(l.article, text)
      end
    end
    self.matches = {}
    for _, l in ipairs(self.links) do
      local f = l.frame
      f:ClearAllPoints()
      local on
      if l.heading then
        on = shown[l.group]
        if on then
          y = y - (y < -8 and 10 or 0)
          f:SetPoint("TOPLEFT", 10, y)
          y = y - 16
        end
      else
        on = matches(l.article, text)
        if on then
          f:SetPoint("TOPLEFT", 4, y)
          f:SetPoint("RIGHT", list, "RIGHT", -4, 0)
          y = y - 18
          self.matches[#self.matches + 1] = l.article
        end
      end
      f:SetShown(on and true or false)
    end
    slots.left.pane:Measure()
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

  -- the article
  local pane = W.ScrollPane(slots.main)
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
    for _, l in ipairs(self.links) do
      if not l.heading then
        l.frame.sel:SetShown(l.article == a)
      end
    end
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
