-- The trade widgets (the canvas's PriceLadder and BuyCard), registered with the layout engine.
--
--   priceladder { picks = { { label, when?, price (copper), selected?, apart? }, ... },
--                 layout? "rows" | "buttons" | "lines", dense?, action? }        action gets { index }
--     The one ladder wherever a price is picked for posting: Quick, Normal, Patient by how fast it sells, and Market
--     set apart. rows: the Sell view's picker; buttons: the bar under the game's AH window; lines: the Item page's
--     summary, read at a glance. dense: the narrow window, rows closer together.
--
--   buycard { summary?, listings = "source" (ctx.sources[name]: rows { key, each, qty, left, selected }), qty?,
--             total?, itemKey?, action?, qtyAction?, bar?, market?, signal?, title? }
--     What is on sale now, cheapest first, the rows an order takes from picked ("40 of 85": the last one partly), how
--     many, what it costs, and Buy. Buy runs the game's purchase from the click itself (Core/AHSearch.lua, the same
--     flow as the Shopping tab): the first click asks the game for the price, then the button reads Confirm with
--     Cancel beside it - one click per purchase, as the game asks. After the call it dispatches action with
--     { itemKey, qty, step = "price" | "confirm" | "cancel" }. qtyAction gets { text } as you change how many.
--     bar: the narrow window's one line under the listings (no table; Market and the signal at its right).
local _, ns = ...
local L = ns.L

local Layout, Kit, W = ns.Layout, ns.Kit, ns.Widgets

local Trade = {}
ns.TradePart = Trade

local function dispatch(ctx, name, payload)
  if name and ctx then
    ctx:Dispatch(name, payload)
  end
end

local function textWidth(fs)
  return math.ceil(fs:GetStringWidth() or 0)
end

-- ------------------------------------------------------------------------------------------------ price ladder

local ROW_H, ROW_H_DENSE, LINE_H = 26, 24, 18

local function ladderRow(f, i, ctx)
  local r = CreateFrame("Button", nil, f, "BackdropTemplate")
  r.label = Kit.Text(r, { size = 12 })
  r.money = Kit.Text(r, { size = 12, justify = "RIGHT" })
  r:SetScript("OnClick", function(self)
    if f.props and f.props.action then
      dispatch(ctx, f.props.action, { index = self.index })
    end
  end)
  r:SetScript("OnEnter", function(self)
    self.hot = true
    Trade.LadderLook(self)
  end)
  r:SetScript("OnLeave", function(self)
    self.hot = false
    Trade.LadderLook(self)
  end)
  f.rows[i] = r
  return r
end

-- a row's look for its layout and whether it's picked
function Trade.LadderLook(r)
  local layout, sel = r.layout, r.selected
  if layout == "lines" then
    Kit.Box(r, { 0, 0, 0, 0 }, false)
    Kit.SetColor(r.label, sel and "text" or "dim")
    Kit.SetFont(r.label, "ui", sel and 13 or 12)
    Kit.SetFont(r.money, "ui", sel and 13 or 12)
  elseif layout == "buttons" then
    if sel then
      Kit.Box(r, Kit.Selected(), Kit.Accent())
    else
      Kit.Box(r, r.hot and "lineSoft" or "control", "controlLine")
    end
    Kit.SetColor(r.label, sel and "white" or "soft")
  else
    if sel then
      Kit.Box(r, Kit.Selected(), Kit.Accent())
    else
      Kit.Box(r, r.hot and "lineSoft" or "control", "controlLine")
    end
    Kit.SetColor(r.label, "text")
  end
end

-- the y of each pick in rows / lines layout, and the whole height
function Trade.LadderOffsets(picks, layout, dense)
  local ys, y = {}, 0
  local h = layout == "lines" and LINE_H or (dense and ROW_H_DENSE or ROW_H)
  local gap = layout == "lines" and 0 or (dense and 5 or 8)
  for i, p in ipairs(picks) do
    if i > 1 then
      y = y + gap
    end
    if p.apart and layout ~= "lines" then
      y = y + (dense and 6 or 10)
    end
    ys[i] = y
    y = y + h
  end
  return ys, y, h
end

