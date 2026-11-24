-- Widgets for the screens outside the main tabs' data (Settings, the Guide, the bell): the canvas's SettingsCard, a
-- scrolling column, the Guide's article and the bell's list.
--
--   settingscard { title?, rows, dense?, action?, width? }    a Settings section: a gold heading, then rows in order
--     { check = label, key, checked?, indent?, off? }          a check; dispatches action {key, value = checked}
--     { field = label, key, value?, options = { {value, label}, ... }, note? }
--                                                             a label with its dropdown on the right; picking one
--                                                             dispatches action {key, value}
--     { field = label, button = label, action, key? }         a label with a plain button (action {key})
--     { text = "..." }                                        a dim explanatory paragraph
--     { input = hint, key, value?, label?, suffix?, numeric?, width?, button?, action? }
--                                                             a text box (a label left of it when given); Enter or
--                                                             the button dispatches action {key, value = text}
--     { name, note?, status?, key?, buttons = { label | {label, action}, ... } }   a player row
--     { buttons = { { label, action, key?, off? }, ... } }    a row of buttons
--     The default action is "setting". off: faded and not clickable (a follow-on option while its switch is off).
--   scrollcolumn container { gap?, pad? }   children one under another at their natural heights; the mouse wheel
--                                           scrolls when they are taller than the box
--   guidearticle { key?, crumb?, title, blocks, action? }     the Guide's article, scrolling when long
--     blocks: { p = text } | { h = text } | { example = name } (Help.EXAMPLES, drawn live) |
--             { buttons = { { label, action, payload? }, ... } } | { links = { { label, key }, ... } }
--     Slash commands in paragraphs are links that put the command in the chat box; an article link dispatches
--     action {key}; item names are links.
--   noticelist   the actionlist (Composites) whose rows are clickable: rowAction gets {key = row.key}
local _, ns = ...
local L = ns.L

local Layout, Kit, W = ns.Layout, ns.Kit, ns.Widgets

local function textWidth(fs)
  return math.ceil(fs:GetStringWidth() or 0)
end

local function textHeight(fs)
  local h = fs.GetStringHeight and fs:GetStringHeight() or 0
  return math.ceil(type(h) == "number" and h or 0)
end

-- ------------------------------------------------------------------------------------------------ the dropdown menu

-- One menu for every dropdown: a list under its button, the current value lit; a click outside or Escape closes it.
local Menu = { ROW = 20, MAX = 14 }
ns.SettingsMenu = Menu

function Menu.Create()
  if Menu.frame then
    return Menu.frame
  end
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  catcher:SetScript("OnClick", function()
    Menu.Close()
  end)
  catcher:Hide()
  local f = CreateFrame("Frame", "AMESettingsMenu", UIParent, "BackdropTemplate")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetFrameLevel((catcher:GetFrameLevel() or 1) + 5)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  Kit.Box(f, "bg", "controlLine")
  f.rows, f.offset = {}, 0
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, #(self.options or {}) - Menu.MAX)
    self.offset = math.max(0, math.min(max, self.offset - delta * 3))
    Menu.Draw()
  end)
  f:SetScript("OnHide", function()
    catcher:Hide()
    Menu.owner = nil
  end)
  f:Hide()
  table.insert(_G.UISpecialFrames or {}, "AMESettingsMenu")
  Menu.frame, Menu.catcher = f, catcher
  return f
end

