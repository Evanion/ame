-- The redesigned window (feature/redesign): one frame drawn by the layout engine. The chrome (title bar, status row,
-- the auction house's tabs) is the same for every screen; the body is the current screen's tree.
--
--   App.Screen(id, def)   def = { tab = "home", Build = function(app, params) -> tree,
--                                 actions = { name = function(app, payload) }, Status = function(app) -> text,
--                                 Title = function(app, params) -> text (history labels) }
--   App:Go(id, params)    open a screen (it goes on the history; Back and Forward walk it)
--   App:Render()          draw again from state (coalesce with App:Redraw())
--   App:Toggle(), App:Show(), App:Hide()
--
-- Until the cut-over the old window stays the default: Settings.newWindow (or /ame new) opens this one instead.
local _, ns = ...
local L = ns.L

local Layout, Kit = ns.Layout, ns.Kit

local App = { screens = {}, back = {}, ahead = {}, actions = {} }
ns.App = App

App.W, App.H = 1100, 640 -- the boards' size
App.MIN_W, App.MIN_H = 760, 460
App.COMPACT_W = 900 -- below this the title bar folds (the narrow boards)
App.HISTORY = 50

App.TABS = {
  { "home", L["Home"] },
  { "market", L["Market"] },
  { "item", L["Item"] },
  { "crafting", L["Crafting"] },
  { "guild", L["Guild"] },
  { "portfolio", L["Portfolio"] },
  { "guide", L["Guide"] },
}

function App.Screen(id, def)
  def.id = id
  App.screens[id] = def
  return def
end

-- a tab's screen: the first screen registered for it, or the placeholder while it's being built
function App:TabScreen(tab)
  if App.screens[tab] then
    return tab
  end
  for id, s in pairs(App.screens) do
    if s.tab == tab and not s.sub then
      return id
    end
  end
  return tab -- not built yet: the placeholder draws it, under its own name
end

App.Screen("soon", {
  Build = function(app, params)
    return {
      id = "soon",
      type = "panel",
      props = { title = L["Being rebuilt"] },
      children = {
        {
          id = "soon.text",
          type = "text",
          props = {
            text = L["This screen is part of the redesign and isn't built yet. /ame new switches back to the current window."],
            color = "dim",
            wrap = true,
          },
          meta = { h = 40 },
        },
      },
    }
  end,
})

-- ------------------------------------------------------------------------------------------------ state

function App:Current()
  return self.state and self.state.screen, self.state and self.state.params or {}
end

function App:AtAH()
  return ns.AME and ns.AME.ahOpen and true or false
end

function App:House()
  return self.viewHouse or (ns.AME and ns.AME.CurrentHouse and ns.AME:CurrentHouse()) or "Horde"
end

function App:Shard()
  return ns.ShardKey(ns.AME:MarketRealmName(), self:House())
end

-- the accent: the viewed market's, unless Settings picks one ("Horde" | "Alliance" | "Neutral")
local function themeKey(house)
  local picked = ns.Settings and ns.Settings:Get("theme")
  if picked and picked ~= "auto" then
    house = picked
  end
  return house == "Neutral" and "goblin" or tostring(house):lower()
end

-- open a screen; replace: don't put the one you leave on the history (a filter change inside a screen)
function App:Go(id, params, replace)
  if self.state and not replace then
    table.insert(self.back, self.state)
    if #self.back > App.HISTORY then
      table.remove(self.back, 1)
    end
    self.ahead = {}
  end
  self.state = { screen = id, params = params or {} }
  self:Show()
  self:Render()
end

function App:Back()
  local prev = table.remove(self.back)
  if prev then
    table.insert(self.ahead, self.state)
    self.state = prev
    self:Render()
  end
end

function App:Forward()
  local nxt = table.remove(self.ahead)
  if nxt then
    table.insert(self.back, self.state)
    self.state = nxt
    self:Render()
  end
end

-- hand a table its rows: a list, or a function returning one (tables read ctx.sources[name] when drawn)
function App:Source(name, rows)
  self:Create()
  self.ctx.sources[name] = rows
end

-- change the current screen's params (no history step)
function App:Set(params)
  local s = self.state
  if not s then
    return
  end
  for k, v in pairs(params) do
    s.params[k] = v
  end
  self:Render()
end

-- ------------------------------------------------------------------------------------------------ actions

App.actions.tab = function(app, p)
  app:Go(app:TabScreen(p.key))
end
App.actions.back = function(app)
  app:Back()
end
App.actions.forward = function(app)
  app:Forward()
end
App.actions.close = function(app)
  app:Hide()
end
App.actions.house = function(app, p)
  app.viewHouse = p.key
  app:Render()
end
App.actions.settings = function(app)
  local id = app:Current()
  if id == "settings" then
    app:Back()
  else
    app:Go("settings")
  end
end
App.actions.bell = function(app)
  app:Go("notifications")
end
App.actions.scan = function()
  if ns.ScanButton and ns.ScanButton.Start then
    ns.ScanButton.Start()
  elseif ns.AME and ns.AME.FullScan then
    ns.AME:FullScan()
  end
end
App.actions.gameAH = function(app)
  if ns.AHTakeover then
    ns.AHTakeover.UseGame() -- the game's window back in sight, this one closed; remembered for the next visit
  else
    app:Hide()
  end
end
App.actions.ahtab = function(app, p)
  local map = { buy = "market", sell = "sell", auctions = "auctions" }
  app:Go(app:TabScreen(map[p.key] or "market"))
end

local handlers = setmetatable({}, {
  __index = function(_, name)
    local id = App:Current()
    local s = id and App.screens[id]
    local fn = s and s.actions and s.actions[name]
    if fn then
      return function(payload)
        fn(App, payload)
      end
    end
    fn = App.actions[name]
    return fn and function(payload)
      fn(App, payload)
    end
  end,
})

-- ------------------------------------------------------------------------------------------------ the tree

function App:Houses()
  local AME, out = ns.AME, {}
  if not (AME and AME.MarketRealmName) then
    return out
  end
  local realm, current = AME:MarketRealmName(), AME:CurrentHouse()
  for _, house in ipairs({ "Horde", "Alliance", "Neutral" }) do
    local shard = ns.ShardKey(realm, house)
    if house == current or (AME.HasData and AME:HasData(shard)) then
      out[#out + 1] = { house, ns.ShardLabel and ns.ShardLabel(shard) or house }
    end
  end
  return out
end

function App:Tree()
  local id, params = self:Current()
  local s = App.screens[id] or App.screens.soon
  local ok, body = pcall(s.Build, self, params)
  if not ok then
    body = {
      id = "error",
      type = "panel",
      props = { title = L["Something went wrong"] },
      children = { { id = "error.text", type = "text", props = { text = tostring(body), color = "bad", wrap = true } } },
    }
  end
  body.meta = body.meta or {}
  body.meta.grow = 1
  local unread = ns.AME and ns.AME.notices and ns.AME.notices.Unread and ns.AME.notices:Unread() or 0
  local house = self:House()
  local shard = ns.AME and ns.AME.MarketRealmName and self:Shard()
  local status = s.Status and s.Status(self, params) or ""
  return {
    id = "app",
    type = "column",
    children = {
      {
        id = "app.title",
        type = "titlebar",
        props = {
          tabs = App.TABS,
          active = s.tab or id,
          house = shard and ns.ShardLabel and ns.ShardLabel(shard) or house,
          houses = self:Houses(),
          compact = self.compact,
          ah = self:AtAH(),
          back = #self.back > 0,
          forward = #self.ahead > 0,
          unread = unread,
          settings = id == "settings",
        },
        meta = { h = 40 },
      },
      { id = "app.body", type = "fill", props = { pad = 12 }, meta = { grow = 1 }, children = { body } },
      { id = "app.status", type = "statusbar", props = { text = status, right = "v" .. tostring(ns.VERSION) }, meta = { h = 26 } },
    },
  }
end

-- ------------------------------------------------------------------------------------------------ the frame

local function saved()
  AME_DB.app = AME_DB.app or {}
  return AME_DB.app
end

function App:Create()
  if self.frame then
    return self.frame
  end
  local f = CreateFrame("Frame", "AMEWindow", UIParent, "BackdropTemplate")
  Kit.Box(f, "bg", "frame")
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(App.MIN_W, App.MIN_H)
  end
  f:EnableMouse(true)
  local pos = saved()
  f:SetSize(pos.w or App.W, pos.h or App.H)
  if pos.x then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
  else
    f:SetPoint("CENTER")
  end
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    App:SavePlace()
  end)
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    App:SavePlace()
  end)
  f:SetScript("OnSizeChanged", function(self, w)
    local compact = (w or App.W) < App.COMPACT_W
    if compact ~= App.compact then
      App.compact = compact
      App:Redraw()
    end
  end)
  table.insert(_G.UISpecialFrames or {}, "AMEWindow")
  -- closed while it is the auction house: the visit ends with it (AHTakeover)
  f:HookScript("OnHide", function()
    if ns.AHTakeover then
      ns.AHTakeover.WindowHidden()
    end
  end)
  f:Hide()
  self.frame = f
  self.compact = f:GetWidth() < App.COMPACT_W
  self.ctx = Layout.Context(handlers, { app = self, sources = {} })
  -- the screen sits 1 px inside the window, so the window's lit border runs round the title bar and status row too
  local inner = CreateFrame("Frame", nil, f)
  inner:SetPoint("TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", -1, 1)
  self.inner = inner
  self.renderer = Layout.Renderer(inner, self.ctx)
  -- the resize grip stays above the screen (it was made first, so the screen would cover it)
  grip:SetFrameLevel(inner:GetFrameLevel() + 50)
  f:SetScale(ns.Settings and ns.Settings:Get("windowScale") or 1)
  -- the bell's count and the notifications screen follow the notices
  if ns.AME and ns.AME.notices and ns.AME.notices.OnChange then
    ns.AME.notices:OnChange(function()
      App:Redraw()
    end)
  end

  -- the auction house's own tabs hang under the window while it's open
  local tabs = CreateFrame("Frame", nil, f)
  tabs:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 1)
  tabs:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 1)
  tabs:SetHeight(32)
  self.ahFrame = tabs
  self.ahRenderer = Layout.Renderer(tabs, self.ctx)
  Kit.SetFaction(UnitFactionGroup and UnitFactionGroup("player"))
  return f
