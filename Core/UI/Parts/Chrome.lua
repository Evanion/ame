-- The window's chrome as widgets (the canvas's TitleBar, StatusBar, AHTabs and FrameTitle):
--
--   titlebar  { tabs = { {key, label}, ... }, active?, house, houses = { {key, label}, ... }, compact?, ah?,
--               back?, forward?, unread?, settings? }
--             actions: tab {key}, back, forward, house {key}, scan, gameAH, settings, bell, close
--   statusbar { text?, right? }
--   ahtabs    { active? "buy" | "sell" | "auctions" }      action: ahtab {key}
--   frametitle { title, note?, close? }                    action: close
local _, ns = ...

local Layout, Kit, W = ns.Layout, ns.Kit, ns.Widgets
local L = ns.L

-- the boards' line icons (media/Icons, drawn by scripts/make-ui-icons.lua): white, tinted the tab colour, white on
-- hover and while on (the cog on Settings), as the boards' .ico and .ico.on
local ICONS = "Interface\\AddOns\\AzerothMercantileExchange\\media\\Icons\\"

local function tint(b, name)
  local c = Kit.C(name)
  b.icon:SetVertexColor(c[1], c[2], c[3], 1)
end

local function iconButton(parent, icon, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(24, 24)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(ICONS .. icon)
  b.icon:SetSize(size or 15, size or 15)
  b.icon:SetPoint("CENTER", 0, 0)
  tint(b, "tab")
  b:SetScript("OnEnter", function(self)
    tint(self, "white")
  end)
  b:SetScript("OnLeave", function(self)
    tint(self, self.on and "white" or "tab")
  end)
  return b
end

-- the logo: AME's own icon (the candles of the minimap button and the addon list)
local function logo(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(16, 16)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetAllPoints()
  f.icon:SetTexture(ns.ICON)
  return f
end

-- ------------------------------------------------------------------------------------------------ title bar

Layout.Register("titlebar", {
  props = {
    tabs = "table",
    active = "string?",
    house = "string",
    houses = "table?",
    compact = "boolean?",
    ah = "boolean?",
    back = "boolean?",
    forward = "boolean?",
    unread = "number?",
    settings = "boolean?",
  },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent)
    Kit.Chrome(f)
    f.edge = Kit.Line(f, "BOTTOM", "frameLit")
    f.mark = f:CreateTexture(nil, "ARTWORK") -- the accent edge on the left
    f.mark:SetPoint("TOPLEFT")
    f.mark:SetPoint("BOTTOMLEFT")
    f.mark:SetWidth(4)
    f.brand = Kit.Text(f, { font = "display", size = 15, color = "heading" })
    f.logo = logo(f)
    f.logo:SetPoint("LEFT", 14, 0)
    f.brand:SetPoint("LEFT", f.logo, "RIGHT", 8, 0)
    local function act(name, payload)
      return function()
        ctx:Dispatch(name, payload)
      end
    end
    -- Back and Forward: the boards' line chevrons (media/Icons), tinted as the button's label would be
    local function chevron(name)
      local b = Kit.Button(f)
      b.icon = b:CreateTexture(nil, "ARTWORK")
      b.icon:SetTexture(ICONS .. name)
      b.icon:SetSize(12, 12)
      b.icon:SetPoint("CENTER", 0, 0)
      b:SetSize(26, 24)
      return b
    end
    f.back = chevron("Back")
    f.back:SetScript("OnClick", act("back"))
    f.forward = chevron("Forward")
    f.forward:SetScript("OnClick", act("forward"))
    f.market = Kit.Button(f)
    f.market:SetHeight(24)
    f.market:SetScript("OnClick", function(self)
      local entries = {}
      for _, h in ipairs(f.props.houses or {}) do
        entries[#entries + 1] = {
          text = h[2],
          checked = h[2] == f.props.house,
          func = act("house", { key = h[1] }),
        }
      end
      if #entries > 1 and W.Menu then
        W.Menu(self, entries)
      end
    end)
    f.scan = Kit.Button(f)
    f.scan:SetHeight(24)
    -- Full scan, or folded (a narrow window, or a title bar too full): "AH ▾", a menu of Full scan and the swap
    f.scan:SetScript("OnClick", function(self)
      if not f.foldAH then
        return ctx:Dispatch("scan")
      end
      local Menu = ns.SettingsMenu
      if Menu then
        Menu.Open(self, { { value = "scan", label = L["Full scan"] }, { value = "gameAH", label = L["Use the game's AH"] } }, nil, function(v)
          ctx:Dispatch(v)
        end)
      end
    end)
    f.gameAH = Kit.Button(f)
    f.gameAH:SetHeight(24)
    f.gameAH:SetScript("OnClick", act("gameAH"))
    f.close = iconButton(f, "Close", 13)
    f.close:SetPoint("RIGHT", -8, 0)
    f.close:SetScript("OnClick", act("close"))
    f.bell = iconButton(f, "Bell", 15)
    f.bell:SetPoint("RIGHT", f.close, "LEFT", -4, 0)
    f.bell:SetScript("OnClick", act("bell"))
    f.badge = CreateFrame("Frame", nil, f.bell, "BackdropTemplate")
    f.badge:SetSize(14, 14)
    f.badge:SetPoint("TOPRIGHT", 4, 2)
    Kit.Box(f.badge, "badge", false)
    f.badge.text = Kit.Text(f.badge, { size = 9, justify = "CENTER", color = "white" })
    f.badge.text:SetPoint("CENTER", 0, 0)
    f.cog = iconButton(f, "Cog", 15)
    f.cog:SetPoint("RIGHT", f.bell, "LEFT", -4, 0)
    f.cog:SetScript("OnClick", act("settings"))
    f.tabs = {}
    f.measure = Kit.Text(f, { font = "display", size = 13 }) -- a tab's width before it is drawn
    f.measure:Hide()
    -- what fits depends on the width: a resize draws it again
    f:SetScript("OnSizeChanged", function(self)
      if self.props then
        self:Draw()
      end
    end)
    Kit.OnTheme(function()
      if f.props then
        f:Draw()
      end
    end)
    function f:Draw()
      local p = self.props
      Kit.Fill(self.mark, Kit.Accent())
      -- what fits: the left side (brand, Back, Forward, market, the AH's buttons) and the tabs and icons on the
      -- right must not meet. Too full: the name folds to "AME", then the AH's two buttons to the "AH ▾" menu.
      local fullName = Kit.Color(Kit.Faction(), "Azeroth") .. " Mercantile Exchange"
      local function width(fs, text)
        fs:SetText(text)
        return math.ceil(fs:GetStringWidth() or 0)
      end
      local tabsW = 8 + 24 * 3 + 8 + 4
      for _, t in ipairs(p.tabs) do
        tabsW = tabsW + width(self.measure, t[2]) + 22
      end
      local marketW = width(self.market.label, p.house .. ((p.houses and #p.houses > 1) and " ▾" or "")) + 20
      local fixedW = 14 + 16 + 8 + 12 + 26 + 4 + 26 + 6 + marketW + 16
      local ahFull = p.ah and (width(self.scan.label, L["Full scan"]) + 26 + width(self.gameAH.label, L["Use the game's AH"]) + 26) or 0
      local ahFolded = p.ah and (width(self.scan.label, L["AH ▾"]) + 26) or 0
      local room = (self.GetWidth and self:GetWidth() or 0) - tabsW - fixedW
      local nameW = width(self.brand, fullName)
      local shortW = width(self.brand, "AME")
      local short = p.compact or room > 0 and nameW + ahFull > room
      self.foldAH = p.compact or (room > 0 and (short and shortW or nameW) + ahFull > room) or false
      self.brand:SetText(short and "AME" or fullName)
      self.back:ClearAllPoints()
      self.back:SetPoint("LEFT", self.brand, "RIGHT", 12, 0)
      self.back.variant = p.back and "normal" or "disabled"
      self.forward:ClearAllPoints()
      self.forward:SetPoint("LEFT", self.back, "RIGHT", 4, 0)
      self.forward.variant = p.forward and "normal" or "disabled"
      self.market.label:SetText(p.house .. ((p.houses and #p.houses > 1) and " ▾" or ""))
      self.market:SetWidth(math.ceil(self.market.label:GetStringWidth() or 0) + 20)
      self.market:ClearAllPoints()
      self.market:SetPoint("LEFT", self.forward, "RIGHT", 6, 0)
      local last = self.market
      for _, b in ipairs({ self.back, self.forward, self.market, self.scan, self.gameAH }) do
        b:GetScript("OnLeave")(b)
      end
      self.scan:SetShown(p.ah and true or false)
      self.gameAH:SetShown(p.ah and not self.foldAH and true or false)
      if p.ah then
        self.scan.label:SetText(self.foldAH and L["AH ▾"] or L["Full scan"])
        self.scan:SetWidth(math.ceil(self.scan.label:GetStringWidth() or 0) + 20)
        self.scan:ClearAllPoints()
        self.scan:SetPoint("LEFT", last, "RIGHT", 6, 0)
        last = self.scan
        if not self.foldAH then
          self.gameAH.label:SetText(L["Use the game's AH"])
          self.gameAH:SetWidth(math.ceil(self.gameAH.label:GetStringWidth() or 0) + 20)
          self.gameAH:ClearAllPoints()
          self.gameAH:SetPoint("LEFT", self.scan, "RIGHT", 6, 0)
        end
      end
      -- the tabs, from the right (left of the cog)
      local anchor = self.cog
      for i = #p.tabs, 1, -1 do
        local t = p.tabs[i]
        local b = self.tabs[i]
        if not b then
          b = CreateFrame("Button", nil, self)
          b.text = Kit.Text(b, { font = "display", size = 13, justify = "CENTER" })
          b.text:SetPoint("CENTER", 0, 0)
          b.line = Kit.Line(b, "BOTTOM", Kit.Accent(), 2)
          b.glow = b:CreateTexture(nil, "BACKGROUND")
          b.glow:SetAllPoints()
          b:SetScript("OnClick", function(btn)
            ctx:Dispatch("tab", { key = btn.key })
          end)
          self.tabs[i] = b
        end
        b.key = t[1]
        b.text:SetText(t[2])
        local on = t[1] == p.active
        Kit.SetColor(b.text, on and "white" or "tab")
        Kit.Fill(b.line, Kit.Accent())
        b.line:SetShown(on)
        local a = Kit.Accent()
        b.glow:SetColorTexture(a[1], a[2], a[3], on and 0.14 or 0)
        b:SetSize(math.ceil(b.text:GetStringWidth() or 0) + 20, 40)
        b:ClearAllPoints()
        b:SetPoint("RIGHT", anchor, "LEFT", anchor == self.cog and -8 or -2, 0)
        b:Show()
        anchor = b
      end
      for i = #p.tabs + 1, #self.tabs do
        self.tabs[i]:Hide()
      end
      self.cog.on = p.settings and true or false
      tint(self.cog, self.cog.on and "white" or "tab")
      local n = p.unread or 0
      self.badge:SetShown(n > 0)
      self.badge.text:SetText(n > 9 and "9+" or tostring(n))
    end
    return f
  end,
  update = function(f, p)
    f.props = p
    f:Draw()
  end,
  size = function()
    return 0, 40
  end,
})

-- ------------------------------------------------------------------------------------------------ status bar

Layout.Register("statusbar", {
  props = { text = "string?", right = "string?" },
  create = function(parent)
    local f = CreateFrame("Frame", nil, parent)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Fill(bg, "chromeBottom")
    Kit.Line(f, "TOP", "frame")
    f.text = Kit.Text(f, { size = 11, color = "dim" })
    f.text:SetPoint("LEFT", 12, 0)
    f.right = Kit.Text(f, { size = 11, color = "dim", justify = "RIGHT" })
    f.right:SetPoint("RIGHT", -12, 0)
    f.text:SetPoint("RIGHT", f.right, "LEFT", -12, 0)
    return f
  end,
  update = function(f, p)
    f.text:SetText(p.text or "")
    f.right:SetText(p.right or "")
  end,
  size = function()
    return 0, 26
  end,
})

-- ------------------------------------------------------------------------------------------------ the AH's tabs

Layout.Register("ahtabs", {
  props = { active = "string?" },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent)
    f.tabs = {}
    for i, t in ipairs({ { "buy", L["Buy"] }, { "sell", L["Sell"] }, { "auctions", L["Auctions"] } }) do
      local b = CreateFrame("Button", nil, f, "BackdropTemplate")
      b.key = t[1]
      b.text = Kit.Text(b, { font = "display", size = 13, justify = "CENTER" })
      b.text:SetPoint("CENTER", 0, 1)
      b.text:SetText(t[2])
      b.line = Kit.Line(b, "BOTTOM", Kit.Accent(), 2)
      b:SetSize(math.ceil(b.text:GetStringWidth() or 0) + 36, 30)
      b:SetPoint("TOPLEFT", f.tabs[i - 1] or f, f.tabs[i - 1] and "TOPRIGHT" or "TOPLEFT", f.tabs[i - 1] and 2 or 16, 0)
      b:SetScript("OnClick", function(self)
        ctx:Dispatch("ahtab", { key = self.key })
      end)
      f.tabs[i] = b
    end
    return f
  end,
  update = function(f, p)
    for _, b in ipairs(f.tabs) do
      local on = b.key == p.active
      Kit.Box(b, on and Kit.Selected() or "chromeBottom", on and "frameLit" or "frame")
      Kit.SetColor(b.text, on and "white" or "tab")
      Kit.Fill(b.line, Kit.Accent())
      b.line:SetShown(on)
    end
  end,
  size = function()
    return 0, 32
  end,
})

-- ------------------------------------------------------------------------------------------------ frame title

Layout.Register("frametitle", {
  props = { title = "string", note = "string?", close = "boolean?" },
  create = function(parent, ctx)
    local f = CreateFrame("Frame", nil, parent)
    f.title = Kit.Text(f, { font = "display", size = 15, color = "heading" })
    f.title:SetPoint("LEFT", 0, 0)
    f.note = Kit.Text(f, { size = 11, color = "dim" })
    f.note:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
    f.close = iconButton(f, "Close", 12)
    f.close:SetPoint("RIGHT", 4, 0)
    f.close:SetScript("OnClick", function()
      ctx:Dispatch("close")
    end)
    return f
  end,
  update = function(f, p)
    f.title:SetText(p.title)
    f.note:SetText(p.note or "")
    f.close:SetShown(p.close ~= false)
  end,
  size = function()
    return 0, 22
  end,
})
