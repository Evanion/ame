-- The bell's notifications (board NotifyPanel): what AME told you in passing (Core/Notices.lua), newest first, the
-- unread ones lit. A panel under the bell, over the screen you are on: opening it marks them read; a click on one
-- opens what it is about; Clear all empties it. The bell again, a click elsewhere or Esc closes it.
--
--   Notify.Row(e, now, unread) -> actionlist row     one notice as a row (pill, title with item links, sub with age)
--   Notify.Rows(list, now, isUnread, max) -> rows, older   newest first; older: how many didn't fit
--   Notify.Target(e) -> screen, params               what a click opens
--   Notify.Key(e) -> "kind:at:itemID"                a row's key
--
-- A notice is { kind, text, itemID?, who?, at } (Core/Notices.lua). The kinds and what they show:
--   alert    a price alert fired: the item, then text ("dropped to 62g (alert at 65g)")
--   request  who asks to share prices with you          update  a newer AME is out: text the version, who has it
--   craft    a craft request: who, text ("asks for 5"), the item
--   sold     an auction sold: the item, then text ("sold for 12g")
--   undercut your auctions are undercut: text ("3 of your auctions are undercut"), the item
--   cooldown text ("Transmute is ready on Kke")         scan   text ("Zakzu's full scan was recorded")
local _, ns = ...
local L = ns.L

local App, Kit = ns.App, ns.Kit

local Notify = { ROW_H = 46, W = 380, H = 400 }
ns.NotifyScreen = Notify

local function ago(t, now)
  local W = ns.Widgets
  return W and W.Ago and W.Ago(t, now) or ""
end

function Notify.Key(e)
  return ("%s:%s:%s"):format(tostring(e.kind), tostring(e.at), tostring(e.itemID or e.who or ""))
end

-- pill, tone, title, sub (without the age) for each kind
local KINDS = {
  alert = function(e)
    return L["ALERT"], "warn", { { item = e.itemID }, " " .. (e.text or "") }
  end,
  request = function(e)
    return L["SHARING"], "link", L["%s wants to share auction prices with you"]:format(e.who or "?")
  end,
  update = function(e)
    return L["UPDATE"],
      "good",
      L["A newer version is out: %s"]:format(e.text or "?"),
      L["%s has it · update from CurseForge or your addon manager"]:format(e.who or "?")
  end,
  craft = function(e)
    local title = { (e.who or "?") .. " " .. (e.text or L["asks for"]) .. " " }
    if e.itemID then
      title[2] = { item = e.itemID }
    end
    return L["REQUEST"], Kit.Accent(), title
  end,
  sold = function(e)
    return L["SOLD"], "gold", { { item = e.itemID }, " " .. (e.text or "") }
  end,
  undercut = function(e)
    return L["AUCTIONS"], "bad", e.text or L["Your auctions are undercut"], e.itemID and { { item = e.itemID } } or nil
  end,
  cooldown = function(e)
    return L["COOLDOWN"], "good", e.text or ""
  end,
  scan = function(e)
    return L["SCAN"], nil, e.text or ""
  end,
}

