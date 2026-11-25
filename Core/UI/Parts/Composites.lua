-- Widgets made of several parts (the canvas's KpiCard, ActionList, PriceLadder, BuyCard, ...). Each takes plain
-- data and reports clicks as named actions.
--
--   kpi        { label, value?, copper?, signed?, delta?, deltaTone?, note? }
--   actionlist { title?, bare?, rows = { row, ... } }
--     row = { key, pill, tone?, title = parts, sub = parts?, value?, valueTone?, button?, action?, primary?,
--             off?, selected? }
--     parts: "text" | { item = key, count? } | { text, tone } | { gold = "g" }, or a list of them. Item names are
--     links (tooltip, Shift-click, click opens the item).
--     The button dispatches the row's action with { key = row.key }; off: greyed, naming where it works.
local _, ns = ...

local Layout, Kit, W = ns.Layout, ns.Kit, ns.Widgets

-- a line of text with item links in it
function Kit.Parts(parts)
  if parts == nil then
    return ""
  end
  if type(parts) ~= "table" or parts.item or parts.text or parts.gold then
    parts = { parts }
  end
  local out = {}
  for i, p in ipairs(parts) do
    if type(p) == "string" then
      out[i] = p
    elseif p.item then
      out[i] = W.LinkText(p.item, p.count)
    elseif p.gold then
      out[i] = Kit.Color("gold", p.gold)
    else
      out[i] = p.tone and Kit.Color(p.tone, p.text or "") or (p.text or "")
    end
  end
  return table.concat(out)
end

-- ------------------------------------------------------------------------------------------------ kpi card

Layout.Register("kpi", {
  props = {
    label = "string",
    value = "string?",
    copper = "number?",
    signed = "boolean?",
    delta = "string?",
    deltaTone = "string?",
    note = "string?",
    rise = "number?",
    fall = "number?",
    term = "string?",
  },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Kit.Box(f, "panel", "line")
    -- term: what the figure means, from the Guide's glossary, on hover (right-click opens it in the Guide)
    if ns.Help and ns.Help.Explain then
      ns.Help.Explain(f, function(self)
        return self.props and self.props.term
      end)
    end
    -- rise / fall: the breadth bar under the value, rising in green, falling in red
    f.rise = f:CreateTexture(nil, "ARTWORK")
    f.fall = f:CreateTexture(nil, "ARTWORK")
    f.top = Kit.Line(f, "TOP", "frameLit")
    -- the board's KpiCard: a dim 11 px label, the value 17 px SemiBold with its change after it (12 px SemiBold,
    -- in its tone), a dim 11 px note; 7 px / 10 px padding
    f.label = Kit.Text(f, { size = 11, color = "dim" })
    f.label:SetPoint("TOPLEFT", 10, -8)
    f.label:SetPoint("RIGHT", -10, 0)
    f.value = Kit.Text(f, { size = 17 })
    Kit.SetFont(f.value, "ui", 17, true)
    f.value:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -4)
    f.delta = Kit.Text(f, { size = 12 })
    Kit.SetFont(f.delta, "ui", 12, true)
    f.delta:SetPoint("BOTTOMLEFT", f.value, "BOTTOMRIGHT", 6, 1)
    f.note = Kit.Text(f, { size = 11, color = "dim" })
    f.note:SetPoint("TOPLEFT", f.value, "BOTTOMLEFT", 0, -4)
    f.note:SetPoint("RIGHT", -10, 0)
    f.rise:SetHeight(5)
    f.fall:SetHeight(5)
    f.rise:SetPoint("TOPLEFT", f.value, "BOTTOMLEFT", 0, -4)
    f.fall:SetPoint("TOPLEFT", f.rise, "TOPRIGHT", 0, 0)
    return f
  end,
  update = function(f, p)
    f.props = p
    f.label:SetText(p.label)
    local v
    if p.copper then
      v = p.signed and W.SignedMoney(p.copper) or W.Money(p.copper, true)
    else
      v = p.value or Kit.Color("dim", "—")
    end
    f.value:SetText(v)
    f.delta:SetText(p.delta and Kit.Color(p.deltaTone or "dim", p.delta) or "")
    f.note:SetText(p.note or "")
    local bar = p.rise and p.fall and (p.rise + p.fall) > 0
    f.rise:SetShown(bar)
    f.fall:SetShown(bar)
    f.note:ClearAllPoints()
    f.note:SetPoint("TOPLEFT", bar and f.rise or f.value, "BOTTOMLEFT", 0, bar and -3 or -4)
    f.note:SetPoint("RIGHT", -10, 0)
    if bar then
      local w = math.max(1, (f:GetWidth() or 200) - 20)
      local r = w * p.rise / (p.rise + p.fall)
      Kit.Fill(f.rise, "good")
      Kit.Fill(f.fall, "bad")
      f.rise:SetWidth(math.max(1, r))
      f.fall:SetWidth(math.max(1, w - r))
    end
  end,
  size = function()
    return 200, 66
  end,
})