end

function App:SavePlace()
  local f, pos = self.frame, saved()
  pos.x, pos.y = f:GetLeft(), f:GetTop()
  pos.w, pos.h = f:GetWidth(), self.grown or f:GetHeight() -- the AH's extra height isn't yours to keep
end

-- taller at the auction house (the Buy card, the price ladder and the AH's tabs need the room); the size you chose
-- comes back when you leave. Never taller than the screen.
App.AH_H = 830
function App:FitAH(at)
  local f = self.frame
  if at and not self.grown then
    local room = UIParent and UIParent.GetHeight and UIParent:GetHeight() or App.AH_H
    local want = math.min(App.AH_H, (room or App.AH_H) / (f:GetScale() or 1) - 40)
    local h = f:GetHeight() or App.H
    if want > h then
      self.grown = h
      f:SetHeight(want)
    end
  elseif not at and self.grown then
    f:SetHeight(self.grown)
    self.grown = nil
  end
end

function App:Render()
  if not (self.frame and self.frame:IsShown()) then
    return
  end
  if not self.state then
    self.state = { screen = App:TabScreen("home"), params = {} }
  end
  Kit.SetTheme(themeKey(self:House()))
  local tree = self:Tree()
  if ns.Dev and ns.Dev.enabled then
    for _, problem in ipairs(Layout.Validate(tree)) do
      ns.Dev.Warn("layout: " .. problem)
    end
  end
  local at = self:AtAH()
  self:FitAH(at)
  self.renderer:Render(tree)
  self.ahFrame:SetShown(at)
  if at then
    local id = self:Current()
    local s = App.screens[id] or {}
    local active = s.ahTab or (s.tab == "market" or s.tab == "item") and "buy" or s.tab == "portfolio" and "sell" or nil
    self.ahRenderer:Render({ id = "ah.tabs", type = "ahtabs", props = { active = active } })
  end
end

-- draw again on the next frame (several changes in one event draw once)
function App:Redraw()
  if self.pending then
    return
  end
  self.pending = true
  local function go()
    self.pending = false
    self:Render()
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, go)
  else
    go()
  end
end

function App:Show()
  self:Create()
  if not self.frame:IsShown() then
    self.frame:Show()
  end
  self:Render()
end

function App:Hide()
  if self.frame then
    self.frame:Hide()
  end
end

function App:Toggle()
  self:Create()
  if self.frame:IsShown() then
    self:Hide()
  else
    self:Show()
  end
end

-- the development switch: /ame new
function App.Enabled()
  return ns.Settings and ns.Settings:Get("newWindow") and true or false
end
