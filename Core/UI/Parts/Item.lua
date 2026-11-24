-- Widgets only the Item page (and Market's Overview) need.
--
--   itemhead { item?, sub?, compact? }       the item's icon, its name as a link (quality colour, tooltip,
--                                            Shift-click) and the subtitle under it
--   itemmenu { label, entries = { { key, label, checked?, item?, separator? }, ... }, action?, variant? }
--     a button that opens a menu (Add to a shopping list ▾, Watching ▾, Alert ▾, 7 days ▾); picking an entry
--     dispatches action with { key = entry.key }
local _, ns = ...

local Layout, Kit, W = ns.Layout, ns.Kit, ns.Widgets

local function textWidth(fs)
  return math.ceil(fs:GetStringWidth() or 0)
end

-- ------------------------------------------------------------------------------------------------ item head

Layout.Register("itemhead", {
  props = { item = "any?", sub = "string?", compact = "boolean?" },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.iconBox = CreateFrame("Button", nil, f, "BackdropTemplate")
    Kit.Box(f.iconBox, "control", "controlLine")
    f.icon = f.iconBox:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    f.iconBox:SetScript("OnEnter", function(self)
      local key = f.props and f.props.item
      local link = key and ns.ItemCache and ns.ItemCache.Link(key)
      if link and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
      end
    end)
    f.iconBox:SetScript("OnLeave", function()
      if GameTooltip then
        GameTooltip:Hide()
      end
    end)
    f.iconBox:SetScript("OnClick", function()
      -- the page is the item's already: only a modified click (link it in chat, try it on) does anything
      local key = f.props and f.props.item
      local link = key and ns.ItemCache and ns.ItemCache.Link(key)
      local modified = IsModifiedClick and (IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP"))
      if link and modified and HandleModifiedItemClick then
        HandleModifiedItemClick(link)
      end
    end)
    f.link = W.ItemLink(f, { kit = true, icon = 0 })
    f.sub = Kit.Text(f, { size = 11, color = "dim" })
    if f.sub.SetWordWrap then
      f.sub:SetWordWrap(false)
    end
    return f
  end,
  update = function(f, p)
    f.props = p
    local size = p.compact and 28 or 36
    f.iconBox:SetSize(size, size)
    f.iconBox:ClearAllPoints()
    f.iconBox:SetPoint("LEFT", 0, 0)
    local _, _, _, icon = W.ItemInfo(p.item or 0)
    f.icon:SetTexture(icon or 134400)
    f.icon:SetShown(p.item ~= nil)
    if f.link.SetFont then
      f.link:SetFont(p.compact and 15 or 17, true)
    end
    f.link:SetItem(p.item or false)
    f.link:ClearAllPoints()
    f.link:SetPoint("TOPLEFT", f.iconBox, "TOPRIGHT", 10, 1)
    f.link:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.link:SetHeight(p.compact and 18 or 22)
    f.sub:ClearAllPoints()
    f.sub:SetPoint("BOTTOMLEFT", f.iconBox, "BOTTOMRIGHT", 10, 0)
    f.sub:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.sub:SetText(p.sub or "")
  end,
  size = function(_, p)
    return 300, p.compact and 30 or 38
  end,
})

-- ------------------------------------------------------------------------------------------------ menu button

Layout.Register("itemmenu", {
  props = { label = "string", entries = "table", action = "string?", variant = "string?" },
  create = function(parent, ctx)
    local b = Kit.Button(parent)
    b:SetScript("OnClick", function(self)
      local p = self.props
      if not p or self.variant == "disabled" or not W.Menu then
        return
      end
      local list = {}
      for _, e in ipairs(p.entries) do
        if e.separator then
          list[#list + 1] = { separator = true }
        else
          list[#list + 1] = {
            text = e.label,
            item = e.item,
            checked = e.checked,
            func = function()
              if p.action then
                ctx:Dispatch(p.action, { key = e.key })
              end
            end,
          }
        end
      end
      W.Menu(self, list)
    end)
    return b
  end,
  update = function(b, p)
    b.props, b.variant = p, p.variant or "normal"
    b.label:SetText(p.label)
    if b.SetEnabled then
      b:SetEnabled(p.variant ~= "disabled")
    end
    local leave = b:GetScript("OnLeave")
    if leave then
      leave(b)
    end
  end,
  size = function(b)
    return math.max(textWidth(b.label) + 20, 24), 24
  end,
})
