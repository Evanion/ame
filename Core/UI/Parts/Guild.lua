-- Widgets only the Guild tab and the request frames use (boards GuildRequests, GuildOffers, RequestForm,
-- RequestAnswer).
--
--   heading       { title, note? }                        a panel title in the game's font with a dim note beside it
--   linktext      { parts, color?, size?, wrap? }         a line with item links in it (Kit.Parts): tooltip,
--                                                         Shift-click
--   statestrip    { steps = { label, ... }, current, ended? }   new › answered › accepted › ... the current one lit
--   textarea      { value?, hint?, action?, payload? }    a box of several lines; action gets { text } as you type
--                                                          (on focus lost too)
--   requestform   container: the frame of a craft request being written (RequestForm); children in a column
--   requestanswer container: the frame of a request being answered or reviewed (RequestAnswer); the same
local _, ns = ...

local Layout, Kit, W = ns.Layout, ns.Kit, ns.Widgets

local function textWidth(fs)
  return math.ceil(fs:GetStringWidth() or 0)
end

-- ------------------------------------------------------------------------------------------------ heading

Layout.Register("heading", {
  props = { title = "string", note = "string?" },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.title = Kit.Text(f, { font = "display", size = 15, color = "heading" })
    f.title:SetPoint("LEFT", 0, 0)
    f.note = Kit.Text(f, { size = 11, color = "dim" })
    f.note:SetPoint("LEFT", f.title, "RIGHT", 8, -1)
    return f
  end,
  update = function(f, p)
    f.title:SetText(p.title)
    f.note:SetText(p.note or "")
  end,
  size = function(f)
    return textWidth(f.title) + 8 + textWidth(f.note), 20
  end,
})

-- ------------------------------------------------------------------------------------------------ link text

Layout.Register("linktext", {
  props = { parts = "any", color = "string?", size = "number?", wrap = "boolean?" },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.fs = Kit.Text(f, { size = 11 })
    f.fs:SetAllPoints()
    W.EnableLinks(f)
    return f
  end,
  update = function(f, p)
    Kit.SetFont(f.fs, "ui", p.size or 11)
    Kit.SetColor(f.fs, p.color or "soft")
    if f.fs.SetWordWrap then
      f.fs:SetWordWrap(p.wrap ~= false)
    end
    if f.fs.SetJustifyV then
      f.fs:SetJustifyV("TOP")
    end
    f.fs:SetText(Kit.Parts(p.parts))
  end,
  size = function(f, p)
    return textWidth(f.fs) + 2, (p.size or 11) + 6
  end,
})

-- ------------------------------------------------------------------------------------------------ state strip

Layout.Register("statestrip", {
  props = { steps = "table", current = "number?", ended = "string?" },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.fs = Kit.Text(f, { size = 11, color = "dim" })
    f.fs:SetPoint("LEFT", 0, 0)
    return f
  end,
  update = function(f, p)
    local out = {}
    for i, label in ipairs(p.steps) do
      out[i] = i == p.current and Kit.Color("warn", label) or Kit.Color("dim", label)
    end
    local text = table.concat(out, Kit.Color("dim", "  ›  "))
    if p.ended then
      text = text .. "   " .. Kit.Color("bad", p.ended)
    end
    f.fs:SetText(text)
  end,
  size = function(f)
    return textWidth(f.fs) + 2, 16
  end,
})

-- ------------------------------------------------------------------------------------------------ text area

Layout.Register("textarea", {
  props = { value = "string?", hint = "string?", action = "string?", payload = "any?" },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Kit.Box(f, "bg", "controlLine")
    local box = CreateFrame("EditBox", nil, f)
    box:SetPoint("TOPLEFT", 7, -5)
    box:SetPoint("BOTTOMRIGHT", -7, 5)
    if box.SetMultiLine then
      box:SetMultiLine(true)
    end
    box:SetAutoFocus(false)
    Kit.SetFont(box, "ui", 12)
    Kit.SetColor(box, "text")
    if box.SetMaxLetters then
      box:SetMaxLetters(ns.CraftRequests and ns.CraftRequests.MAX_MESSAGE or 200)
    end
    f.box = box
    f.hint = Kit.Text(f, { size = 11, color = "dim" })
    f.hint:SetPoint("TOPLEFT", 7, -6)
    local function send(self, typed)
      local props = f.props
      if props and props.action and typed then
        local payload = props.payload ~= nil and { payload = props.payload } or {}
        payload.text = self:GetText() or ""
        ctx:Dispatch(props.action, payload)
      end
    end
    box:SetScript("OnTextChanged", function(self, user)
      f.hint:SetShown((self:GetText() or "") == "")
      if user then
        f.typed = true
        send(self, true)
      end
    end)
    box:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", function()
      Kit.Box(f, "bg", Kit.Accent())
    end)
    box:SetScript("OnEditFocusLost", function()
      Kit.Box(f, "bg", "controlLine")
    end)
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function()
      box:SetFocus()
    end)
    return f
  end,
  update = function(f, p)
    f.props = p
    if not (f.box.HasFocus and f.box:HasFocus()) then
      f.box:SetText(p.value or "")
    end
    f.hint:SetText(p.hint or "")
    f.hint:SetShown((f.box:GetText() or "") == "")
  end,
  size = function()
    return 200, 52
  end,
})

-- ------------------------------------------------------------------------------------------------ the request frames

-- the frame's body: the window's look (bg, the bronze frame), its children in a column with the boards' padding
local function requestFrame()
  return {
    container = true,
    props = { gap = "number?", pad = "number?" },
    create = function(parent)
      local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
      Kit.Box(f, "bg", "frame")
      f.content = CreateFrame("Frame", nil, f)
      return f
    end,
    update = function(f, p)
      local pad = p.pad or 12
      f.content:ClearAllPoints()
      f.content:SetPoint("TOPLEFT", pad, -10)
      f.content:SetPoint("BOTTOMRIGHT", -pad, pad)
      f.inset = { pad, pad, 10, pad }
    end,
    content = function(f)
      return f.content
    end,
    inset = function(f)
      return unpack(f.inset or { 12, 12, 10, 12 })
    end,
    arrange = function(frame, kids, w, h, props)
      Layout.ARRANGE.column(frame, kids, w, h, { gap = props.gap or 10 })
    end,
  }
end

Layout.Register("requestform", requestFrame())
Layout.Register("requestanswer", requestFrame())