function Menu.Draw()
  local f = Menu.frame
  local options, n = f.options or {}, math.min(#(f.options or {}), Menu.MAX)
  local width = f.minWidth or 120
  for i = 1, n do
    local b = f.rows[i]
    if not b then
      b = CreateFrame("Button", nil, f)
      b:SetHeight(Menu.ROW)
      b.sel = b:CreateTexture(nil, "BACKGROUND")
      b.sel:SetAllPoints()
      b.hl = b:CreateTexture(nil, "HIGHLIGHT")
      b.hl:SetAllPoints()
      b.hl:SetColorTexture(1, 1, 1, 0.06)
      b.text = Kit.Text(b, { size = 11, color = "soft" })
      b.text:SetPoint("LEFT", 8, 0)
      b:SetScript("OnClick", function(self)
        local pick = Menu.onPick
        local opt = self.option
        Menu.Close()
        if pick and opt then
          pick(opt.value)
        end
      end)
      f.rows[i] = b
    end
    local opt = options[i + f.offset]
    b.option = opt
    b.text:SetText(opt and opt.label or "")
    local on = opt and opt.value == f.value
    local row = Kit.Row()
    b.sel:SetColorTexture(row[1], row[2], row[3], on and row[4] or 0)
    Kit.SetColor(b.text, on and "white" or "soft")
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 1, -1 - (i - 1) * Menu.ROW)
    b:SetPoint("RIGHT", -1, 0)
    b:Show()
    width = math.max(width, textWidth(b.text) + 24)
  end
  for i = n + 1, #f.rows do
    f.rows[i]:Hide()
  end
  f:SetSize(width, n * Menu.ROW + 2)
end

