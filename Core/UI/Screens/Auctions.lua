-- Auctions (board AHAuctions): your auctions against what's on sale now - lowest, undercut (by how much, and how
-- many are ahead of you) or not checked yet - with Undercut only, a character filter and Check prices (a search of
-- each item). The panel on the right: the picked auction, how it stands, what reposting would ask and net, and
-- Cancel this auction (one auction, one click, as the game asks). Away from the auction house it shows what each
-- character last saw; Check prices and Cancel wait for the auction house.
local _, ns = ...
local L = ns.L

local App, P = ns.App, ns.PortfolioPage

local function clock()
  return GetTime and GetTime() or os.time()
end

local function money(c)
  return ns.Widgets and ns.Widgets.Money(c, true) or tostring(c)
end

local function books()
  return ns.AHSearch and ns.AHSearch.results or {}
end

local function me()
  return UnitName and UnitName("player") or nil
end

-- auctions cancelled a moment ago: left out until the game's list catches up (OWNED_AUCTIONS_UPDATED)
P.CANCEL_HIDE = 15 -- seconds
P.cancelling = {}

local function cancelling()
  local out, t = nil, clock()
  for id, at in pairs(P.cancelling) do
    if t - at < P.CANCEL_HIDE then
      out = out or {}
      out[id] = true
    else
      P.cancelling[id] = nil
    end
  end
  return out
end

function P.AuctionState(app, p)
  local rows, sum = P.AuctionRows(P.AuctionList(cancelling()), books(), {
    me = me(),
    atAH = app:AtAH(),
    undercutOnly = p.undercut,
    char = p.char ~= "all" and p.char or nil,
    now = GetServerTime and GetServerTime() or nil,
    scanMin = P.ScanMin(), -- not searched yet: the last scan's lowest, as Home counts
  })
  local picked
  for _, r in ipairs(rows) do
    if r.key == p.pick then
      picked = r
    end
  end
  return rows, sum, picked or rows[1]
end

-- the repost advice and the hours to sell at the auction's own price (nil when the model can't say)
local function advise(row)
  local a = row and row.a
  if not (a and a.itemID and ns.Posting and ns.AME and ns.AME.CurrentShard) then
    return nil, nil
  end
  local shard = ns.AME:CurrentShard()
  local hours = ns.Posting.DurationHours(P.DefaultDuration())
  local ok, advice = pcall(ns.Posting.Suggest, ns.Posting, shard, a.itemID, a.qty or 1, hours)
  local ok2, _, toSell = pcall(ns.Posting.ChanceAt, ns.Posting, shard, a.itemID, a.qty or 1, hours, a.unit)
  return ok and advice or nil, ok2 and toSell or nil
end

local function summary(sum)
  local text = L["%d auctions · asking %s"]:format(sum.count, money(sum.asking))
  if sum.undercut > 0 then
    text = text .. " · " .. (ns.Kit and ns.Kit.Color("bad", L["%d undercut"]:format(sum.undercut)) or L["%d undercut"]:format(sum.undercut))
  end
  return text
end

