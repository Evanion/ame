-- Layouts as data, drawn by widgets (docs/ux/redesign-review.md, "How the screens are built").
--
-- A screen is a tree of items: { id, type, props, meta, children }. `type` names a registered widget, `props` is the
-- widget's data, `meta` is its placement (read by the container it sits in), `children` only on containers. The
-- tree holds no functions: behaviour stays in the view, and a widget reports a click by dispatching a named action
-- (ctx:Dispatch(name, payload)), which the view handles before handing the renderer new props.
--
--   Layout.Register(type, def)   def = {
--       props = { name = "string" | "number" | "boolean" | "table" | "any", optional = "string?", ... },
--       container = true,                       -- may have children; def.arrange places them (or a layout does)
--       create = function(parent, ctx) -> frame -- once per frame; frames are kept and reused, never freed
--       update = function(frame, props, ctx, item) -- any number of times
--       size = function(frame, props) -> w, h  -- optional: its natural size, when meta gives none
--       content = function(frame) -> frame      -- optional (containers): where the children go
--       arrange = function(frame, kids, w, h, props) -- optional (containers): place kids, see Layout.Place
--   }
--   Layout.Validate(tree) -> { "problem", ... }  never errors; the specs run it over every screen
--   Layout.Renderer(root, ctx) -> r              r:Render(tree), r:Set(id, props) (update in place), r:Frame(id)
--   Layout.Context(handlers) -> ctx              ctx:Dispatch(name, payload) calls handlers[name](payload, ctx)
--
-- The renderer keeps one frame per id. An id the new tree drops is hidden and pooled by type, and a new id of that
-- type takes it. An unknown type is skipped with one warning. Sizes are worked out top down: the root fills its
-- frame, each container hands its children their sizes, so nothing waits for the game to lay frames out.
local _, ns = ...

local Layout = { widgets = {} }
ns.Layout = Layout

local KINDS = { string = true, number = true, boolean = true, table = true, any = true }
Layout.META = { w = true, h = true, grow = true, span = true, minW = true, minH = true, x = true, y = true }

local warned = {}
local function warnOnce(key, text)
  if warned[key] then
    return
  end
  warned[key] = true
  if ns.Dev and ns.Dev.Warn then
    ns.Dev.Warn(text)
  end
  Layout.lastWarning = text
end
Layout.warned = warned

function Layout.Register(name, def)
  assert(type(name) == "string" and type(def) == "table", "Layout.Register(name, def)")
  assert(type(def.create) == "function" and type(def.update) == "function", name .. ": create and update")
  def.name = name
  def.props = def.props or {}
  Layout.widgets[name] = def
  return def
end

function Layout.Get(name)
  return Layout.widgets[name]
end

-- "string?" -> "string", true (optional)
local function kindOf(spec)
  local kind, optional = tostring(spec):match("^(%a+)(%??)$")
  return kind, optional == "?"
end