-- ------------------------------------------------------------------------------------------------ action list

local ROW_H, PILL_W = 46, 66

local function newRow(list, ctx)
  local r = CreateFrame("Button", nil, list.body)
  r:SetHeight(ROW_H)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints()
  r.edge = r:CreateTexture(nil, "ARTWORK")
  r.edge:SetPoint("TOPLEFT")
  r.edge:SetPoint("BOTTOMLEFT")
  r.edge:SetWidth(2)
  r.rule = Kit.Line(r, "TOP", "lineSoft")
  r.pill = CreateFrame("Frame", nil, r, "BackdropTemplate")
  r.pill:SetSize(PILL_W, 18)
  r.pill:SetPoint("LEFT", 12, 0)
  Kit.Box(r.pill, "control", false)
  r.pill.text = Kit.Text(r.pill, { size = 9, justify = "CENTER" })
  r.pill.text:SetPoint("CENTER", 0, 0)
  r.button = Kit.Button(r)
  r.button:SetHeight(24)
  r.button:SetPoint("RIGHT", -12, 0)
  r.button:SetScript("OnClick", function(self)
    if self.variant ~= "disabled" and r.data and r.data.action then
      ctx:Dispatch(r.data.action, { key = r.data.key })
    end
  end)
  r.value = Kit.Text(r, { size = 12, justify = "RIGHT" })
  r.text = CreateFrame("Frame", nil, r)
  r.text:SetPoint("LEFT", r.pill, "RIGHT", 10, 0)
  r.title = Kit.Text(r.text, { size = 12 })
  r.title:SetPoint("TOPLEFT", 0, -6)
  r.title:SetPoint("RIGHT", 0, 0)
  r.sub = Kit.Text(r.text, { size = 11, color = "dim" })
  r.sub:SetPoint("BOTTOMLEFT", 0, 7)
  r.sub:SetPoint("RIGHT", 0, 0)
  W.EnableLinks(r.text)
  return r
end

