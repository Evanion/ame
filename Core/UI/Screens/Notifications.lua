-- The bell's notifications (board NotifyPanel): what AME told you in passing (Core/Notices.lua), newest first, the
-- unread ones lit. Opening it marks them read; a click on one opens what it is about; Clear all empties it. The bell
-- again goes back to where you were.
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

local Notify = { ROW_H = 46 }
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

-- ------------------------------------------------------------------------------------------------ the screen

local function notices()
  return ns.AME and ns.AME.notices
end

local function fit(app)
  local h = app.frame and app.frame:GetHeight() or App.H
  -- the window less the title bar, status row, padding, the card's own padding, heading, note and gaps
  local room = (h or App.H) - 40 - 26 - 24 - 20 - 22 - 34 - 12
  return math.max(3, math.floor(room / Notify.ROW_H))
end

local function build(app, params)
  local n = notices()
  local now = GetServerTime and GetServerTime() or 0
  -- opening marks everything read; what was unread when you opened it stays lit while you look
  if params.seenAt == nil then
    params.seenAt = n and n.db and n.db.readAt or 0
    if n then
      n:MarkRead(now)
    end
  end
  local seenAt = params.seenAt
  local list = n and n:List() or {}
  local rows, older = Notify.Rows(list, now, function(e)
    return (e.at or 0) > seenAt
  end, fit(app))
  if #rows == 0 then
    rows[1] = {
      key = "none",
      pill = "—",
      title = L["Nothing yet"],
      sub = L["Alerts, craft requests and news of a newer AME show up here"],
    }
  end
  local note = L["Click one to open what it is about. What shows here, and whether it also prints in chat or plays a sound, is set under Settings > Notifications."]
  if older > 0 then
    note = L["+ %d older."]:format(older) .. " " .. note
  end
  return {
    id = "notify",
    type = "row",
    children = {
      { id = "notify.space", type = "spacer", meta = { grow = 1 } },
      {
        id = "notify.card",
        type = "card",
        props = { layout = "column", gap = 6, pad = 10 },
        meta = app.compact and { grow = 1 } or { w = 380 },
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
                props = { text = L["Clear all"], action = "clearAll" },
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
          { id = "notify.note", type = "text", props = { text = note, color = "dim", size = 11, wrap = true }, meta = { h = 34 } },
        },
      },
    },
  }
end

App.Screen("notifications", {
  Build = build,
  Title = function()
    return L["Notifications"]
  end,
  Status = function()
    local n = notices()
    local count = n and #n.db.list or 0
    return count == 1 and L["1 notification"] or L["%d notifications"]:format(count)
  end,
  actions = {
    -- the bell again: back to where you were
    bell = function(app)
      app:Back()
    end,
    clearAll = function(app)
      local n = notices()
      if n then
        n:Clear()
      end
      app:Render()
    end,
    openNotice = function(app, p)
      local n = notices()
      if not (n and p and p.key) then
        return
      end
      for _, e in ipairs(n:List()) do
        if Notify.Key(e) == p.key then
          local screen, params = Notify.Target(e)
          if screen then
            app:Go(App.screens[screen] and screen or app:TabScreen(screen), params)
          end
          return
        end
      end
    end,
  },
})