-- Problems with a tree, as text; an empty list is a valid tree. Never errors.
function Layout.Validate(tree)
  local problems, ids = {}, {}
  local function add(where, text)
    problems[#problems + 1] = where .. ": " .. text
  end
  local function walk(item, path)
    if type(item) ~= "table" then
      return add(path, "not an item")
    end
    local where = path .. (item.id and ("(" .. tostring(item.id) .. ")") or "")
    if type(item.id) ~= "string" or item.id == "" then
      add(where, "no id")
    elseif ids[item.id] then
      add(where, "duplicate id " .. item.id)
    else
      ids[item.id] = true
    end
    local def = Layout.widgets[item.type]
    if not def then
      add(where, "unknown type " .. tostring(item.type))
    else
      local props = item.props or {}
      if type(props) ~= "table" then
        add(where, "props is not a table")
        props = {}
      end
      for key, spec in pairs(def.props) do
        local kind, optional = kindOf(spec)
        local v = props[key]
        if v == nil then
          if not optional then
            add(where, "missing prop " .. key)
          end
        elseif not KINDS[kind] then
          add(where, "prop " .. key .. " declared as " .. tostring(spec))
        elseif kind ~= "any" and type(v) ~= kind then
          add(where, ("prop %s is %s, not %s"):format(key, type(v), kind))
        end
      end
      for key, v in pairs(props) do
        if def.props[key] == nil then
          add(where, "unknown prop " .. tostring(key))
        end
        if type(v) == "function" then
          add(where, "prop " .. tostring(key) .. " is a function (layouts are data: name an action)")
        end
      end
      if item.children and not def.container then
        add(where, "children on " .. item.type .. ", which is not a container")
      end
    end
    for key in pairs(item.meta or {}) do
      if not Layout.META[key] then
        add(where, "unknown meta " .. tostring(key))
      end
    end
    for i, child in ipairs(item.children or {}) do
      walk(child, where .. "/" .. i)
    end
  end
  walk(tree, "")
  return problems
end

-- ---------------------------------------------------------------------------------------------------- actions

local Context = {}
Context.__index = Context

function Layout.Context(handlers, fields)
  local ctx = setmetatable(fields or {}, Context)
  ctx.handlers = handlers or {}
  return ctx
end

-- a widget reports what happened; the view's handler changes state. An unknown action warns once.
function Context:Dispatch(name, payload)
  local fn = name and self.handlers[name]
  if not fn then
    warnOnce("action:" .. tostring(name), "layout: no handler for action " .. tostring(name))
    return false
  end
  fn(payload, self)
  return true
end

-- ---------------------------------------------------------------------------------------------------- placement

-- Where children go along one axis: fixed sizes (meta.w / meta.h, or the widget's natural size) first, then the
-- rest shared by weight among the children that grow. Returns { {offset, size}, ... }.
function Layout.Split(total, items, gap)
  gap = gap or 0
  local used, weight = 0, 0
  for _, it in ipairs(items) do
    if it.grow then
      weight = weight + it.grow
      used = used + (it.min or 0)
    else
      used = used + (it.size or 0)
    end
  end
  used = used + gap * math.max(0, #items - 1)
  local free = math.max(0, total - used)
  local out, at = {}, 0
  for i, it in ipairs(items) do
    local size = it.size or 0
    if it.grow then
      size = (it.min or 0) + (weight > 0 and free * it.grow / weight or 0)
    end
    size = math.floor(size + 0.5)
    out[i] = { at, size }
    at = at + size + gap
  end
  return out
end

-- one child's natural size along an axis: meta first, then the widget's own size(), then its frame
local function natural(kid, axis)
  local meta = kid.item.meta or {}
  if axis == "w" and meta.w then
    return meta.w
  elseif axis == "h" and meta.h then
    return meta.h
  end
  local def = Layout.widgets[kid.item.type]
  if def and def.size then
    local w, h = def.size(kid.frame, kid.item.props or {})
    if axis == "w" and w then
      return w
    elseif axis == "h" and h then
      return h
    end
  end
  return axis == "w" and kid.frame:GetWidth() or kid.frame:GetHeight()
end
Layout.Natural = natural

-- put a child frame at (x, y) from its container's top left, sized w x h
function Layout.Place(kid, parent, x, y, w, h)
  local f = kid.frame
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  f:SetSize(math.max(0, w), math.max(0, h))
  kid.w, kid.h = w, h
end

local function pad(props)
  local p = props.pad or 0
  return p, p
end

-- row / column: children one after another; meta.w (meta.h) fixes a size, meta.grow shares what's left
local function linear(axis)
  return function(frame, kids, w, h, props)
    local px, py = pad(props)
    local along, across = w - 2 * px, h - 2 * py
    if axis == "v" then
      along, across = h - 2 * py, w - 2 * px
    end
    local items = {}
    for i, kid in ipairs(kids) do
      local meta = kid.item.meta or {}
      if meta.grow then
        items[i] = { grow = meta.grow, min = axis == "h" and meta.minW or meta.minH }
      else
        items[i] = { size = natural(kid, axis == "h" and "w" or "h") }
      end
    end
    local slots = Layout.Split(along, items, props.gap)
    for i, kid in ipairs(kids) do
      local meta = kid.item.meta or {}
      local at, size = slots[i][1], slots[i][2]
      if axis == "h" then
        local ch = meta.h or across
        local y = py + (props.align == "center" and math.floor((across - ch) / 2) or 0)
        Layout.Place(kid, frame, px + at, y, size, ch)
      else
        local cw = meta.w or across
        Layout.Place(kid, frame, px, py + at, cw, size)
      end
    end
  end
end

-- grid: props.cols equal columns (or props.widths), children flow row by row; meta.span takes several columns,
-- props.rowH (or the child's meta.h) is a row's height
local function grid(frame, kids, w, h, props)
  local px, py = pad(props)
  local gap = props.gap or 0
  local widths = {}
  if props.widths then
    local items = {}
    for i, v in ipairs(props.widths) do
      items[i] = v == 0 and { grow = 1 } or { size = v }
    end
    for i, s in ipairs(Layout.Split(w - 2 * px, items, gap)) do
      widths[i] = s
    end
  else
    local n = props.cols or 1
    local items = {}
    for i = 1, n do
      items[i] = { grow = 1 }
    end
    for i, s in ipairs(Layout.Split(w - 2 * px, items, gap)) do
      widths[i] = s
    end
  end
  local col, y, rowH = 1, py, 0
  for _, kid in ipairs(kids) do
    local meta = kid.item.meta or {}
    local span = math.min(meta.span or 1, #widths)
    if col + span - 1 > #widths then
      col, y, rowH = 1, y + rowH + gap, 0
    end
    local x, cw = widths[col][1], 0
    for c = col, col + span - 1 do
      cw = cw + widths[c][2] + (c > col and gap or 0)
    end
    local ch = meta.h or props.rowH or natural(kid, "h")
    Layout.Place(kid, frame, px + x, y, cw, ch)
    rowH = math.max(rowH, ch)
    col = col + span
    if col > #widths then
      col, y, rowH = 1, y + rowH + gap, 0
    end
  end
end

-- fill: every child takes the whole box (less pad); meta.x / meta.y / meta.w / meta.h pin one instead
local function fill(frame, kids, w, h, props)
  local px, py = pad(props)
  for _, kid in ipairs(kids) do
    local meta = kid.item.meta or {}
    Layout.Place(kid, frame, px + (meta.x or 0), py + (meta.y or 0), meta.w or (w - 2 * px), meta.h or (h - 2 * py))
  end
end

Layout.ARRANGE = { row = linear("h"), column = linear("v"), grid = grid, fill = fill }

local function plainFrame(parent)
  local f = CreateFrame("Frame", nil, parent)
  return f
end

local LAYOUT_PROPS = {
  gap = "number?",
  pad = "number?",
  align = "string?",
  cols = "number?",
  widths = "table?",
  rowH = "number?",
}
for name, arrange in pairs(Layout.ARRANGE) do
  Layout.Register(name, {
    container = true,
    props = LAYOUT_PROPS,
    create = plainFrame,
    update = function() end,
    arrange = arrange,
  })
end

-- ---------------------------------------------------------------------------------------------------- renderer

local Renderer = {}
Renderer.__index = Renderer

function Layout.Renderer(root, ctx)
  local r = setmetatable({ root = root, ctx = ctx or Layout.Context({}), frames = {}, pool = {} }, Renderer)
  if root.HookScript then
    root:HookScript("OnSizeChanged", function()
      if r.tree then
        r:Arrange()
      end
    end)
  end
  return r
end

function Renderer:Frame(id)
  local e = self.frames[id]
  return e and e.frame
end

local function release(self, id)
  local e = self.frames[id]
  self.frames[id] = nil
  e.frame:Hide()
  e.frame:ClearAllPoints()
  local pool = self.pool[e.type] or {}
  self.pool[e.type] = pool
  pool[#pool + 1] = e.frame
end

function Renderer:node(item, parent, seen)
  local def = type(item) == "table" and Layout.widgets[item.type]
  if not def then
    warnOnce("type:" .. tostring(type(item) == "table" and item.type), "layout: unknown widget type " .. tostring(
      type(item) == "table" and item.type
    ))
    return nil
  end
  local id = item.id
  if type(id) ~= "string" or seen[id] then
    warnOnce("id:" .. tostring(id), "layout: missing or duplicate id " .. tostring(id))
    return nil
  end
  seen[id] = true
  local e = self.frames[id]
  if e and e.type ~= item.type then
    release(self, id)
    e = nil
  end
  if not e then
    local pool = self.pool[item.type]
    local frame = pool and table.remove(pool) or def.create(parent, self.ctx)
    e = { frame = frame, type = item.type }
    self.frames[id] = e
  end
  if e.frame:GetParent() ~= parent and e.frame.SetParent then
    e.frame:SetParent(parent)
  end
  e.item = item
  e.frame:Show()
  def.update(e.frame, item.props or {}, self.ctx, item)
  e.kids = nil
  if def.container then
    local inner = def.content and def.content(e.frame) or e.frame
    e.inner = inner
    e.kids = {}
    for _, child in ipairs(item.children or {}) do
      local k = self:node(child, inner, seen)
      if k then
        e.kids[#e.kids + 1] = { frame = k.frame, item = child, e = k }
      end
    end
  end
  return e
end

-- draw a tree: frames made or reused by id, props applied, dropped ids hidden, then everything placed
function Renderer:Render(tree)
  self.tree = tree
  local seen = {}
  self.top = self:node(tree, self.root, seen)
  for id in pairs(self.frames) do
    if not seen[id] then
      release(self, id)
    end
  end
  self:Arrange()
  return self.top
end

local function arrange(e, w, h)
  if not e.kids then
    return
  end
  local def = Layout.widgets[e.type]
  local props = e.item.props or {}
  local place = def.arrange or Layout.ARRANGE.fill
  local iw, ih = w, h
  if def.inset then
    local l, r, t, b = def.inset(e.frame, props)
    iw, ih = w - (l or 0) - (r or 0), h - (t or 0) - (b or 0)
  end
  place(e.inner, e.kids, iw, ih, props)
  for _, kid in ipairs(e.kids) do
    arrange(kid.e, kid.w or 0, kid.h or 0)
  end
end

-- place everything from the root's size down (again on every resize)
function Renderer:Arrange()
  local top = self.top
  if not top then
    return
  end
  local w, h = self.root:GetWidth(), self.root:GetHeight()
  top.frame:ClearAllPoints()
  top.frame:SetPoint("TOPLEFT", self.root, "TOPLEFT", 0, 0)
  top.frame:SetSize(w, h)
  arrange(top, w, h)
end

-- update one item's props in place (no new tree, no re-layout): for what changes during a scan
function Renderer:Set(id, props)
  local e = self.frames[id]
  if not e then
    return false
  end
  local item = e.item
  item.props = item.props or {}
  for k, v in pairs(props) do
    item.props[k] = v
  end
  Layout.widgets[e.type].update(e.frame, item.props, self.ctx, item)
  return true
end

-- walk a tree: fn(item, parent) for every item (for views and specs)
function Layout.Each(tree, fn, parent)
  if type(tree) ~= "table" then
    return
  end
  fn(tree, parent)
  for _, child in ipairs(tree.children or {}) do
    Layout.Each(child, fn, tree)
  end
end

-- find an item by id
function Layout.Find(tree, id)
  local found
  Layout.Each(tree, function(item)
    if item.id == id then
      found = found or item
    end
  end)
  return found
end
