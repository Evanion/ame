-- Sell, at the auction house (boards AHSell, SellCompact narrow, AHSellTips): your bags with a Tip and what each is
-- worth; the card beside them posts the picked row (the price ladder from Posting:Suggest, quantity, price, duration,
-- deposit, what you net, Post, Skip, then the next) or, for a row tipped Craft, DE or Vendor, says why something
-- else pays more with one button that does it. Beside them, the item's last 7 days and what's on sale now (the
-- narrow window leaves those to the Item page). Post runs the game's posting from the click.
local _, ns = ...
local L = ns.L

local App, P = ns.App, ns.PortfolioPage

P.BAGS_AGE = 3 -- seconds the bag scan is reused (several draws in a row)
P.SEARCH_AGE = 60 -- an item's listings are searched again after this long

local function clock()
  return GetTime and GetTime() or os.time()
end

local function money(c)
  return ns.Widgets and ns.Widgets.Money(c, true) or tostring(c)
end

local function count(n)
  return ns.Widgets and ns.Widgets.Count(n) or tostring(n)
end

-- the bags, scanned at most every P.BAGS_AGE seconds (P.bagsDirty: a bag changed)
function P.Bags()
  if P.bagsDirty or not P.bagsAt or clock() - P.bagsAt > P.BAGS_AGE then
    local ok, list = pcall(P.SellEntries)
    P.bags = ok and list or (P.bags or {})
    P.bagsAt, P.bagsDirty = clock(), false
  end
  return P.bags or {}
end

local function book(key)
  return ns.AHSearch and ns.AHSearch.results and ns.AHSearch.results[key]
end

-- search the item's listings (once a minute at most): the ladder and the on-sale table follow them
local function search(app, key)
  if not (key and app:AtAH() and ns.AHSearch and ns.AHSearch.Push) then
    return
  end
  if ns.Settings and ns.Settings:Get("autoSearch") == false then
    return -- Settings: searched only when you ask
  end
  local last = P.searched[key]
  if last and clock() - last < P.SEARCH_AGE then
    return
  end
  P.searched[key] = clock()
  pcall(ns.AHSearch.Push, ns.AHSearch, key, function()
    App:Redraw()
  end)
end

-- the state of the card: the picked entry, quantity, duration, advice, price
function P.SellState(_app, p)
  local entries = P.Bags()
  p.skipped, p.asis = p.skipped or {}, p.asis or {}
  local e = p.item and P.Find(entries, p.item) or P.FirstPick(entries, p.skipped)
  local s = { entries = entries, e = e }
  if not e then
    return s
  end
  s.tip = P.TipOf(e)
  s.ladder = s.tip == "sell" or s.tip == nil or p.asis[tostring(e.key)] or false
  s.duration = tonumber(p.duration) or P.DefaultDuration()
  s.qty = math.max(1, math.min(tonumber(p.qty) or (e.commodity and e.qty or 1), e.qty or 1))
  if s.ladder then
    s.advice = P.Suggest(e.key, s.qty, s.duration)
    s.picked = p.pick or (p.price == nil and "normal" or nil)
    local c = s.advice and s.picked and s.advice[s.picked]
    s.price = p.price or (c and c.price) or nil
    s.deposit = P.Deposit(e, s.qty, s.duration)
  end
  s.cut = P.Cut()
  s.n = e.commodity and math.min(s.qty, e.qty) or 1
  s.next = P.NextSell(entries, e.key, p.skipped)
  return s
end

-- ------------------------------------------------------------------------------------------------ the card