-- options: { { value, label }, ... }; onPick(value)
function Menu.Open(owner, options, value, onPick)
  local f = Menu.Create()
  if Menu.owner == owner and f:IsShown() then
    return Menu.Close() -- the button again: closed
  end
  Menu.owner, Menu.onPick = owner, onPick
  f.options, f.value, f.offset = options, value, 0
  f.minWidth = owner.GetWidth and owner:GetWidth() or 120
  for i, o in ipairs(options) do
    if o.value == value and i > Menu.MAX then
      f.offset = math.min(i - 1, #options - Menu.MAX)
    end
  end
  Menu.Draw()
  f:ClearAllPoints()
  f:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
  Menu.catcher:Show()
  f:Show()
end

function Menu.Close()
  if Menu.frame then
    Menu.frame:Hide()
  end
end

-- the label of a value among options
local function labelOf(options, value)
  for _, o in ipairs(options or {}) do
    if o.value == value then
      return o.label
    end
  end
  return options and options[1] and options[1].label or ""
end
Menu.LabelOf = labelOf

-- ------------------------------------------------------------------------------------------------ settings card

local H = { check = 18, field = 24, input = 24, person = 26, buttons = 24 }

local function kindOf(r)
  if r.check ~= nil then
    return "check"
  elseif r.field ~= nil then
    return "field"
  elseif r.text ~= nil then
    return "text"
  elseif r.input ~= nil then
    return "input"
  elseif r.name ~= nil then
    return "person"
  elseif r.buttons ~= nil then
    return "buttons"
  end
end

local function send(card, r, extra)
  local ctx, p = card.ctx, card.props
  local action = r.action or (p and p.action) or "setting"
  local payload = { key = r.key }
  for k, v in pairs(extra or {}) do
    payload[k] = v
  end
  ctx:Dispatch(action, payload)
end

-- a dropdown button: the value's label and a small arrow (a texture: the fonts have no arrow glyph)
local function dropButton(parent)
  local b = Kit.Button(parent)
  b:SetHeight(24)
  b.arrow = b:CreateTexture(nil, "OVERLAY")
  b.arrow:SetSize(10, 10)
  b.arrow:SetPoint("RIGHT", -7, 0)
  b.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  local c = Kit.C("dim")
  if b.arrow.SetVertexColor then
    b.arrow:SetVertexColor(c[1], c[2], c[3], 1)
  end
  b.label:ClearAllPoints()
  b.label:SetPoint("RIGHT", b.arrow, "LEFT", -5, 0)
  return b
end

local function checkBox(row)
  local b = CreateFrame("Button", nil, row)
  b.box = CreateFrame("Frame", nil, b, "BackdropTemplate")
  b.box:SetSize(14, 14)
  b.box:SetPoint("LEFT", 0, 0)
  b.mark = b.box:CreateTexture(nil, "OVERLAY")
  b.mark:SetPoint("TOPLEFT", 3, -3)
  b.mark:SetPoint("BOTTOMRIGHT", -3, 3)
  b.label = Kit.Text(b, { size = 12, color = "soft" })
  b.label:SetPoint("LEFT", b.box, "RIGHT", 6, 0)
  b.label:SetPoint("RIGHT", 0, 0)
  function b:Draw()
    Kit.Box(self.box, "bg", self.checked and Kit.Accent() or "controlLine")
    Kit.Fill(self.mark, Kit.Accent())
    self.mark:SetShown(self.checked)
  end
  return b
end

local function newRow(card, kind)
  local row = CreateFrame("Frame", nil, card)
  row.kind = kind
  if kind == "check" then
    row.check = checkBox(row)
    row.check:SetAllPoints()
    row.check:SetScript("OnClick", function(self)
      local r = row.data
      if not r or r.off then
        return
      end
      self.checked = not self.checked
      self:Draw()
      send(card, r, { value = self.checked })
    end)
  elseif kind == "field" or kind == "input" or kind == "person" then
    row.label = Kit.Text(row, { size = 12, color = "soft" })
    row.label:SetPoint("LEFT", 0, 0)
    row.note = Kit.Text(row, { size = 11, color = "dim" })
    row.note:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
    if kind == "field" then
      row.button = dropButton(row)
      row.button:SetPoint("RIGHT", 0, 0)
      row.button:SetScript("OnClick", function(self)
        local r = row.data
        if not r or r.off then
          return
        end
        if r.options then
          Menu.Open(self, r.options, r.value, function(value)
            send(card, r, { value = value })
          end)
        else
          send(card, r)
        end
      end)
    elseif kind == "input" then
      local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
      Kit.Box(box, "bg", "controlLine")
      Kit.SetFont(box, "ui", 11)
      Kit.SetColor(box, "soft")
      box:SetTextInsets(7, 7, 0, 0)
      box:SetAutoFocus(false)
      box:SetHeight(24)
      box.hint = Kit.Text(box, { size = 11, color = "dim" })
      box.hint:SetPoint("LEFT", 7, 0)
      local function submit(self)
        local r = row.data
        if r and not r.button then
          send(card, r, { value = self:GetText() or "" })
        end
      end
      box:SetScript("OnEnterPressed", function(self)
        submit(self)
        self:ClearFocus()
      end)
      box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
      end)
      box:SetScript("OnEditFocusLost", submit)
      box:SetScript("OnTextChanged", function(self)
        self.hint:SetShown((self:GetText() or "") == "")
      end)
      row.box = box
      row.suffix = Kit.Text(row, { size = 12, color = "soft" })
      row.go = Kit.Button(row)
      row.go:SetHeight(24)
      row.go:SetScript("OnClick", function()
        local r = row.data
        if r then
          send(card, r, { value = row.box:GetText() or "" })
          row.box:SetText("")
        end
      end)
    else
      row.status = Kit.Text(row, { size = 11, color = "dim", justify = "RIGHT" })
      row.rule = Kit.Line(row, "BOTTOM", "control")
      row.buttons = {}
    end
  elseif kind == "text" then
    row.text = Kit.Text(row, { size = 11, color = "dim", wrap = true })
    row.text:SetPoint("TOPLEFT", 0, 0)
    row.text:SetPoint("RIGHT", 0, 0)
    if row.text.SetJustifyV then
      row.text:SetJustifyV("TOP")
    end
  elseif kind == "buttons" then
    row.buttons = {}
  end
  return row
end

