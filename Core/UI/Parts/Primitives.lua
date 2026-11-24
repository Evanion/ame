-- The small widgets every screen is made of, registered with the layout engine (Core/UI/Layout.lua) and drawn in the
-- redesign's look (Core/UI/Kit.lua). Each is the canvas component of the same name (docs/ux/design boards).
--
--   text      { text, color?, font? "ui"|"display", size?, justify?, wrap? }
--   button    { label, action?, payload?, variant? "normal"|"primary"|"selected"|"disabled", color? }
--   input     { value?, hint?, action?, numeric? }          action gets { text = } on Enter and on focus lost
--   field     { label, value?, hint?, action?, numeric? }   a label over an input
--   check     { label?, checked?, action?, payload? }       action gets { checked = , payload }
--   segmented { options = { {key, label, color?}, ... }, selected?, action? }  action gets { key = }
--   money     { copper?, signed?, size?, bold?, color? }
--   itemlink  { item?, count?, size?, bold?, icon? }        the game's link: tooltip, Shift-click, click opens it
--   keyvalue  { label?, item?, quality-free, count?, copper?, signed?, text?, tone?, note?, noteTone?, valueItem?,
--               action?, payload?, total?, big? }
--   signal    { signal? }      tag { text, kind? }      spacer {}      divider {}
--   card      container: a framed block; { title?, layout? "column"|"row"|"grid"|"fill", gap?, pad?, cols?, widths? }
--   panel     container: a titled region with a rule under its title; same props as card
local _, ns = ...

local Layout, Kit, W = ns.Layout, ns.Kit, ns.Widgets

local function dispatch(ctx, props, extra)
  if props.action and ctx then
    local payload = props.payload
    if extra then
      payload = payload ~= nil and { payload = payload } or {}
      for k, v in pairs(extra) do
        payload[k] = v
      end
    end
    ctx:Dispatch(props.action, payload)
  end
end

local function textWidth(fs)
  return math.ceil(fs:GetStringWidth() or 0)
end

-- ----------------------------------------------------------------------------------------------------- text

Layout.Register("text", {
  props = {
    text = "string",
    color = "string?",
    font = "string?",
    size = "number?",
    justify = "string?",
    wrap = "boolean?",
  },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.fs = Kit.Text(f)
    f.fs:SetAllPoints()
    return f
  end,
  update = function(f, p)
    Kit.SetFont(f.fs, p.font, p.size or (p.font == "display" and 15 or 12))
    Kit.SetColor(f.fs, p.color or (p.font == "display" and "heading" or "text"))
    f.fs:SetJustifyH(p.justify or "LEFT")
    if f.fs.SetJustifyV then
      f.fs:SetJustifyV(p.wrap and "TOP" or "MIDDLE")
    end
    if f.fs.SetWordWrap then
      f.fs:SetWordWrap(p.wrap and true or false)
    end
    f.fs:SetText(p.text)
  end,
  size = function(f, p)
    return textWidth(f.fs) + 2, (p.size or 12) + 6
  end,
})

-- ----------------------------------------------------------------------------------------------------- button

local VARIANT = {
  normal = { fill = "control", line = "controlLine", text = "soft" },
  disabled = { fill = "control", line = "controlLine", text = "dim", alpha = 0.45 },
}