local function header(e, size)
  local s = e.summary
  local bits = {}
  if s and s.market then
    bits[#bits + 1] = L["market %s"]:format(money(s.market))
  end
  local sub = {
    { id = "sell.mkt", type = "text", props = { text = table.concat(bits), color = "dim", size = 11 } },
  }
  if s and s.signal and s.signal ~= "none" then
    sub[#sub + 1] = { id = "sell.sig", type = "signal", props = { signal = s.signal } }
  end
  if s and s.soldPerDay then
    sub[#sub + 1] = {
      id = "sell.rate",
      type = "text",
      props = { text = "· " .. L["~%s sells/day"]:format(count(s.soldPerDay)), color = "dim", size = 11 },
    }
  end
  return {
    {
      id = "sell.item",
      type = "itemlink",
      props = { item = e.key, count = e.qty, size = size, bold = true },
      meta = { h = 20 },
    },
    { id = "sell.sub", type = "row", props = { gap = 5, align = "center" }, meta = { h = 16 }, children = sub },
  }
end

local function add(list, items)
  for _, it in ipairs(items) do
    list[#list + 1] = it
  end
  return list
end

local function kvs(prefix, rows)
  local out = {}
  for i, r in ipairs(rows) do
    out[i] = { id = prefix .. i, type = "keyvalue", props = r, meta = { h = 18 } }
  end
  return out
end

local function ladderCard(app, s, compact)
  local e = s.e
  local picks = P.Ladder(s.advice, s.picked, compact)
  local kids = compact
      and {
        {
          id = "sell.item",
          type = "itemlink",
          props = { item = e.key, count = e.qty, size = 13, bold = true },
          meta = { h = 20 },
        },
      }
    or header(e, 14)
  if not compact then
    kids[#kids + 1] = {
      id = "sell.priceHead",
      type = "text",
      props = { text = L["Price each"], font = "display", size = 13 },
      meta = { h = 16 },
    }
  end
  if #picks > 0 then
    kids[#kids + 1] = {
      id = "sell.ladder",
      type = "priceladder",
      props = { picks = picks, dense = compact or nil, action = "pick" },
      meta = { h = compact and 130 or 150 },
    }
  else
    kids[#kids + 1] = {
      id = "sell.noLadder",
      type = "text",
      props = { text = L["No suggestion yet: searching what's on sale"], color = "dim", size = 11 },
      meta = { h = 18 },
    }
  end
  local durLabel = L["%d h"]:format(ns.Posting and ns.Posting.DurationHours(s.duration) or 24)
  kids[#kids + 1] = {
    id = "sell.inputs",
    type = "row",
    props = { gap = 8 },
    meta = { h = 42 },
    children = {
      {
        id = "sell.qty",
        type = "field",
        props = { label = L["Quantity"], value = tostring(s.qty), numeric = true, action = "qty" },
        meta = { w = compact and 50 or 56 },
      },
      {
        id = "sell.price",
        type = "field",
        props = {
          label = L["Price each"],
          value = s.price and ns.MoneyInputText(s.price) or "",
          hint = L["gold"],
          action = "price",
          money = true,
        },
        meta = { w = compact and 80 or 90 },
      },
      {
        id = "sell.dur",
        type = "column",
        props = { gap = 3 },
        meta = { w = 70 },
        children = {
          {
            id = "sell.durLabel",
            type = "text",
            props = { text = L["Duration"], color = "dim", size = 11 },
            meta = { h = 15 },
          },
          {
            id = "sell.duration",
            type = "menubutton",
            props = { label = durLabel, options = P.Durations(), selected = tostring(s.duration), action = "duration" },
            meta = { h = 24 },
          },
        },
      },
    },
  }
  if not compact then
    local last = P.LastPost(e.key)
    if last then
      kids[#kids + 1] = {
        id = "sell.last",
        type = "text",
        props = {
          text = L["Last time you posted it: %s for %s"]:format(money(last.unit), L["%d h"]:format(last.hours or 24)),
          color = "dim",
          size = 11,
        },
        meta = { h = 16 },
      }
    end
    kids[#kids + 1] = {
      id = "sell.deposit",
      type = "keyvalue",
      props = { label = L["Deposit"], copper = s.deposit, text = not s.deposit and "—" or nil },
      meta = { h = 18 },
    }
  end
  local cutLabel = compact and L["You net, after the cut"]
    or L["You net, after the %d%% cut"]:format(math.floor((s.cut or 0.05) * 100 + 0.5))
  local net = P.Net(s.price, s.n, s.cut)
  kids[#kids + 1] = {
    id = "sell.net",
    type = "keyvalue",
    props = { label = cutLabel, copper = net, text = not net and "—" or nil },
    meta = { h = 18 },
  }
  kids[#kids + 1] = { id = "sell.push", type = "spacer", meta = { grow = 1 } }
  local canPost = app:AtAH() and (s.price or 0) > 0 and s.n > 0
  local buttons = {
    {
      id = "sell.post",
      type = "gamebutton",
      props = {
        label = L["Post %s"]:format(count(s.n)),
        call = "post",
        payload = { key = e.key, price = s.price, qty = s.n, duration = s.duration },
        action = "posted",
        variant = canPost and "primary" or "disabled",
      },
      meta = { w = 80 },
    },
    { id = "sell.skip", type = "button", props = { label = L["Skip"], action = "skip" }, meta = { w = 50 } },
  }
  if compact and s.next then
    buttons[#buttons + 1] = {
      id = "sell.thenC",
      type = "text",
      props = {
        text = L["then %s"]:format(ns.Widgets and ns.Widgets.LinkText(s.next.key) or ""),
        color = "dim",
        size = 11,
      },
    }
  end
  kids[#kids + 1] =
    { id = "sell.buttons", type = "row", props = { gap = 6, align = "center" }, meta = { h = 24 }, children = buttons }
  if not compact then
    if s.next then
      kids[#kids + 1] = {
        id = "sell.then",
        type = "row",
        props = { gap = 5, align = "center" },
        meta = { h = 16 },
        children = {
          { id = "sell.thenLabel", type = "text", props = { text = L["Then:"], color = "dim", size = 11 } },
          { id = "sell.thenItem", type = "itemlink", props = { item = s.next.key, size = 11 } },
        },
      }
    end
    kids[#kids + 1] = {
      id = "sell.howto",
      type = "text",
      props = { text = L["Each post takes one click: the game asks for one."], color = "dim", size = 11, wrap = true },
      meta = { h = 16 },
    }
  end
  return kids
end

local function tipButtons(primary)
  return {
    id = "sell.buttons",
    type = "row",
    props = { gap = 6 },
    meta = { h = 24 },
    children = {
      primary,
      { id = "sell.asis", type = "button", props = { label = L["Sell it as it is"], action = "asis" } },
      { id = "sell.skip", type = "button", props = { label = L["Skip"], action = "skip" } },
    },
  }
end

local function note(text, h)
  return {
    id = "sell.note",
    type = "text",
    props = { text = text, color = "dim", size = 11, wrap = true },
    meta = { h = h or 30 },
  }
end

local function tipCard(_app, s)
  local e = s.e
  local kids = {
    {
      id = "sell.item",
      type = "itemlink",
      props = { item = e.key, count = e.qty, size = 14, bold = true },
      meta = { h = 20 },
    },
  }
  if s.tip == "craft" then
    local c = P.CraftCard(e)
    kids[#kids + 1] =
      { id = "sell.tipSub", type = "text", props = { text = c.sub, color = "dim", size = 11 }, meta = { h = 16 } }
    kids[#kids + 1] = {
      id = "sell.tipHead",
      type = "text",
      props = { text = L["Worth more made first"], font = "display", size = 13 },
      meta = { h = 18 },
    }
    add(kids, kvs("sell.kv", c.rows))
    kids[#kids + 1] = { id = "sell.push", type = "spacer", meta = { grow = 1 } }
    kids[#kids + 1] = tipButtons({
      id = "sell.queue",
      type = "button",
      props = {
        label = L["Queue %d"]:format(c.crafts),
        action = "queue",
        payload = { recipe = c.recipe, n = c.crafts },
        variant = (c.recipe and c.crafts > 0) and "primary" or "disabled",
      },
    })
    kids[#kids + 1] = note(L["Queue puts it on your crafting queue. What you make comes back to this list once made."])
  elseif s.tip == "disenchant" then
    local c = P.DECard(e, P.quote)
    kids[#kids + 1] =
      { id = "sell.tipSub", type = "text", props = { text = c.sub, color = "dim", size = 11 }, meta = { h = 16 } }
    kids[#kids + 1] = {
      id = "sell.tipHead",
      type = "text",
      props = { text = L["Worth more disenchanted"], font = "display", size = 13 },
      meta = { h = 18 },
    }
    add(kids, kvs("sell.kv", c.rows))
    kids[#kids + 1] = { id = "sell.push", type = "spacer", meta = { grow = 1 } }
    local bag, slot
    local loc = e.locs and e.locs[1]
    if loc and loc.GetBagAndSlot then
      local ok, b, sl = pcall(loc.GetBagAndSlot, loc)
      if ok then
        bag, slot = b, sl
      end
    end
    kids[#kids + 1] = tipButtons({
      id = "sell.de",
      type = "debutton",
      props = { label = L["Disenchant"], bag = bag, slot = slot, action = "disenchanted" },
    })
    kids[#kids + 1] =
      note(L["One click each: the game wants a click for every disenchant. Not an enchanter on this character?"], 28)
    kids[#kids + 1] = {
      id = "sell.findDE",
      type = "button",
      props = { label = L["Find one in your guild"], action = "findEnchanter" },
      meta = { h = 22 },
    }
  else
    local c = P.VendorCard(e, P.Deposit(e, e.qty, P.DefaultDuration()), s.cut)
    kids[#kids + 1] =
      { id = "sell.tipSub", type = "text", props = { text = c.sub, color = "dim", size = 11 }, meta = { h = 16 } }
    kids[#kids + 1] = {
      id = "sell.tipHead",
      type = "text",
      props = { text = L["Worth more at a vendor"], font = "display", size = 13 },
      meta = { h = 18 },
    }
    add(kids, kvs("sell.kv", c.rows))
    kids[#kids + 1] = { id = "sell.push", type = "spacer", meta = { grow = 1 } }
    kids[#kids + 1] =
      tipButtons({ id = "sell.vendor", type = "button", props = { label = L["At a vendor"], variant = "disabled" } })
    kids[#kids + 1] = note(
      L["Nothing to do here. At any vendor, AME's panel beside the merchant window sells everything tipped Vendor in one go."],
      42
    )
  end
  return kids
end

-- The wide window's card is landscape (board AHSell): the item and its market on one line, then two columns -
-- the price list on the left, the quantity, price, duration, deposit, net and Post on the right (226 px, where
-- they fit side by side). A Craft, DE or Vendor tip keeps the same shape: what it's worth on the left, its
-- buttons and note on the right.
local function byId(kids)
  local out = {}
  for _, k in ipairs(kids) do
    out[k.id] = k
  end
  return out
end

local function headLine(e)
  local h = header(e, 14)
  local item, sub = h[1], h[2]
  item.meta, sub.meta = nil, { grow = 1 } -- the market line takes the rest of the width
  return {
    id = "sell.head",
    type = "row",
    props = { gap = 8, align = "center" },
    meta = { h = 20 },
    children = { item, sub },
  }
end

local function ladderWide(app, s)
  local k = byId(ladderCard(app, s, false))
  local left = { k["sell.ladder"] or k["sell.noLadder"] }
  if left[1] and left[1].type == "priceladder" then
    left[1].props.dense = true
    left[1].meta = { h = 130 }
  end
  local right = {
    k["sell.inputs"],
    k["sell.deposit"],
    k["sell.net"],
    { id = "sell.push", type = "spacer", meta = { grow = 1 } },
    k["sell.buttons"],
  }
  if k["sell.then"] then
    right[#right + 1] = k["sell.then"]
  end
  return {
    headLine(s.e),
    {
      id = "sell.cols",
      type = "row",
      props = { gap = 12 },
      meta = { grow = 1 },
      children = {
        { id = "sell.left", type = "column", props = { gap = 6 }, meta = { grow = 1 }, children = left },
        { id = "sell.right", type = "column", props = { gap = 6 }, meta = { w = 226 }, children = right },
      },
    },
  }
end

local function tipWide(app, s)
  local kids = tipCard(app, s)
  local left, right = {}, {}
  for i, kid in ipairs(kids) do
    local top = i == 1 or kid.id == "sell.tipSub" -- the item and its line go on top
    if not top then
      if kid.id == "sell.buttons" or kid.id == "sell.note" or kid.id == "sell.findDE" or kid.id == "sell.push" then
        right[#right + 1] = kid
      else
        left[#left + 1] = kid
      end
    end
  end
  local top = { kids[1] }
  kids[1].meta = nil
  for _, kid in ipairs(kids) do
    if kid.id == "sell.tipSub" then
      kid.meta = nil
      top[#top + 1] = kid
    end
  end
  return {
    { id = "sell.head", type = "row", props = { gap = 8, align = "center" }, meta = { h = 20 }, children = top },
    {
      id = "sell.cols",
      type = "row",
      props = { gap = 12 },
      meta = { grow = 1 },
      children = {
        { id = "sell.left", type = "column", props = { gap = 6 }, meta = { grow = 1 }, children = left },
        { id = "sell.right", type = "column", props = { gap = 6 }, meta = { w = 250 }, children = right },
      },
    },
  }
end

local function card(app, s, compact)
  local kids
  if not s.e then
    kids = {
      {
        id = "sell.none",
        type = "text",
        props = { text = L["Nothing in your bags can be listed here."], color = "dim", wrap = true },
        meta = { h = 40 },
      },
    }
  elseif compact then
    kids = s.ladder and ladderCard(app, s, true) or tipCard(app, s)
  else
    kids = s.ladder and ladderWide(app, s) or tipWide(app, s)
  end
  return {
    id = "sell.card",
    type = "card",
    props = { gap = compact and 5 or 8 },
    meta = compact and { w = 300 } or { grow = 1.7 }, -- wide: beside what's on sale now, 1.7 to its 1
    children = kids,
  }
end

-- ------------------------------------------------------------------------------------------------ the screen

function P.SellSummary(entries)
  local n, worth = 0, 0
  for _, e in ipairs(entries or {}) do
    if P.TipOf(e) == "sell" then
      n, worth = n + 1, worth + (e.worth or 0)
    end
  end
  return L["%d items worth posting · %s after the cut"]:format(n, money(worth))
end

local function body(app, p)
  local s = P.SellState(app, p)
  local e = s.e
  app:Source("sell.bags", P.BagRows(s.entries))
  local compact = app.compact
  if e then
    search(app, e.key)
  end
  local bar = {
    P.ViewControl(app, "sell.views", "sell"),
    { id = "sell.gap", type = "spacer", meta = { w = 6 } },
    { id = "sell.summary", type = "text", props = { text = P.SellSummary(s.entries), color = "dim", size = 11 } },
    { id = "sell.barGap", type = "spacer", meta = { grow = 1 } },
  }
  if compact then
    bar[#bar + 1] = {
      id = "sell.open",
      type = "button",
      props = { label = L["Open item"], action = "openItem", variant = e and "normal" or "disabled" },
    }
  end
  local bags = {
    id = "sell.bags",
    type = "table",
    props = {
      source = "sell.bags",
      columns = P.Columns("bags"),
      action = "pickBag",
      selected = e and tostring(e.key) or nil,
      note = not compact
          and L["Worth: all of it, after the cut and the deposit you'd lose if it didn't sell; at a vendor when that pays more."]
        or nil,
      empty = L["Nothing in your bags can be listed here."],
    },
  }
  local main
  if compact then
    bags.meta = { grow = 1 }
    main = { bags, card(app, s, true) }
  else
    bags.meta = { w = 340 }
    local key = e and e.key
    -- the Item page's own chart widget and data (ItemPage.Gather / ChartData), in a smaller box: Sell stands in for
    -- the Item page while you post. 2D / 7D / 30D pick its span.
    -- the span you last picked stays as Post moves on, and across sessions (Settings sellRange)
    local range = p.range or (ns.Settings and ns.Settings:Get("sellRange")) or "7D"
    local IP = ns.ItemPage
    if key and IP then
      local fc = IP.Gather(app, key, function()
        app:Redraw()
      end)
      app:Source(
        "sell.chart",
        IP.ChartData(fc.entry, fc.sum, range, fc.now, { vendor = fc.vendor, trades = fc.trades })
      )
    else
      app:Source("sell.chart", { points = {}, message = L["Pick an item on the left."] })
    end
    local style = ns.Settings and ns.Settings:Get("chartStyle") == "candles" and "candles" or "line"
    app:Source("sell.sale", P.SaleRows(key and book(key), GetServerTime and GetServerTime()))
    local b = key and book(key)
    local saleEmpty = not key and L["Pick an item on the left."] or (not b and L["searching..."]) or L["none listed"]
    local sale = {
      id = "sell.sale",
      type = "table",
      props = {
        source = "sell.sale",
        columns = P.Columns("sale"),
        action = "under",
        note = L["Click a listing to price just under it."],
        empty = saleEmpty,
      },
      meta = { grow = 1 },
    }
    main = {
      bags,
      {
        id = "sell.market",
        type = "column",
        props = { gap = 8 },
        meta = { grow = 1 },
        children = {
          -- on top, beside the top of the bags (the least mouse travel): the card and what's on sale now
          {
            id = "sell.top",
            type = "row",
            props = { gap = 8 },
            meta = { h = 192 },
            children = { card(app, s, false), sale },
          },
          {
            id = "sell.chartCard",
            type = "card",
            props = { gap = 6 },
            meta = { grow = 1 }, -- the rest of the height, under the card and the listings (board AHSell)
            children = {
              {
                id = "sell.chartHead",
                type = "row",
                props = { gap = 6, align = "center" },
                meta = { h = 22 },
                children = {
                  {
                    id = "sell.chartTitle",
                    type = "text",
                    props = { text = L["Price history"], font = "display", size = 13 },
                  },
                  { id = "sell.chartGap", type = "spacer", meta = { grow = 1 } },
                  {
                    id = "sell.range",
                    type = "segmented",
                    props = {
                      options = IP and IP.RangeOptions(false) or { { "7D", "7D" } },
                      selected = range,
                      action = "range",
                    },
                  },
                  {
                    id = "sell.open",
                    type = "button",
                    props = { label = L["Open item"], action = "openItem", variant = e and "normal" or "disabled" },
                    meta = { h = 22 },
                  },
                },
              },
              {
                id = "sell.chart",
                type = "chart",
                -- compact: the legend folds into its corner button (the full one would cover this smaller chart)
                props = {
                  source = "sell.chart",
                  kind = "item",
                  range = range,
                  style = style,
                  compact = true,
                  bare = true,
                },
                meta = { grow = 1 },
              },
            },
          },
        },
      },
    }
  end
  return {
    id = "sell",
    type = "column",
    props = { gap = compact and 6 or 8 },
    children = {
      { id = "sell.bar", type = "row", props = { gap = 6, align = "center" }, meta = { h = 24 }, children = bar },
      { id = "sell.main", type = "row", props = { gap = compact and 8 or 10 }, meta = { grow = 1 }, children = main },
    },
  }
end

-- the card moves on: to the next row tipped Sell (none: stays)
local function moveOn(app, p, skip)
  local s = P.SellState(app, p)
  if not s.e then
    return
  end
  if skip then
    p.skipped[tostring(s.e.key)] = true
  end
  local nxt = P.NextSell(s.entries, s.e.key, p.skipped)
  p.pick, p.price, p.qty = nil, nil, nil
  app:Set({ item = nxt and nxt.key or s.e.key })
end

-- the card's fields cleared for a new item (app:Set can't clear a param: nil is no change)
local function pick(app, key)
  local _, p = app:Current()
  p.pick, p.price, p.qty = nil, nil, nil
  app:Set({ item = key })
end

local function current(app)
  local _, p = app:Current()
  return p
end

App.Screen("sell", {
  tab = "portfolio",
  ahTab = "sell",
  Build = body,
  Title = function()
    return L["Sell"]
  end,
  Status = function(app, p)
    local house = ns.AME and ns.AME.CurrentHouse and ns.AME:CurrentHouse()
    local where = house and L["At the %s"]:format(ns.HOUSE_LABEL and ns.HOUSE_LABEL[house] or house) or ""
    if not app:AtAH() then
      return L["Sell works at the auction house"]
    end
    if P.message and clock() - P.message.at < 30 then
      return where .. " · " .. P.message.text
    end
    local b = p.item and book(p.item)
    if b and b.at and ns.Widgets and GetServerTime then
      return where .. " · " .. L["listings searched %s"]:format(ns.Widgets.Ago(b.at, GetServerTime()))
    end
    return where
  end,
  actions = {
    view = function(app, pl)
      P.GoView(app, pl.key)
    end,
    range = function(app, pl)
      if ns.Settings then
        ns.Settings:Set("sellRange", pl.key)
      end
      app:Set({ range = pl.key })
    end,
    pickBag = function(app, pl)
      if pl.button == "RightButton" then
        return
      end
      pick(app, pl.item)
    end,
    pick = function(app, pl)
      local p = current(app)
      local s = P.SellState(app, p)
      local _, keys = P.Ladder(s.advice, s.picked)
      local key = keys[pl.index]
      if key then
        p.price = nil
        app:Set({ pick = key })
      end
    end,
    qty = function(app, pl)
      local n = tonumber(pl.text)
      if n and n > 0 then
        app:Set({ qty = math.floor(n) })
      end
    end,
    price = function(app, pl)
      local c = ns.ParseMoney(pl.text)
      if c and c > 0 then
        local p = current(app)
        p.pick = nil
        app:Set({ price = c })
      end
    end,
    duration = function(app, pl)
      app:Set({ duration = tonumber(pl.key) })
    end,
    under = function(app, pl)
      local p = current(app)
      local e = P.SellState(app, p).e
      for _, r in ipairs(P.SaleRows(e and book(e.key))) do
        if r.key == pl.key then
          p.pick = nil
          app:Set({ price = P.Under(r.row) })
          return
        end
      end
    end,
    posted = function(app, pl)
      P.message = { text = pl.message or "", at = clock() }
      P.bagsDirty = true
      if pl.ok then
        moveOn(app, current(app), false)
      else
        app:Redraw()
      end
    end,
    skip = function(app)
      moveOn(app, current(app), true)
    end,
    asis = function(app)
      local p = current(app)
      local s = P.SellState(app, p)
      if s.e then
        p.asis[tostring(s.e.key)] = true
        app:Set({ item = s.e.key })
      end
    end,
    queue = function(app, pl)
      local pay = pl and pl.payload or pl
      if pay and pay.recipe and pay.n and pay.n > 0 and AME_DB and ns.CraftQueue then
        AME_DB.craftQueue = AME_DB.craftQueue or {}
        ns.CraftQueue.New(AME_DB.craftQueue):Add(pay.recipe, pay.n)
        P.message = { text = L["Queued %d"]:format(pay.n), at = clock() }
      end
      moveOn(app, current(app), true)
    end,
    disenchanted = function(app)
      P.bagsDirty = true
      app:Redraw()
    end,
    findEnchanter = function(app)
      app:Go("guild")
    end,
    openItem = function(app)
      local s = P.SellState(app, current(app))
      if s.e then
        app:Go("item", { item = s.e.key })
      end
    end,
  },
})

-- a bag changed (a post, a disenchant, loot): the list again on the next draw
if CreateFrame then
  local events = CreateFrame("Frame")
  pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED")
  pcall(events.RegisterEvent, events, "AUCTION_HOUSE_AUCTION_CREATED")
  events:SetScript("OnEvent", function()
    P.bagsDirty = true
    local id = App:Current()
    if id == "sell" and App.frame and App.frame:IsShown() then
      App:Redraw()
    end
  end)
end