-- one notice as an action list row; unread ones are lit
function Notify.Row(e, now, unread)
  local kind = KINDS[e.kind]
  local pill, tone, title, sub
  if kind then
    pill, tone, title, sub = kind(e)
  else
    pill, title = L["NOTE"], e.text or ""
  end
  if e.kind == "alert" and not e.itemID then
    title = e.text or ""
  end
  local when = ago(e.at, now)
  if sub then
    sub = type(sub) == "table" and sub or { sub }
    local parts = {}
    for i, s in ipairs(sub) do
      parts[i] = s
    end
    parts[#parts + 1] = " · " .. when
    sub = parts
  else
    sub = when
  end
  return { key = Notify.Key(e), pill = pill, tone = tone, title = title, sub = sub, selected = unread and true or nil }
end

-- newest first (list is Notices:List()), at most max of them
function Notify.Rows(list, now, isUnread, max)
  local rows = {}
  max = max or #list
  for i, e in ipairs(list) do
    if i > max then
      break
    end
    rows[i] = Notify.Row(e, now, isUnread(e))
  end
  return rows, math.max(0, #list - max)
end

function Notify.Target(e)
  local kind = e.kind
  if (kind == "alert" or kind == "sold") and e.itemID then
    return "item", { item = e.itemID }
  elseif kind == "undercut" then
    return "auctions", {}
  elseif kind == "request" or kind == "update" then
    return "sharing", {}
  elseif kind == "craft" then
    return "requests", {}
  elseif kind == "cooldown" then
    return "crafting", { filter = "ready" }
  elseif e.itemID then
    return "item", { item = e.itemID }
  end
  return nil
end

-- ------------------------------------------------------------------------------------------------ the panel

local function notices()
  return ns.AME and ns.AME.notices
end

-- as many rows as the panel holds: its height less its padding, heading, note and gaps
function Notify.Fit()
  local room = Notify.H - 24 - 22 - 34 - 12
  return math.max(3, math.floor(room / Notify.ROW_H))
end

-- the panel's tree; seenAt: what was unread when it opened stays lit while you look
function Notify.Tree(seenAt, now)
  local n = notices()
  local list = n and n:List() or {}
  local rows, older = Notify.Rows(list, now, function(e)
    return (e.at or 0) > seenAt
  end, Notify.Fit())
  if #rows == 0 then
    rows[1] = {
      key = "none",
      pill = "—",
      title = L["Nothing yet"],
      sub = L["Alerts, craft requests and news of a newer AME show up here"],
    }
  end
  local note =
    L["Click one to open what it is about. What shows here, and whether it also prints in chat or plays a sound, is set under Settings > Notifications."]
  if older > 0 then
    note = L["+ %d older."]:format(older) .. " " .. note
  end
  return {
    id = "notify",
    type = "column",
    props = { gap = 6, pad = 12 },
    children = {
      {
        id = "notify.head",
        type = "row",
        props = { align = "center" },
        meta = { h = 22 },
        children = {
          {
            id = "notify.title",
            type = "text",
            props = { text = L["Notifications"], font = "display", size = 14 },
            meta = { grow = 1 },
          },
          #list > 0 and {
            id = "notify.clear",
            type = "keyvalue",
            props = { text = L["Clear all"], action = "clearNotices" },
            meta = { w = 70 },
          } or { id = "notify.clear", type = "spacer", meta = { w = 70 } },
        },
      },
      {
        id = "notify.list",
        type = "noticelist",
        props = { bare = true, rows = rows, rowAction = "openNotice" },
        meta = { grow = 1 },
      },
      {
        id = "notify.note",
        type = "text",
        props = { text = note, color = "dim", size = 11, wrap = true },
        meta = { h = 34 },
      },
    },
  }
end

local function bell(app)
  local title = app.renderer and app.renderer:Frame("app.title")
  return title and title.bell
end

-- the panel's frame: over the screen, its top right under the bell
local function panel(app)
  if app.notifyPanel then
    return app.notifyPanel
  end
  local p = CreateFrame("Frame", nil, app.frame, "BackdropTemplate")
  Kit.Box(p, "bg", "frame")
  p:SetSize(Notify.W, Notify.H)
  p:SetFrameLevel((app.inner and app.inner:GetFrameLevel() or 1) + 100)
  p:EnableMouse(true)
  p:Hide()
  p.renderer = ns.Layout.Renderer(p, app.ctx)
  -- closes on a click elsewhere, like a menu
  p:SetScript("OnShow", function(self)
    pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
  end)
  p:SetScript("OnHide", function(self)
    pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
  end)
  p:SetScript("OnEvent", function(self)
    local b = bell(app)
    if not self:IsMouseOver() and not (b and b:IsMouseOver()) then
      self:Hide()
    end
  end)
  -- Esc closes the panel, not the window (out of combat: the key is passed on otherwise)
  if p.EnableKeyboard then
    p:EnableKeyboard(true)
    p:SetScript("OnKeyDown", function(self, key)
      local fight = InCombatLockdown and InCombatLockdown()
      if key == "ESCAPE" and not fight then
        if self.SetPropagateKeyboardInput then
          self:SetPropagateKeyboardInput(false)
        end
        self:Hide()
      elseif not fight and self.SetPropagateKeyboardInput then
        self:SetPropagateKeyboardInput(true)
      end
    end)
  end
  app.notifyPanel = p
  return p
end

function App:NotifyShown()
  return self.notifyPanel ~= nil and self.notifyPanel:IsShown()
end

-- draw the panel again (notices came or went while it shows)
function App:DrawNotify()
  local p = self.notifyPanel
  if not (p and p:IsShown()) then
    return
  end
  p.renderer:Render(Notify.Tree(p.seenAt or 0, GetServerTime and GetServerTime() or 0))
end

function App:OpenNotify()
  self:Show()
  local p = panel(self)
  local n = notices()
  local now = GetServerTime and GetServerTime() or 0
  p.seenAt = n and n.db and n.db.readAt or 0
  if n then
    n:MarkRead(now)
  end
  p:ClearAllPoints()
  local b = bell(self)
  if b then
    p:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 8, -6)
  else
    p:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -8, -40)
  end
  p:Show()
  self:DrawNotify()
end

function App:CloseNotify()
  if self.notifyPanel then
    self.notifyPanel:Hide()
  end
end

-- the bell: opens the panel, or closes it
App.actions.bell = function(app)
  if app:NotifyShown() then
    app:CloseNotify()
  else
    app:OpenNotify()
  end
end

App.actions.clearNotices = function(app)
  local n = notices()
  if n then
    n:Clear()
  end
  app:DrawNotify()
end

-- a click on a notice opens what it is about, and the panel closes
App.actions.openNotice = function(app, p)
  local n = notices()
  if not (n and p and p.key) then
    return
  end
  for _, e in ipairs(n:List()) do
    if Notify.Key(e) == p.key then
      local screen, params = Notify.Target(e)
      app:CloseNotify()
      if screen then
        app:Go(App.screens[screen] and screen or app:TabScreen(screen), params)
      end
      return
    end
  end
end