local function drawRow(r, d)
  r.data = d
  local tone = d.tone
  r.pill.text:SetText(d.pill or "")
  Kit.SetColor(r.pill.text, tone or "soft")
  local sel = d.selected and true or false
  local row = Kit.Row()
  r.sel:SetColorTexture(row[1], row[2], row[3], sel and row[4] or 0)
  Kit.Fill(r.edge, Kit.Accent())
  r.edge:SetShown(sel)
  r.title:SetText(Kit.Parts(d.title))
  r.sub:SetText(Kit.Parts(d.sub))
  r.sub:SetShown(d.sub ~= nil)
  r.title:ClearAllPoints()
  if d.sub ~= nil then
    r.title:SetPoint("TOPLEFT", 0, -7)
  else
    r.title:SetPoint("LEFT", 0, 0)
  end
  r.title:SetPoint("RIGHT", 0, 0)
  local right = r
  r.button:SetShown(d.button ~= nil)
  if d.button then
    r.button.label:SetText(d.button)
    r.button.variant = d.off and "disabled" or d.primary and "primary" or "normal"
    r.button:GetScript("OnLeave")(r.button)
    r.button:SetWidth(math.ceil(r.button.label:GetStringWidth() or 0) + 20)
    right = r.button
  end
  r.value:SetText(d.value and Kit.Color(d.valueTone or "text", d.value) or "")
  r.value:ClearAllPoints()
  r.value:SetPoint("RIGHT", right, right == r and "RIGHT" or "LEFT", right == r and -12 or -10, 0)
  r.text:ClearAllPoints()
  r.text:SetPoint("TOPLEFT", r.pill, "TOPRIGHT", 10, 14)
  r.text:SetPoint("BOTTOM", r, "BOTTOM", 0, 0)
  if d.value or right ~= r then
    r.text:SetPoint("RIGHT", d.value and r.value or right, "LEFT", -10, 0)
  else
    r.text:SetPoint("RIGHT", r, "RIGHT", -12, 0) -- nothing on the right: the text runs to the row's edge
  end
end

-- only whole rows: those past the list's height are hidden, not drawn over what is under it
local function fitRows(f)
  local h = f.body:GetHeight() or 0
  for i = 1, f.shown or 0 do
    f.rows[i]:SetShown(h <= 0 or i * ROW_H <= h + 1)
  end
end

Layout.Register("actionlist", {
  props = { title = "string?", bare = "boolean?", rows = "table" },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f.title = Kit.Text(f, { font = "display", size = 15, color = "heading" })
    f.title:SetPoint("TOPLEFT", 12, -9)
    f.rule = Kit.Line(f, "TOP", "line")
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetScript("OnSizeChanged", function()
      fitRows(f)
    end)
    f.rows = {}
    f.ctx = ctx
    return f
  end,
  update = function(f, p, ctx)
    local framed = not p.bare
    Kit.Box(f, framed and "panel" or { 0, 0, 0, 0 }, framed and "line" or false)
    local hasTitle = framed and p.title ~= nil
    f.title:SetShown(hasTitle)
    f.title:SetText(p.title or "")
    f.rule:ClearAllPoints()
    f.rule:SetPoint("TOPLEFT", 0, -32)
    f.rule:SetPoint("TOPRIGHT", 0, -32)
    f.rule:SetShown(hasTitle)
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", 0, hasTitle and -32 or 0)
    f.body:SetPoint("BOTTOMRIGHT")
    for i, d in ipairs(p.rows) do
      local r = f.rows[i] or newRow(f, ctx)
      f.rows[i] = r
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
      r:SetPoint("RIGHT")
      r.rule:SetShown(i > 1)
      drawRow(r, d)
      r:Show()
    end
    for i = #p.rows + 1, #f.rows do
      f.rows[i]:Hide()
    end
    f.shown = #p.rows
    fitRows(f)
  end,
  size = function(_, p)
    return 300, (p.bare and 0 or 32) + #(p.rows or {}) * ROW_H
  end,
})

-- ------------------------------------------------------------------------------------------------ sidebar

-- sidebar { entries = { { key?, label, count?, heading?, link?, selected?, tone? }, ... }, action? }
-- A heading is a small dim caption; a link entry is blue ("+ New list"); the picked entry is lit with the accent.
-- A click dispatches the action with { key = entry.key }.
local SIDE_ROW, SIDE_HEAD = 22, 24

