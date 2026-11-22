-- Item tooltip lines from the market index (no history decoding on hover), and the modified click (Settings) that
-- opens an item's chart.
--
-- The AME block, under the game's lines (prices from your faction's auction house), after a gap:
--   AME                                     Horde AH · 2 h ago
--                                          each        your 43   (the columns: only when you have more than one)
--   Market                               1g 20s        51g 60s
--   Vendor                                    ·            86s   (only a total: the game shows the price per item)
--   Disenchant ~                            99s        42g 57s   (gear)
--   You have 43 · bags 20 · bank 18 · guild bank 5
--   +8% vs 7d avg · 3.4k listed · ~140 sold/day
--   Sells 16% better at the goblin AH, after its cut              (when it does)
--   (icon) BUY  supply falling                          Shift: more
-- A row is { left, right, middle }: the middle column (each) is a font string of its own, lined up across the rows
-- (a game tooltip line has only a left and a right text).
-- Shift (or the "always" setting) adds what it disenchants into, yours per character and guild bank (with your
-- average cost), every auction house you have prices for, and the price and data details. When the UI has little
-- room (a large UI scale on a small screen) the block is compact: no freshness, holdings or context lines.
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

local function section(rows, title, note)
  rows[#rows + 1] = { W.Color("dim", title) .. (note and Dim("  ·  " .. note) or "") }
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
--           lines = { bits, ... } }                                -- plain lines (after the rows)
-- A row with two cells puts the first in the middle column and the second on the right, as the block's own price
-- rows do. -> rows ({ left, right, middle } of text), for Tooltip.AddRows
local function cell(v)
  if v == false then
    return Dim("·") -- an empty cell
  end
  return Tooltip.Bits(v) or Dim("·")
end

