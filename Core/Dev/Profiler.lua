-- The profiler: /amedev on measures what AME costs the client while you play, until /amedev off (kept across
-- /reload). It ships, but does nothing while off: no timing, no saved data, nothing in chat.
--   CPU     time per background job (by name) and per game event handler: total, calls, worst single run
--   frames  AME's share of each frame (jobs + events), and spikes over SPIKE_MS with what caused them
--   sizes   an estimate of what each big structure takes in memory and in SavedVariables (/amedev sizes)
--   fights  every fight, per addon (LagProbe.lua), kept quietly while on
-- /amedev prints the summary, /amedev send whispers it all to the developer (Report.lua). Everything is kept in
-- AME_DB.dev (saved on logout / reload). /amedev reset starts over.
local ADDON, ns = ...

local Dev = {}
ns.Dev = Dev

Dev.SPIKE_MS = 12 -- a frame where AME took longer than this is logged
Dev.SPIKES_KEEP = 200

---------------------------------------------------------------------------------------------------------------------
-- pure helpers (spec/dev_spec.lua)

-- add one timed run to a stats table: stats[name] = { ms (total), n, max }
function Dev.Record(stats, name, ms)
  local e = stats[name]
  if not e then
    e = { ms = 0, n = 0, max = 0 }
    stats[name] = e
  end
  e.ms, e.n = e.ms + ms, e.n + 1
  if ms > e.max then
    e.max = ms
  end
  return e
end

