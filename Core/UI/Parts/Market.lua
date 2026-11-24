-- The Market screen's own widgets (canvas components SignalFilter and the filter chips, and the bar for buying down
-- a shopping list at the auction house). Each takes plain data and reports clicks as named actions.
--
--   signalfilter { selected?, signals?, short?, action? }   one button per signal; action gets { key = }
--   chips        { chips = { {key, label}, ... }, action?, clearAction? }   each chip's ✕ dispatches action { key };
--                "Clear all" (a link) dispatches clearAction
--   buybar       { key?, item?, count?, copper?, note?, after?, qty?, commodity?, empty?, action?, skipAction?,
--                  cancelAction? }
--     The next item to buy and its price. Buy and Confirm call the game themselves, from the click (a purchase must
--     come from a button press): the first asks the game for the price (ns.AHSearch:Buy), the second buys
--     (ns.AHSearch:Confirm). Then the action is dispatched with { key } to report it. Skip and Cancel only dispatch.
local _, ns = ...
local L = ns.L

local Layout, Kit, W = ns.Layout, ns.Kit, ns.Widgets

local function width(fs)
  return math.ceil(fs:GetStringWidth() or 0)
end

-- ------------------------------------------------------------------------------------------------ signal filter

Layout.Register("signalfilter", {
  props = { selected = "string?", signals = "table?", short = "boolean?", action = "string?" },
  create = function(parent)
    return CreateFrame("Frame", nil, parent)
  end,
  update = function(f, p, ctx)
    f.props = p
    local list = p.signals or W.SIGNAL_ORDER
    local sig = table.concat(list, ",") .. (p.short and ":short" or "")
    if f.sig ~= sig then
      if f.seg then
        f.seg:Hide()
      end
      f.seg = W.SignalFilter(f, {
        signals = list,
        short = p.short,
        height = 24,
        onSelect = function(key)
          if f.props and f.props.action then
            ctx:Dispatch(f.props.action, { key = key })
          end
        end,
      })
      f.seg:ClearAllPoints()
      f.seg:SetPoint("LEFT", f, "LEFT", 0, 0)
      f.sig = sig
    end
    f.seg:Show()
    if f.seg.Select then
      f.seg:Select(p.selected or "all", true)
    end
  end,
  size = function(f)
    return f.seg and f.seg:GetWidth() or 0, 24
  end,
})

-- ------------------------------------------------------------------------------------------------ chips

Layout.Register("chips", {
  props = { chips = "table", action = "string?", clearAction = "string?" },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent)
    f.pool = {}
    f.clear = CreateFrame("Button", nil, f)
    f.clear:SetHeight(20)
    f.clear.label = Kit.Text(f.clear, { size = 11, color = "link" })
    f.clear.label:SetPoint("LEFT", 0, 0)
    f.clear.label:SetText(L["Clear all"])
    f.clear:SetScript("OnEnter", function(self)
      Kit.SetColor(self.label, "white")
    end)
    f.clear:SetScript("OnLeave", function(self)
      Kit.SetColor(self.label, "link")
    end)
    f.clear:SetScript("OnClick", function()
      if f.props and f.props.clearAction then
        ctx:Dispatch(f.props.clearAction, {})
      end
    end)
    f.ctx = ctx
    return f
  end,
  update = function(f, p, ctx)
    f.props = p
    local x = 0
    for i, chip in ipairs(p.chips) do
      local b = f.pool[i]
      if not b then
        b = Kit.Button(f)
        b:SetScript("OnClick", function(self)
          if f.props and f.props.action then
            ctx:Dispatch(f.props.action, { key = self.key })
          end
        end)
        f.pool[i] = b
      end
      b.key = chip.key
      b.variant = "normal"
      b.label:SetText(tostring(chip.label or "") .. "  " .. Kit.Color("dim", "x"))
      b:GetScript("OnLeave")(b)
      local w = width(b.label) + 16
      b:ClearAllPoints()
      b:SetPoint("LEFT", f, "LEFT", x, 0)
      b:SetSize(w, 20)
      b:Show()
      x = x + w + 4
    end
    for i = #p.chips + 1, #f.pool do
      f.pool[i]:Hide()
    end
    f.clear:SetShown(#p.chips > 0 and p.clearAction ~= nil)
    f.clear:ClearAllPoints()
    f.clear:SetPoint("LEFT", f, "LEFT", x + 4, 0)
    f.clear:SetWidth(width(f.clear.label) + 4)
    f.natural = x + 8 + width(f.clear.label)
  end,
  size = function(f)
    return f.natural or 0, 20
  end,
})

-- ------------------------------------------------------------------------------------------------ buying bar

-- the purchase this bar's item has waiting (priced by the game, not yet sent)
local function pendingFor(key)
  local S = ns.AHSearch
  local p = S and S.pending
  if p and not p.sent and key ~= nil and p.key == key then
    return p
  end
end

local function jump(p, expected)
  local warn = ns.Settings and ns.Settings.Get and ns.Settings:Get("buyWarnPct")
  if ns.AHShopping and ns.AHShopping.PriceJump then
    return ns.AHShopping.PriceJump(p.total, expected, warn)
  end