local function look(b)
  local v, hot = b.variant or "normal", b.hot
  if v == "primary" then
    local p = Kit.Primary()
    Kit.Box(b, hot and { p[1] * 1.15, p[2] * 1.15, p[3] * 1.15, 1 } or p, "primaryLine")
    Kit.SetColor(b.label, b.color or "white")
  elseif v == "selected" then
    Kit.Box(b, Kit.Selected(), Kit.Accent())
    Kit.SetColor(b.label, b.color or "white")
  else
    local s = VARIANT[v] or VARIANT.normal
    Kit.Box(b, hot and v ~= "disabled" and "lineSoft" or s.fill, s.line)
    Kit.SetColor(b.label, b.color or s.text)
  end
  if b.icon then -- a button that shows an icon (the title bar's Back and Forward): tinted as its label would be
    local r, g, bl = b.label:GetTextColor()
    b.icon:SetVertexColor(r or 1, g or 1, bl or 1, 1)
  end
  b:SetAlpha(v == "disabled" and 0.45 or 1)
end

function ns.Kit.Button(parent)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b.label = Kit.Text(b, { size = 11, justify = "CENTER" })
  b.label:SetPoint("CENTER", 0, 0)
  b:SetScript("OnEnter", function(self)
    self.hot = true
    look(self)
  end)
  b:SetScript("OnLeave", function(self)
    self.hot = false
    look(self)
  end)
  Kit.OnTheme(function()
    look(b)
  end)
  return b
end

Layout.Register("button", {
  props = { label = "string", action = "string?", payload = "any?", variant = "string?", color = "string?" },
  create = function(parent, ctx)
    local b = Kit.Button(parent)
    b:SetScript("OnClick", function(self)
      if self.variant ~= "disabled" then
        dispatch(ctx, self.props)
      end
    end)
    return b
  end,
  update = function(b, p)
    b.props, b.variant, b.color = p, p.variant or "normal", p.color or false
    b.label:SetText(p.label)
    if b.SetEnabled then
      b:SetEnabled(p.variant ~= "disabled")
    end
    look(b)
  end,
  size = function(b)
    return math.max(textWidth(b.label) + 20, 24), 24
  end,
})

-- ----------------------------------------------------------------------------------------------------- input

local function newInput(parent, ctx)
  local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  Kit.Box(box, "bg", "controlLine")
  Kit.SetFont(box, "ui", 11)
  Kit.SetColor(box, "soft")
  box:SetTextInsets(7, 7, 0, 0)
  box:SetAutoFocus(false)
  box.hintText = Kit.Text(box, { size = 11, color = "dim" })
  box.hintText:SetPoint("LEFT", 7, 0)
  local function send(self)
    if self.props and self.props.action then
      dispatch(ctx, self.props, { text = self:GetText() or "" })
    end
  end
  box:SetScript("OnEnterPressed", function(self)
    send(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEditFocusLost", send)
  box:SetScript("OnTextChanged", function(self)
    self.hintText:SetShown((self:GetText() or "") == "")
  end)
  box:SetScript("OnEditFocusGained", function(self)
    Kit.Box(self, "bg", Kit.Accent())
  end)
  box:HookScript("OnEditFocusLost", function(self)
    Kit.Box(self, "bg", "controlLine")
  end)
  return box
end

local function setInput(box, p)
  box.props = p
  if not (box.HasFocus and box:HasFocus()) then
    box:SetText(p.value or "")
  end
  if box.SetNumeric then
    box:SetNumeric(p.numeric and true or false)
  end
  box.hintText:SetText(p.hint or "")
  box.hintText:SetShown((box:GetText() or "") == "")
end

Layout.Register("input", {
  props = { value = "string?", hint = "string?", action = "string?", payload = "any?", numeric = "boolean?" },
  create = newInput,
  update = setInput,
  size = function()
    return 120, 24
  end,
})

Layout.Register("field", {
  props = {
    label = "string",
    value = "string?",
    hint = "string?",
    action = "string?",
    payload = "any?",
    numeric = "boolean?",
  },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent)
    f.label = Kit.Text(f, { size = 11, color = "dim" })
    f.label:SetPoint("TOPLEFT", 0, 0)
    f.box = newInput(f, ctx)
    f.box:SetPoint("TOPLEFT", 0, -15)
    f.box:SetPoint("BOTTOMRIGHT", 0, 0)
    return f
  end,
  update = function(f, p)
    f.label:SetText(p.label)
    setInput(f.box, p)
  end,
  size = function()
    return 90, 40
  end,
})

-- ----------------------------------------------------------------------------------------------------- check

Layout.Register("check", {
  props = { label = "string?", checked = "boolean?", action = "string?", payload = "any?" },
  create = function(parent, ctx)
    local b = CreateFrame("Button", nil, parent)
    b.box = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.box:SetSize(14, 14)
    b.box:SetPoint("LEFT", 0, 0)
    b.mark = b.box:CreateTexture(nil, "OVERLAY")
    b.mark:SetPoint("TOPLEFT", 3, -3)
    b.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    b.label = Kit.Text(b, { size = 11, color = "soft" })
    b.label:SetPoint("LEFT", b.box, "RIGHT", 6, 0)
    b:SetScript("OnClick", function(self)
      self.checked = not self.checked
      self:Draw()
      dispatch(ctx, self.props, { checked = self.checked })
    end)
    function b:Draw()
      Kit.Box(self.box, "bg", self.checked and Kit.Accent() or "controlLine")
      Kit.Fill(self.mark, Kit.Accent())
      self.mark:SetShown(self.checked)
    end
    return b
  end,
  update = function(b, p)
    b.props, b.checked = p, p.checked and true or false
    b.label:SetText(p.label or "")
    b:Draw()
  end,
  size = function(b)
    return 20 + textWidth(b.label), 18
  end,
})

-- ----------------------------------------------------------------------------------------------------- segmented

Layout.Register("segmented", {
  props = { options = "table", selected = "string?", action = "string?", payload = "any?", gap = "number?" },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.buttons = {}
    return f
  end,
  update = function(f, p, ctx)
    local gap, x = p.gap or 2, 0
    for i, opt in ipairs(p.options) do
      local b = f.buttons[i]
      if not b then
        b = Kit.Button(f)
        b:SetScript("OnClick", function(self)
          dispatch(ctx, f.props, { key = self.key })
        end)
        f.buttons[i] = b
      end
      b.key = opt[1]
      b.label:SetText(opt[2])
      b.variant = opt[1] == p.selected and "selected" or "normal"
      b.color = opt[3] or false
      look(b)
      local w = math.max(textWidth(b.label) + 18, 28)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", x, 0)
      b:SetSize(w, 24)
      b:Show()
      x = x + w + gap
    end
    for i = #p.options + 1, #f.buttons do
      f.buttons[i]:Hide()
    end
    f.props, f.natural = p, math.max(0, x - gap)
  end,
  size = function(f)
    return f.natural or 0, 24
  end,
})

-- ----------------------------------------------------------------------------------------------------- money

Layout.Register("money", {
  props = {
    copper = "number?",
    signed = "boolean?",
    size = "number?",
    bold = "boolean?",
    justify = "string?",
  },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.fs = Kit.Text(f, { justify = "RIGHT" })
    f.fs:SetAllPoints()
    return f
  end,
  update = function(f, p)
    Kit.SetFont(f.fs, "ui", (p.size or 12) + (p.bold and 1 or 0))
    f.fs:SetJustifyH(p.justify or "RIGHT")
    local text
    if not p.copper then
      text = Kit.Color("dim", "—")
    elseif p.signed then
      text = W.SignedMoney(p.copper)
    else
      text = W.Money(p.copper, true)
    end
    f.fs:SetText(text)
  end,
  size = function(f, p)
    return textWidth(f.fs) + 2, (p.size or 12) + 6
  end,
})

-- ----------------------------------------------------------------------------------------------------- item link

Layout.Register("itemlink", {
  props = { item = "any?", count = "any?", size = "number?", bold = "boolean?", icon = "number?" },
  create = function(parent)
    return W.ItemLink(parent, { kit = true, icon = 14 })
  end,
  update = function(f, p)
    if f.SetFont then
      f:SetFont(p.size or 12, p.bold)
    end
    f:SetItem(p.item or false, p.count)
  end,
  size = function(f)
    local w = (f.nameX or 18) + textWidth(f.name) + (f.count and f.count:GetText() ~= "" and textWidth(f.count) + 6 or 0)
    return w + 2, 18
  end,
})

-- ----------------------------------------------------------------------------------------------------- key / value

Layout.Register("keyvalue", {
  props = {
    label = "string?",
    item = "any?",
    count = "any?",
    copper = "number?",
    signed = "boolean?",
    text = "string?",
    tone = "string?",
    note = "string?",
    noteTone = "string?",
    valueItem = "any?",
    action = "string?",
    payload = "any?",
    total = "boolean?",
    big = "boolean?",
  },
  create = function(parent, ctx)
    local f = CreateFrame("Button", nil, parent)
    f.link = W.ItemLink(f, { kit = true, icon = 12 })
    f.link:SetPoint("LEFT", 0, 0)
    f.label = Kit.Text(f, { size = 12, color = "dim" })
    f.value = Kit.Text(f, { size = 12, justify = "RIGHT" })
    f.value:SetPoint("RIGHT", 0, 0)
    f.vlink = W.ItemLink(f, { kit = true, icon = 12 })
    f.vlink:SetPoint("RIGHT", 0, 0)
    f:SetScript("OnClick", function(self)
      dispatch(ctx, self.props)
    end)
    return f
  end,
  update = function(f, p)
    f.props = p
    local font = (p.total or p.big) and 13 or 12
    f.link:SetShown(p.item ~= nil)
    if p.item ~= nil then
      f.link:SetItem(p.item, p.count)
    end
    f.label:ClearAllPoints()
    f.label:SetPoint("LEFT", p.item ~= nil and f.link or f, p.item ~= nil and "RIGHT" or "LEFT", p.item and 4 or 0, 0)
    Kit.SetFont(f.label, "ui", font)
    Kit.SetColor(f.label, p.total and "text" or "dim")
    f.label:SetText(p.label or "")
    local value
    if p.copper then
      value = p.signed and W.SignedMoney(p.copper) or W.Money(p.copper, true)
    elseif p.text then
      value = p.action and Kit.Color("link", p.text) or (p.tone and Kit.Color(p.tone, p.text) or p.text)
    end
    if p.note then
      value = (value and value .. "  " or "") .. Kit.Color(p.noteTone or "dim", p.note)
    end
    Kit.SetFont(f.value, "ui", p.big and 15 or font)
    f.value:SetText(value or "")
    f.vlink:SetShown(p.valueItem ~= nil and not p.copper and not p.text)
    if p.valueItem ~= nil then
      f.vlink:SetItem(p.valueItem)
    end
  end,
  size = function(f, p)
    return 200, p.big and 22 or 18
  end,
})

-- ----------------------------------------------------------------------------------------------------- badges

Layout.Register("signal", {
  props = { signal = "string?" },
  create = function(parent)
    return W.SignalBadge(parent)
  end,
  update = function(f, p)
    f:SetSignal(p.signal)
  end,
  size = function(f)
    return f:GetWidth(), 14
  end,
})

Layout.Register("tag", {
  props = { text = "string", kind = "string?" },
  create = function(parent)
    return W.Tag(parent)
  end,
  update = function(f, p)
    f:Set(p.text, p.kind)
  end,
  size = function(f)
    return f:GetWidth(), 16
  end,
})

Layout.Register("spacer", {
  props = {},
  create = function(parent)
    return CreateFrame("Frame", nil, parent)
  end,
  update = function() end,
  size = function()
    return 0, 0
  end,
})

Layout.Register("divider", {
  props = { color = "string?" },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.line = f:CreateTexture(nil, "BORDER")
    f.line:SetPoint("LEFT")
    f.line:SetPoint("RIGHT")
    f.line:SetHeight(1)
    return f
  end,
  update = function(f, p)
    Kit.Fill(f.line, p.color or "line")
  end,
  size = function()
    return 1, 1
  end,
})

-- ----------------------------------------------------------------------------------------------------- containers

local BOX_PROPS = {
  title = "string?",
  layout = "string?",
  gap = "number?",
  pad = "number?",
  cols = "number?",
  widths = "table?",
  rowH = "number?",
  align = "string?",
  note = "string?",
}

local function box(kind)
  local titleH = kind == "panel" and 32 or 22
  return {
    container = true,
    props = BOX_PROPS,
    create = function(parent)
      local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
      Kit.Box(f, "panel", "line")
      f.title = Kit.Text(f, { font = "display", size = kind == "panel" and 15 or 14, color = "heading" })
      f.note = Kit.Text(f, { size = 11, color = "dim" })
      f.rule = Kit.Line(f, "TOP", "line")
      f.content = CreateFrame("Frame", nil, f)
      if kind == "card" then
        f.top = Kit.Line(f, "TOP", "frameLit")
      end
      return f
    end,
    update = function(f, p)
      local pad = p.pad or (kind == "panel" and 12 or 10)
      local hasTitle = p.title and p.title ~= ""
      f.title:SetShown(hasTitle)
      f.title:SetText(p.title or "")
      f.title:ClearAllPoints()
      f.title:SetPoint("TOPLEFT", pad, kind == "panel" and -9 or -8)
      f.note:SetShown(hasTitle and p.note ~= nil)
      f.note:SetText(p.note or "")
      f.note:ClearAllPoints()
      f.note:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
      f.rule:ClearAllPoints()
      f.rule:SetPoint("TOPLEFT", 0, -titleH)
      f.rule:SetPoint("TOPRIGHT", 0, -titleH)
      f.rule:SetShown(hasTitle and kind == "panel")
      local top = hasTitle and (titleH + (kind == "panel" and 0 or 2)) or pad
      f.content:ClearAllPoints()
      f.content:SetPoint("TOPLEFT", kind == "panel" and 0 or pad, -top)
      f.content:SetPoint("BOTTOMRIGHT", kind == "panel" and 0 or -pad, kind == "panel" and 0 or pad)
      f.inset = { kind == "panel" and 0 or pad, kind == "panel" and 0 or pad, top, kind == "panel" and 0 or pad }
    end,
    content = function(f)
      return f.content
    end,
    inset = function(f)
      return unpack(f.inset)
    end,
    arrange = function(frame, kids, w, h, props)
      local place = Layout.ARRANGE[props.layout or "column"] or Layout.ARRANGE.column
      place(frame, kids, w, h, { gap = props.gap or 4, cols = props.cols, widths = props.widths, rowH = props.rowH, align = props.align })
    end,
  }
end

Layout.Register("card", box("card"))
Layout.Register("panel", box("panel"))