-- a row of buttons from the right (person rows) or the left (button rows)
local function drawButtons(card, row, list, fromRight, anchor)
  local prev
  for i, spec in ipairs(list or {}) do
    local b = row.buttons[i]
    if not b then
      b = Kit.Button(row)
      b:SetHeight(fromRight and 22 or 24)
      b:SetScript("OnClick", function(self)
        if self.variant ~= "disabled" and self.spec then
          local r = row.data
          send(card, { action = self.spec.action or r.action, key = self.spec.key or r.key }, { button = self.index })
        end
      end)
      row.buttons[i] = b
    end
    spec = type(spec) == "table" and spec or { label = tostring(spec) }
    b.spec, b.index = spec, i
    b.label:SetText(spec.label or spec[1] or "")
    b.variant = spec.off and "disabled" or spec.primary and "primary" or "normal"
    b:GetScript("OnLeave")(b)
    b:SetWidth(math.max(textWidth(b.label) + 20, 24))
    b:ClearAllPoints()
    if fromRight then
      b:SetPoint("RIGHT", prev or anchor, prev and "LEFT" or "RIGHT", prev and -4 or 0, 0)
    else
      b:SetPoint("LEFT", prev or row, prev and "RIGHT" or "LEFT", prev and 6 or 0, 0)
    end
    b:Show()
    prev = b
  end
  for i = #(list or {}) + 1, #row.buttons do
    row.buttons[i]:Hide()
  end
  return prev
end

local function drawRow(card, row, r, width)
  row.data = r
  local indent = r.indent and 20 or 0
  local h = H[row.kind] or 18
  row:SetAlpha(r.off and 0.45 or 1)
  if row.kind == "check" then
    row.check.checked = r.checked and true or false
    row.check.label:SetText(r.check)
    row.check:Draw()
  elseif row.kind == "field" then
    row.label:SetText(r.field)
    row.note:SetText(r.note or "")
    local label = r.options and labelOf(r.options, r.value) or r.button or ""
    row.button.label:SetText(label)
    row.button:SetWidth(math.max(90, textWidth(row.button.label) + 34))
    row.button.arrow:SetShown(r.options ~= nil)
  elseif row.kind == "input" then
    row.label:SetText(r.label or "")
    row.note:SetText("")
    local box = row.box
    if not (box.HasFocus and box:HasFocus()) then
      box:SetText(r.value ~= nil and tostring(r.value) or "")
    end
    box.hint:SetText(r.input or "")
    box.hint:SetShown((box:GetText() or "") == "")
    if box.SetNumeric then
      box:SetNumeric(r.numeric and true or false)
    end
    row.suffix:SetText(r.suffix or "")
    row.suffix:ClearAllPoints()
    row.suffix:SetPoint("RIGHT", 0, 0)
    row.go:SetShown(r.button ~= nil)
    row.go.label:SetText(r.button or "")
    row.go:SetWidth(math.max(textWidth(row.go.label) + 20, 24))
    row.go:ClearAllPoints()
    row.go:SetPoint("RIGHT", 0, 0)
    box:ClearAllPoints()
    if r.label then -- a short box on the right, like a dropdown
      box:SetWidth(r.width or 60)
      box:SetPoint("RIGHT", r.suffix and row.suffix or row, r.suffix and "LEFT" or "RIGHT", r.suffix and -4 or 0, 0)
    else
      box:SetPoint("LEFT", 0, 0)
      box:SetPoint("RIGHT", r.button and row.go or row, r.button and "LEFT" or "RIGHT", r.button and -6 or 0, 0)
    end
  elseif row.kind == "person" then
    row.label:SetText(r.name)
    row.note:SetText(r.note or "")
    local first = drawButtons(card, row, r.buttons, true, row)
    row.status:SetText(r.status or "")
    row.status:ClearAllPoints()
    row.status:SetPoint("RIGHT", first and row.buttons[1] or row, first and "LEFT" or "RIGHT", first and -6 or 0, 0)
  elseif row.kind == "text" then
    row.text:SetWidth(math.max(1, width - indent))
    row.text:SetText(r.text)
    h = math.max(14, textHeight(row.text))
  elseif row.kind == "buttons" then
    drawButtons(card, row, r.buttons, false)
  end
  return h, indent
end