Layout.Register("priceladder", {
  props = { picks = "table", layout = "string?", dense = "boolean?", action = "string?" },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent)
    f.rows = {}
    f.ctx = ctx
    return f
  end,
  update = function(f, p, ctx)
    f.props = p
    local layout = p.layout or "rows"
    local ys, total, h = Trade.LadderOffsets(p.picks, layout, p.dense)
    local x = 0
    for i, pick in ipairs(p.picks) do
      local r = f.rows[i] or ladderRow(f, i, ctx)
      r.index, r.layout, r.selected = i, layout, pick.selected and true or false
      local when = pick.when and pick.when ~= "" and pick.when or nil
      local price = pick.price and W.Money(pick.price, true) or Kit.Color("dim", "—")
      r:ClearAllPoints()
      r.label:ClearAllPoints()
      r.money:ClearAllPoints()
      if layout == "buttons" then
        r.label:SetText(pick.label .. " " .. price)
        r.label:SetPoint("CENTER", 0, 0)
        local w = textWidth(r.label) + 20
        if pick.apart then
          x = x + 6
        end
        r:SetPoint("TOPLEFT", x, 0)
        r:SetSize(w, 24)
        x = x + w + 6
      else
        if layout == "lines" then
          r.label:SetText(pick.label .. (when and (" · " .. when) or ""))
        else
          r.label:SetText(pick.label .. (when and ("  " .. Kit.Color("dim", when)) or ""))
        end
        r.money:SetText(price)
        local inset = layout == "lines" and 0 or 9
        r.label:SetPoint("LEFT", inset, 0)
        r.money:SetPoint("RIGHT", -inset, 0)
        r.label:SetPoint("RIGHT", r.money, "LEFT", -6, 0)
        r:SetPoint("TOPLEFT", 0, -ys[i])
        r:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        r:SetHeight(h)
      end
      Trade.LadderLook(r)
      r:Show()
    end
    for i = #p.picks + 1, #f.rows do
      f.rows[i]:Hide()
    end
    f.natural = layout == "buttons" and { math.max(0, x - 6), 24 } or { 200, total }
  end,
  size = function(f)
    local n = f.natural or { 200, 0 }
    return n[1], n[2]
  end,
})

-- ------------------------------------------------------------------------------------------------ buy card

local function sourceRows(ctx, name)
  local s = ctx and ctx.sources and ctx.sources[name]
  if type(s) == "function" then
    s = s()
  end
  return type(s) == "table" and s or {}
end

local function search()
  return ns.AHSearch
end

-- the purchase the game priced for this item and nobody confirmed yet
function Trade.Pending(key)
  local S = search()
  local p = S and S.pending
  if p and not p.sent and key ~= nil and p.key == key then
    return p
  end
  return nil
end

-- what the Buy button says and whether Cancel shows: "Buy"; "asking the price..." while the game works it out;
-- "Confirm" (or "Confirm anyway" when the price jumped over Settings buyWarnPct)
function Trade.BuyState(key)
  local p = Trade.Pending(key)
  if not p then
    return { label = L["Buy"], priced = false }
  end
  if p.commodity and not p.total then
    return { label = L["Buy"], priced = true, asking = true, note = L["asking the price..."] }
  end
  local warn = ns.Settings and ns.Settings:Get("buyWarnPct")
  local jump
  local shop = ns.AHShopping
  if shop and shop.PriceJump then
    jump = shop.PriceJump(p.total, p.expected, warn)
  end
  return {
    label = jump and L["Confirm anyway"] or L["Confirm"],
    priced = true,
    total = p.total,
    qty = p.qty,
    jump = jump,
    note = jump and Kit.Color("bad", L["%d%% above the listings shown"]:format(math.floor(jump * 100 + 0.5))) or nil,
  }
end

-- The click: confirm what Buy priced, or ask the game for the price of qty. It runs from the button press itself
-- (the game wants a hardware click for a purchase). Returns the step it took ("confirm" | "price") or nil.
function Trade.Buy(key, qty)
  local S = search()
  if not (S and key) then
    return nil
  end
  local p = Trade.Pending(key)
  if p then
    if S:Confirm() then
      return "confirm"
    end
    return nil
  end
  qty = math.max(1, math.floor(tonumber(qty) or 1))
  local book = S.results and S.results[key]
  local expected
  if book and book.rows then
    local fill = ns.ItemPage and ns.ItemPage.Fill
    if fill then
      local _, cost = fill(book.rows, qty)
      expected = cost
    end
  end
  if not (book and book.commodity) then
    -- gear: one auction, the cheapest listing (the game buys one listing at a time)
    local row = book and book.rows and book.rows[1]
    if row and S:Buy(key, 1, row) then
      return "price"
    end
    return nil
  end
  if S:Buy(key, qty) then
    if S.pending then
      S.pending.expected = expected -- what the listings shown added up to (the price warning)
    end
    return "price"
  end
  return nil
