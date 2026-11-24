-- The Crafting tab's own widgets (boards CraftingOne ... CraftingLearn, CraftQueue, QueueStrip): the recipe table
-- with the game's sections, the picked recipe's card, the Tools card, lines of text with item links, the queue as
-- one line, the Make bar (Create / Create all / Queue), a button that crafts from the click, and the skill colour bar.
--
--   crafttable { source, columns = { { key, label, width, format?, align?, item?, button = { label, action, variant? }? } },
--                action?, selected?, note?, empty?, flex?, bare?, sorted? }
--     rows: { key, item?, label? (text where there's no item: an enchant, a section header), suffix?, faded?, header? }
--   crafthead  { item?, title?, subtitle? }                  a recipe's card: the item as a link, a line under it
--   toolscard  { title?, tools = { { item?, place?, have?, tone?, line?, price? } } }
--   partslines { title?, lines = { parts, ... } }            Kit.Parts lines (item names are links)
--   queuestrip { items = { { item?, count?, label? } }, toBuy?, button?, buttonAction?, action?, empty? }
--   makebar    { count?, label?, recipe?, buttons = { { key, label, variant?, call? } }, action? }
--   craftbutton { label, variant?, call?, payload?, action? }
--   skillbar   { lo, yellow, green, grey, hi, from?, to? }
-- A button with `call` runs the game's own action from the click (CraftingUI.Calls: create, createAll, craftNext),
-- then dispatches its action with { key, count, recipe, ran } to report it.
local _, ns = ...
local L = ns.L

local Layout, Kit, W = ns.Layout, ns.Kit, ns.Widgets

local CraftingUI = {}
ns.CraftingUI = CraftingUI

-- ------------------------------------------------------------------------------------------------ game calls

-- what only a real click may do: crafting goes through the open profession window
local Calls = {}
CraftingUI.Calls = Calls

local function recipeInfo(id)
  local api = _G.C_TradeSkillUI
  local ok, info = pcall(api and api.GetRecipeInfo or error, id)
  return ok and type(info) == "table" and info or nil
end

-- can this character create the recipe here (its window is open and it knows it)?
function CraftingUI.CanCreate(recipeID)
  local info = recipeID and recipeInfo(recipeID)
  return info and info.learned and true or false, info and info.numAvailable or 0
end

function Calls.create(p)
  local api = _G.C_TradeSkillUI
  if not (p and p.recipe and api and api.CraftRecipe and CraftingUI.CanCreate(p.recipe)) then
    return false
  end
  return pcall(api.CraftRecipe, p.recipe, math.max(1, math.floor(p.count or 1))) and true or false
end

function Calls.createAll(p)
  local api = _G.C_TradeSkillUI
  local can, n = CraftingUI.CanCreate(p and p.recipe)
  if not (can and n > 0 and api.CraftRecipe) then
    return false
  end
  return pcall(api.CraftRecipe, p.recipe, n) and true or false
end

function Calls.craftNext()
  local PB = ns.ProfessionBar
  if not (PB and PB.CraftNext) then
    return false
  end
  return pcall(PB.CraftNext, PB) and true or false
end

local function run(call, payload)
  local fn = call and Calls[call]
  return fn and fn(payload) or false
end

local function dispatch(ctx, action, payload)
  if action and ctx then
    ctx:Dispatch(action, payload)
  end
end

-- ------------------------------------------------------------------------------------------------ skill colours

-- the game's skill-up colours (orange, yellow, green, grey); the tokens' nearest when the game has none to read
local DIFF_TOKEN = { orange = "q5", yellow = "warn", green = "good", grey = "q0" }
local DIFF_GAME = { orange = "optimal", yellow = "medium", green = "easy", grey = "trivial" }
function CraftingUI.DiffColor(diff)
  local game = _G.TradeSkillTypeColor and _G.TradeSkillTypeColor[DIFF_GAME[diff] or ""]
  if type(game) == "table" and game.r then
    return { game.r, game.g, game.b, 1 }
  end
  return Kit.C(DIFF_TOKEN[diff] or "dim")
end

-- the skill-up arrows beside a recipe: two for orange, one for yellow and green, none at grey
local ARROW = "|TInterface\\AddOns\\AzerothMercantileExchange\\media\\Signals\\Up:9:9:0:0:32:32:0:32:0:32:%d:%d:%d|t"
function CraftingUI.Arrows(diff)
  if not DIFF_TOKEN[diff] or diff == "grey" then
    return ""
  end
  local c = CraftingUI.DiffColor(diff)
  local one = ARROW:format(c[1] * 255, c[2] * 255, c[3] * 255)
  return diff == "orange" and (one .. one) or one
end

-- ------------------------------------------------------------------------------------------------ shared bits

local function textWidth(fs)
  return math.ceil(fs:GetStringWidth() or 0)
end

-- the card look: a panel with the lit top edge, and its title in the display font
local function cardFrame(parent, frameType)
  local f = CreateFrame(frameType or "Frame", nil, parent, "BackdropTemplate")
  Kit.Box(f, "panel", "line")
  f.top = Kit.Line(f, "TOP", "frameLit")
  f.title = Kit.Text(f, { font = "display", size = 14, color = "heading" })
  f.title:SetPoint("TOPLEFT", 10, -8)
  return f
end

local function input(parent)
  local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  Kit.Box(box, "bg", "controlLine")
  Kit.SetFont(box, "ui", 11)
  Kit.SetColor(box, "soft")
  box:SetTextInsets(6, 6, 0, 0)
  box:SetAutoFocus(false)
  if box.SetNumeric then
    box:SetNumeric(true)
  end
  box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEditFocusGained", function(self)
    Kit.Box(self, "bg", Kit.Accent())
  end)
  box:SetScript("OnEditFocusLost", function(self)
    Kit.Box(self, "bg", "controlLine")
  end)
  return box
end

local function setVariant(b, variant)
  b.variant = variant or "normal"
  if b.SetEnabled then
    b:SetEnabled(b.variant ~= "disabled")
  end
  local leave = b:GetScript("OnLeave")
  if leave then
    leave(b) -- redraws the look (Kit.Button)
  end
end

-- ------------------------------------------------------------------------------------------------ crafttable

local function rows(ctx, source)
  local s = ctx.sources and ctx.sources[source]
  if type(s) == "function" then
    s = s()
  end
  return type(s) == "table" and s or {}
end

local function signature(columns, sorted)
  local parts = { tostring(sorted) }
  for i, c in ipairs(columns) do
    parts[i + 1] = tostring(c.key) .. ":" .. tostring(c.format) .. ":" .. tostring(c.item) .. ":" .. tostring(c.button ~= nil) .. ":" .. tostring(c.width)
  end
  return table.concat(parts, ",")
end

local function columnsFor(f, specs, ctx, sorted)
  local out = {}
  for i, spec in ipairs(specs) do
    local col = {
      key = spec.key,
      label = spec.label or "",
      width = spec.width or 80,
      format = spec.format,
      align = spec.align,
      sortKey = not (sorted and not spec.item) and false or nil,
    }
    if spec.item then
      col.item = true
      col.fallback = function(d)
        return d.label
      end
      col.suffix = function(d)
        return d.suffix or ""
      end
    elseif spec.button then
      local def = spec.button
      col.button = {
        label = function(d)
          local v = d[spec.key]
          return type(v) == "string" and v or def.label or ""
        end,
        shown = function(d)
          return not d.header and d[spec.key] ~= false and d[spec.key] ~= nil
        end,
        variant = function()
          return def.variant
        end,
        onClick = function(d)
          ctx:Dispatch(def.action, { key = d.key, item = d.item })
        end,
      }
    end
    if not col.item and not col.button then
      local format = spec.format
      col.format = nil
      col.text = function(d)
        local v = d[spec.key]
        if d.header then
          return ""
        end
        if type(v) == "table" then
          return v.color and Kit.Color(v.color, v.text or "") or (v.text or "")
        end
        if v == nil then
          return format and "" or ""
        end
        if format == "money" then
          return W.Money(v, true)
        elseif format == "signedMoney" then
          return W.SignedMoney(v)
        elseif format == "count" then
          return W.Count(v)
        end
        return tostring(v)
      end
      if format == "tag" then
        col.format, col.text = "tag", nil
      end
    end
    out[i] = col
  end
  return out
end

local function build(f, p, ctx)
  if f.dt then
    f.dt.frame:Hide()
  end
  f.dt = ns.DataTable.New(f, {
    columns = columnsFor(f, p.columns, ctx, p.sorted),
    fill = true,
    bare = p.bare,
    note = p.note,
    flex = p.flex,
    itemID = function(d)
      return d.item
    end,
    rowAlpha = function(d)
      return d.faded and 0.5 or 1
    end,
    selected = function(d)
      return f.props and f.props.selected ~= nil and d.key == f.props.selected or false
    end,
    onClick = function(d, button)
      if f.props and f.props.action then
        ctx:Dispatch(f.props.action, { key = d.key, item = d.item, button = button, header = d.header })
      end
    end,
  })
  f.dt.frame:SetPoint("TOPLEFT", 0, 0)
  f.dt.frame:SetPoint("BOTTOMRIGHT", 0, 0)
  f.sig = signature(p.columns, p.sorted)
end

Layout.Register("crafttable", {
  props = {
    source = "string",
    columns = "table",
    action = "string?",
    selected = "any?",
    note = "string?",
    empty = "string?",
    flex = "string?",
    bare = "boolean?",
    sorted = "boolean?",
  },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetScript("OnSizeChanged", function(self)
      if self.dt then
        self.dt:Render()
      end
    end)
    return f
  end,
  update = function(f, p, ctx)
    f.props = p
    if not f.dt or f.sig ~= signature(p.columns, p.sorted) then
      build(f, p, ctx)
    end
    if p.note then
      f.dt:SetNote(p.note)
    end
    local list = rows(ctx, p.source)
    f.dt:SetData(list)
    f.dt:SetMessage(#list == 0 and (p.empty or nil) or nil)
    f.dt:Render()
  end,
  size = function()
    return 0, 0
  end,
})

-- a section header's text: the fold arrow, the game's name, how many it holds
function CraftingUI.HeaderLabel(label, count, folded)
  return Kit.Color("dim", folded and "+ " or "– ") .. Kit.Color("heading", label) .. "  " .. Kit.Color("dim", tostring(count))
end

-- ------------------------------------------------------------------------------------------------ crafthead

Layout.Register("crafthead", {
  props = { item = "any?", title = "string?", subtitle = "string?" },
  create = function(parent)
    local f = cardFrame(parent)
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.link = W.ItemLink(f, { icon = 16 })
    f.link:SetPoint("TOPLEFT", 10, -6)
    f.link:SetPoint("RIGHT", -10, 0)
    f.sub = Kit.Text(f, { size = 11, color = "dim" })
    f.sub:SetPoint("TOPLEFT", 10, -27)
    f.sub:SetPoint("RIGHT", -10, 0)
    return f
  end,
  update = function(f, p)
    f.link:SetShown(p.item ~= nil)
    if p.item ~= nil then
      if f.link.SetFont then
        f.link:SetFont(13, true)
      end
      f.link:SetItem(p.item)
    end
    f.title:SetShown(p.item == nil)
    f.title:SetText(p.title or "")
    f.sub:SetText(p.subtitle or "")
  end,
  size = function()
    return 300, 48
  end,
})

-- ------------------------------------------------------------------------------------------------ toolscard

local TOOL_H, WAY_H = 18, 15

Layout.Register("toolscard", {
  props = { title = "string?", tools = "table" },
  create = function(parent)
    local f = cardFrame(parent)
    f.lines = {}
    W.EnableLinks(f)
    return f
  end,
  update = function(f, p)
    f.title:SetText(p.title or L["Tools"])
    local y = 28
    for i, t in ipairs(p.tools) do
      local line = f.lines[i]
      if not line then
        line = {
          link = W.ItemLink(f, { icon = 12 }),
          place = Kit.Text(f, { size = 12 }),
          have = Kit.Text(f, { size = 11, justify = "RIGHT" }),
          how = Kit.Text(f, { size = 11, color = "dim" }),
          price = Kit.Text(f, { size = 11, justify = "RIGHT" }),
        }
        f.lines[i] = line
      end
      line.link:ClearAllPoints()
      line.link:SetPoint("TOPLEFT", 10, -y)
      line.link:SetShown(t.item ~= nil)
      if t.item ~= nil then
        line.link:SetItem(t.item)
      end
      line.place:ClearAllPoints()
      line.place:SetPoint("TOPLEFT", 10, -y - 2)
      line.place:SetShown(t.item == nil)
      line.place:SetText(t.place or "")
      line.have:ClearAllPoints()
      line.have:SetPoint("TOPRIGHT", -10, -y - 2)
      line.have:SetText(t.have and Kit.Color(t.tone or "dim", t.have) or "")
      line.have:Show()
      y = y + TOOL_H
      local hasWay = t.line ~= nil
      line.how:SetShown(hasWay)
      line.price:SetShown(hasWay)
      if hasWay then
        line.how:ClearAllPoints()
        line.how:SetPoint("TOPLEFT", 20, -y)
        line.how:SetPoint("RIGHT", line.price, "LEFT", -8, 0)
        line.how:SetText(t.line)
        line.price:ClearAllPoints()
        line.price:SetPoint("TOPRIGHT", -10, -y)
        line.price:SetText(t.price and W.Money(t.price, true) or "")
        y = y + WAY_H
      end
    end
    for i = #p.tools + 1, #f.lines do
      local line = f.lines[i]
      for _, part in pairs(line) do
        part:Hide()
      end
    end
    f.natural = y + 8
  end,
  size = function(f)
    return 300, f.natural or 48
  end,
})

-- ------------------------------------------------------------------------------------------------ partslines

local LINE_H = 18

Layout.Register("partslines", {
  props = { title = "string?", lines = "table", note = "string?" },
  create = function(parent)
    local f = cardFrame(parent)
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 10, -28)
    f.body:SetPoint("BOTTOMRIGHT", -10, 6)
    W.EnableLinks(f.body)
    f.fs = {}
    f.note = Kit.Text(f.body, { size = 11, color = "dim", wrap = true })
    return f
  end,
  update = function(f, p)
    local titled = p.title ~= nil
    f.title:SetShown(titled)
    f.title:SetText(p.title or "")
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", 10, titled and -28 or -8)
    f.body:SetPoint("BOTTOMRIGHT", -10, 6)
    for i, parts in ipairs(p.lines) do
      local fs = f.fs[i]
      if not fs then
        fs = Kit.Text(f.body, { size = 12 })
        f.fs[i] = fs
      end
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 0, -(i - 1) * LINE_H)
      fs:SetPoint("RIGHT", 0, 0)
      fs:SetText(Kit.Parts(parts))
      fs:Show()
    end
    for i = #p.lines + 1, #f.fs do
      f.fs[i]:Hide()
    end
    f.note:ClearAllPoints()
    f.note:SetPoint("TOPLEFT", 0, -#p.lines * LINE_H - 2)
    f.note:SetPoint("RIGHT", 0, 0)
    f.note:SetText(p.note or "")
    f.note:SetShown(p.note ~= nil)
    f.natural = (titled and 28 or 8) + #p.lines * LINE_H + (p.note and 30 or 0) + 6
  end,
  size = function(f)
    return 300, f.natural or 40
  end,
})

-- ------------------------------------------------------------------------------------------------ queuestrip

Layout.Register("queuestrip", {
  props = {
    items = "table",
    toBuy = "number?",
    button = "string?",
    buttonAction = "string?",
    action = "string?",
    empty = "string?",
  },
  create = function(parent, ctx)
    local f = cardFrame(parent, "Button")
    f.title:ClearAllPoints()
    f.title:SetPoint("LEFT", 10, 0)
    f.title:SetText(L["Queued"])
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
    f.body:SetHeight(20)
    W.EnableLinks(f.body)
    f.text = Kit.Text(f.body, { size = 12 })
    f.text:SetAllPoints()
    f.cost = Kit.Text(f, { size = 11, color = "dim", justify = "RIGHT" })
    f.button = Kit.Button(f)
    f.button:SetHeight(24)
    f.button:SetPoint("RIGHT", -8, 0)
    f.button:SetScript("OnClick", function()
      if f.props and f.props.buttonAction then
        dispatch(ctx, f.props.buttonAction, {})
      end
    end)
    f:SetScript("OnClick", function()
      if f.props and f.props.action then
        dispatch(ctx, f.props.action, {})
      end
    end)
    return f
  end,
  update = function(f, p)
    f.props = p
    local parts = {}
    for _, it in ipairs(p.items) do
      local count = it.count and (W.Thousands and W.Thousands(math.floor(it.count + 0.5)) or tostring(it.count)) .. " " or ""
      parts[#parts + 1] = count .. (it.item and W.LinkText(it.item) or (it.label or "?"))
    end
    f.text:SetText(#parts > 0 and table.concat(parts, "   ") or Kit.Color("dim", p.empty or ""))
    f.button:SetShown(p.button ~= nil)
    if p.button then
      f.button.label:SetText(p.button)
      f.button:SetWidth(textWidth(f.button.label) + 20)
      setVariant(f.button, "primary")
    end
    local right = p.button and f.button or f
    f.cost:ClearAllPoints()
    f.cost:SetPoint("RIGHT", right, right == f and "RIGHT" or "LEFT", right == f and -10 or -8, 0)
    f.cost:SetText(p.toBuy and (L["to buy"] .. " " .. W.Money(p.toBuy, true)) or "")
    f.body:ClearAllPoints()
    f.body:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
    f.body:SetPoint("RIGHT", f.cost, "LEFT", -8, 0)
  end,
  size = function()
    return 400, 42
  end,
})

-- ------------------------------------------------------------------------------------------------ makebar

Layout.Register("makebar", {
  props = { count = "number?", label = "string?", recipe = "number?", buttons = "table", action = "string?", noCount = "boolean?" },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent)
    f.label = Kit.Text(f, { size = 11, color = "dim" })
    f.label:SetPoint("LEFT", 0, 0)
    f.box = input(f)
    f.box:SetSize(40, 24)
    f.box:SetPoint("LEFT", f.label, "RIGHT", 6, 0)
    f.buttons = {}
    local function count()
      local n = tonumber(f.box:GetText() or "")
      return math.max(1, math.floor(n or (f.props and f.props.count) or 1))
    end
    f.box:SetScript("OnEnterPressed", function(self)
      self:ClearFocus()
      dispatch(ctx, f.props and f.props.action, { key = "count", count = count() })
    end)
    f.count = count
    f.ctx = ctx
    return f
  end,
  update = function(f, p)
    f.props = p
    f.label:SetText(p.noCount and "" or (p.label or L["Make"]))
    f.box:SetShown(not p.noCount)
    if not (f.box.HasFocus and f.box:HasFocus()) then
      f.box:SetText(tostring(p.count or 1))
    end
    local x = p.noCount and 0 or (textWidth(f.label) + 6 + 40 + 6)
    for i, def in ipairs(p.buttons) do
      local b = f.buttons[i]
      if not b then
        b = Kit.Button(f)
        b:SetScript("OnClick", function(self)
          if self.variant == "disabled" then
            return
          end
          local d = self.def
          local payload = { key = d.key, count = f.count(), recipe = f.props.recipe }
          payload.ran = run(d.call, payload)
          dispatch(f.ctx, f.props.action, payload)
        end)
        f.buttons[i] = b
      end
      b.def = def
      b.label:SetText(def.label)
      local w = math.max(textWidth(b.label) + 20, 40)
      b:ClearAllPoints()
      b:SetPoint("LEFT", x, 0)
      b:SetSize(w, 24)
      setVariant(b, def.variant)
      b:Show()
      x = x + w + 6
    end
    for i = #p.buttons + 1, #f.buttons do
      f.buttons[i]:Hide()
    end
    f.natural = x
  end,
  size = function(f)
    return f.natural or 200, 24
  end,
})

-- ------------------------------------------------------------------------------------------------ craftbutton (Create, Create all, Craft next: the game is called from the click)

Layout.Register("craftbutton", {
  props = { label = "string", variant = "string?", call = "string?", payload = "any?", action = "string?" },
  create = function(parent, ctx)
    local b = Kit.Button(parent)
    b:SetScript("OnClick", function(self)
      if self.variant == "disabled" then
        return
      end
      local p = self.props or {}
      local ran = run(p.call, p.payload)
      dispatch(ctx, p.action, { payload = p.payload, ran = ran })
    end)
    return b
  end,
  update = function(b, p)
    b.props = p
    b.label:SetText(p.label)
    setVariant(b, p.variant)
  end,
  size = function(b)
    return math.max(textWidth(b.label) + 20, 24), 24
  end,
})

-- ------------------------------------------------------------------------------------------------ skillbar

Layout.Register("skillbar", {
  props = {
    lo = "number",
    yellow = "number",
    green = "number",
    grey = "number",
    hi = "number",
    from = "number?",
    to = "number?",
  },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.parts = {}
    for i, diff in ipairs({ "orange", "yellow", "green", "grey" }) do
      local t = f:CreateTexture(nil, "ARTWORK")
      t.diff = diff
      f.parts[i] = t
    end
    f.mark = f:CreateTexture(nil, "OVERLAY")
    return f
  end,
  update = function(f, p)
    local w = f:GetWidth()
    if not w or w <= 0 then
      w = 270
    end
    local edges = { p.lo, p.yellow, p.green, p.grey, p.hi }
    local scale = w / math.max(1, p.hi - p.lo)
    for i, t in ipairs(f.parts) do
      Kit.Fill(t, CraftingUI.DiffColor(t.diff))
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", (edges[i] - p.lo) * scale, 0)
      t:SetSize(math.max(1, (edges[i + 1] - edges[i]) * scale), 14)
    end
    local white = Kit.C("white")
    f.mark:SetColorTexture(white[1], white[2], white[3], 0.35)
    f.mark:ClearAllPoints()
    f.mark:SetPoint("TOPLEFT", ((p.from or p.lo) - p.lo) * scale, 0)
    f.mark:SetSize(math.max(2, ((p.to or p.from or p.lo) - (p.from or p.lo)) * scale), 14)
    f.mark:SetShown(p.from ~= nil)
  end,
  size = function()
    return 270, 14
  end,
})