local function layoutCard(f)
  local p = f.props
  if not p then
    return
  end
  local width = (f:GetWidth() or 0) > 0 and f:GetWidth() or p.width or 560
  local padX, padY, gap = 12, p.dense and 9 or 10, p.dense and 5 or 7
  local inner = width - 2 * padX
  local y = padY
  f.title:SetShown(p.title ~= nil)
  if p.title then
    f.title:SetText(p.title)
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", padX, -y)
    y = y + 16 + gap
  end
  local used = {}
  for i, r in ipairs(p.rows) do
    local kind = kindOf(r) or "text"
    f.pool[kind] = f.pool[kind] or {}
    used[kind] = (used[kind] or 0) + 1
    local row = f.pool[kind][used[kind]]
    if not row then
      row = newRow(f, kind)
      f.pool[kind][used[kind]] = row
    end
    local h, indent = drawRow(f, row, r, inner)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", padX + indent, -y)
    row:SetPoint("RIGHT", f, "RIGHT", -padX, 0)
    row:SetHeight(h)
    row:Show()
    y = y + h + (i < #p.rows and gap or 0)
  end
  for kind, rows in pairs(f.pool) do
    for i = (used[kind] or 0) + 1, #rows do
      rows[i]:Hide()
    end
  end
  f.natural = y + padY
end

Layout.Register("settingscard", {
  props = { title = "string?", rows = "table", dense = "boolean?", action = "string?", width = "number?" },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Kit.Box(f, "panel", "line")
    f.title = Kit.Text(f, { size = 13, color = "heading" })
    f.pool, f.ctx = {}, ctx
    f:SetScript("OnSizeChanged", function(self, w)
      if self.props and w and w > 0 and w ~= self.laidW then
        self.laidW = w
        layoutCard(self)
      end
    end)
    return f
  end,
  update = function(f, p, ctx)
    f.props, f.ctx = p, ctx
    layoutCard(f)
  end,
  size = function(f, p)
    return p.width or 560, f.natural or 0
  end,
})

-- ------------------------------------------------------------------------------------------------ scrolling column

local function scrollTo(f, y)
  local view = f:GetHeight() or 0
  local max = math.max(0, (f.contentH or 0) - view)
  y = math.max(0, math.min(max, y or 0))
  f.y = y
  if f.SetVerticalScroll then
    f:SetVerticalScroll(y)
  end
  f.bar:SetShown(max > 0)
  if max > 0 and view > 0 then
    local h = math.max(20, view * view / (view + max))
    f.bar:SetHeight(h)
    f.bar:ClearAllPoints()
    f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(view - h) * y / max)
  end
end
ns.SettingsScrollTo = scrollTo

Layout.Register("scrollcolumn", {
  container = true,
  props = { gap = "number?", pad = "number?" },
  create = function(parent)
    local f = CreateFrame("ScrollFrame", nil, parent)
    f.child = CreateFrame("Frame", nil, f)
    f.child:SetSize(1, 1)
    if f.SetScrollChild then
      f:SetScrollChild(f.child)
    end
    f.bar = f:CreateTexture(nil, "OVERLAY")
    f.bar:SetColorTexture(1, 1, 1, 0.25)
    f.bar:SetWidth(4)
    f.bar:Hide()
    f.y = 0
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
      scrollTo(self, (self.y or 0) - delta * 40)
    end)
    return f
  end,
  update = function() end,
  content = function(f)
    return f.child
  end,
  arrange = function(child, kids, w, _, props)
    local pad, gap = props.pad or 0, props.gap or 10
    local y = pad
    local inner = w - 2 * pad - 8 -- room for the bar
    for i, kid in ipairs(kids) do
      local meta = kid.item.meta or {}
      local kh = Layout.Natural(kid, "h")
      Layout.Place(kid, child, pad, y, math.min(meta.w or inner, inner), kh)
      y = y + kh + (i < #kids and gap or 0)
    end
    child:SetSize(math.max(1, w - 8), math.max(1, y + pad))
    local f = child:GetParent()
    if f and f.bar then
      f.contentH = y + pad
      scrollTo(f, f.y)
    end
  end,
})

-- ------------------------------------------------------------------------------------------------ guide article

local ARTICLE_W = 640 -- the longest comfortable line

