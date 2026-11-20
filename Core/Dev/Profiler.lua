-- Dev-only profiler (Core/Dev never ships: scripts/package.sh and .pkgmeta strip it). Measures what AME costs the
-- client while you play:
--   CPU     time per background job (by name) and per game event handler: total, calls, worst single run
--   frames  AME's share of each frame (jobs + events), and spikes over SPIKE_MS with what caused them
--   memory  AME's Lua memory sampled every SAMPLE_S seconds (current, peak, the last hour)
--   sizes   an estimate of what each big structure takes in memory and in SavedVariables (/amedev sizes)
-- /amedev prints the summary; everything is kept in AME_DB.dev (saved on logout / reload) so it can be read from the
-- SavedVariables file. /amedev reset starts over.
local ADDON, ns = ...

local Dev = {}
ns.Dev = Dev

Dev.SPIKE_MS = 12 -- a frame where AME took longer than this is logged
Dev.SPIKES_KEEP = 40
Dev.SAMPLE_S = 10
Dev.SAMPLES_KEEP = 360 -- an hour of memory samples

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
local db -- AME_DB.dev
local frameMs = 0 -- AME's time in the current frame
local frameWhat -- the biggest single cost in it

local function account(kind, name, ms)
  if not db then
    return
  end
  Dev.Record(db[kind], name, ms)
  frameMs = frameMs + ms
  if not frameWhat or ms > frameWhat.ms then
    frameWhat = { what = kind .. " " .. tostring(name), ms = ms }
  end
end

-- jobs: time each Tick (the runner records which job it ran)
local runner = AME.jobs
local tick = runner.Tick
runner.Tick = function(self, ...)
  local t0 = clock()
  tick(self, ...)
  account("jobs", self.lastName or "?", clock() - t0)
end

-- events: wrap AME's handlers (Main.lua dispatches through this table on every event)
for event, fn in pairs(AME.handlers or {}) do
  AME.handlers[event] = function(...)
    local t0 = clock()
    fn(...)
    account("events", event, clock() - t0)
  end
end

local function memoryKB()
  if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    UpdateAddOnMemoryUsage()
    return GetAddOnMemoryUsage(ADDON)
  end
  return nil
end