end

Layout.Register("buybar", {
  props = {
    key = "any?",
    item = "any?",
    count = "number?",
    copper = "number?",
    note = "string?",
    after = "string?",
    qty = "number?",
    commodity = "boolean?",
    empty = "string?",
    action = "string?",
    skipAction = "string?",
    cancelAction = "string?",
  },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Kit.Box(f, "panel", "line")
    f.next = Kit.Text(f, { size = 11, color = "dim" })
    f.next:SetPoint("LEFT", 10, 0)
    f.next:SetText(L["Next"])
    f.link = W.ItemLink(f, { icon = 14 })
    f.link:SetPoint("LEFT", f.next, "RIGHT", 8, 0)
    f.price = Kit.Text(f, { size = 12 })
    f.note = Kit.Text(f, { size = 11, color = "dim" })
    f.empty = Kit.Text(f, { size = 11, color = "dim" })
    f.empty:SetPoint("LEFT", 10, 0)
    f.confirm = Kit.Button(f)
    f.confirm:SetSize(90, 24)
    f.confirm:SetPoint("RIGHT", -10, 0)
    f.cancel = Kit.Button(f)
    f.cancel.label:SetText(L["Cancel"])
    f.cancel:SetSize(64, 24)
    f.cancel:SetPoint("RIGHT", f.confirm, "LEFT", -6, 0)
    f.skip = Kit.Button(f)
    f.skip.label:SetText(L["Skip"])
    f.skip:SetSize(54, 24)
    f.skip:SetPoint("RIGHT", f.cancel, "LEFT", -6, 0)
    f.after = Kit.Text(f, { size = 11, color = "dim", justify = "RIGHT" })
    f.after:SetPoint("RIGHT", f.skip, "LEFT", -10, 0)
    -- the purchase itself: straight from the click, as the game requires
    f.confirm:SetScript("OnClick", function(self)
      local p = f.props
      local S = ns.AHSearch
      if self.variant == "disabled" or not (p and p.key ~= nil and S) then
        return
      end
      local pend = pendingFor(p.key)
      if pend then
        if pend.total or not pend.commodity then
          S:Confirm()
        end
      else
        local book = S.results and S.results[p.key]
        if S:Buy(p.key, p.qty or 1, book and book.rows and book.rows[1]) and S.pending then
          S.pending.expected = p.copper -- what the listings shown add up to (the price warning)
        end
      end
      if p.action then
        ctx:Dispatch(p.action, { key = p.key })
      end
    end)
    f.cancel:SetScript("OnClick", function()
      local p = f.props
      if pendingFor(p and p.key) and ns.AHSearch then
        ns.AHSearch:Cancel()
      end
      if p and p.cancelAction then
        ctx:Dispatch(p.cancelAction, { key = p.key })
      end
    end)
    f.skip:SetScript("OnClick", function()
      local p = f.props
      if p and p.skipAction then
        ctx:Dispatch(p.skipAction, { key = p.key })
      end
    end)
    return f
  end,
  update = function(f, p)
    f.props = p
    local has = p.key ~= nil
    for _, part in ipairs({ f.next, f.link, f.price, f.note, f.after, f.skip, f.cancel, f.confirm }) do
      part:SetShown(has)
    end
    f.empty:SetShown(not has)
    f.empty:SetText(p.empty or "")
    if not has then
      return
    end
    f.link:SetItem(p.item or p.key, p.count)
    local pend = pendingFor(p.key)
    local label, note, variant = L["Buy"], p.note or "", "primary"
    local total = p.copper
    if pend then
      if pend.commodity and not pend.total then
        label, variant, note = L["Confirm"], "disabled", L["asking the price..."]
      else
        total = pend.total or total
        local up = jump(pend, pend.expected)
        if up then
          label = L["Confirm anyway"]
          note = Kit.Color("bad", L["%d%% above the listings shown"]:format(math.floor(up * 100 + 0.5)))
        else
          label = L["Confirm"]
        end
      end
    end
    f.price:SetText(L["for %s"]:format(total and W.Money(total, true) or "—"))
    f.price:ClearAllPoints()
    f.price:SetPoint("LEFT", f.link, "RIGHT", 8, 0)
    f.note:SetText(note)
    f.note:ClearAllPoints()
    f.note:SetPoint("LEFT", f.price, "RIGHT", 10, 0)
    f.note:SetPoint("RIGHT", f.after, "LEFT", -10, 0)
    f.after:SetText(p.after and L["Then: %s"]:format(p.after) or "")
    f.confirm.variant = variant
    f.confirm.label:SetText(label)
    f.confirm:SetWidth(math.max(80, width(f.confirm.label) + 20))
    f.confirm:GetScript("OnLeave")(f.confirm)
    f.cancel.variant = pend and "normal" or "disabled"
    f.cancel:GetScript("OnLeave")(f.cancel)
    f.skip.variant = "normal"
    f.skip:GetScript("OnLeave")(f.skip)
  end,
  size = function()
    return 400, 40
  end,
})