end

function Trade.Cancel()
  local S = search()
  if S and S.Cancel then
    S:Cancel()
  end
end

local LISTING_COLUMNS = {
  { key = "each", label = L["Each"], width = 80, format = "money", align = "LEFT" },
  { key = "qty", label = L["Qty"], width = 70 },
  { key = "left", label = L["Time left"], width = 60 },
}

local function newListings(f)
  local cols = {}
  for i, c in ipairs(LISTING_COLUMNS) do
    cols[i] = {
      key = c.key,
      label = c.label,
      width = c.width,
      format = c.format,
      align = c.align,
      text = not c.format and function(d)
        local v = d[c.key]
        if c.key == "left" then
          return Kit.Color("dim", v or "")
        end
        return v ~= nil and tostring(v) or ""
      end or nil,
    }
  end
  local t = ns.DataTable.New(f.tableHolder, {
    columns = cols,
    fill = true,
    flex = "qty",
    selected = function(d)
      return d.selected and true or false
    end,
  })
  t.frame:SetPoint("TOPLEFT", 0, 0)
  t.frame:SetPoint("BOTTOMRIGHT", 0, 0)
  f.listings = t
end

Layout.Register("buycard", {
  props = {
    summary = "string?",
    listings = "string?",
    qty = "any?",
    total = "number?",
    itemKey = "any?",
    action = "string?",
    qtyAction = "string?",
    bar = "boolean?",
    market = "number?",
    signal = "string?",
    title = "string?",
  },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f.ctx = ctx
    Kit.Box(f, "panel", "line")
    f.top = Kit.Line(f, "TOP", "frameLit")
    f.title = Kit.Text(f, { font = "display", size = 14, color = "heading" })
    f.summary = Kit.Text(f, { size = 11, color = "dim" })
    f.tableHolder = CreateFrame("Frame", nil, f)
    f.tableHolder:SetScript("OnSizeChanged", function()
      if f.listings then
        f.listings:Render()
      end
    end)
    -- the order line: how many, what for, Cancel and Buy
    f.qtyLabel = Kit.Text(f, { size = 12, color = "dim" })
    f.qtyLabel:SetText(L["Buy"])
    f.box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    Kit.Box(f.box, "bg", "controlLine")
    Kit.SetFont(f.box, "ui", 11)
    Kit.SetColor(f.box, "soft")
    f.box:SetTextInsets(6, 6, 0, 0)
    f.box:SetAutoFocus(false)
    if f.box.SetNumeric then
      f.box:SetNumeric(true)
    end
    f.box:SetSize(50, 24)
    local function sendQty(self)
      if f.props and f.props.qtyAction then
        dispatch(ctx, f.props.qtyAction, { text = self:GetText() or "" })
      end
    end
    f.box:SetScript("OnEnterPressed", function(self)
      sendQty(self)
      self:ClearFocus()
    end)
    f.box:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
    end)
    f.box:SetScript("OnEditFocusLost", sendQty)
    f.forText = Kit.Text(f, { size = 12 })
    f.marketText = Kit.Text(f, { size = 12, justify = "RIGHT" })
    f.badge = W.SignalBadge(f)
    f.buy = Kit.Button(f)
    f.buy:SetSize(80, 24)
    f.cancel = Kit.Button(f)
    f.cancel:SetSize(60, 24)
    f.cancel.label:SetText(L["Cancel"])
    f.note = Kit.Text(f, { size = 11, color = "dim", justify = "RIGHT" })
    -- the purchase itself, from this click (Core/AHSearch.lua)
    f.buy:SetScript("OnClick", function()
      local p = f.props or {}
      local qty = tonumber(f.box:GetText()) or tonumber(p.qty) or 1
      local step = Trade.Buy(p.itemKey, qty)
      if step then
        dispatch(ctx, p.action, { itemKey = p.itemKey, qty = qty, step = step })
      end
      Trade.DrawState(f)
    end)
    f.cancel:SetScript("OnClick", function()
      local p = f.props or {}
      Trade.Cancel()
      dispatch(ctx, p.action, { itemKey = p.itemKey, step = "cancel" })
      Trade.DrawState(f)
    end)
    return f
  end,
  update = function(f, p, ctx)
    f.props = p
    local bar = p.bar and true or false
    f.title:SetShown(not bar)
    f.summary:SetShown(not bar)
    f.tableHolder:SetShown(not bar)
    f.top:SetShown(not bar)
    f.title:SetText(p.title or L["Buy"])
    f.summary:SetText(p.summary or "")
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.summary:ClearAllPoints()
    f.summary:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
    f.tableHolder:ClearAllPoints()
    f.tableHolder:SetPoint("TOPLEFT", 10, -28)
    f.tableHolder:SetPoint("BOTTOMRIGHT", -10, 38)
    if not bar then
      if not f.listings then
        newListings(f)
      end
      f.listings:SetData(sourceRows(ctx, p.listings))
      f.listings:SetMessage(#sourceRows(ctx, p.listings) == 0 and (p.summary or L["none listed"]) or nil)
      f.listings:Render()
    end
    if not (f.box.HasFocus and f.box:HasFocus()) then
      f.box:SetText(p.qty ~= nil and tostring(p.qty) or "")
    end
    -- the order line's pieces, left to right (bar: "Buy [100] 100 for 9g ... Market 9s 57c [SELL] Cancel Confirm")
    f.qtyLabel:SetShown(bar)
    f.qtyLabel:ClearAllPoints()
    f.box:ClearAllPoints()
    if bar then
      f.qtyLabel:SetPoint("LEFT", 10, 0)
      f.box:SetPoint("LEFT", f.qtyLabel, "RIGHT", 6, 0)
    else
      f.box:SetPoint("BOTTOMLEFT", 10, 8)
    end
    f.forText:ClearAllPoints()
    f.forText:SetPoint("LEFT", f.box, "RIGHT", 8, 0)
    f.buy:ClearAllPoints()
    if bar then
      f.buy:SetPoint("RIGHT", -10, 0)
    else
      f.buy:SetPoint("BOTTOMRIGHT", -10, 8)
    end
    f.cancel:ClearAllPoints()
    f.cancel:SetPoint("RIGHT", f.buy, "LEFT", -6, 0)
    f.badge:SetShown(bar and p.signal ~= nil and p.signal ~= "none")
    f.badge:SetSignal(p.signal)
    f.marketText:SetShown(bar and p.market ~= nil)
    f.marketText:SetText(p.market and (Kit.Color("dim", L["Market"]) .. " " .. W.Money(p.market, true)) or "")
    Trade.DrawState(f)
  end,
  size = function(_, p)
    return 270, p.bar and 38 or 200
  end,
})