-- the top entries of a stats table by total time: { { name, ms, n, max }, ... }
function Dev.Top(stats, limit)
  local list = {}
  for name, e in pairs(stats) do
    list[#list + 1] = { name = name, ms = e.ms, n = e.n, max = e.max }
  end
  table.sort(list, function(a, b)
    return a.ms > b.ms
  end)
  for i = (limit or 10) + 1, #list do
    list[i] = nil
  end
  return list
end

-- Rough sizes of a value: mem = Lua memory (bytes, 5.1 layout estimates: a table ~56 bytes, array slots 16 and hash
-- nodes 40 each, a string ~25 + its length, counted once), text = its size written out as SavedVariables. Shared
-- tables and strings count once (seen). step() (optional) is called every 1000 tables, to time-slice big walks.
function Dev.Size(value, seen, step)
  seen = seen or {}
  local mem, text, tables = 0, 0, 0
  local function walk(v)
    local t = type(v)
    if t == "string" then
      text = text + #v + 4
      if not seen[v] then
        seen[v] = true
        mem = mem + 25 + #v
      end
    elseif t == "number" then
      text = text + 8
    elseif t == "boolean" then
      text = text + 5
    elseif t == "table" then
      if seen[v] then
        return
      end
      seen[v] = true
      tables = tables + 1
      if step and tables % 1000 == 0 then
        step()
      end
      local n = #v
      mem = mem + 56 + n * 16
      text = text + 4
      for k, x in pairs(v) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
          mem = mem + 40
          walk(k)
        end
        text = text + 6
        walk(x)
      end
    end
  end
  walk(value)
  return { mem = mem, text = text, tables = tables }
end

local function kb(bytes)
  return ("%.0f KB"):format((bytes or 0) / 1024)
end
Dev.KB = kb

---------------------------------------------------------------------------------------------------------------------
-- in game (nothing below runs in specs: there's no AME there)

local AME = ns.AME
if not (AME and AME.jobs and CreateFrame) then
  return
end

local clock = debugprofilestop
local db -- AME_DB.dev while profiling is on (/amedev on), nil while it's off
local frameMs = 0 -- AME's time in the current frame
local frameWhat -- the biggest single cost in it

local function account(kind, name, ms)
  Dev.Record(db[kind], name, ms)
  frameMs = frameMs + ms
  if not frameWhat or ms > frameWhat.ms then
    frameWhat = { what = kind .. " " .. tostring(name), ms = ms }
  end
end

-- Timed sections nest (a job's callback redraws a window, a render gathers Home's facts): each is recorded under its
-- own kind and name, but only the outermost counts toward the frame's total, so nothing is counted twice.
local depth = 0
local function finish(kind, name, t0, ...)
  depth = depth - 1
  local ms = clock() - t0
  if depth == 0 then
    account(kind, name, ms)
  else
    Dev.Record(db[kind], name, ms)
  end
  return ...
end

local function timed(kind, name, fn, ...)
  if not db then
    return fn(...)
  end
  db[kind] = db[kind] or {}
  depth = depth + 1
  local t0 = clock()
  return finish(kind, name, t0, fn(...))
end
Dev.Timed = timed

-- jobs: time each Tick (the runner records which job it ran); while off, straight through
local runner = AME.jobs
local tick = runner.Tick
runner.Tick = function(self, ...)
  if not db then
    return tick(self, ...)
  end
  -- the job's name is known once it has run
  depth = depth + 1
  local t0 = clock()
  tick(self, ...)
  finish("jobs", self.lastName or "?", t0)
end

-- events: wrap AME's handlers (Main.lua dispatches through this table on every event)
for event, fn in pairs(AME.handlers or {}) do
  AME.handlers[event] = function(...)
    return timed("events", event, fn, ...)
  end
end

-- The new window (Core/UI/App.lua): each draw by its screen ("render home"), the screen's tree on its own ("build
-- home"), and the status row's half-second refresh. Home's facts: the whole gather and each of its pieces.
local App = ns.App
if App then
  local render, tree = App.Render, App.Tree
  App.Render = function(self, ...)
    local id = self.Current and self:Current() or "?"
    return timed("ui", "render " .. tostring(id), render, self, ...)
  end
  App.Tree = function(self, ...)
    local id = self.Current and self:Current() or "?"
    return timed("ui", "build " .. tostring(id), tree, self, ...)
  end
  for _, name in ipairs({ "StatusRight", "ScanButtonState" }) do
    local fn = App[name]
    if fn then
      App[name] = function(...)
        return timed("ui", "status " .. name, fn, ...)
      end
    end
  end
end
local Home = ns.Home
if Home and Home.Gather then
  local gather = Home.Gather
  Home.Gather = function(...)
    return timed("ui", "home gather", gather, ...)
  end
  Home.Timed = function(label, fn, ...)
    return timed("ui", "home " .. label, fn, ...)
  end
end
-- the old window: its Render* and Refresh* methods ("old RenderMarket"), for sessions with both windows open
local UI = ns.UI
if UI then
  local names = {}
  for name, fn in pairs(UI) do
    if type(fn) == "function" and (name:match("^Render") or name:match("^Refresh")) then
      names[#names + 1] = name
    end
  end
  for _, name in ipairs(names) do
    local fn = UI[name]
    UI[name] = function(...)
      return timed("ui", "old " .. name, fn, ...)
    end
  end
end

local function memoryKB()
  if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    UpdateAddOnMemoryUsage()
    return GetAddOnMemoryUsage(ADDON)
  end
  return nil
end

-- the frame that just ended (only while profiling is on)
local function onUpdate()
  if frameMs > 0 then
    local f = db.frames
    f.n, f.ms = f.n + 1, f.ms + frameMs
    if frameMs > f.max then
      f.max = frameMs
    end
    if frameMs > Dev.SPIKE_MS then
      local spikes = db.spikes
      spikes[#spikes + 1] = {
        t = GetServerTime(),
        ms = math.floor(frameMs * 10 + 0.5) / 10,
        what = frameWhat and frameWhat.what,
        combat = InCombatLockdown and InCombatLockdown() or nil,
      }
      while #spikes > Dev.SPIKES_KEEP do
        table.remove(spikes, 1)
      end
    end
  end
  frameMs, frameWhat, depth = 0, nil, 0 -- (a timed section that errored never closed: start the next frame clean)
end
local frames = CreateFrame("Frame")

local function fresh(on)
  return {
    on = on,
    since = GetServerTime(),
    jobs = {},
    events = {},
    ui = {},
    frames = { n = 0, ms = 0, max = 0 },
    spikes = {},
  }
end

local function say(fmt, ...)
  print("|cff33ccffAME dev|r " .. fmt:format(...))
end
Dev.Say = say

-- profiling on or off: kept across /reload; on also measures every fight quietly (/amedev lag)
local function start(on)
  if on then
    AME_DB.dev = AME_DB.dev or fresh()
    AME_DB.dev.on = true
    for k, v in pairs(fresh()) do
      if AME_DB.dev[k] == nil then
        AME_DB.dev[k] = v
      end
    end
    db = AME_DB.dev
    frameMs, frameWhat = 0, nil
    frames:SetScript("OnUpdate", onUpdate)
  else
    if AME_DB.dev then
      AME_DB.dev.on = nil
    end
    db = nil
    frames:SetScript("OnUpdate", nil)
  end
end

function Dev.On()
  return db ~= nil
end

local function summary()
  local mins = math.max(1, (GetServerTime() - db.since) / 60)
  say("since %s (%.0f min)", date("%H:%M", db.since), mins)
  local m = memoryKB()
  say("memory: %s now", m and kb(m * 1024) or "?")
  local f = db.frames
  say(
    "frames with AME work: %d, %.1f ms each on average, worst %.1f ms, %d over %d ms",
    f.n,
    f.n > 0 and f.ms / f.n or 0,
    f.max,
    #db.spikes,
    Dev.SPIKE_MS
  )
  say("CPU per minute: %.0f ms", f.ms / mins)
  for _, kind in ipairs({ "jobs", "events", "ui" }) do
    for _, e in ipairs(Dev.Top(db[kind], 6)) do
      say("  %s %s: %.0f ms total, %d runs, worst %.1f ms", kind, e.name, e.ms, e.n, e.max)
    end
  end
  local last = db.spikes[#db.spikes]
  if last then
    say("last spike: %.1f ms at %s (%s)", last.ms, date("%H:%M:%S", last.t), tostring(last.what))
  end
end

-- what the big structures take: in memory (live) and in SavedVariables (AME_DB's top-level keys)
local function sizes()
  local parts = {}
  local function add(name, value)
    parts[#parts + 1] = { name = name, value = value }
  end
  for shard, index in pairs(AME.indexes or {}) do
    add("index " .. ns.ShardLabel(shard), index)
  end
  for shard, store in pairs(AME.stores or {}) do
    add(
      "store " .. ns.ShardLabel(shard),
      { data = store.data, cache = store.cache, texts = store.texts, rows = store.rows }
    )
  end
  add("item cache", ns.ItemCache and ns.ItemCache.info)
  if ns.UI then
    add("market list", ns.UI.list)
  end
  for key, value in pairs(AME_DB or {}) do
    if key ~= "dev" then
      add("saved " .. key, value)
    end
  end
  AME.jobs:Add("dev-sizes", function(job)
    local out = {}
    for _, p in ipairs(parts) do
      local s = Dev.Size(p.value, nil, function()
        job:Checkpoint()
      end)
      out[#out + 1] = { name = p.name, mem = s.mem, text = s.text, tables = s.tables }
      job:Checkpoint()
    end
    table.sort(out, function(a, b)
      return a.mem > b.mem
    end)
    return out
  end, function(ok, out)
    if not ok then
      return say("sizes failed: %s", tostring(out))
    end
    if db then
      db.sizes = { at = GetServerTime(), parts = out }
    end
    say("estimated sizes (memory / as saved data / tables):")
    for i, p in ipairs(out) do
      if i > 14 then
        break
      end
      say("  %s: %s / %s / %d", p.name, kb(p.mem), kb(p.text), p.tables)
    end
  end, 4)
  say("measuring sizes in the background...")
end

local HELP = "/amedev on - start measuring what AME costs (and every fight, quietly)  ·  /amedev send - send it to the"
  .. " developer  ·  /amedev off  ·  /amedev - the summary  ·  /amedev sync - why sharing does or doesn't work here"
  .. "  ·  /amedev lag [now | last]  ·  /amedev hud  ·  /amedev sizes  ·  /amedev reset"

SLASH_AMEDEV1 = "/amedev"
SlashCmdList.AMEDEV = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "on" then
    if db then
      return say("already on - /amedev send when you're done")
    end
    start(true)
    if Dev.Lag then
      Dev.Lag.Arm(true)
    end
    return say("on: measuring what AME costs, and every fight, until /amedev off. Play a while, then /amedev send.")
  elseif cmd == "off" then
    start(false)
    if Dev.Lag then
      Dev.Lag.Arm(false)
    end
    if Dev.Hud then
      Dev.Hud.Off()
    end
    return say("off (what was measured is kept: /amedev send still sends it)")
  elseif cmd == "send" then
    return Dev.Report.Send(rest:match("^(.-)%s*$"))
  elseif cmd == "receive" then
    return Dev.Report.Receive()
  elseif cmd == "sync" then
    -- sharing's state here, in a few lines; /amedev send sends it all (with the last messages in and out)
    local svc = ns.SyncService
    if not (svc and svc.DiagnosticLines and svc.AME) then
      return say("sync isn't running")
    end
    for _, line in ipairs(svc:DiagnosticLines()) do
      say(line)
    end
    return say("/amedev send sends this, and the last sync messages in and out, to AME's developer")
  elseif cmd == "help" or cmd == "?" then
    return say(HELP)
  end
  if not db then
    return say("off - /amedev on to start measuring  ·  /amedev help for the rest")
  end
  if cmd == "reset" then
    AME_DB.dev = fresh(true)
    db = AME_DB.dev
    say("reset")
  elseif cmd == "sizes" then
    sizes()
  elseif cmd == "hud" then
    Dev.HudCommand()
  elseif cmd == "lag" then
    Dev.LagCommand(rest)
  elseif cmd == "" or cmd == "stats" then
    summary()
  else
    say(HELP)
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, _, name)
  if name == ADDON then
    self:UnregisterEvent("ADDON_LOADED")
    if AME_DB and AME_DB.dev and AME_DB.dev.on then
      start(true)
      say("measuring (/amedev send when you're done, /amedev off to stop)")
    end
  end
end)
