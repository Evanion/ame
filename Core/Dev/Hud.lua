-- Dev-only: /amedev hud. A small box on screen saying what AME is doing right now, for watching it while the game
-- stutters: its time per frame (the game's addon profiler), the frame rate, the background job running and those
-- waiting, sync transfers, saved tables still unpacking, memory and when Lua's garbage collector last ran, and the
-- slowest frame AME took in the last 10 seconds (with what it was running). Drag it to move it; it remembers where
-- it was and stays on across /reload until /amedev hud again.
local _, ns = ...

local Dev = ns.Dev
local Hud = {}
Dev.Hud = Hud

Hud.EVERY = 0.25 -- seconds between refreshes
Hud.WORST_WINDOW = 10 -- seconds the "worst" line looks back over
Hud.SELF = "AzerothMercantileExchange"
-- the log (AME_DB.dev.hudLog, read from the SavedVariables file after a /reload or logout): one line a second while
-- the box is on, and every hitch - a frame where AME took over SELF_HITCH_MS, or the whole frame took over
-- FRAME_HITCH_MS whoever caused it - with what AME was doing
Hud.LOG_SECONDS = 1800 -- half an hour of seconds
Hud.LOG_HITCHES = 300
Hud.SELF_HITCH_MS = 20
Hud.FRAME_HITCH_MS = 100

local function db()
  AME_DB.dev = AME_DB.dev or {}
  AME_DB.dev.hud = AME_DB.dev.hud or {}
  return AME_DB.dev.hud
end

local function metric(name)
  return Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric[name]
end

local function mine(name)
  local P = C_AddOnProfiler
  local m = metric(name)
  return P and P.GetAddOnMetric and m and P.GetAddOnMetric(Hud.SELF, m) or nil
end

local function color(ms, warn, bad)
  if not ms then
    return "?"
  end
  local c = ms >= bad and "ff6159" or ms >= warn and "ffcc33" or "66dd77"
  return ("|cff%s%.1f ms|r"):format(c, ms)
end

-- the lines shown (pure enough to test: reads AME's state)
function Hud.Lines(state)
  local AME = ns.AME
  local lines = {}
  local fps = GetFramerate and GetFramerate() or 0
  lines[#lines + 1] = ("AME %s a frame (avg %s)  ·  %.0f fps"):format(
    color(state.last, 2, 10),
    color(mine("RecentAverageTime"), 1, 4),
    fps
  )
  if state.worst then
    lines[#lines + 1] = ("worst 10 s: %s  %s"):format(color(state.worst.ms, 5, 30), state.worst.what or "")
  end
  -- background jobs: the one running, then the queue
  local jobs = AME and AME.jobs
  local queue = jobs and jobs.queue or {}
  if #queue > 0 then
    local names = {}
    for i, j in ipairs(queue) do
      if i > 4 then
        names[#names + 1] = ("+%d"):format(#queue - 4)
        break
      end
      names[#names + 1] = j.name .. (j.budgetMs and " (low)" or "")
    end
    local paused = AME.JobsMayRun and not AME:JobsMayRun()
    lines[#lines + 1] = ("jobs: %s%s"):format(
      table.concat(names, ", "),
      paused and "  |cffffcc33(paused: combat)|r" or ""
    )
  else
    lines[#lines + 1] = "jobs: none"
  end
  if AME and AME.IndexBusy and AME:IndexBusy() then
    local shards = {}
    for shard in pairs(AME.indexBuilding or {}) do
      shards[#shards + 1] = tostring(shard)
    end
    lines[#lines + 1] = "market data: rebuilding " .. table.concat(shards, ", ")
  end
  -- saved tables still unpacking after login
  local packed = ns.Packed and ns.Packed.tasks
  if packed and next(packed) then
    local names = {}
    for name in pairs(packed) do
      names[#names + 1] = name
    end
    table.sort(names)
    lines[#lines + 1] = "unpacking: " .. table.concat(names, ", ")
  end
  -- sync
  local svc = ns.SyncService
  local v2 = svc and svc.V2Status and svc:V2Status()
  if v2 then
    local parts = {}
    if v2.sending then
      parts[#parts + 1] = ("sending %d/%d"):format(v2.sending.sent or 0, v2.sending.n or 0)
    end
    if (v2.queued or 0) > 0 then
      parts[#parts + 1] = ("%d waiting"):format(v2.queued)
    end
    for _, e in ipairs(v2.senders or {}) do -- per sender: a catch-up queues a dozen objects from one guildmate
      parts[#parts + 1] = ("from %s: %d obj, %d/%d blocks, ~%d min left"):format(
        e.from,
        e.objects,
        e.got,
        e.n,
        math.ceil(e.secondsLeft / 60)
      )
    end
    lines[#lines + 1] = "sync v2: " .. (#parts > 0 and table.concat(parts, ", ") or "idle")
  end
  -- what sync kept and turned down: since the box came on, and all time (with the reasons)
  local st = svc and svc.stats
  if st then
    local base = state.syncBase
    if not base then
      base = { ok = st.syncReceived or 0, bad = st.syncRejected or 0, why = {} }
      for k, n in pairs(st.rejectedWhy or {}) do
        base.why[k] = n
      end
      state.syncBase = base
    end
    local why = {}
    for k, n in pairs(st.rejectedWhy or {}) do
      local d = n - (base.why[k] or 0)
      if d > 0 then
        why[#why + 1] = ("%s %d"):format(k, d)
      end
    end
    table.sort(why)
    local ok, bad = (st.syncReceived or 0) - base.ok, (st.syncRejected or 0) - base.bad
    lines[#lines + 1] = ("sync: accepted |cff66dd77%d|r, rejected %s%d|r%s  ·  all time %d / %d"):format(
      ok,
      bad > 0 and "|cffff6159" or "|cff66dd77",
      bad,
      #why > 0 and (" (" .. table.concat(why, ", ") .. ")") or "",
      st.syncReceived or 0,
      st.syncRejected or 0
    )
  end
  -- memory and the garbage collector
  lines[#lines + 1] = ("Lua memory %.1f MB (all addons)%s"):format(
    (collectgarbage("count") or 0) / 1024,
    state.gcAt and ("  ·  GC %.0f s ago (-%d KB)"):format(GetTime() - state.gcAt, state.gcFreed or 0) or ""
  )
  if InCombatLockdown and InCombatLockdown() then
    lines[#lines + 1] = "|cffff6159in combat|r"
  end
  return lines
end

---------------------------------------------------------------------------------------------------------------------
-- the box

local box
local state = { samples = {} }

local function logTable()
  AME_DB.dev = AME_DB.dev or {}
  local log = AME_DB.dev.hudLog
  if not log or not log.seconds then
    log = { seconds = {}, hitches = {} }
    AME_DB.dev.hudLog = log
  end
  return log
end

local function push(list, entry, keep)
  list[#list + 1] = entry
  while #list > keep do
    table.remove(list, 1)
  end
end

local function queueNames()
  local jobs = ns.AME and ns.AME.jobs
  local names = {}
  for i, j in ipairs(jobs and jobs.queue or {}) do
    if i > 6 then
      break
    end
    names[#names + 1] = j.name
  end
  return table.concat(names, ",")
end

local function inCombat()
  return InCombatLockdown and InCombatLockdown() or false
end

local function build()
  box = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  box:SetSize(330, 40)
  box:SetFrameStrata("HIGH")
  if box.SetBackdrop then
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    box:SetBackdropColor(0, 0, 0, 0.7)
  end
  local pos = db().pos
  box:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos and pos[1] or 20, pos and pos[2] or -200)
  box:SetMovable(true)
  box:EnableMouse(true)
  box:RegisterForDrag("LeftButton")
  box:SetScript("OnDragStart", box.StartMoving)
  box:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local left, top = self:GetLeft(), self:GetTop()
    if left and top then
      db().pos = { left, top - (UIParent:GetTop() or 0) }
    end
  end)
  box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  box.text:SetPoint("TOPLEFT", 6, -6)
  box.text:SetJustifyH("LEFT")
  local since, lastMem = 0, collectgarbage("count")
  local sec = { frames = 0, ame = 0, worst = 0, gameWorst = 0, elapsed = 0 }
  box:SetScript("OnUpdate", function(_, elapsed)
    -- every frame: AME's time in it, and whether memory fell (the garbage collector ran)
    local now = GetTime()
    local ms = mine("LastTime")
    state.last = ms
    local jobs = ns.AME and ns.AME.jobs
    if ms and ms > 1 then
      state.samples[#state.samples + 1] = { at = now, ms = ms, what = jobs and jobs.lastName }
    end
    local mem = collectgarbage("count")
    local gc = mem < lastMem - 64
    if gc then
      state.gcAt, state.gcFreed = now, math.floor(lastMem - mem)
    end
    -- the log
    local frameMs = elapsed * 1000
    sec.frames, sec.ame, sec.elapsed = sec.frames + 1, sec.ame + (ms or 0), sec.elapsed + elapsed
    sec.worst, sec.gameWorst = math.max(sec.worst, ms or 0), math.max(sec.gameWorst, frameMs)
    if (ms or 0) > Hud.SELF_HITCH_MS or frameMs > Hud.FRAME_HITCH_MS then
      push(logTable().hitches, {
        t = GetServerTime(),
        frame = math.floor(frameMs),
        ame = ms and math.floor(ms * 10 + 0.5) / 10,
        job = jobs and jobs:Busy() and jobs.lastName or "none", -- lastName stays after the queue empties
        queue = queueNames(),
        memKB = math.floor(mem - lastMem),
        gc = gc or nil,
        combat = inCombat() or nil,
        ui = ns.UI and ns.UI.frame and ns.UI.frame:IsShown() and ns.UI.current or nil,
      }, Hud.LOG_HITCHES)
    end
    if sec.elapsed >= 1 then
      push(logTable().seconds, {
        t = GetServerTime(),
        fps = sec.frames,
        ame = math.floor(sec.ame * 10 + 0.5) / 10, -- AME's ms in that second
        worst = math.floor(sec.worst * 10 + 0.5) / 10,
        frameWorst = math.floor(sec.gameWorst),
        queue = queueNames(),
        memMB = math.floor(mem / 102.4) / 10,
        combat = inCombat() or nil,
      }, Hud.LOG_SECONDS)
      sec = { frames = 0, ame = 0, worst = 0, gameWorst = 0, elapsed = 0 }
    end
    lastMem = mem
    since = since + elapsed
    if since < Hud.EVERY then
      return
    end
    since = 0
    -- the worst frame in the window
    local keep, worst = {}, nil
    for _, s in ipairs(state.samples) do
      if now - s.at <= Hud.WORST_WINDOW then
        keep[#keep + 1] = s
        if not worst or s.ms > worst.ms then
          worst = s
        end
      end
    end
    state.samples, state.worst = keep, worst
    local lines = Hud.Lines(state)
    box.text:SetText(table.concat(lines, "\n"))
    box:SetHeight(12 + #lines * 13)
  end)
end

function Hud.Show(on)
  if on and not box then
    build()
  end
  if box then
    box:SetShown(on)
  end
end

function Dev.HudCommand()
  local d = db()
  d.on = not d.on
  Hud.Show(d.on)
  print(
    "|cff33ccffAME dev|r hud "
      .. (d.on and "on, and logging (drag it to move it; /amedev hud to hide; /reload saves the log)" or "off")
  )
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  if AME_DB and AME_DB.dev and AME_DB.dev.hud and AME_DB.dev.hud.on then
    Hud.Show(true)
  end
end)