function Tooltip.SectionRows(sec)
  local rows = {}
  local cols = sec.columns or {}
  local head = W.TipSectionText(sec.heading, sec.note)
  if #cols >= 2 then
    rows[1] = { head, Dim(cols[2]), Dim(cols[1]) }
  elseif #cols == 1 then
    rows[1] = { head, Dim(cols[1]) }
  else
    rows[1] = { head }
  end
  for _, r in ipairs(sec.rows or {}) do
    if r.cells or r.label then
      local left = Tooltip.Bits(r.label) or ""
      if r.note then
        left = left .. " " .. Dim(r.note)
      end
      local cells = r.cells or {}
      if #cells >= 2 then
        rows[#rows + 1] = { left, cell(cells[2]), cell(cells[1]) }
      else
        rows[#rows + 1] = { left, cells[1] ~= nil and cell(cells[1]) or nil }
      end
    else
      rows[#rows + 1] = { Tooltip.Bits(r[1]) or "", Tooltip.Bits(r[2]), Tooltip.Bits(r[3]) }
    end
  end
  for _, l in ipairs(sec.lines or {}) do
    rows[#rows + 1] = { Tooltip.Bits(l) or "" }
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

-- "bags 12 · bank 10 · on AH 5": the places that hold some
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
  if (p.auctions or 0) > 0 then
    out[#out + 1] = L["on AH %s"]:format(W.Count(p.auctions))
  end
  if (p.guildBank or 0) > 0 then
    out[#out + 1] = L["guild bank %s"]:format(W.Count(p.guildBank))
  end
  return table.concat(out, " · ")
end

-- Pure: the tooltip's rows for an item summary.
--   s     the item's summary at your faction's auction house (index item)
--   opts  avgDays (3/7/14/30), detail (Shift), compact, today (day number),
--         house (its label, "Horde AH"), age ("2 h ago": its newest scan),
--         held (Trading.Held), vendor (sell price each), basis ({ units, unit }: your average cost),
--         de = { value, outcomes = { { name, chance, min, max, price } } } (gear),
--         houses = { { label, market, net, cut, mine } } (every AH with a price; mine = yours),
--         better (the goblin AH pays this fraction more, after its cut),
--         sections = { sec, ... } (Tooltip.SectionRows; after the signal, sec.detail = true ones only with Shift)
-- returns { { left, right }, ... } (a row with only left is a plain line)
function Tooltip.Lines(s, opts)
  opts = opts or {}
  local rows = {}
  local held = opts.held or { total = 0 }
  local n = held.total or 0
  local many = n > 1
  local function row(left, each, total)
    if many and total then
      rows[#rows + 1] = { left, money(total), money(each) }
    else
      rows[#rows + 1] = { left, money(each) }
    end
  end

  -- header: where the prices come from (no addon name: the block speaks for itself) and how fresh; then the
  -- columns' heads (compact: on the header line)
  local label = W.Color("brand", opts.house or L["Auction house"])
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
    rows[#rows + 1] = { L["Vendor"], money(opts.vendor * n), Dim("·") }
  end
  local de = opts.de
  if de and de.value then
    row(L["Disenchant"] .. Dim(" ~"), de.value, de.value * n)
  end

  if not opts.compact then
    if n > 0 then
      local where_ = places(held)
      rows[#rows + 1] = { L["You have %s"]:format(W.Count(n)) .. (where_ ~= "" and Dim("  ·  " .. where_) or "") }
    end
    -- how it trades: against its average, how many sell, how much of what's listed sells
    local days = opts.avgDays or 7
    local avg = s["avg" .. days] or s.avg30
    local parts = {}
    if s.market and avg and avg > 0 and s.days ~= 1 then
      parts[#parts + 1] = W.Percent(s.market / avg - 1, 0) .. Dim(" " .. L["vs %dd avg"]:format(days))
    end
    parts[#parts + 1] = Dim(W.Count(s.qty or 0) .. " " .. L["listed"])
    if s.sellRate then
      local r = s.sellRate
      local count = r >= 10 and W.Count(r) or (("%.1f"):format(r):gsub("%.0$", ""))
      parts[#parts + 1] = Dim(L["~%s sold/day"]:format(count))
    end
    if s.sellThrough and s.stEnded then
      -- real auction outcomes (yours and your guildmates'): how much of what was listed sold
      parts[#parts + 1] = Dim(
        L["%d%% sell-through"]:format(pct(s.sellThrough))
          .. " ("
          .. L["%s of %s sold"]:format(W.Count(s.stSold or 0), W.Count(s.stEnded))
          .. ")"
      )
    end
    rows[#rows + 1] = { table.concat(parts, Dim("  ·  ")) }
    if opts.better then
      rows[#rows + 1] =
        { W.Color("warn", L["Sells %d%% better at the goblin AH, after its cut"]:format(pct(opts.better))) }
    end
  end

  -- the signal, and the Shift hint
  local hint = not opts.detail and Dim(L["Shift: more"]) or nil
  local phase = s.phase and ns.Analytics and ns.Analytics.PHASE_LABEL[s.phase]
  local goblin = ""
  if opts.compact and opts.better then
    goblin = W.Color("warn", "  ·  " .. L["goblin AH +%d%%"]:format(pct(opts.better)))
  end
  if s.signal and s.signal ~= "none" then
    local icon = W.SignalIcon and W.SignalIcon(s.signal, 12) or ""
    rows[#rows + 1] = {
      (icon ~= "" and icon .. " " or "")
        .. W.Signal(s.signal)
        .. (phase and Dim("  " .. phase:lower()) or "")
        .. goblin,
      hint,
    }
  elseif not opts.detail then
    rows[#rows + 1] = { Dim(L["Hold Shift for more AME data"]) .. goblin }
  end
  -- the caller's sections (Tooltip.SectionRows) come after the signal; detail = true ones only with Shift
  addSections(rows, opts.sections, opts.detail)
  if not opts.detail then
    return rows
  end

  -- what a disenchant gives: each outcome by its chance, what that many are worth, and the expected value
  if de and de.outcomes then
    section(rows, L["Disenchants into"])
    for _, o in ipairs(de.outcomes) do
      local count = o.min == o.max and tostring(o.min) or (o.min .. "-" .. o.max)
      local worth = o.price and money(o.price * (o.min + o.max) / 2) or W.NONE
      rows[#rows + 1] = { ("%d%%  %s %s"):format(pct(o.chance), count, o.name or "?"), worth }
    end
    if de.value then
      rows[#rows + 1] = { Dim(L["Expected, weighted by chance"]), money(de.value) }
    end
  end

  -- yours: per character, then each guild bank, and what you paid for it
  if n > 0 then
    section(rows, L["Yours"])
    for _, c in ipairs(held.chars or {}) do
      rows[#rows + 1] = { c.name .. (c.me and Dim(" " .. L["(you)"]) or ""), places(c) }
    end
    for _, g in ipairs(held.guilds or {}) do
      rows[#rows + 1] = { "<" .. g.name .. ">" .. Dim(" " .. L["guild bank"]), W.Count(g.qty) }
    end
    local basis = opts.basis
    if basis and basis.unit then
      rows[#rows + 1] = { L["Average cost"], money(basis.unit) }
      if s.market then
        rows[#rows + 1] = { L["Unrealized"], signed((s.market - basis.unit) * math.min(basis.units or n, n)) }
      end
    end
  end

  -- every auction house with a price: its market and what you'd get there after its cut
  local houses = opts.houses or {}
  if #houses > 1 then
    section(rows, L["Auction houses"], L["after each one's cut"])
    local mine
    for _, h in ipairs(houses) do
      if h.mine then
        mine = h.net
      end
    end
    for _, h in ipairs(houses) do
      -- how much more it pays than yours, after the label and its cut: only when it does
      local vs = ""
      if mine and mine > 0 and not h.mine and h.net > mine then
        vs = " " .. W.Color("good", ("+%d%%"):format(pct(h.net / mine - 1)))
      end
      rows[#rows + 1] = {
        h.label .. Dim((" (%d%%)"):format(pct(h.cut))) .. vs,
        money(h.market) .. Dim("  >  ") .. money(h.net),
      }
    end
  end

  section(rows, L["Price"])
  local days = opts.avgDays or 7
  local avg = s["avg" .. days] or s.avg30
  if avg then
    rows[#rows + 1] = { L["%d-day average"]:format(days), money(avg) }
  end
  rows[#rows + 1] = { L["lowest"], money(s.min) }
  if s.change7 then
    rows[#rows + 1] = { L["7d change"], W.Percent(s.change7) }
  end
  if s.supplyTrend30 then
    rows[#rows + 1] = { L["supply trend"], W.Percent(s.supplyTrend30 * 7, 0) .. Dim(L["/week"]) }
  end
  if s.vol30 then
    rows[#rows + 1] = { L["volatility"], ("%.1f%%"):format(s.vol30 * 100) }
  end
  rows[#rows + 1] = { L["score"], ("%+d"):format(s.score or 0) }
  local seen = ns.Widgets.DaysAgo(s.day, opts.today)
  if seen then
    local level = ns.Analytics and ns.Analytics.Confidence(s, opts.today) or nil
    local scans = L["%d scans/7d, %s"]:format(s.scans7 or 0, seen)
    rows[#rows + 1] = { L["data"], Dim(level and W.Confidence(level) or "") .. "  " .. scans }
  end
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

-- what one disenchant of the item gives, at market prices (gear of uncommon quality and up), or nil
function Tooltip.Disenchant(itemID, items)
  local info = ns.ItemCache.Get(itemID)
  if not (info and (info.classID == 2 or info.classID == 4)) then
    return nil
  end
  local quality = info.quality
  local outcomes = quality and quality >= 2 and ns.Disenchant.Outcomes(info.level, quality, info.classID)
  if not outcomes then
    return nil
  end
  local out, value = { outcomes = {} }, 0
  for i, o in ipairs(outcomes) do
    local m = items[o[1]]
    local price = m and m.market
    out.outcomes[i] = { name = ns.ItemCache.Name(o[1]), chance = o[2], min = o[3], max = o[4], price = price }
    value = value and price and value + price * o[2] * (o[3] + o[4]) / 2 or nil
  end
  table.sort(out.outcomes, function(a, b)
    return a.chance > b.chance
  end)
  out.value = value
  return out
end

-- every auction house of this market with a price for the item: { house, label, market, net, cut, mine, day }
local function houses(itemID, own)
  local AME = ns.AME
  local realm = AME:MarketRealmName()
  local out = {}
  for _, house in ipairs({ own, "Neutral", own == "Horde" and "Alliance" or "Horde" }) do
    local index = AME:CachedIndex(ns.ShardKey(realm, house))
    local s = index and index.items[itemID]
    if s and s.market then
      local cut = ns.Settings:AuctionCut(house)
      out[#out + 1] = {
        house = house,
        label = ns.HOUSE_LABEL[house] or house,
        market = s.market,
        net = s.market * (1 - cut),
        cut = cut,
        mine = house == own,
        day = s.day,
      }
    end
  end
  return out
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

-- how fresh the price is: the newest scan that had the item, else the day the index last saw it
local function age(shard, itemID, s, today)
  local fresh = ns.Posting and ns.Posting.fresh and ns.Posting.fresh[shard]
  local t = fresh and fresh[itemID] and fresh[itemID].t
  if t then
    return W.Ago(t, GetServerTime())
  end
  return W.DaysAgo(s.day, today)
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
    de = Tooltip.Disenchant(itemID, factionIndex().items),
  }
  local all = houses(itemID, own)
  local mine = all[1] and all[1].mine and all[1].net
  for _, h in ipairs(all) do
    if h.house == "Neutral" and not h.mine and mine and mine > 0 then
      local recent = h.day and today - h.day <= Tooltip.BETTER_DAYS
      if recent and h.net / mine - 1 >= Tooltip.BETTER then
        opts.better = h.net / mine - 1
      end
    end
  end
  if detail then
    opts.houses = all
    opts.basis = basisFor(itemID)
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
  local index = factionIndex()
  if not (teaches and index) then
    return nil
  end
  local house = UnitFactionGroup and UnitFactionGroup("player")
  local cut = (house == "Neutral" and ns.Settings:Get("cutNeutral") or ns.Settings:Get("cutFaction")) / 100
  local craft = ns.Crafting.New({
    market = function(id)
      return index.items[id]
    end,
    vendorBuy = function(id)
      return data:VendorPrice(id)
    end,
    vendorSell = function(id)
      return ns.ItemCache.Get(id).sellPrice
    end,
    cut = cut,
    deposit = function(id)
      local sell = ns.ItemCache.Get(id).sellPrice
      return sell and ns.Arbitrage.Deposit(sell, house, ns.Settings:Get("listingHours")) or 0
    end,
    factor = ns.Settings:Get("outlierFactor"),
  })
  local rows = {}
  for i, spell in ipairs(teaches.spells) do
    if i > Tooltip.RECIPE_MAX then
      break
    end
    local recipe = data:Recipe(spell)
    local product = recipe and recipe.product
    if product then
      local name = W.ItemLabel(product)
      local made = (recipe.made or 1) > 1 and (" x" .. recipe.made) or ""
      local price = craft:Price(product)
      rows[#rows + 1] = {
        L["Makes %s"]:format(name .. made),
        price and W.Money(price) or Dim(L["no price yet"]),
      }
      local e = craft:Evaluate(recipe)
      if e.profit then
        rows[#rows + 1] = {
          Dim("  " .. L["Per craft, after reagents"]),
          W.Color(e.profit >= 0 and "good" or "bad", e.profit < 0 and "-" or "+") .. W.Money(math.abs(e.profit)),
        }
      end
    end
  end
  return #rows > 0 and rows or nil
end

local function addLines(tooltip, itemID)
  if ns.Settings and not ns.Settings:Get("tooltip") then
    return
  end
  local recipe = Tooltip.RecipeLines(itemID)
  for _, r in ipairs(recipe or {}) do
    W.TipPair(tooltip, r[1], r[2])
  end
  -- a recipe item: where it's sold or drops (learned as you and your guild play), else the game's own words
  for i, line in ipairs(ns.RecipeSources and ns.RecipeSources.TooltipLines(itemID) or {}) do
    local label = i == 1 and (W.Dim(L["Source:"]) .. " ") or "      "
    tooltip:AddLine(label .. line, 1, 1, 1, true)
  end
  local detail = ns.Settings:Get("tooltipDetail") or (IsShiftKeyDown and IsShiftKeyDown())
  local s, opts = Tooltip.Gather(itemID, detail)
  if not s then
    return
  end
  local rows = Tooltip.Lines(s, opts)
  -- with Shift: who among your guild, trusted players and your characters can make it
  local madeBy = detail and ns.CraftersView and ns.CraftersView.MadeBy(itemID)
  if madeBy then
    rows[#rows + 1] = { W.Color("dim", L["Made by"]), madeBy }
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
  for _, r in ipairs(flat) do
    if r[3] and not columns then
      W.TipPair(tooltip, r[1], r[3] .. "   " .. (r[2] or "")) -- no font strings to add: both on the right
    elseif r[2] or r[3] then
      W.TipPair(tooltip, r[1], r[2] or " ")
      if r[3] then
        placed[#placed + 1] = { line = tooltip:NumLines(), text = r[3], rightText = r[2] or "" }
      end
    else
      tooltip:AddLine(r[1])
    end
  end
  if #placed == 0 then
    return
  end
  local m = middles(tooltip)
  local wLeft, wMid, wRight = 0, 0, 0
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
    local fs = m.strings[p.line]
    if not fs then
      fs = tooltip:CreateFontString(nil, "ARTWORK")
      m.strings[p.line] = fs
    end
    fs:SetFontObject(right:GetFontObject() or _G.GameTooltipText)
    fs:SetText(p.text)
    fs:Show()
    p.fs, p.right = fs, right
    wLeft = math.max(wLeft, width(left))
    wMid = math.max(wMid, width(fs))
    wRight = math.max(wRight, width(right))
  end
  if hidden then
    -- the widths are secret: no lined-up column - each goes beside the total on the right, as plain text
    for _, p in ipairs(placed) do
      p.fs:Hide()
      p.right:SetText(p.text .. "   " .. p.rightText)
    end
    return
  end
  for _, p in ipairs(placed) do
    p.fs:ClearAllPoints()
    p.fs:SetPoint("RIGHT", p.right, "RIGHT", -(wRight + Tooltip.GAP), 0)
  end
  if tooltip.SetMinimumWidth then
    local total = math.ceil(wLeft + wMid + wRight + 2 * Tooltip.GAP + 22) -- and the tooltip's own padding
    m.width = math.max(m.width or 0, total)
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