local frames = CreateFrame("Frame")
local sinceSample = 0
frames:SetScript("OnUpdate", function(_, elapsed)
  if not db then
    return
  end
  -- the frame that just ended
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
  frameMs, frameWhat = 0, nil
  sinceSample = sinceSample + elapsed
  if sinceSample >= Dev.SAMPLE_S then
    sinceSample = 0
    local m = memoryKB()
    if m then
      local mem = db.memory
      mem.now = math.floor(m)
      mem.peak = math.max(mem.peak or 0, mem.now)
      local list = mem.samples
      list[#list + 1] = { GetServerTime(), mem.now }
      while #list > Dev.SAMPLES_KEEP do
        table.remove(list, 1)
      end
    end
  end
end)

local function fresh()
  return {
    since = GetServerTime(),
    jobs = {},
    events = {},
    frames = { n = 0, ms = 0, max = 0 },
    spikes = {},
    memory = { samples = {} },
  }
end

local function say(fmt, ...)
  print("|cff33ccffAME dev|r " .. fmt:format(...))
end

local function summary()
  local mins = math.max(1, (GetServerTime() - db.since) / 60)
  say("since %s (%.0f min)", date("%H:%M", db.since), mins)
  local m = memoryKB()
  say("memory: %s now, peak %s", m and kb(m * 1024) or "?", kb((db.memory.peak or 0) * 1024))
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
  for _, kind in ipairs({ "jobs", "events" }) do
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
    add("store " .. ns.ShardLabel(shard), { data = store.data, cache = store.cache, texts = store.texts })
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
    db.sizes = { at = GetServerTime(), parts = out }
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

SLASH_AMEDEV1 = "/amedev"
SlashCmdList.AMEDEV = function(msg)
  local cmd = (msg or ""):match("^%s*(%S*)"):lower()
  if not db then
    return say("not started yet")
  end
  if cmd == "reset" then
    AME_DB.dev = fresh()
    db = AME_DB.dev
    say("reset")
  elseif cmd == "sizes" then
    sizes()
  elseif cmd == "gc" then
    local before = collectgarbage("count")
    collectgarbage("collect")
    say("garbage collected: %s -> %s (all addons)", kb(before * 1024), kb(collectgarbage("count") * 1024))
  elseif cmd == "ui" then
    local ok, err = pcall(Dev.ProbeUI, say)
    if not ok then
      say("ui probe failed: %s", tostring(err))
    end
  elseif cmd == "crafting" then
    -- switch Crafting's recording on / off before it has its Settings checkbox
    local on = not ns.Settings:Get("crafting")
    ns.Settings:Set("crafting", on)
    say("crafting %s", on and "on: open your professions, then /reload" or "off")
    if on and ns.Professions then
      ns.Professions:RecordSpellbook()
      ns.Professions:Record() -- a profession window that's already open
    end
  elseif cmd == "ah" then
    local ok, err = pcall(Dev.ProbeAH, say, (msg or ""):match("^%s*%S+%s*(.*)$"))
    if not ok then
      say("auction house probe failed: %s", tostring(err))
    end
  elseif cmd == "recipes" then
    local ok, err = pcall(Dev.ProbeRecipes, say)
    if not ok then
      say("recipe probe failed: %s", tostring(err))
    end
  elseif cmd == "scanbutton" then
    -- why the Full scan button isn't where it should be
    local S = ns.ScanButton
    local b = S and S.button
    local ah = AuctionHouseFrame or AuctionFrame
    say(
      "frames: modern %s, old %s  ·  auctionator %s, tsm %s  ·  ReplicateItems %s",
      tostring(AuctionHouseFrame ~= nil),
      tostring(AuctionFrame ~= nil),
      tostring(_G.Auctionator ~= nil),
      tostring(_G.TSM_API ~= nil),
      tostring(C_AuctionHouse and C_AuctionHouse.ReplicateItems ~= nil)
    )
    if not b then
      return say("no button made (Attach never ran or failed)")
    end
    local state, left = S:State()
    say(
      "button: shown %s, visible %s, text %s, state %s %s, parent %s",
      tostring(b:IsShown()),
      tostring(b:IsVisible()),
      tostring(b:GetText()),
      tostring(state),
      tostring(left or ""),
      tostring(b:GetParent() and b:GetParent():GetName())
    )
    say(
      "where: left %s top %s size %sx%s alpha %s strata %s level %s  ·  screen top %s  ·  window top %s right %s",
      tostring(b:GetLeft()),
      tostring(b:GetTop()),
      tostring(b:GetWidth()),
      tostring(b:GetHeight()),
      tostring(b:GetEffectiveAlpha()),
      tostring(b:GetFrameStrata()),
      tostring(b:GetFrameLevel()),
      tostring(UIParent:GetTop()),
      tostring(ah and ah:GetTop()),
      tostring(ah and ah:GetRight())
    )
    local close = ah and rawget(ah, "CloseButton")
    say(
      "close button: %s  level %s strata %s  top %s left %s",
      tostring(close ~= nil),
      tostring(close and close:GetFrameLevel()),
      tostring(close and close:GetFrameStrata()),
      tostring(close and close:GetTop()),
      tostring(close and close:GetLeft())
    )
  elseif cmd == "" or cmd == "stats" then
    summary()
  else
    say(
      "/amedev - CPU, frames and memory since the last reset  ·  /amedev sizes  ·  /amedev gc  ·  /amedev recipes"
        .. "  ·  /amedev crafting  ·  /amedev ah <item>  ·  /amedev scanbutton"
        .. "  ·  /amedev reset"
    )
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, name)
  if name == ADDON then
    AME_DB = AME_DB or {}
    AME_DB.dev = AME_DB.dev or fresh()
    db = AME_DB.dev
    say("profiling (dev build) - /amedev")
  end
end)
