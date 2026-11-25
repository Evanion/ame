-- Guild > Sharing prices (board Sync): how fresh each auction house's data is, sync activity (the next announce,
-- what's moving, what others have that you don't), and the three groups you share with: the guild, trusted
-- players, and the blocked. The facts come from Core/UI/SyncView.lua's and Core/UI/SyncActivity.lua's readers
-- (UI:Freshness, UI:SyncActivityData) and Core/SyncService.lua.
local _, ns = ...
local L = ns.L

local App, G = ns.App, ns.GuildScreen
local Kit = ns.Kit

local MISSING_COLUMNS = {
  { key = "c1", label = L["From"], width = 110, align = "LEFT" },
  { key = "c2", label = L["Auction house"], width = 100, align = "LEFT" },
  { key = "c3", label = L["Full scan"], width = 80 },
  { key = "c4", label = L["Hours"], width = 50 },
  { key = "c5", label = L["Days"], width = 44 },
  { key = "c6", label = L["Size"], width = 64 },
  { key = "c7", label = L["Time"], width = 60 },
  { key = "c8", label = L["State"], width = 90, align = "LEFT" },
}

local PEER_COLUMNS = {
  { key = "name", label = L["Player"], width = 110, align = "LEFT" },
  { key = "state", label = "", width = 170, align = "LEFT" },
  { key = "act", label = "", width = 64, button = { label = L["Block"], action = "peerAct" } },
}

local function ago(t)
  return ns.Widgets.Ago(t, GetServerTime())
end