-- the order line from the purchase's state: Buy, or the game's price with Confirm and Cancel
function Trade.DrawState(f)
  local p = f.props or {}
  local st = Trade.BuyState(p.itemKey)
  f.buy.label:SetText(st.asking and L["Buy"] or st.label)
  f.buy.variant = st.asking and "disabled" or "primary"
  local look = f.buy:GetScript("OnLeave")
  if look then
    look(f.buy)
  end
  f.buy:SetWidth(math.max(60, textWidth(f.buy.label) + 22))
  f.cancel:SetShown(st.priced)
  local qty = st.qty or tonumber(f.box:GetText()) or tonumber(p.qty)
  local total = st.total or p.total
  local text = ""
  if st.asking then
    text = W.Dim(L["asking the price..."])
  elseif total and qty then
    text = (p.bar and (W.Count(qty) .. " ") or "") .. L["for %s"]:format(W.Money(total, true))
  end
  f.forText:SetText(text)
  f.note:SetShown(st.note ~= nil and not p.bar)
  f.note:SetText(st.note or "")
  f.note:ClearAllPoints()
  f.note:SetPoint("BOTTOMRIGHT", f.buy, "TOPRIGHT", 0, 4)
  -- the bar's right side: Market and the signal, left of the buttons
  local right = st.priced and f.cancel or f.buy
  f.badge:ClearAllPoints()
  f.badge:SetPoint("RIGHT", right, "LEFT", -8, 0)
  f.marketText:ClearAllPoints()
  f.marketText:SetPoint("RIGHT", f.badge:IsShown() and f.badge or right, "LEFT", -8, 0)
end
