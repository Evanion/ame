-- Item tooltip lines from the market index (no history decoding on hover), and the modified click (Settings) that
-- opens an item's chart.
--
-- The block, under the game's lines (prices from your faction's auction house), after a gap:
--   Horde AH                                                2 h ago   (the house in gold: no addon name)
--                                          each        your 43   (the columns: only when you have more than one)
--   Market                               1g 20s        51g 60s
--   Vendor                                    ·            86s   (only a total: the game shows the price per item)
--   Disenchant ~                            99s        42g 57s   (gear)
--   You have 43 · bags 20 · bank 18 · guild bank 5
--   +8% vs 7-day avg · 3.4k listed · ~140 sold/day
--   (!) Sells 16% better at the goblin AH, after its cut          (when it does)
--   (icon) BUY  supply falling, price steady            Shift: more   (the signal's reason: Tooltip.Reason)
--   RECIPE / SOURCE                                      (a recipe item: what it makes, where it's sold or drops)
-- A row is { left, right, middle, ... }: the middle columns (each; a grid's further columns at r[4], r[5]) are font
-- strings of their own, lined up across the rows (a game tooltip line has only a left and a right text).
-- Shift (or the "always" setting) adds sections: what it disenchants into, yours per character (bags / bank / AH)
-- and guild bank with your average cost, every auction house you have prices for (market / you get; "alt there" on
-- the other faction's when one of your characters is of it) with the goblin AH's sales a day and data age, the price
-- with what to post at (Normal), its sell chance and, for gear, the deposit, and the data it rests on. When the UI
-- has little room (a large UI scale on a small screen) the block is compact: no freshness, holdings or context lines.
local _, ns = ...
local L = ns.L

local W = ns.Widgets

local Tooltip = {}
ns.Tooltip = Tooltip

local Dim = W.Dim

Tooltip.BETTER = 0.10 -- the goblin AH is mentioned when it pays this much more, after its cut
Tooltip.BETTER_DAYS = 3 -- ... and its prices are this recent
Tooltip.COMPACT_HEIGHT = 700 -- the UI (UIParent) shorter than this (a UI scale over ~1.1): compact tooltips
Tooltip.SMALL_SCREEN = 900 -- ... or a screen fewer pixels tall than this

local money = W.Money
local function signed(c)
  return W.SignedMoney(c, { full = true })
end

local function pct(x)
  return math.floor(x * 100 + 0.5)
end

-- Bits: the pieces a tooltip cell is written in, turned into the line's text. A cell is a string, a number (copper,
-- drawn as money), nil (nothing), or a bit or a list of bits, joined by spaces:
--   { text = "...", dim = true, color = "good" }   text, dim or in a colour (a text role or "RRGGBB")
--   { copper = 1200, signed = true }               money (signed: + / - in the gain / loss colour, every unit)
--   { item = key, count = 4 }                      an item's name in its quality colour (tooltips can't be clicked),
--                                                  a dim count after it
--   { icon = "warn" }                              the warning icon
--   { bars = "high" | "medium" | "low" }           confidence bars (W.Confidence)
--   { signal = "buy" }                             the signal's icon and word in its tone (W.SignalText)
local function bit(b)
  if b.copper ~= nil then
    return b.signed and signed(b.copper) or money(b.copper)
  elseif b.item ~= nil then
    local name, _, quality = W.ItemInfo(b.item)
    local out = name and W.QualityText(quality, name) or W.ItemLabel(b.item)
    local c = type(b.count) == "number" and W.Thousands(b.count) or b.count
    if c and c ~= "" then
      out = out .. " " .. Dim(c)
    end
    return out
  elseif b.icon == "warn" then
    return W.WARN_ICON
  elseif b.bars ~= nil then
    return W.Confidence(b.bars)
  elseif b.signal ~= nil then
    return W.SignalText(b.signal)
  end
  local text = tostring(b.text or "")
  if b.dim then
    return Dim(text)
  elseif b.color then
    return W.Color(b.color, text)
  end
  return text
end

function Tooltip.Bits(v)
  if v == nil then
    return nil
  end
  local kind = type(v)
  if kind == "string" then
    return v
  elseif kind == "number" then
    return money(v)
  elseif v[1] == nil and next(v) ~= nil then -- one bit
    return bit(v)
  end
  local out = {}
  for _, b in ipairs(v) do
    out[#out + 1] = Tooltip.Bits(b)
  end
  return table.concat(out, " ")
end

-- A section of the block: its heading (W.TipSectionText), then its rows.
--   sec = { heading, note, columns = { "each", "your 43" },        -- heads over the value columns, left to right
--           rows = { { label = bits, note = "dim text", cells = { bits, bits } } | { left, right, middle } },
--             (a cell that is false is empty: a dim "·")
--           lines = { bits, ... },                                 -- plain lines (after the rows)
--           wrap = true }                                          -- the lines wrap (long sentences)
-- Cells fill the columns left to right with the last on the right: two cells put the first in the middle column, as
-- the block's own price rows do; three (bags / bank / AH) use a second middle column. -> rows ({ left, right,
-- middle, middle2 } of text), for Tooltip.AddRows
local function cell(v)
  if v == false then
    return Dim("·") -- an empty cell
  end
  return Tooltip.Bits(v) or Dim("·")
end

-- { left, last, ..., first }: the last value on the right, the others leftwards into the middle columns
local function spread(left, values)
  local row = { left }
  for i = #values, 1, -1 do
    row[#row + 1] = values[i]
  end
  return row
end

function Tooltip.SectionRows(sec)
  local rows = {}
  local heads = {}
  for i, c in ipairs(sec.columns or {}) do
    heads[i] = Dim(c)
  end
  rows[1] = spread(W.TipSectionText(sec.heading, sec.note), heads)
  for _, r in ipairs(sec.rows or {}) do
    if r.cells or r.label then
      local left = Tooltip.Bits(r.label) or ""
      if r.note then
        left = left .. " " .. Dim(r.note)
      end
      local values = {}
      for i, v in ipairs(r.cells or {}) do
        values[i] = cell(v)
      end
      rows[#rows + 1] = spread(left, values)
    else
      rows[#rows + 1] = { Tooltip.Bits(r[1]) or "", Tooltip.Bits(r[2]), Tooltip.Bits(r[3]) }
    end
  end
  for _, l in ipairs(sec.lines or {}) do
    rows[#rows + 1] = { Tooltip.Bits(l) or "", wrap = sec.wrap }
  end
  return rows
end

local function addSections(rows, sections, detail)
  for _, sec in ipairs(sections or {}) do
    if detail or not sec.detail then
      for _, r in ipairs(Tooltip.SectionRows(sec)) do
        rows[#rows + 1] = r
      end
    end
  end
end

-- "bags 12 · bank 10 · guild bank 5": the places you can use it from that hold some (the AH is its own row)
local function places(p)
  local out = {}
  if (p.bags or 0) > 0 then
    out[#out + 1] = L["bags %s"]:format(W.Count(p.bags))
  end
  if (p.bank or 0) > 0 then
    out[#out + 1] = L["bank %s"]:format(W.Count(p.bank))
  end
  if (p.mail or 0) > 0 then
    out[#out + 1] = L["mail %s"]:format(W.Count(p.mail))
  end
  if (p.guildBank or 0) > 0 then
    out[#out + 1] = L["guild bank %s"]:format(W.Count(p.guildBank))
  end
  return table.concat(out, " · ")
end

-- a sales rate as the tooltip writes it: "140", "2.5", "0.4"
local function rate(r)
  return r >= 10 and W.Count(r) or (("%.1f"):format(r):gsub("%.0$", ""))
end

-- The signal's reason, in a few words: for DE and VENDOR how much they beat listing by (the index's numbers, which
-- the signal itself came from), else the market phase as what price and supply do. nil: nothing to say.
local PHASE_REASON = {
  shortage = L["supply falling, price rising"],
  demand = L["price rising, supply steady"],
  piling = L["price rising, sellers piling in"],
  tightening = L["supply falling, price steady"],
  balanced = L["price and supply steady"],
  pressure = L["supply building, price steady"],
  withdrawing = L["supply and price falling"],
  weak = L["price falling, supply steady"],
  dumping = L["supply rising, price falling"],
}
function Tooltip.Reason(s)
  if s.signal == "disenchant" and s.deValue and s.vendorNet then
    return L["disenchanting beats listing by %s"]:format(money(s.deValue - s.vendorNet))
  elseif s.signal == "vendor" and s.vendorPrice and s.vendorNet then
    return L["a vendor beats listing by %s"]:format(money(s.vendorPrice - s.vendorNet))
  end
  return s.phase and PHASE_REASON[s.phase] or nil
end

-- Pure: the tooltip's rows for an item summary.
--   s     the item's summary at your faction's auction house (index item)
--   opts  avgDays (3/7/14/30), detail (Shift), compact, today (day number),
--         house (its label, "Horde AH"), age ("2 h ago": its newest scan),
--         held (Trading.Held), vendor (sell price each), basis ({ units, unit }: your average cost),
--         de = { value, outcomes = { { name, chance, min, max, price } } } (gear),
--         houses = { { house, label, market, net, cut, mine, sold, age, alt } } (every AH with a price; mine =
--           yours; sold: units a day; age: "6 h ago"; alt: one of your characters is of that faction),
--         noGoblin (the goblin AH has no price for it),
--         post = { label, price, chance, hours, deposit } (what to post at: Posting:Suggest's Normal; deposit: gear),
--         better (the goblin AH pays this fraction more, after its cut),
--         sections = { sec, ... } (Tooltip.SectionRows; after the signal, sec.detail = true ones only with Shift)
-- returns { { left, right }, ... } (a row with only left is a plain line)
function Tooltip.Lines(s, opts)
  opts = opts or {}
  local rows = {}
  local held = opts.held or { total = 0 }
  -- what you have to use or sell: what's up for sale on the AH is counted apart
  local onAH = held.auctions or 0
  local n = (held.total or 0) - onAH
  local many = n > 1
  local function row(left, each, total)
    if many and total then
      rows[#rows + 1] = { left, money(total), money(each) }
    else
      rows[#rows + 1] = { left, money(each) }
    end
  end

  -- header: where the prices come from, in gold (no addon name: the block speaks for itself) and how fresh; then the
  -- columns' heads (compact: on the header line)
  local label = W.Color("gold", opts.house or L["Auction house"])
  local heads = many and { Dim(L["your %s"]:format(W.Count(n))), Dim(L["each"]) } or nil
  if opts.compact or not opts.age then
    rows[#rows + 1] = { label, heads and heads[1], heads and heads[2] }
  else
    rows[#rows + 1] = { label, Dim(opts.age) }
    if heads then
      rows[#rows + 1] = { " ", heads[1], heads[2] }
    end
  end

  row(L["Market"], s.market, s.market and s.market * n)
  if many and (opts.vendor or 0) > 0 then
    row(L["Vendor"], opts.vendor, opts.vendor * n)
  end
  local de = opts.de
  if de and de.value then
    row(L["Disenchant"] .. Dim(" ~"), de.value, de.value * n)
  end

  if not opts.compact then
    -- what you have, and where, on one line ("You have 43 · bags 20 · bank 18"); what's up for sale on the line
    -- under it; then what what's in your bags and bank is worth
    if n > 0 then
      local where_ = places(held)
      rows[#rows + 1] = { L["You have %s"]:format(W.Count(n)) .. (where_ ~= "" and Dim(" · " .. where_) or "") }
    end
    if onAH > 0 then
      rows[#rows + 1] = { L["AH"] .. " " .. Dim(W.Count(onAH)) }
    end
    -- what you have of it in bags and bank, at the market price (in the column for all of yours)
    local stock = (held.bags or 0) + (held.bank or 0)
    if stock > 0 and s.market then
      rows[#rows + 1] = { L["Bags + bank"] .. " " .. Dim(W.Count(stock)), money(s.market * stock) }
    end
    -- how it trades, one dim line: the change against its average (in its colour), how many sell a day (else how
    -- many are listed), how much of what's listed sells
    local days = opts.avgDays or 7
    local avg = s["avg" .. days] or s.avg30
    local parts = {}
    if s.market and avg and avg > 0 and s.days ~= 1 then
      parts[#parts + 1] = W.Percent(s.market / avg - 1, 0) .. Dim(" " .. L["vs %d-day avg"]:format(days))
    end
    if s.soldPerDay then
      parts[#parts + 1] = Dim(L["%s sold/day"]:format(rate(s.soldPerDay)))
    else
      parts[#parts + 1] = Dim(W.Count(s.qty or 0) .. " " .. L["listed"])
    end
    if s.sellThrough and s.stEnded then
      -- real auction outcomes (yours and your guildmates'): how much of what was listed sold
      parts[#parts + 1] = Dim(L["%d%% sell-through"]:format(pct(s.sellThrough)))
    end
    rows[#rows + 1] = { table.concat(parts, Dim(" · ")) }
    if opts.better then
      -- the notice: the warning icon and the line in amber
      rows[#rows + 1] = {
        W.WARN_ICON
          .. " "
          .. W.Color("warn", L["Sells %d%% better at the goblin AH, after its cut"]:format(pct(opts.better))),
      }
    end
  end

  -- the signal and its reason (compact: the goblin AH in its place, when it pays better), and the Shift hint
  local hint = not opts.detail and Dim(L["Shift: more"]) or nil
  local goblin = ""
  if opts.compact and opts.better then
    goblin = W.Color("warn", "  ·  " .. L["goblin AH +%d%%"]:format(pct(opts.better)))
  end
  if s.signal and s.signal ~= "none" then
    local icon = W.SignalIcon and W.SignalIcon(s.signal, 12) or ""
    local reason = goblin == "" and Tooltip.Reason(s)
    rows[#rows + 1] = {
      (icon ~= "" and icon .. " " or "") .. W.Signal(s.signal) .. (reason and Dim("  " .. reason) or "") .. goblin,
      hint,
    }
  elseif not opts.detail then
    rows[#rows + 1] = { Dim(L["Hold Shift for more"]) .. goblin }
  end
  -- the caller's sections (Tooltip.SectionRows) come after the signal; detail = true ones only with Shift
  addSections(rows, opts.sections, opts.detail)
  if not opts.detail then
    return rows
  end

  local more = {}
  -- what a disenchant gives: each outcome by its chance, a count of the material at its market price each, what that
  -- many are worth, and the expected value
  if de and de.outcomes then
    local list = {}
    for _, o in ipairs(de.outcomes) do
      local count = o.min == o.max and tostring(o.min) or (o.min .. "-" .. o.max)
      local name = o.item and Tooltip.Bits({ item = o.item }) or (o.name or "?")
      local worth = o.price and money(o.price * (o.min + o.max) / 2) or W.NONE
      list[#list + 1] = {
        Dim(("%d%%"):format(pct(o.chance))) .. "  " .. count .. " " .. name,
        worth,
        o.price and (Dim("× ") .. money(o.price)) or nil,
      }
    end
    if de.value then
      list[#list + 1] = { Dim(L["Expected, weighted by chance"]), money(de.value) }
    end
    local note
    if de.level then
      note = L["item level %d, %s"]:format(de.level, de.classID == 2 and L["weapon"] or L["armor"])
    end
    more[#more + 1] = { heading = L["Disenchants into"], note = note, rows = list }
  end

  -- yours: a grid of each character's bags / bank (mail) / AH, then each guild bank, and what you paid for it
  if n > 0 then
    local chars = held.chars or {}
    local mail = false
    for _, c in ipairs(chars) do
      mail = mail or (c.mail or 0) > 0
    end
    local keys = { "bags", "bank" }
    local columns = { L["bags"], L["bank"] }
    if mail then
      keys[#keys + 1], columns[#columns + 1] = "mail", L["mail"]
    end
    keys[#keys + 1], columns[#columns + 1] = "auctions", L["AH"]
    local list = {}
    for _, c in ipairs(chars) do
      local cells = {}
      for i, k in ipairs(keys) do
        cells[i] = (c[k] or 0) > 0 and W.Count(c[k]) or false
      end
      list[#list + 1] = { label = c.name, note = c.me and L["(you)"] or nil, cells = cells }
    end
    for _, g in ipairs(held.guilds or {}) do
      list[#list + 1] = { label = "<" .. g.name .. ">", note = L["guild bank"], cells = { W.Count(g.qty) } }
    end
    local basis = opts.basis
    if basis and basis.unit then
      list[#list + 1] = { L["Average cost"], money(basis.unit) }
      if s.market then
        list[#list + 1] = { L["Unrealized"], signed((s.market - basis.unit) * math.min(basis.units or n, n)) }
      end
    end
    local note = #chars > 1 and L["%s on %d characters"]:format(W.Count(n), #chars) or W.Count(n)
    more[#more + 1] = { heading = L["Yours"], note = note, columns = columns, rows = list }
  end

  -- every auction house with a price: its market and what you'd get there after its cut (the other faction's: "alt
  -- there" instead, when one of your characters is of it), then how much the goblin AH sells and how fresh it is
  local houses = opts.houses or {}
  local goblinNoData = { label = L["Goblin AH"], cells = { { text = L["no data"], dim = true } } }
  if #houses > 1 then
    local mine
    for _, h in ipairs(houses) do
      if h.mine then
        mine = h.net
      end
    end
    local list, lines = {}, {}
    for _, h in ipairs(houses) do
      -- how much more it pays than yours, after the label and its cut: only when it does
      local vs = ""
      if mine and mine > 0 and not h.mine and h.net and h.net > mine then
        vs = " " .. W.Color("good", ("+%d%%"):format(pct(h.net / mine - 1)))
      end
      local note = h.alt and L["(alt there)"] or ("(%d%%)"):format(pct(h.cut or 0))
      list[#list + 1] = { h.label .. " " .. Dim(note) .. vs, money(h.net), money(h.market) }
      if h.house == "Neutral" and not h.mine then
        local sells = h.sold and L["Goblin AH sells %s/day"]:format(rate(h.sold))
        local seen = h.age and L["scanned %s"]:format(h.age)
        local line = sells and seen and (sells .. ", " .. seen) or sells or (seen and L["Goblin AH"] .. " " .. seen)
        if line then
          lines[#lines + 1] = Dim(line)
        end
      end
    end
    if opts.noGoblin then
      list[#list + 1] = goblinNoData
    end
    more[#more + 1] = {
      heading = L["Auction houses"],
      note = L["after each one's cut"],
      columns = { L["market"], L["you get"] },
      rows = list,
      lines = lines,
    }
  end

  -- the price: the lowest listing, its average, the week's change, and what to post at (the sell window's Normal
  -- price), how soon that sells and how surely - and for gear, the deposit it risks. With your own auction house the
  -- only one priced, this is its section, and it says the goblin AH has no data.
  local days = opts.avgDays or 7
  local avg = s["avg" .. days] or s.avg30
  local single = #houses <= 1
  local price = {}
  price[#price + 1] = {
    label = L["Lowest listing"],
    note = single and opts.house and ("(" .. opts.house .. ")") or nil,
    cells = { money(s.min) },
  }
  if avg then
    price[#price + 1] = { L["%d-day average"]:format(days), money(avg) }
  end
  if s.change7 then
    price[#price + 1] = { L["7d change"], W.Percent(s.change7) }
  end
  if single and opts.noGoblin then
    price[#price + 1] = goblinNoData
  end
  local post = opts.post
  if post and post.price then
    price[#price + 1] = { label = L["Post at"], note = "(" .. post.label .. ")", cells = { post.price } }
    local when = L["sells in %s"]:format(W.Hours(post.hours))
    if post.chance then
      when = when .. " · " .. L["%d%% chance"]:format(pct(post.chance))
    end
    local deposit = (post.deposit or 0) > 0 and { { text = L["deposit"], dim = true }, { copper = post.deposit } }
    price[#price + 1] = { label = { text = when, dim = true }, cells = { deposit or "" } }
  end
  more[#more + 1] = { heading = single and L["Auction houses"] or L["Price"], rows = price }

  -- the data it rests on: confidence and scans, the supply trend, volatility and the score
  local data = {}
  local seen = ns.Widgets.DaysAgo(s.day, opts.today)
  if seen then
    local level = ns.Analytics and ns.Analytics.Confidence(s, opts.today) or nil
    local scans = L["%d scans in 7 days, %s"]:format(s.scans7 or 0, seen)
    data[#data + 1] = { L["Confidence"], (level and (W.Confidence(level) .. "  ") or "") .. Dim(scans) }
  end
  if s.supplyTrend30 then
    data[#data + 1] = { L["Supply trend"], W.Percent(s.supplyTrend30 * 7, 0) .. Dim(L["/week"]) }
  end
  if s.vol30 then
    data[#data + 1] = { L["Volatility"], ("%.1f%%"):format(s.vol30 * 100) }
  end
  data[#data + 1] = { L["Score"], ("%+d"):format(s.score or 0) }
  more[#more + 1] = { heading = L["Data"], rows = data }

  addSections(rows, more, true)
  return rows
end

-- Tooltips quote your own faction's auction house (the market you trade in), even right after visiting the goblin
-- AH or the other faction's; Shift compares them.
local function factionIndex()
  return ns.AME and ns.AME:FactionIndex()
end

-- the item's summary at your faction's auction house (nil when unknown)
function Tooltip.Summary(itemID)
  local index = factionIndex()
  return index and itemID and index.items[itemID] or nil
end

-- little room: a small screen (a laptop's 768 or 800 pixels), or a UI scaled up so far that the game's UI (768 units
-- tall at the default scale, on any screen) has less height than that -> compact tooltips
function Tooltip.Compact()
  local getSize = _G.GetPhysicalScreenSize
  local ph
  if getSize then
    ph = select(2, getSize())
  end
  if type(ph) == "number" and ph > 0 and ph < Tooltip.SMALL_SCREEN then
    return true
  end
  local h = UIParent and UIParent.GetHeight and UIParent:GetHeight()
  return type(h) == "number" and h > 0 and h < Tooltip.COMPACT_HEIGHT
end

-- how fresh the price is: the newest scan that had the item, else the day the index last saw it
local function age(shard, itemID, s, today)
  local fresh = ns.Posting and ns.Posting.fresh and ns.Posting.fresh[shard]
  local t = fresh and fresh[itemID] and fresh[itemID].t
  if t then
    return W.Ago(t, GetServerTime())
  end
  return W.DaysAgo(s.day, today)
end

-- the factions your characters on this market are (Holdings.Factions)
local function factions()
  local db = AME_DB or {}
  return ns.Holdings and ns.Holdings.Factions(db.holdings, ns.Holdings.Keep("market")) or {}
end

-- every auction house of this market with a price for the item: { house, label, market, net, cut, mine, day, sold,
-- age, alt } - net: what listing one there nets after its cut and deposit (Quote:ListingNet); sold: units a day;
-- alt: the other faction's house, and one of your characters is of that faction
local function houses(itemID, own, today)
  local AME = ns.AME
  local realm = AME:MarketRealmName()
  local have = factions()
  local out = {}
  for _, house in ipairs({ own, "Neutral", own == "Horde" and "Alliance" or "Horde" }) do
    local shard = ns.ShardKey(realm, house)
    local index = AME:CachedIndex(shard)
    local s = index and index.items[itemID]
    if s and s.market then
      local q = ns.Quote.For(shard, index, { house = house, fresh = false })
      out[#out + 1] = {
        house = house,
        label = ns.HOUSE_LABEL[house] or house,
        market = s.market,
        net = q:ListingNet(itemID),
        cut = q.cut,
        mine = house == own,
        day = s.day,
        sold = q:SoldPerDay(itemID),
        age = age(shard, itemID, s, today),
        alt = house ~= own and house ~= "Neutral" and have[house] or nil,
      }
    end
  end
  return out
end

-- what to post one at (your usual listing time) at your faction's auction house: the sell window's Normal price,
-- its chance to sell within the listing time and the hours it should take; gear: the deposit it risks
-- -> { label, price, chance, hours, deposit } or nil (too little data)
local function postAt(shard, itemID)
  local Posting = ns.Posting
  if not (Posting and Posting.Suggest) then
    return nil
  end
  local ok, advice = pcall(Posting.Suggest, Posting, shard, itemID, 1, ns.Settings:Get("listingHours"))
  if not ok then
    if ns.AME and ns.AME.ReportError then
      ns.AME:ReportError("tooltip posting price", advice)
    end
    return nil
  end
  if not (advice and advice.normal) then
    return nil
  end
  local info = ns.ItemCache.Get(itemID)
  local gear = info.classID == 2 or info.classID == 4
  local n = advice.normal
  return {
    label = L["Normal"],
    price = n.price,
    chance = n.chance,
    hours = n.hours,
    deposit = gear and advice.deposit or nil,
  }
end

-- your average cost per item, from the ledger (worked out again only when it changes)
local basisCache = { n = -1 }
local function basisFor(itemID)
  local ledger = ns.AME and ns.AME.ledger
  if not ledger then
    return nil
  end
  local entries = ledger.db and ledger.db.entries or {}
  if basisCache.n ~= #entries then
    basisCache.n, basisCache.basis = #entries, ledger:CostBasis()
  end
  return basisCache.basis[itemID]
end

-- everything the tooltip shows for an item: its summary and Tooltip.Lines' opts (nil when AME has no price for it)
function Tooltip.Gather(itemID, detail)
  local s = Tooltip.Summary(itemID)
  if not s then
    return nil
  end
  local shard = ns.AME:FactionShard()
  local _, own = ns.SplitShard(shard)
  local today = ns.Today(GetServerTime())
  local opts = {
    avgDays = ns.Settings:Get("tooltipAvgDays"),
    detail = detail,
    compact = Tooltip.Compact(),
    today = today,
    house = ns.HOUSE_LABEL[own] or own,
    age = age(shard, itemID, s, today),
    held = ns.Trading and AME_DB and ns.Trading.Held(itemID) or nil,
    vendor = ns.ItemCache.Get(itemID).sellPrice,
    -- what one disenchant gives, its materials at what selling them nets (Quote:Disenchant, as the DE signal)
    de = ns.Quote.For(shard, factionIndex(), { fresh = false }):Disenchant(itemID),
  }
  local all = houses(itemID, own, today)
  local mine = all[1] and all[1].mine and all[1].net
  local goblin = false
  for _, h in ipairs(all) do
    goblin = goblin or h.house == "Neutral"
    if h.house == "Neutral" and not h.mine and mine and mine > 0 and h.net then
      local recent = h.day and today - h.day <= Tooltip.BETTER_DAYS
      if recent and h.net / mine - 1 >= Tooltip.BETTER then
        opts.better = h.net / mine - 1
      end
    end
  end
  if detail then
    opts.houses = all
    opts.noGoblin = not goblin and own ~= "Neutral"
    opts.basis = basisFor(itemID)
    opts.post = postAt(shard, itemID)
  end
  return s, opts
end

-- A recipe (pattern, plans, formula...): what it makes, at its market price, and what a craft earns after the
-- reagents (bought at market) and the AH cut and deposit. Needs Crafting on (its data says what a recipe teaches).
-- -> rows like Tooltip.Lines, or nil when the item teaches nothing
Tooltip.RECIPE_MAX = 2 -- a recipe teaching more than one craft (rare): the first two
function Tooltip.RecipeLines(itemID)
  local data = ns.CraftingData
  if not (itemID and data and data:Enabled() and data:Load()) then
    return nil
  end
  local teaches = data:Teaches(itemID)
  if not (teaches and factionIndex()) then
    return nil
  end
  local craft = ns.CraftModel.Craft() -- the Crafting tab's prices: parts crafted when cheaper, fresh searches
  local rows = {}
  for i, spell in ipairs(teaches.spells) do
    if i > Tooltip.RECIPE_MAX then
      break
    end
    local recipe = ns.Recipes.Get(spell) -- its yield as scanned, when one of your characters has
    local product = recipe and recipe.product
    if product then
      local name = Tooltip.Bits({ item = product }) -- in its quality colour
      local lo, hi = recipe.madeMin or 1, recipe.madeMax or 1
      local made = hi > 1 and (" x" .. (lo < hi and lo .. "-" .. hi or hi)) or ""
      local price = craft:Price(product)
      rows[#rows + 1] = {
        L["Makes %s"]:format(name .. made),
        price and W.Money(price) or Dim(L["no price yet"]),
      }
      local e = craft:Evaluate(recipe)
      if e.profit then
        rows[#rows + 1] = { Dim("  " .. L["Per craft, after reagents"]), signed(e.profit) }
      end
    end
  end
  return #rows > 0 and rows or nil
end

local function addLines(tooltip, itemID)
  if ns.Settings and not ns.Settings:Get("tooltip") then
    return
  end
  -- a recipe item: what it makes, and where it's sold or drops (learned as you and your guild play, else the game's
  -- own words): sections of the block, after the signal
  local sections = {}
  local recipe = Tooltip.RecipeLines(itemID)
  if recipe then
    sections[#sections + 1] = { heading = L["Recipe"], rows = recipe }
  end
  local sources = ns.RecipeSources and ns.RecipeSources.TooltipLines(itemID)
  if sources then
    sections[#sections + 1] = { heading = L["Source"], lines = sources, wrap = true }
  end
  local detail = ns.Settings:Get("tooltipDetail") or (IsShiftKeyDown and IsShiftKeyDown())
  local s, opts = Tooltip.Gather(itemID, detail)
  local rows
  if s then
    opts.sections = sections
    rows = Tooltip.Lines(s, opts)
  else
    -- no price for it (a recipe nobody lists): only the sections
    rows = {}
    addSections(rows, sections, detail)
    if #rows == 0 then
      return
    end
  end
  -- with Shift: who among your guild, trusted players and your characters can make it
  local madeBy = detail and ns.CraftersView and ns.CraftersView.MadeBy(itemID)
  if madeBy then
    rows[#rows + 1] = { section = madeBy } -- its own section: a line per crafter
  end
  tooltip:AddLine(" ") -- a gap: AME's block apart from the game's lines and other addons'
  Tooltip.AddRows(tooltip, rows)
end

-- The middle column: a font string per line, right-aligned a fixed distance left of the right texts (the widest of
-- them, plus a gap), and the tooltip made wide enough for all three. Hidden again when the tooltip is cleared.
Tooltip.GAP = 14
local function middles(tooltip)
  local m = tooltip.ameMiddle
  if not m then
    m = { strings = {} }
    tooltip.ameMiddle = m
    if tooltip.HookScript then
      tooltip:HookScript("OnTooltipCleared", function(self)
        for _, fs in pairs(self.ameMiddle.strings) do
          fs:Hide()
        end
        if self.ameMiddle.width and self.SetMinimumWidth then
          self:SetMinimumWidth(0)
        end
        self.ameMiddle.width = nil
      end)
    end
  end
  return m
end

-- rows (Tooltip.Lines) onto a game tooltip. A row may also be { section = sec } (Tooltip.SectionRows), so a
-- tooltip built by hand (the minimap button, Portfolio) draws its sections the same way.
function Tooltip.AddRows(tooltip, rows)
  local name = tooltip.GetName and tooltip:GetName()
  local columns = name and tooltip.CreateFontString and tooltip.NumLines
  local placed = {}
  local flat = {}
  for _, r in ipairs(rows) do
    if r.section then
      for _, sr in ipairs(Tooltip.SectionRows(r.section)) do
        flat[#flat + 1] = sr
      end
    else
      flat[#flat + 1] = r
    end
  end
  local cols = 0 -- the most middle columns a row has
  for _, r in ipairs(flat) do
    local mids = {} -- r[3] (next to the right text), r[4] (left of it), ...
    local k = 3
    while r[k] ~= nil do
      mids[#mids + 1] = r[k]
      k = k + 1
    end
    if #mids > 0 and not columns then
      -- no font strings to add: all of them on the right, the furthest left first
      local out = {}
      for i = #mids, 1, -1 do
        out[#out + 1] = mids[i]
      end
      out[#out + 1] = r[2] or ""
      W.TipPair(tooltip, r[1], table.concat(out, "   "))
    elseif r[2] or #mids > 0 then
      W.TipPair(tooltip, r[1], r[2] or " ")
      if #mids > 0 then
        placed[#placed + 1] = { line = tooltip:NumLines(), texts = mids, rightText = r[2] or "" }
        cols = math.max(cols, #mids)
      end
    else
      -- a plain line: white unless its text says otherwise; wrapped when asked (long sentences)
      tooltip:AddLine(r[1], 1, 1, 1, r.wrap)
    end
  end
  if #placed == 0 then
    return
  end
  local m = middles(tooltip)
  local wLeft, wRight = 0, 0
  local wMid = {}
  for j = 1, cols do
    wMid[j] = 0
  end
  -- a text's width; nil when the game hands it over as a secret value (12.x: some tooltips, e.g. one shown while an
  -- auction is posted, measure as secrets addons can't do arithmetic on)
  local secret = _G.issecretvalue
  local hidden = false
  local function width(fs)
    local w = fs:GetStringWidth()
    if secret and secret(w) then
      hidden = true
      return 0
    end
    return w or 0
  end
  for _, p in ipairs(placed) do
    local left, right = _G[name .. "TextLeft" .. p.line], _G[name .. "TextRight" .. p.line]
    if not (left and right) then
      return
    end
    p.fs, p.right = {}, right
    for j, text in ipairs(p.texts) do
      local key = j == 1 and p.line or (p.line .. ":" .. j)
      local fs = m.strings[key]
      if not fs then
        fs = tooltip:CreateFontString(nil, "ARTWORK")
        m.strings[key] = fs
      end
      fs:SetFontObject(right:GetFontObject() or _G.GameTooltipText)
      fs:SetText(text)
      fs:Show()
      p.fs[j] = fs
      wMid[j] = math.max(wMid[j], width(fs))
    end
    wLeft = math.max(wLeft, width(left))
    wRight = math.max(wRight, width(right))
  end
  if hidden then
    -- the widths are secret: no lined-up columns - each goes beside the total on the right, as plain text
    for _, p in ipairs(placed) do
      local out = {}
      for j = #p.texts, 1, -1 do
        p.fs[j]:Hide()
        out[#out + 1] = p.texts[j]
      end
      out[#out + 1] = p.rightText
      p.right:SetText(table.concat(out, "   "))
    end
    return
  end
  for _, p in ipairs(placed) do
    local x = wRight + Tooltip.GAP
    for j, fs in ipairs(p.fs) do
      fs:ClearAllPoints()
      fs:SetPoint("RIGHT", p.right, "RIGHT", -x, 0)
      x = x + wMid[j] + Tooltip.GAP
    end
  end
  if tooltip.SetMinimumWidth then
    local total = wLeft + wRight + Tooltip.GAP + 22 -- and the tooltip's own padding
    for j = 1, cols do
      total = total + wMid[j] + Tooltip.GAP
    end
    m.width = math.max(m.width or 0, math.ceil(total))
    tooltip:SetMinimumWidth(m.width)
  end
end

function Tooltip:Install()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if tooltip == GameTooltip or tooltip == ItemRefTooltip then
        -- the link carries a random suffix (data.id is only the base item)
        local link = data and data.hyperlink
        if not link and tooltip.GetItem then
          link = select(2, tooltip:GetItem())
        end
        addLines(tooltip, link and ns.ItemCache.Learn(link) or (data and data.id))
      end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
      local _, link = tooltip:GetItem()
      addLines(tooltip, link and ns.ItemCache.Learn(link))
    end)
  end

  -- modified click on an item (bags, chat links, AH) opens its chart; modifier is configurable
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if link and ns.Settings:ClickModifierDown() then
        local id = ns.ItemCache.Learn(link)
        if id then
          ns.UI:ShowItem(id)
        end
      elseif link and IsShiftKeyDown() and not IsAltKeyDown() and not IsControlKeyDown() then
        ns.UI:OnItemLinkClicked(link)
      end
    end)
  end
end