local function others(svc, list)
  local out = {}
  for _, e in ipairs(list or {}) do
    if not svc:IsMine(e.name) then
      out[#out + 1] = e
    end
  end
  return out
end

-- the freshness of each auction house: kpi props
function G.FreshKpis()
  local UI = ns.UI
  local out = {}
  local ok, fresh = pcall(function()
    return UI:Freshness()
  end)
  if not ok then
    fresh = {}
  end
  local now = GetServerTime()
  local me = UnitName("player")
  for _, f in ipairs(fresh) do
    local label = ns.HOUSE_LABEL[f.house] or f.house
    if f.t then
      local days = (now - f.t) / 86400
      local tone = days < 1 and "good" or days < 3 and "warn" or "dim"
      local who = (not f.src or f.src == me) and L["you"] or f.src
      local note = L["Full scan by %s"]:format(who)
      if f.items then
        note = note .. " · " .. L["%s items"]:format(ns.Widgets.Thousands(f.items))
      end
      out[#out + 1] =
        { label = label, value = Kit.Color(tone, L["%s old"]:format(ns.Widgets.Age(f.t, now))), note = note }
    else
      out[#out + 1] =
        { label = label, value = Kit.Color("dim", L["No data"]), note = L["Scan there, or trust someone who does"] }
    end
  end
  return out
end

-- what the sync activity card shows (UI:SyncActivityData), or a stand-in when it can't be read
function G.Activity()
  local UI = ns.UI
  local ok, d = pcall(function()
    return UI:SyncActivityData()
  end)
  if ok and d then
    return d
  end
  return {
    next = L["Sharing is off"],
    moving = {},
    rows = {},
    emptyText = L["Nothing: you're up to date."],
    receivingFrom = 0,
    catchUp = 0,
  }
end

local function plainNext(text)
  return tostring(text or "")
end

local function build(app)
  local svc = ns.SyncService or {}
  local trust = svc.trust
  local kpis = {}
  for i, k in ipairs(G.FreshKpis()) do
    kpis[i] = { id = "share.kpi" .. i, type = "kpi", props = k }
  end
  local act = G.Activity()
  local actKids = {
    {
      id = "share.act.head",
      type = "row",
      props = { gap = 10, align = "center" },
      meta = { h = 22 },
      children = {
        { id = "share.act.t", type = "text", props = { text = L["Sync activity"], color = "gold", size = 13 } },
        { id = "share.act.fill", type = "spacer", meta = { grow = 1 } },
        { id = "share.act.next", type = "text", props = { text = plainNext(act.next), color = "dim", size = 11 } },
        {
          id = "share.act.now",
          type = "button",
          props = { label = L["Sync now"], action = "syncNow" },
          meta = { h = 22 },
        },
      },
    },
  }
  for i, m in ipairs(act.moving or {}) do
    local pct = math.floor((m.frac or 0) * 100 + 0.5) .. "%"
    actKids[#actKids + 1] = {
      id = "share.mv" .. i,
      type = "text",
      props = {
        text = ("%s   %s   %s   %s"):format(
          m.mine and Kit.Color("dim", m.who) or m.who,
          m.what or "",
          pct,
          tostring(m.left or "")
        ),
        size = 12,
      },
      meta = { h = 18 },
    }
    if m.why then
      actKids[#actKids + 1] = {
        id = "share.mv" .. i .. ".why",
        type = "text",
        props = { text = m.why, color = "dim", size = 11 },
        meta = { h = 14 },
      }
    end
  end
  actKids[#actKids + 1] = G.Heading("share.miss.h", L["Missing here"], L["what others have that you don't"])
  local missRows = {}
  for i, cells in ipairs(act.rows or {}) do
    local row = { key = tostring(i) }
    for c = 1, 8 do
      row["c" .. c] = cells[c] ~= nil and tostring(cells[c]) or ""
    end
    missRows[i] = row
  end
  app:Source("guild.missing", missRows)
  actKids[#actKids + 1] = {
    id = "share.miss",
    type = "table",
    props = { source = "guild.missing", columns = MISSING_COLUMNS, bare = true, empty = act.emptyText },
    meta = { h = 112 },
  }
  if act.total then
    actKids[#actKids + 1] = {
      id = "share.miss.total",
      type = "text",
      props = { text = act.total, color = "dim", size = 11 },
      meta = { h = 14 },
    }
  end
  local actH = 22 + 20 * #(act.moving or {}) + 20 + 112 + (act.total and 18 or 0) + 8 * #actKids + 20

  -- guild sharing: the switches, the protocol, the counts, the players heard from
  local stats = AME_DB and AME_DB.stats or {}
  local peers = trust and others(svc, trust:PeerList()) or {}
  local peerRows = {}
  for i, p in ipairs(peers) do
    if i > 40 then
      break
    end
    local blocked = trust:IsBlocked(p.name)
    local version = ns.UI and ns.UI.SyncVersionText and ns.UI.SyncVersionText(p.name) or ""
    local proto = svc.ProtocolOf and svc:ProtocolOf(p.name)
    peerRows[#peerRows + 1] = {
      key = p.name,
      name = p.name,
      state = version .. (proto and ("v" .. proto .. " · ") or "") .. L["heard %s"]:format(ago(p.at)),
      act = blocked and L["Unblock"] or L["Block"],
    }
  end
  app:Source("guild.peers", peerRows)
  local guildCard = {
    id = "share.guild",
    type = "card",
    props = { title = L["Guild sharing"], gap = 4 },
    meta = { grow = 1 },
    children = {
      {
        id = "share.g.scans",
        type = "check",
        props = {
          label = L["Share full scans with my guild"],
          checked = ns.Settings:Get("syncGuild") and true or false,
          action = "setting",
          payload = "syncGuild",
        },
        meta = { h = 18 },
      },
      {
        id = "share.g.recipes",
        type = "check",
        props = {
          label = L["Share what my characters can craft (who can make it)"],
          checked = ns.Settings:Get("shareRecipes") and true or false,
          action = "setting",
          payload = "shareRecipes",
        },
        meta = { h = 18 },
      },
      {
        id = "share.g.proto",
        type = "row",
        props = { gap = 8, align = "center" },
        meta = { h = 24 },
        children = {
          G.Text("share.g.proto.l", L["Sync protocol"], { meta = { w = 90, h = 18 } }),
          {
            id = "share.g.proto.s",
            type = "segmented",
            props = {
              options = { { "2", L["v2: the whole guild at once"] }, { "1", L["v1: lighter"] } },
              selected = tostring(svc.Protocol and svc:Protocol() or 2),
              action = "protocol",
            },
          },
        },
      },
      G.Text(
        "share.g.stats",
        L["Announced %d · served %d · received %d · rejected %d"]:format(
          stats.syncAnnounced or 0,
          stats.syncServed or 0,
          stats.syncReceived or 0,
          stats.syncRejected or 0
        ),
        { meta = { h = 14 } }
      ),
      {
        id = "share.g.peers",
        type = "table",
        props = { source = "guild.peers", columns = PEER_COLUMNS, bare = true, empty = L["Nobody heard from yet."] },
        meta = { grow = 1 },
      },
    },
  }

  -- trusted players: the switch, asking someone, the trusted and those who ask
  local trustRows = {}
  for _, p in ipairs(trust and others(svc, trust:PendingList()) or {}) do
    trustRows[#trustRows + 1] =
      { key = "p:" .. p.name, name = p.name, state = { text = L["asks to share"], color = "warn" }, act = L["Approve"] }
  end
  for _, e in ipairs(trust and others(svc, trust:TrustedList()) or {}) do
    local heard = trust:LastHeard(e.name)
    trustRows[#trustRows + 1] = {
      key = "t:" .. e.name,
      name = e.name,
      state = e.mutual
          and (L["trusted"] .. " · " .. (heard and L["heard %s"]:format(ago(heard)) or L["not heard yet"]))
        or { text = L["waiting for them to approve"], color = "dim" },
      act = L["Remove"],
    }
  end
  app:Source("guild.trusted", trustRows)
  local trustCard = {
    id = "share.trust",
    type = "card",
    props = { title = L["Trusted players"], gap = 4 },
    meta = { grow = 1 },
    children = {
      G.Text(
        "share.t.text",
        L["Swap scans with friends, or your own characters on other accounts."],
        { meta = { h = 14 } }
      ),
      {
        id = "share.t.on",
        type = "check",
        props = {
          label = L["Share with trusted players"],
          checked = ns.Settings:Get("syncTrusted") and true or false,
          action = "setting",
          payload = "syncTrusted",
        },
        meta = { h = 18 },
      },
      {
        id = "share.t.add",
        type = "row",
        props = { gap = 6 },
        meta = { h = 24 },
        children = {
          {
            id = "share.t.name",
            type = "input",
            props = { value = app.trustName or "", hint = L["Character name"], action = "trustName" },
            meta = { grow = 1 },
          },
          { id = "share.t.ask", type = "button", props = { label = L["Ask to share"], action = "trustAdd" } },
        },
      },
      {
        id = "share.t.list",
        type = "table",
        props = { source = "guild.trusted", columns = PEER_COLUMNS, bare = true },
        meta = { grow = 1 },
      },
    },
  }
  local guildBlocked = {}
  for _, name in pairs(trust and trust.guildBlocked or {}) do
    guildBlocked[#guildBlocked + 1] = name
  end
  table.sort(guildBlocked)
  local blockedText = L["Scans from these players are ignored."] .. " "
  if #guildBlocked > 0 then
    blockedText = blockedText .. L["By your guild officers: %s"]:format(table.concat(guildBlocked, ", "))
  else
    blockedText = blockedText
      .. L['Guild officers can block players for everyone: add a line "%s" to the guild info.']:format(
        "AME block: Name, Name"
      )
  end
  local blockRows = {}
  for _, b in ipairs(trust and others(svc, trust:BlockedList()) or {}) do
    blockRows[#blockRows + 1] =
      { key = "b:" .. b.name, name = b.name, state = L["blocked %s"]:format(ago(b.at)), act = L["Unblock"] }
  end
  app:Source("guild.blocked", blockRows)
  local blockCard = {
    id = "share.block",
    type = "card",
    props = { title = L["Blocked"], gap = 4 },
    meta = { h = 130 },
    children = {
      G.Text("share.b.text", blockedText, { wrap = true, meta = { h = 28 } }),
      {
        id = "share.b.list",
        type = "table",
        props = { source = "guild.blocked", columns = PEER_COLUMNS, bare = true },
        meta = { grow = 1 },
      },
    },
  }
  local main = {
    id = "share.main",
    type = "column",
    props = { gap = 8 },
    children = {
      {
        id = "share.kpis",
        type = "grid",
        props = { cols = math.max(1, #kpis), gap = 8, rowH = 66 },
        meta = { h = 66 },
        children = kpis,
      },
      { id = "share.act", type = "card", props = { gap = 4 }, meta = { h = actH }, children = actKids },
      {
        id = "share.cards",
        type = "row",
        props = { gap = 8 },
        meta = { grow = 1 },
        children = {
          guildCard,
          {
            id = "share.col2",
            type = "column",
            props = { gap = 8 },
            meta = { grow = 1 },
            children = { trustCard, blockCard },
          },
        },
      },
    },
  }
  return G.Page("sharing", main)
end

local function status()
  local on = ns.Settings:Get("syncGuild") or ns.Settings:Get("syncTrusted")
  if not on then
    return L["Sync is off: turn on guild or trusted sharing below"]
  end
  local act = G.Activity()
  local text = L["Sync is on"]
  if (act.receivingFrom or 0) > 0 then
    text = text
      .. " · "
      .. (
        act.receivingFrom == 1 and L["receiving from 1 player"]
        or L["receiving from %d players"]:format(act.receivingFrom)
      )
  end
  if (act.catchUp or 0) > 0 and ns.UI and ns.UI.Duration then
    text = text .. " · " .. L["caught up in ~%s"]:format(ns.UI.Duration(act.catchUp))
  end
  return text
end

local function svcCall(method, name)
  local svc = ns.SyncService
  if svc and svc[method] then
    local ok, a, b = pcall(svc[method], svc, name)
    if ok and a == nil and b and ns.AME and ns.AME.Say then
      ns.AME.Say(b)
    end
  end
end

App.Screen("sharing", {
  tab = "guild",
  sub = true,
  Build = build,
  Title = function()
    return L["Sharing prices"]
  end,
  Status = status,
  actions = G.Actions({
    setting = function(app, p)
      if p.payload then
        ns.Settings:Set(p.payload, p.checked and true or false)
      end
      app:Render()
    end,
    protocol = function(app, p)
      local v = tonumber(p.key)
      local svc = ns.SyncService
      if v and svc and svc.Protocol and v ~= svc:Protocol() then
        ns.Settings:Set("syncProtocol", v)
        if svc.InitV2 then
          pcall(svc.InitV2, svc)
        end
      end
      app:Render()
    end,
    syncNow = function(app)
      svcCall("SyncNow")
      app:Render()
    end,
    trustName = function(app, p)
      app.trustName = p.text
    end,
    trustAdd = function(app)
      if app.trustName and app.trustName ~= "" then
        svcCall("AddTrusted", app.trustName)
        app.trustName = nil
      end
      app:Render()
    end,
    peerAct = function(app, p)
      local kind, name = tostring(p.key):match("^(%a):(.+)$")
      local svc = ns.SyncService
      if not kind then
        name = p.key
        kind = svc and svc.trust and svc.trust:IsBlocked(name) and "b" or "g"
      end
      if kind == "p" then
        svcCall("Approve", name)
      elseif kind == "t" then
        svcCall("RemoveTrusted", name)
      elseif kind == "b" then
        svcCall("Unblock", name)
      else
        svcCall("Block", name)
      end
      app:Render()
    end,
  }),
})
