-- The table widget (the canvas's DataTable): Core/UI/DataTable.lua drawn by the layout engine. The rows never go in
-- the layout: the view hands them to the renderer's context as a data source, and the table draws the ones that fit.
--
--   table { source = "name",           -- ctx.sources[name]: a list of rows, or a function returning one
--           columns = { { key, label, width, format?, align?, item?, term?, button = { label, action }? }, ... },
--           action?,                   -- a row click: { key = row.key, item = row.item, button = "LeftButton" }
--           selected?,                 -- the picked row's key
--           sort = { key, ascending }?, sortAction?, note?, bare?, star?, flex?, empty? }
--
-- A row is plain data: { key, item?, faded?, [column key] = value }. A value is shown by the column's format
-- (money, signedMoney, count, pct, signal, tag, ...); a table { text, color } is text in a token colour. A button
-- column dispatches its action with { key = row.key }; the row's own value for that column overrides the label
-- (a string) or hides the button (false).
local _, ns = ...

local Layout, Kit, W = ns.Layout, ns.Kit, ns.Widgets

local function signature(columns)
  local parts = {}
  for i, c in ipairs(columns) do
    parts[i] = tostring(c.key)
      .. ":"
      .. tostring(c.format)
      .. ":"
      .. tostring(c.item)
      .. ":"
      .. tostring(c.button ~= nil)
  end
  return table.concat(parts, ",")
end

local function rows(ctx, source)
  local s = ctx.sources and ctx.sources[source]
  if type(s) == "function" then
    s = s()
  end
  return type(s) == "table" and s or {}
end

-- the data columns as the table's own column definitions
local function columnsFor(_f, specs, ctx)
  local out = {}
  for i, spec in ipairs(specs) do
    local col = {
      key = spec.key,
      label = spec.label or "",
      width = spec.width or 80,
      format = spec.format,
      align = spec.align,
      term = spec.term,
      ascendingFirst = spec.ascendingFirst,
    }
    if spec.item then
      col.item = true
      -- spec.count: a row field shown dim after the name ("×43"); a row's name stands in until the item is known
      if spec.count then
        col.suffix = function(d)
          local n = d[spec.count]
          return type(n) == "number" and n > 1 and W.Dim("  " .. W.Count(n)) or ""
        end
      end
      col.fallback = function(d)
        return d[spec.fallback or "name"]
      end
    end
    if spec.button then
      local def = spec.button
      col.button = {
        label = function(d)
          local v = d[spec.key]
          return type(v) == "string" and v or def.label or ""
        end,
        shown = function(d)
          return d[spec.key] ~= false
        end,
        variant = function(_d)
          return def.variant
        end,
        onClick = function(d)
          ctx:Dispatch(def.action, { key = d.key, item = d.item })
        end,
      }
    elseif not spec.format and not spec.item then
      col.text = function(d)
        local v = d[spec.key]
        if type(v) == "table" then
          return v.color and Kit.Color(v.color, v.text or "") or (v.text or "")
        end
        return v ~= nil and tostring(v) or W.NONE
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
  local opts = {
    columns = columnsFor(f, p.columns, ctx),
    fill = true,
    -- headers 11 px, cells and notes 12 px, in Kit's text font (Settings' pick reaches them)
    styleText = function(fs, gameFont)
      Kit.SetFont(fs, "ui", gameFont == "GameFontNormalSmall" and 11 or 12)
    end,
    bare = p.bare,
    note = p.note,
    star = p.star,
    flex = p.flex,
    sort = p.sort and { key = p.sort.key or p.sort[1], ascending = p.sort.ascending } or nil,
    itemID = function(d)
      return d.item
    end,
    confidence = p.confidence and function(d)
      return d.conf
    end or nil,
    rowAlpha = function(d)
      return d.faded and 0.5 or 1
    end,
    selected = function(d)
      return f.props and f.props.selected ~= nil and d.key == f.props.selected or false
    end,
    onClick = function(d, button)
      if f.props and f.props.action then
        ctx:Dispatch(f.props.action, { key = d.key, item = d.item, button = button })
      end
    end,
  }
  if p.sortAction then
    opts.onSort = function(key, ascending)
      ctx:Dispatch(p.sortAction, { key = key, ascending = ascending })
    end
  end
  f.dt = ns.DataTable.New(f, opts)
  f.dt.frame:SetPoint("TOPLEFT", 0, 0)
  f.dt.frame:SetPoint("BOTTOMRIGHT", 0, 0)
  f.sig = signature(p.columns) .. tostring(p.confidence)
end

Layout.Register("table", {
  props = {
    source = "string",
    columns = "table",
    action = "string?",
    selected = "any?",
    sort = "table?",
    sortAction = "string?",
    note = "string?",
    bare = "boolean?",
    star = "boolean?",
    flex = "string?",
    empty = "string?",
    confidence = "boolean?",
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
    if not f.dt or f.sig ~= signature(p.columns) .. tostring(p.confidence) then
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
