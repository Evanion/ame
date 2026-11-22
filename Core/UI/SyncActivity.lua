-- Sync activity (the Sharing section, under the freshness cards): when the next announcement goes out, what's being
-- sent and received right now (a progress bar each), and what others announced that you don't have yet - per
-- player and auction house, with its size and how long it takes to come (SyncService:V2Missing).
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

local MAX_MOVING, MAX_MISSING = 6, 8
local ROW_H, LINE_GAP = 18, 4
-- Missing here: the columns (width; nil: the rest); the numbers right-aligned
local COLUMNS = {
  { key = "from", label = L["From"], width = 110 },
  { key = "house", label = L["Auction house"], width = 90 },
  { key = "scan", label = L["Full scan"], width = 80, right = true },
  { key = "hours", label = L["Hours"], width = 44, right = true },
  { key = "days", label = L["Days"], width = 40, right = true },
  { key = "size", label = L["Size"], width = 64, right = true },
  { key = "time", label = L["Time"], width = 60, right = true },
  { key = "state", label = L["State"] },
}
local COL_GAP = 10

-- bytes, roughly: "12 KB", "1.4 MB"
function UI.SyncBytes(bytes)
  bytes = bytes or 0
  if bytes >= 1024 * 1024 then
    return ("%.1f MB"):format(bytes / 1024 / 1024)
  end
  return ("%d KB"):format(math.max(1, math.floor(bytes / 1024 + 0.5)))
end