local function articleLayout(f)
  local p = f.props
  if not p then
    return
  end
  local page = f.page
  local w = math.min(ARTICLE_W, math.max(200, ((f:GetWidth() or 0) > 0 and f:GetWidth() or ARTICLE_W + 36) - 36))
  page:SetWidth(w + 36)
  local x, y = 18, 14
  local used = { p = 0, h = 0, buttons = 0 }
  local function pooled(kind, make)
    used[kind] = used[kind] + 1
    local list = f.pools[kind]
    local obj = list[used[kind]]
    if not obj then
      obj = make()
      list[used[kind]] = obj
    end
    obj:ClearAllPoints()
    obj:Show()
    return obj
  end
  f.crumb:SetText(p.crumb or "")
  f.crumb:ClearAllPoints()
  f.crumb:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
  f.crumb:SetShown(p.crumb ~= nil)
  if p.crumb then
    y = y + 15
  end
  f.title:SetText(p.title)
  f.title:ClearAllPoints()
  f.title:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
  f.title:SetWidth(w)
  y = y + 22
  for _, e in pairs(f.examples) do
    e:Hide()
  end
  for i, b in ipairs(p.blocks) do
    if b.p or b.links then
      local fs = pooled("p", function()
        local t = Kit.Text(page, { size = 12, color = "soft", wrap = true })
        if t.SetSpacing then
          t:SetSpacing(3)
        end
        if t.SetJustifyV then
          t:SetJustifyV("TOP")
        end
        return t
      end)
      local text
      if b.links then
        local parts = {}
        for j, l in ipairs(b.links) do
          parts[j] = ("|Hameguide:%s|h%s|h"):format(l.key, Kit.Color("link", l.label))
        end
        text = table.concat(parts, Kit.Color("dim", "  ·  "))
      else
        text = ns.Help and ns.Help.LinkCommands and ns.Help.LinkCommands(b.p) or b.p
      end
      fs:SetWidth(w)
      fs:SetText(text)
      fs:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
      y = y + math.max(14, textHeight(fs)) + 8
    elseif b.h then
      local fs = pooled("h", function()
        return Kit.Text(page, { size = 13, color = "heading" })
      end)
      y = y + 4
      fs:SetText(b.h)
      fs:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
      y = y + 20
    elseif b.buttons then
      local holder = pooled("buttons", function()
        local hf = CreateFrame("Frame", nil, page)
        hf.list = {}
        return hf
      end)
      holder:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
      holder:SetSize(w, 24)
      local prev
      for j, spec in ipairs(b.buttons) do
        local btn = holder.list[j]
        if not btn then
          btn = Kit.Button(holder)
          btn:SetHeight(24)
          btn:SetScript("OnClick", function(self)
            if self.spec and self.spec.action then
              f.ctx:Dispatch(self.spec.action, self.spec.payload)
            end
          end)
          holder.list[j] = btn
        end
        btn.spec = spec
        btn.label:SetText(spec.label)
        btn.variant = "normal"
        btn:GetScript("OnLeave")(btn)
        btn:SetWidth(textWidth(btn.label) + 20)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", prev or holder, prev and "RIGHT" or "LEFT", prev and 6 or 0, 0)
        btn:Show()
        prev = btn
      end
      for j = #b.buttons + 1, #holder.list do
        holder.list[j]:Hide()
      end
      y = y + 24 + 10
    elseif b.example then
      local id = tostring(p.key) .. ":" .. i
      local e = f.examples[id]
      local make = ns.Help and ns.Help.EXAMPLES and ns.Help.EXAMPLES[b.example]
      if not e and make then
        local ok, made = pcall(make, page)
        e = ok and made or nil
        f.examples[id] = e or false
      end
      if e then
        e:ClearAllPoints()
        e:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
        e:SetWidth(w)
        e:Show()
        local eh = e.GetHeight and e:GetHeight() or 0
        y = y + (type(eh) == "number" and eh or 0) + 10
      end
    end
  end
  for kind, list in pairs(f.pools) do
    for j = used[kind] + 1, #list do
      list[j]:Hide()
    end
  end
  page:SetHeight(math.max(1, y + 10))
  f.contentH = y + 10
  scrollTo(f, f.y)