Layout.Register("sidebar", {
  props = { entries = "table", action = "string?" },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Kit.Box(f, "panel", "line")
    f.rows = {}
    f.ctx = ctx
    -- longer than its box (a category opened into its subcategories): it clips to the box and the mouse wheel
    -- scrolls it, a thin thumb on the right showing where you are
    if f.SetClipsChildren then
      f:SetClipsChildren(true)
    end
    f.offset = 0
    f.thumb = f:CreateTexture(nil, "OVERLAY")
    f.thumb:SetWidth(3)
    f.thumb:Hide()
    if f.EnableMouseWheel then
      f:EnableMouseWheel(true)
    end
    f:SetScript("OnMouseWheel", function(self, delta)
      self.offset = (self.offset or 0) - delta * SIDE_ROW * 3
      self:Place()
    end)
    f:SetScript("OnSizeChanged", function(self)
      if self.props then
        self:Place()
      end
    end)
    -- the rows at the scroll offset (clamped to what there is to scroll), and the thumb
    function f:Place()
      local visible = (self:GetHeight() or 0) - 12
      local total = (self.natural or 0) - 12
      local most = math.max(0, total - visible)
      self.offset = math.max(0, math.min(most, self.offset or 0))
      for _, b in ipairs(self.rows) do
        if b:IsShown() and b.y then
          b:ClearAllPoints()
          b:SetPoint("TOPLEFT", 4, -(b.y - self.offset))
          b:SetPoint("RIGHT", -4, 0)
        end
      end
      local show = most > 0 and visible > 0
      self.thumb:SetShown(show)
      if show then
        local c = Kit.C("controlLine")
        self.thumb:SetColorTexture(c[1], c[2], c[3], 1)
        local h = math.max(16, visible * visible / total)
        self.thumb:SetHeight(h)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOPRIGHT", -1, -6 - (visible - h) * self.offset / most)
      end
    end
    return f
  end,
  update = function(f, p, ctx)
    local y = 6
    local selectedY
    for i, e in ipairs(p.entries) do
      local b = f.rows[i]
      if not b then
        b = CreateFrame("Button", nil, f)
        b.sel = b:CreateTexture(nil, "BACKGROUND")
        b.sel:SetAllPoints()
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.05)
        b.text = Kit.Text(b, { size = 12 })
        b.text:SetPoint("LEFT", 10, 0)
        b.count = Kit.Text(b, { size = 11, color = "dim", justify = "RIGHT" })
        b.count:SetPoint("RIGHT", -10, 0)
        b.text:SetPoint("RIGHT", b.count, "LEFT", -6, 0)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, button)
          if self.key ~= nil and f.props.action then
            ctx:Dispatch(f.props.action, { key = self.key, button = button })
          end
        end)
        f.rows[i] = b
      end
      b.key = not e.heading and e.key or nil
      local h = e.heading and SIDE_HEAD or SIDE_ROW
      b.y = y
      b:SetHeight(h)
      if e.selected then
        selectedY = y
      end
      y = y + h
      b.text:SetText(e.label or "")
      if e.heading then
        Kit.SetFont(b.text, "ui", 11)
        Kit.SetColor(b.text, "dim")
      else
        Kit.SetFont(b.text, "ui", 12)
        Kit.SetColor(b.text, e.link and "link" or e.tone or (e.selected and "white" or "heading"))
      end
      b.count:SetText(e.count and tostring(e.count) or "")
      local row = Kit.Row()
      b.sel:SetColorTexture(row[1], row[2], row[3], e.selected and row[4] or 0)
      b.hl:SetShown(not e.heading)
      b:EnableMouse(not e.heading)
      b:Show()
    end
    for i = #p.entries + 1, #f.rows do
      f.rows[i]:Hide()
    end
    local first = f.props == nil or f.lastEntries ~= #p.entries
    f.props, f.natural, f.lastEntries = p, y + 6, #p.entries
    -- the picked row in view when the list changes (a category opened): scrolled to, if it's below the box
    local visible = (f:GetHeight() or 0) - 12
    if first and selectedY and visible > 0 and (selectedY - f.offset > visible - SIDE_ROW or selectedY < f.offset) then
      f.offset = selectedY - math.floor(visible / 3)
    end
    f:Place()
  end,
  size = function(f)
    return 190, f.natural or 0
  end,
})