-- what objects are, in words: { s = 1, h = 3 } -> "full scan, 3 hours of prices" (an hour: one hourly price point
-- per item, for the 7D chart; a day: one day's prices)
function UI.SyncKinds(kinds)
  local parts = {}
  local s, h, d = kinds.s or 0, kinds.h or 0, kinds.d or 0
  if s > 0 then
    parts[#parts + 1] = s == 1 and L["full scan"] or L["%d full scans"]:format(s)
  end
  if h > 0 then
    parts[#parts + 1] = h == 1 and L["1 hour of prices"] or L["%d hours of prices"]:format(h)
  end
  if d > 0 then
    parts[#parts + 1] = d == 1 and L["1 day of prices"] or L["%d days of prices"]:format(d)
  end
  return table.concat(parts, ", ")
end

local function houseOf(shard)
  local _, house = ns.SplitShard(shard or "")
  return ns.HOUSE_LABEL[house] or house or "?"
end

-- one object in words: "Horde AH full scan", "Goblin AH hour 14:00", "Alliance AH day Nov 20"
function UI.SyncObject(o)
  local what
  if o.kind == "s" then
    what = L["full scan"]
  elseif o.kind == "h" then
    what = L["hour %s"]:format(date("%H:00", o.ref * 3600))
  else
    what = L["day %s"]:format(date("%b %d", o.ref * 86400))
  end
  return houseOf(o.shard) .. " " .. what
end

-- the transfers under way, as rows: { who, what, frac, left, mine }
function UI.SyncMoving(status)
  local out = {}
  if not status then
    return out
  end
  local pace = ns.SyncV2.PACE
  if status.sending then
    local s = status.sending
    local what = UI.SyncObject(s) .. " " .. L["to the guild"]
    if #(status.queue or {}) > 0 then
      local kinds = {}
      for _, q in ipairs(status.queue) do
        kinds[q.kind] = (kinds[q.kind] or 0) + 1
      end
      what = what .. W.SEP .. L["next: %s guildmates asked for"]:format(UI.SyncKinds(kinds))
    end
    out[#out + 1] = {
      who = L["Sending"],
      what = what,
      frac = s.sent / math.max(1, s.n),
      left = L["~%s left"]:format(UI.Duration(math.ceil((status.sendLeft or 0) * pace))),
      mine = true,
    }
  end
  for _, e in ipairs(status.senders or {}) do
    local houses = {}
    for shard in pairs(e.shards or {}) do
      houses[#houses + 1] = houseOf(shard)
    end
    table.sort(houses)
    local what = table.concat(houses, ", ") .. ": " .. UI.SyncKinds(e.kinds or {})
    local left, why = L["~%s left"]:format(UI.Duration(e.secondsLeft)), nil
    if e.state == "turn" then
      -- offered, but the sender is sending other data first: it waits its turn there
      left = W.Color("warn", L["waiting %s"]:format(UI.Duration(e.since)))
      why = L["%s is sending other data first; this starts when its turn comes"]:format(e.from)
    elseif e.state == "stalled" then
      left = W.Color("bad", L["stalled %s"]:format(UI.Duration(e.since)))
      why = (e.asked or 0) > 0
          and L["nothing from %s lately; asked for the missing blocks %d times (gives up after %d)"]:format(
            e.from,
            e.asked,
            ns.SyncV2.MAX_NACKS
          )
        or L["nothing from %s lately (offline, or reloaded?); it asks for the missing blocks on its own"]:format(e.from)
    end
    out[#out + 1] = {
      who = L["From %s"]:format(e.from),
      what = what,
      why = why,
      frac = e.got / math.max(1, e.n),
      left = left,
      from = e.from,
      state = e.state,
    }
  end
  return out
end

UI.SYNC_STATES = {
  receiving = { "good", L["receiving"] },
  offered = { "good", L["offered · its turn is coming"] },
  asked = { "dim", L["asked · waiting for an answer"] },
  waiting = { "dim", L["asks on their next announcement"] },
}

-- a Missing here row's cells, in COLUMNS order (text with colour codes)
function UI.SyncMissingCells(r)
  local scan = W.NONE
  if r.scan then
    scan = (r.mine and r.mine > 0) and L["%s newer"]:format(UI.Duration(r.scan - r.mine)) or L["new"]
  end
  local count = function(n)
    return n > 0 and W.Thousands(n) or W.NONE
  end
  local size = r.bytes > 0 and ("~" .. UI.SyncBytes(r.bytes)) or W.Dim("?")
  if r.bytes > 0 and r.unknown > 0 then
    size = size .. "+"
  end
  local time = (r.bytes > 0 or r.state == "receiving") and ("~" .. UI.Duration(r.seconds)) or W.Dim("?")
  local state = UI.SYNC_STATES[r.state] or UI.SYNC_STATES.waiting
  return {
    r.from,
    houseOf(r.shard),
    scan,
    count(r.hours),
    count(r.days),
    size,
    time,
    W.Color(state[1], state[2]),
  }
end

-- the line under the table: what's missing in all, its size and how long until you're caught up
function UI.SyncMissingTotal(total)
  local kinds = UI.SyncKinds({ s = total.scans, h = total.hours, d = total.days })
  local parts = { L["In all: %s"]:format(W.Color("white", kinds)) }
  if total.bytes > 0 then
    parts[#parts + 1] =
      L["about %s"]:format(W.Color("white", UI.SyncBytes(total.bytes) .. (total.unknown > 0 and "+" or "")))
    parts[#parts + 1] = L["~%s to catch up"]:format(W.Color("white", UI.Duration(total.seconds)))
  end
  local text = table.concat(parts, W.SEP)
  if total.senders > 1 then
    text = text .. " " .. L["(players send at the same time, about a block a second each)"]
  end
  return text
end

---------------------------------------------------------------------------------------------------------------------
-- the card

-- holder: the frame under the freshness cards; returns the card (card:Fit(width) lays it out at that width)
function UI:CreateSyncActivity(v, holder)
  local svc = ns.SyncService
  local stack = UI.Stack(holder, 0)
  local card = stack:Card(0)
  local body = card.stack:Row(1, 0)
  body.fits = true
  local a = { moving = {}, rows = {}, cells = {} }
  v.act = a

  a.title = W.Text(body, "GameFontNormal")
  a.title:SetText(L["Sync activity"])
  a.syncNow = W.Button(body, L["Sync now"], 90, 20, function()
    local ok, why = svc:SyncNow()
    a.message = ok
        and L["Asked your guild and trusted players for their latest scans: they arrive over the next minutes."]
      or W.Color("bad", why or "")
    UI:RefreshSync()
  end)
  a.syncNow:SetWidth(math.ceil(a.syncNow.label:GetStringWidth() or 60) + 16)
  v.syncNow = a.syncNow
  a.bar = CreateFrame("Frame", nil, body)
  a.bar:SetSize(110, 5)
  a.bar.bg = a.bar:CreateTexture(nil, "BACKGROUND")
  a.bar.bg:SetAllPoints()
  a.bar.bg:SetColorTexture(1, 1, 1, 0.08)
  a.bar.fill = a.bar:CreateTexture(nil, "ARTWORK")
  a.bar.fill:SetPoint("TOPLEFT")
  a.bar.fill:SetPoint("BOTTOMLEFT")
  a.bar.fill:SetColorTexture(W.RGB("wait")[1], W.RGB("wait")[2], W.RGB("wait")[3], 1)
  a.next = W.Text(body, "GameFontDisableSmall", "RIGHT")
  a.status = W.Text(body, "GameFontHighlightSmall")
  a.status:SetWordWrap(true)

  local function progress(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(140, 6)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 1, 1, 0.08)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("TOPLEFT")
    b.fill:SetPoint("BOTTOMLEFT")
    local c = W.COLORS.accent
    b.fill:SetColorTexture(c[1], c[2], c[3], 1)
    return b
  end
  for i = 1, MAX_MOVING do
    local r = CreateFrame("Frame", nil, body)
    r:SetHeight(ROW_H)
    r.who = W.Text(r, "GameFontHighlightSmall")
    r.who:SetPoint("TOPLEFT", 0, -3)
    r.who:SetWidth(150)
    r.who:SetWordWrap(false)
    -- Retry and Cancel on a transfer from someone (not on what you send)
    r.cancel = W.Button(r, L["Cancel"], 56, 18, function()
      if r.from then
        local n = ns.SyncService:V2Cancel(r.from)
        a.message = L["Stopped %d from %s: they're asked for again later, from whoever has them."]:format(n, r.from)
        UI:RefreshSync()
      end
    end)
    r.cancel:SetPoint("TOPRIGHT", 0, 0)
    r.retry = W.Button(r, L["Retry"], 50, 18, function()
      if r.from then
        local n = ns.SyncService:V2Retry(r.from)
        a.message = L["Asked %s again for what's missing of %d."]:format(r.from, n)
        UI:RefreshSync()
      end
    end)
    r.retry:SetPoint("RIGHT", r.cancel, "LEFT", -4, 0)
    r.left = W.Text(r, "GameFontDisableSmall", "RIGHT")
    r.left:SetWidth(110)
    -- why it isn't moving, under the row
    r.why = W.Text(r, "GameFontDisableSmall")
    r.why:SetPoint("TOPLEFT", r.who, "BOTTOMLEFT", 0, -3)
    r.why:SetPoint("RIGHT", r.retry, "LEFT", -8, 0)
    r.why:SetWordWrap(false)
    W.Truncated(r.why)
    r.pct = W.Text(r, "GameFontHighlightSmall", "RIGHT")
    r.pct:SetPoint("RIGHT", r.left, "LEFT", -8, 0)
    r.pct:SetWidth(36)
    r.bar = progress(r)
    r.bar:SetPoint("RIGHT", r.pct, "LEFT", -8, 0)
    r.what = W.Text(r, "GameFontHighlightSmall")
    r.what:SetPoint("LEFT", r.who, "RIGHT", 8, 0)
    r.what:SetPoint("RIGHT", r.bar, "LEFT", -10, 0)
    r.what:SetWordWrap(false)
    W.Truncated(r.what)
    a.moving[i] = r
  end

  a.missHead = W.Text(body, "GameFontNormalSmall")
  a.missHead:SetText(L["Missing here"])
  a.missNote = W.Text(body, "GameFontDisableSmall")
  a.missNote:SetText(L["what guild members and trusted players announced that you don't have yet"])
  a.missNote:SetWordWrap(false)
  a.empty = W.Text(body, "GameFontDisableSmall")
  -- the table: a header line, then a row per player and auction house (the DataTable's look: gold headers, a line
  -- under each row, every other row tinted)
  local function line(header)
    local r = CreateFrame("Frame", nil, body)
    r:SetHeight(ROW_H)
    r.cells = {}
    for k, c in ipairs(COLUMNS) do
      local fs = W.Text(r, header and "GameFontNormalSmall" or "GameFontHighlightSmall", c.right and "RIGHT" or "LEFT")
      fs:SetWordWrap(false)
      r.cells[k] = fs
      if header then
        fs:SetText(c.label)
      end
    end
    r.rule = r:CreateTexture(nil, "BORDER")
    r.rule:SetPoint("BOTTOMLEFT")
    r.rule:SetPoint("BOTTOMRIGHT")
    r.rule:SetHeight(1)
    r.rule:SetColorTexture(1, 1, 1, header and 0.12 or 0.05)
    r.tint = r:CreateTexture(nil, "BACKGROUND")
    r.tint:SetAllPoints()
    r.tint:SetColorTexture(1, 1, 1, 0.025)
    r.tint:Hide()
    return r
  end
  a.head = line(true)
  for i = 1, MAX_MISSING do
    a.rows[i] = line(false)
    a.rows[i].tint:SetShown(i % 2 == 0)
  end
  a.more = W.Text(body, "GameFontDisableSmall")
  a.total = W.Text(body, "GameFontDisableSmall")
  a.total:SetWordWrap(true)

  -- lay it all out at the card's inner width, top to bottom; the body's height is what that takes
  function body:Fit(width)
    width = math.max(200, width or 600)
    local d = a.data or {}
    local y = 0
    a.title:ClearAllPoints()
    a.title:SetPoint("TOPLEFT", 0, -3)
    a.syncNow:ClearAllPoints()
    a.syncNow:SetPoint("TOPRIGHT", 0, 0)
    a.bar:ClearAllPoints()
    a.bar:SetPoint("RIGHT", a.syncNow, "LEFT", -10, 0)
    a.next:ClearAllPoints()
    a.next:SetPoint("RIGHT", a.bar, "LEFT", -8, 0)
    a.next:SetText(d.next or "")
    a.bar:SetShown(d.nextFrac ~= nil)
    a.bar.fill:SetWidth(math.max(1, 110 * (d.nextFrac or 0)))
    y = y + 24
    if a.message and a.message ~= "" then
      a.status:SetText(a.message)
      a.status:ClearAllPoints()
      a.status:SetPoint("TOPLEFT", 0, -y)
      a.status:SetWidth(width)
      a.status:Show()
      y = y + math.ceil(a.status:GetStringHeight() or 12) + LINE_GAP
    else
      a.status:Hide()
    end
    local moving = d.moving or {}
    for i, r in ipairs(a.moving) do
      local m = moving[i]
      r:SetShown(m ~= nil)
      if m then
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetWidth(width)
        r.who:SetText(m.mine and W.Dim(m.who) or m.who)
        r.what:SetText(m.what)
        r.pct:SetText(math.floor(100 * m.frac + 0.5) .. "%")
        r.left:SetText(m.left)
        r.bar.fill:SetWidth(math.max(1, 140 * math.min(1, m.frac)))
        r.from = m.from
        r.left:ClearAllPoints()
        if m.from then
          r.left:SetPoint("RIGHT", r.retry, "LEFT", -8, 0)
        else
          r.left:SetPoint("TOPRIGHT", 0, -3)
        end
        r.retry:SetShown(m.from ~= nil)
        r.cancel:SetShown(m.from ~= nil)
        r.why:SetText(m.why or "")
        r.why:SetShown(m.why ~= nil)
        local h = m.why and (ROW_H + 14) or ROW_H
        r:SetHeight(h)
        y = y + h
      end
    end
    y = y + LINE_GAP
    a.missHead:ClearAllPoints()
    a.missHead:SetPoint("TOPLEFT", 0, -y)
    a.missNote:ClearAllPoints()
    a.missNote:SetPoint("LEFT", a.missHead, "RIGHT", 8, 0)
    a.missNote:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    y = y + 18
    local rows = d.rows or {}
    a.empty:SetShown(#rows == 0)
    a.head:SetShown(#rows > 0)
    if #rows == 0 then
      for _, r in ipairs(a.rows) do -- (rows drawn while there were some)
        r:Hide()
      end
      a.empty:SetText(d.emptyText or "")
      a.empty:ClearAllPoints()
      a.empty:SetPoint("TOPLEFT", 0, -y)
      y = y + 16
    else
      -- the columns: fixed widths, the state gets the rest
      local fixed = 0
      for _, c in ipairs(COLUMNS) do
        fixed = fixed + (c.width or 0) + COL_GAP
      end
      local rest = math.max(80, width - fixed)
      local function place(r)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetWidth(width)
        local x = 4
        for k, c in ipairs(COLUMNS) do
          local w = c.width or rest
          r.cells[k]:ClearAllPoints()
          r.cells[k]:SetPoint("LEFT", x, 0)
          r.cells[k]:SetWidth(w)
          x = x + w + COL_GAP
        end
        y = y + ROW_H
      end
      place(a.head)
      for i, r in ipairs(a.rows) do
        local cells = rows[i]
        r:SetShown(cells ~= nil)
        if cells then
          place(r)
          for k, fs in ipairs(r.cells) do
            fs:SetText(cells[k] or "")
          end
        end
      end
    end
    a.more:SetShown((d.more or 0) > 0)
    if (d.more or 0) > 0 then
      a.more:SetText(L["+ %d more"]:format(d.more))
      a.more:ClearAllPoints()
      a.more:SetPoint("TOPLEFT", 0, -y - 2)
      y = y + 16
    end
    a.total:SetShown(d.total ~= nil)
    if d.total then
      a.total:SetText(d.total)
      a.total:ClearAllPoints()
      a.total:SetPoint("TOPLEFT", 0, -y - LINE_GAP)
      a.total:SetWidth(width)
      y = y + LINE_GAP + math.ceil(a.total:GetStringHeight() or 12)
    end
    self:SetHeight(math.max(1, y + 2))
  end

  function a:Height(width)
    return stack:Height(width)
  end
  return a
end

-- what the card shows now (RefreshSync calls it; the layout happens when the section measures itself)
function UI:SyncActivityData()
  local svc = ns.SyncService
  local d = {}
  local now = GetServerTime()
  local nextIn = svc.NextAnnounceIn and svc:NextAnnounceIn(now)
  if nextIn then
    d.next = L["Next announce in %s"]:format(W.Color("white", UI.Duration(nextIn)))
    local every = svc.ANNOUNCE_EVERY or 600
    d.nextFrac = math.max(0, math.min(1, 1 - nextIn / every))
  else
    d.next = W.Dim(L["Sharing is off"])
  end
  local status = svc.V2Status and svc:V2Status()
  d.moving = UI.SyncMoving(status)
  local rows, total = nil, nil
  if svc.V2Missing then
    rows, total = svc:V2Missing()
  end
  d.rows = {}
  for i, r in ipairs(rows or {}) do
    if i <= MAX_MISSING then
      d.rows[i] = UI.SyncMissingCells(r)
    end
  end
  d.more = rows and math.max(0, #rows - MAX_MISSING) or 0
  d.total = rows and #rows > 0 and UI.SyncMissingTotal(total) or nil
  if not svc.v2 then
    d.emptyText = L["Shown with the v2 sync protocol (Guild sharing, Sync protocol)."]
  elseif not rows then
    d.emptyText = L["Loading your price history..."]
  else
    d.emptyText = L["Nothing: you have everything the players you share with announced."]
  end
  d.receivingFrom, d.catchUp = #(status and status.senders or {}), total and total.seconds or 0
  return d
end
