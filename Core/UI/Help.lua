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
  arbProfit = { L["Profit"], L["Per item: what it sells for, minus the AH cut, minus what you paid."] },
  arbNet = {
    L["Net"],
    L["Per item: what it sells for, minus the AH cut, minus the listing deposit, minus what you paid. The deposit is counted for one post of the units the route pays for (or up to 20), at least 1 silver per post - you get it back when it sells."],
  },
  arbUnits = {
    L["Units"],
    L["How many units at the buy house still pay after the cut, of how many are listed there. The first number needs the item's listings: search it at the buy house (it then stays for 6 hours)."],
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
  "arbProfit",
  "arbMargin",
  "arbSupply",
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

-- The Guide's articles, grouped like a documentation site. Each article: key, title, label (optional: a shorter
-- name in the sidebar, e.g. "Market" under "Tabs"; the title otherwise), body (paragraphs). The glossary group is
-- built from Help.TERMS (Help.GLOSSARY order), so every hover explanation has its own page.
local function guideText(i)
  return Help.GUIDE[i][2]
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
            L["After one scan you can browse the Market tab and see posting prices. Signals, trends and sell rates need history: they get better with a scan a day, and mean the most after a week."],
            L["Open the window with /ame, the minimap button, or set it to open with the auction house (Settings > Window)."],
          },
        },
        { key = "data", title = Help.GUIDE[1][1], body = { guideText(1) } },
        {
          key = "window",
          title = L["The window"],
          body = {
            L["Drag the title bar to move the window and the bottom-right corner to resize it. AME remembers the size, and where you put it with and without the auction house open. When the auction house opens and there's room beside it, AME docks next to it (Settings > Window)."],
            L["On a narrow window the tabs switch to a compact layout: sidebars become a dropdown or a Details button. Window scale changes AME's size without touching the rest of your UI."],
            L["The status row at the bottom says where the numbers come from, how old they are, and when a scan is being read or market data is being updated."],
          },
        },
      },
    },
    {
      L["Tabs"],
      {
        { key = "tabMarket", title = Help.GUIDE[2][1], label = L["Market"], body = { guideText(2) } },
        { key = "tabItem", title = Help.GUIDE[5][1], label = L["Item"], body = { guideText(5) } },
        { key = "tabArbitrage", title = Help.GUIDE[3][1], label = L["Arbitrage"], body = { guideText(3) } },
        { key = "tabPortfolio", title = Help.GUIDE[4][1], label = L["Portfolio"], body = { guideText(4) } },
        {
          key = "tabSync",
          title = L["Sync tab"],
          label = L["Sync"],
          body = {
            L["Guild members running AME share their full scans automatically, so everyone's prices stay fresh. Players outside your guild can share too: add them under Trusted players; they get a request to approve."],
            L["Scans that disagree wildly with your own prices are rejected, and you can block players. Guild officers can block players for the whole guild with a line in the guild info. The cards at the top show how fresh each auction house's data is and who scanned it."],
          },
        },
        {
          key = "tabSettings",
          title = L["Settings tab"],
          label = L["Settings"],
          body = {
            L["Every setting is on one page, in cards: the window, tooltips, charts, selling, notifications and data (importing from Auctionator, rebuilding market data, the self-test, and how outrageous prices are ignored). Hover a setting for what it does."],
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
            Help.TERMS.posting[2],
            L["At the auction house, a bar under the sell window shows the price for the item you're posting, why, and what you'd get after the cut. Fill price puts it in the price box; you still click Post yourself. Click a listing in the sell window to aim just under it instead."],
          },
        },
        { key = "numbers", title = Help.GUIDE[7][1], body = { guideText(7), Help.TERMS.signal[2] } },
        { key = "watch", title = Help.GUIDE[6][1], body = { guideText(6) } },
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

-- The Guide: a sidebar of articles by group (filtered by the search box) and the article on the right, scrolling
-- when long. Narrow window: the sidebar becomes a dropdown next to the search box.
Help.GUIDE_SIDEBAR = 210
Help.ARTICLE_WIDTH = 640 -- longest comfortable line

function Help.CreateGuide(parent, contentArea)
  local UI = ns.UI
  local v = contentArea(parent)
  local slots = UI.Slots(v, { toolbar = 22, left = Help.GUIDE_SIDEBAR, status = true })
  v.slots = slots
  slots.status:SetText(
    L["Azeroth Mercantile Exchange %s  ·  created by Tyken Evanion  ·  PvP Horde, WoW Forever"]:format(ns.VERSION)
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
    for _, p in ipairs(a.body) do
      if p:lower():find(text, 1, true) then
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
    width = 200,
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
  v.crumb = W.Text(page, "GameFontDisableSmall")
  v.crumb:SetPoint("BOTTOMLEFT", v.title, "TOPLEFT", 0, 2)
  v.paras = {}
  local function para(i)
    local p = v.paras[i]
    if not p then
      p = W.Text(page, "GameFontHighlight")
      p:SetJustifyH("LEFT")
      p:SetWordWrap(true)
      p:SetSpacing(4)
      if i == 1 then
        p:SetPoint("TOPLEFT", v.title, "BOTTOMLEFT", 0, -12)
      else
        p:SetPoint("TOPLEFT", v.paras[i - 1], "BOTTOMLEFT", 0, -10)
      end
      v.paras[i] = p
    end
    return p
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
    for i, text in ipairs(a.body) do
      local p = para(i)
      p:SetText(text)
      p:Show()
    end
    for i = #a.body + 1, #self.paras do
      self.paras[i]:Hide()
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