end

Layout.Register("guidearticle", {
  props = { key = "string?", crumb = "string?", title = "string", blocks = "table", action = "string?" },
  create = function(parent, ctx)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Kit.Box(holder, "panel", "line")
    local f = CreateFrame("ScrollFrame", nil, holder)
    f:SetPoint("TOPLEFT", 1, -1)
    f:SetPoint("BOTTOMRIGHT", -1, 1)
    f.page = CreateFrame("Frame", nil, f)
    f.page:SetSize(ARTICLE_W, 1)
    if f.SetScrollChild then
      f:SetScrollChild(f.page)
    end
    f.bar = f:CreateTexture(nil, "OVERLAY")
    f.bar:SetColorTexture(1, 1, 1, 0.25)
    f.bar:SetWidth(4)
    f.bar:Hide()
    f.y, f.ctx = 0, ctx
    f.pools = { p = {}, h = {}, buttons = {} }
    f.examples = {}
    f.crumb = Kit.Text(f.page, { size = 11, color = "dim" })
    f.title = Kit.Text(f.page, { size = 16, color = "heading" })
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
      scrollTo(self, (self.y or 0) - delta * 40)
    end)
    f:SetScript("OnSizeChanged", function(self)
      articleLayout(self)
    end)
    -- links in the text: slash commands go to the chat box, articles open, item names are the game's links
    local page = f.page
    W.EnableLinks(page)
    page:SetScript("OnHyperlinkClick", function(_, link)
      local Help = ns.Help
      local cmd = Help and Help.LinkedCommand and Help.LinkedCommand(link)
      if cmd then
        Help.PrefillChat(cmd)
        return
      end
      local key = type(link) == "string" and link:match("^ameguide:(.+)$")
      if key and f.props then
        f.ctx:Dispatch(f.props.action or "article", { key = key })
      elseif W.LinkKey and W.LinkKey(link) then
        W.ItemLinkClicked(W.LinkKey(link))
      end
    end)
    page:HookScript("OnHyperlinkEnter", function(self, link)
      local cmd = ns.Help and ns.Help.LinkedCommand and ns.Help.LinkedCommand(link)
      if cmd and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(cmd, 1, 1, 1)
        GameTooltip:AddLine(L["Click to put it in your chat box"], nil, nil, nil, true)
        GameTooltip:Show()
      end
    end)
    page:HookScript("OnHyperlinkLeave", function()
      if GameTooltip then
        GameTooltip:Hide()
      end
    end)
    holder.scroll = f
    return holder
  end,
  update = function(holder, p, ctx)
    local f = holder.scroll
    if f.props and f.props.key ~= p.key then
      f.y = 0 -- another article starts at its top
    end
    f.props, f.ctx = p, ctx
    articleLayout(f)
  end,
})

-- ------------------------------------------------------------------------------------------------ notice list

-- the actionlist, with each row a button: a click on a row dispatches rowAction {key = row.key}
local base = Layout.Get("actionlist")
if base then
  local props = {}
  for k, v in pairs(base.props) do
    props[k] = v
  end
  props.rowAction = "string?"
  Layout.Register("noticelist", {
    props = props,
    create = base.create,
    update = function(f, p, ctx)
      base.update(f, p, ctx)
      f.props = p
      for _, r in ipairs(f.rows) do
        if not r.noticeClick then
          r.noticeClick = true
          local function click()
            if r.data and f.props and f.props.rowAction then
              ctx:Dispatch(f.props.rowAction, { key = r.data.key })
            end
          end
          r:SetScript("OnClick", click)
          r.hover = r:CreateTexture(nil, "HIGHLIGHT")
          r.hover:SetAllPoints()
          r.hover:SetColorTexture(1, 1, 1, 0.04)
          -- the text over the row takes the mouse for its item links; a click there opens the row too
          if r.text and r.text.HookScript then
            r.text:HookScript("OnMouseUp", click)
          end
        end
      end
    end,
    size = base.size,
  })
end
