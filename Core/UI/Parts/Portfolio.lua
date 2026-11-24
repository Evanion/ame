-- Widgets only the Portfolio tab needs (Sell, Auctions):
--
--   gamebutton { label, call = "post" | "cancel", payload?, action?, variant? }
--       a button that makes the game's call itself, from the click (the game wants a click or key press for each
--       post and cancel), then dispatches action with { ok, message, payload } to report it
--   debutton   { label, bag?, slot?, action?, variant? }
--       Disenchant on the item in bag / slot: a secure button (the game only casts from one), drawn as a button
--   menubutton { label, options = { {key, label}, ... }, selected?, action? }
--       "24 h ▾": a menu of options (the game's menu where it has one; else each click takes the next); action
--       gets { key }
local _, ns = ...

local Layout, Kit = ns.Layout, ns.Kit

local base = Layout.Get("button")

local function dispatch(ctx, action, payload)
  if action and ctx then
    ctx:Dispatch(action, payload)
  end
end

-- the calls a gamebutton can make (Core/PortfolioPage.lua)
local CALLS = {
  post = function(p)
    return ns.PortfolioPage.Post(p)
  end,
  cancel = function(p)
    return ns.PortfolioPage.Cancel(p)
  end,
}
ns.PortfolioPage.CALLS = CALLS

Layout.Register("gamebutton", {
  props = { label = "string", call = "string", payload = "any?", action = "string?", variant = "string?" },
  create = function(parent, ctx)
    local b = base.create(parent, ctx)
    b:SetScript("OnClick", function(self)
      local p = self.gprops
      if not p or self.variant == "disabled" then
        return
      end
      local fn = CALLS[p.call]
      local ok, done, message = false, false, nil
      if fn then
        ok, done, message = pcall(fn, p.payload)
      end
      if not ok then
        message, done = tostring(done), false
      end
      dispatch(ctx, p.action, { ok = done and true or false, message = message, payload = p.payload })
    end)
    return b
  end,
  update = function(b, p, ctx, item)
    b.gprops = p
    base.update(b, { label = p.label, variant = p.variant }, ctx, item)
  end,
  size = base.size,
})

-- ------------------------------------------------------------------------------------------------ disenchant

local DISENCHANT = 13262

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and name then
      return name
    end
  end
  if GetSpellInfo then
    local ok, name = pcall(GetSpellInfo, id)
    if ok and name then
      return name
    end
  end
  return nil
end

-- does this character know Disenchant? (true where the client can't say)
local function knows(id)
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, id)
    if ok then
      return v and true or false
    end
  end
  if IsSpellKnown then
    local ok, v = pcall(IsSpellKnown, id)
    if ok then
      return v and true or false
    end
  end
  return true
end

local function locked()
  return InCombatLockdown and InCombatLockdown() or false
end

Layout.Register("debutton", {
  props = { label = "string", bag = "number?", slot = "number?", action = "string?", variant = "string?" },
  create = function(parent, ctx)
    local b = base.create(parent, ctx)
    b:SetScript("OnClick", nil)
    local s = CreateFrame("Button", nil, b, "SecureActionButtonTemplate")
    s:SetAllPoints(b)
    if s.RegisterForClicks then
      s:RegisterForClicks("AnyUp", "AnyDown")
    end
    s:SetScript("OnEnter", function()
      local fn = b:GetScript("OnEnter")
      if fn then
        fn(b)
      end
    end)
    s:SetScript("OnLeave", function()
      local fn = b:GetScript("OnLeave")
      if fn then
        fn(b)
      end
    end)
    s:SetScript("PostClick", function()
      local p = b.dprops
      if p then
        dispatch(ctx, p.action, { bag = p.bag, slot = p.slot })
      end
    end)
    b.secure = s
    return b
  end,
  update = function(b, p, ctx, item)
    b.dprops = p
    local name = spellName(DISENCHANT)
    local usable = name and p.bag and p.slot and p.variant ~= "disabled" and knows(DISENCHANT)
    base.update(b, { label = p.label, variant = usable and (p.variant or "primary") or "disabled" }, ctx, item)
    if not locked() then
      local s = b.secure
      if usable then
        s:SetAttribute("type", "macro")
        s:SetAttribute("macrotext", ("/cast %s\n/use %d %d"):format(name, p.bag, p.slot))
        s:Show()
      else
        s:SetAttribute("type", nil)
        s:Hide()
      end
    end
  end,
  size = base.size,
})

-- ------------------------------------------------------------------------------------------------ menu button

local function nextKey(options, selected)
  for i, o in ipairs(options) do
    if o[1] == selected then
      return (options[i % #options + 1] or options[1])[1]
    end
  end
  return options[1] and options[1][1]
end

Layout.Register("menubutton", {
  props = { label = "string", options = "table", selected = "string?", action = "string?", variant = "string?" },
  create = function(parent, ctx)
    local b = base.create(parent, ctx)
    b:SetScript("OnClick", function(self)
      local p = self.mprops
      if not p or #p.options == 0 then
        return
      end
      if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(self, function(_, root)
          for _, o in ipairs(p.options) do
            root:CreateRadio(o[2], function()
              return o[1] == p.selected
            end, function()
              dispatch(ctx, p.action, { key = o[1] })
            end)
          end
        end)
      else
        dispatch(ctx, p.action, { key = nextKey(p.options, p.selected) })
      end
    end)
    return b
  end,
  update = function(b, p, ctx, item)
    b.mprops = p
    base.update(b, { label = p.label .. " ▾", variant = p.variant }, ctx, item)
  end,
  size = base.size,
})