local function panel(app, row)
  if not row then
    return {
      { id = "auc.none", type = "text", props = { text = L["Pick an auction on the left."], color = "dim", wrap = true }, meta = { h = 40 } },
    }
  end
  local advice, hours = advise(row)
  local d = P.AuctionDetail(row, advice, hours, P.Cut(), GetServerTime and GetServerTime())
  local kids = {
    {
      id = "auc.head",
      type = "card",
      props = { gap = 2 },
      meta = { h = 62 },
      children = {
        { id = "auc.item", type = "itemlink", props = { item = row.item, count = row.qty, size = 13, bold = true }, meta = { h = 20 } },
        { id = "auc.posted", type = "text", props = { text = d.posted, color = "dim", size = 11 }, meta = { h = 16 } },
      },
    },
  }
  local cut = {}
  for i, r in ipairs(d.rows) do
    cut[i] = { id = "auc.cut" .. i, type = "keyvalue", props = r, meta = { h = 18 } }
  end
  cut[#cut + 1] = { id = "auc.cutNote", type = "text", props = { text = d.note, color = "dim", size = 11, wrap = true }, meta = { h = 28 } }
  kids[#kids + 1] = { id = "auc.standing", type = "card", props = { title = d.title, gap = 2 }, meta = { h = 32 + 20 * #d.rows + 30 }, children = cut }
  if d.repost then
    local rep = {}
    for i, r in ipairs(d.repost) do
      rep[i] = { id = "auc.rep" .. i, type = "keyvalue", props = r, meta = { h = r.big and 22 or 18 } }
    end
    kids[#kids + 1] = { id = "auc.repost", type = "card", props = { title = L["If you repost"], gap = 2 }, meta = { h = 96 }, children = rep }
  end
  local can = row.cancel and app:AtAH()
  kids[#kids + 1] = {
    id = "auc.cancel",
    type = "gamebutton",
    props = {
      label = L["Cancel this auction"],
      call = "cancel",
      payload = { auctionID = row.auctionID },
      action = "cancelled",
      variant = can and "primary" or "disabled",
    },
    meta = { h = 28 },
  }
  local why
  if row.faded then
    why = L["Another character's auction: cancel it there."]
  elseif not app:AtAH() then
    why = L["Cancel works at the auction house."]
  else
    why = L["A cancelled auction comes back by mail, and its deposit is lost. Repost it from Sell."]
  end
  kids[#kids + 1] = { id = "auc.why", type = "text", props = { text = why, color = "dim", size = 11, wrap = true }, meta = { h = 28 } }
  kids[#kids + 1] = {
    id = "auc.links",
    type = "row",
    props = { gap = 6 },
    meta = { h = 24 },
    children = { { id = "auc.open", type = "button", props = { label = L["Open item"], action = "openItem" }, meta = { w = 80 } } },
  }
  return kids
end

local function charOptions(sum)
  local out = { { "all", L["All characters"] } }
  for _, c in ipairs(sum.chars) do
    out[#out + 1] = { c, c }
  end
  return out
end

local function body(app, p)
  local rows, sum, picked = P.AuctionState(app, p)
  app:Source("auctions.rows", rows)
  local chars = charOptions(sum)
  local charLabel = L["All characters"]
  for _, o in ipairs(chars) do
    if o[1] == p.char then
      charLabel = o[2]
    end
  end
  return {
    id = "auctions",
    type = "column",
    props = { gap = 8 },
    children = {
      {
        id = "auc.bar",
        type = "row",
        props = { gap = 8, align = "center" },
        meta = { h = 24 },
        children = {
          P.ViewControl(app, "auc.views", "auctions"),
          { id = "auc.gap", type = "spacer", meta = { w = 4 } },
          { id = "auc.summary", type = "text", props = { text = summary(sum), color = "dim", size = 11 } },
          { id = "auc.only", type = "check", props = { label = L["Undercut only"], checked = p.undercut and true or false, action = "undercutOnly" }, meta = { w = 110, h = 18 } },
          { id = "auc.chars", type = "menubutton", props = { label = charLabel, options = chars, selected = p.char or "all", action = "chars" } },
          { id = "auc.barGap", type = "spacer", meta = { grow = 1 } },
          { id = "auc.check", type = "button", props = { label = L["Check prices"], action = "checkPrices", variant = app:AtAH() and "normal" or "disabled" } },
        },
      },
      {
        id = "auc.main",
        type = "row",
        props = { gap = 10 },
        meta = { grow = 1 },
        children = {
          {
            id = "auc.table",
            type = "table",
            props = {
              source = "auctions.rows",
              columns = P.Columns("auctions"),
              action = "pickRow",
              selected = picked and picked.key or nil,
              note = L["Lowest now is from the last search of each item, or the last full scan until you search it: Check prices searches them all. Faded: another character's (cancel them there)."],
              empty = p.undercut and L["None of your auctions is undercut."] or L["No auctions: post some from Sell."],
            },
            meta = { grow = 1 },
          },
          { id = "auc.side", type = "column", props = { gap = 8 }, meta = { w = 270 }, children = panel(app, picked) },
        },
      },
    },
  }
end

local function current(app)
  local _, p = app:Current()
  return p
end

-- a cancel went to the game: the row leaves at once, and the game is asked for your auctions again; its answer
-- (OWNED_AUCTIONS_UPDATED) rescans them, and the screen is drawn again from them (Stamp)
local function cancelled(app, pl)
  P.message = { text = pl.message or "", at = clock() }
  local id = pl.auctionID or (pl.payload and pl.payload.auctionID)
  if pl.ok and id then
    P.cancelling[id] = clock()
  end
  if pl.ok and ns.Trading and ns.Trading.QueryAuctions then
    pcall(ns.Trading.QueryAuctions, ns.Trading)
  end
  P.cached = nil
  app:Redraw()
end

App.Screen("auctions", {
  tab = "portfolio",
  ahTab = "auctions",
  Build = body,
  -- your characters' saved auction lists (a rescan replaces the list) and the game's owned list: a cancel or a new
  -- post draws it again, the window idling doesn't
  Stamp = function()
    local parts = {}
    for key, h in pairs((AME_DB and AME_DB.holdings) or {}) do
      parts[#parts + 1] = key .. "=" .. tostring(h.auctionList)
    end
    table.sort(parts)
    local ah = C_AuctionHouse
    local ok, n = pcall(function()
      return ah and ah.GetNumOwnedAuctions and ah.GetNumOwnedAuctions() or 0
    end)
    parts[#parts + 1] = "owned=" .. tostring(ok and n or 0)
    return table.concat(parts, ";")
  end,
  Title = function()
    return L["Auctions"]
  end,
  Status = function(app, p)
    local _, sum = P.AuctionState(app, p)
    local t = GetServerTime and GetServerTime() or 0
    if P.message and clock() - P.message.at < 30 then
      return P.message.text
    end
    if not app:AtAH() then
      return L["Your auctions as each character last saw them at the auction house"]
    end
    local house = ns.AME and ns.AME.CurrentHouse and ns.AME:CurrentHouse()
    local text = L["At the %s"]:format(ns.HOUSE_LABEL and ns.HOUSE_LABEL[house] or house or "") .. " · " .. L["your auctions as of now"]
    if sum.checked and ns.Widgets then
      text = text .. " · " .. L["prices checked %s"]:format(ns.Widgets.Ago(sum.checked, t))
    end
    return text
  end,
  actions = {
    view = function(app, pl)
      P.GoView(app, pl.key)
    end,
    pickRow = function(app, pl)
      if pl.button == "RightButton" then
        return
      end
      app:Set({ pick = pl.key })
    end,
    undercutOnly = function(app, pl)
      app:Set({ undercut = pl.checked and true or false })
    end,
    chars = function(app, pl)
      app:Set({ char = pl.key })
    end,
    checkPrices = function(app)
      if not (app:AtAH() and ns.AHSearch and ns.AHSearch.Start) then
        return
      end
      local keys, seen = {}, {}
      for _, a in ipairs(P.AuctionList()) do
        if a.itemID and not seen[a.itemID] then
          seen[a.itemID] = true
          keys[#keys + 1] = a.itemID
        end
      end
      pcall(ns.AHSearch.Start, ns.AHSearch, keys, function()
        App:Redraw()
      end)
    end,
    -- a row's Cancel: the table's button dispatches from its click, so the game's cancel still runs from it
    cancelRow = function(app, pl)
      local rows = P.AuctionState(app, current(app))
      for _, r in ipairs(rows) do
        if r.key == pl.key and r.cancel and app:AtAH() then
          local ok, message = P.Cancel({ auctionID = r.auctionID })
          cancelled(app, { ok = ok, message = message, auctionID = r.auctionID })
          return
        end
      end
    end,
    cancelled = cancelled,
    openItem = function(app)
      local _, _, picked = P.AuctionState(app, current(app))
      if picked then
        app:Go("item", { item = picked.item })
      end
    end,
  },
})
