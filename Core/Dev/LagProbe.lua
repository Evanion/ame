-- Dev-only: /amedev lag. Which addon makes the game stutter in combat. Uses the game's addon profiler
-- (C_AddOnProfiler: the time each addon took in the last frame), or, on clients without it, the old CPU counters
-- (GetAddOnCPUUsage, which need /console scriptProfile 1 and a /reload, and slow everything down while on).
--
--   /amedev lag        arm / disarm: every fight from then on is measured (kept armed across /reload)
--   /amedev lag now    measure the next 15 seconds, in or out of combat
--   /amedev lag last   the last report again
--
-- A fight: from entering combat to leaving it. Every frame, each loaded addon's time in that frame is added up;
-- the report lists the addons that took the most in all, their worst single frame, and how many frames each held
-- up by over 5 and 50 ms. With it, the game's own frame times: how many frames were slow (under 30 fps) and the
-- worst. Reports are saved in AME_DB.dev.lag (the last 10) to be read from the SavedVariables file.
local _, ns = ...

local Dev = ns.Dev
local Lag = {}
Dev.Lag = Lag

Lag.TOP = 8
Lag.KEEP = 10
Lag.NOW_SECONDS = 15
Lag.SLOW_FRAME_MS = 33 -- under 30 fps
Lag.MIN_FRAMES = 30 -- shorter fights aren't worth a report

local function say(fmt, ...)
  print("|cff33ccffAME dev|r " .. fmt:format(...))
end

local function metric(name)
  return Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric[name]
end

-- how this client can measure addons: "profiler", "cpu" (scriptProfile on) or nil, and why not
function Lag.Source()
  local P = C_AddOnProfiler
  if P and P.GetAddOnMetric and metric("LastTime") then
    if P.IsEnabled and not P.IsEnabled() then
      return nil, "the game's addon profiler is switched off"
    end
    return "profiler"
  end
  if GetAddOnCPUUsage and GetCVar and GetCVar("scriptProfile") == "1" then
    return "cpu"
  end
  return nil, "this client has no addon profiler: /console scriptProfile 1, then /reload (slows the game while on)"
end

local function loadedAddOns()
  local out = {}
  local A = C_AddOns
  local n = (A and A.GetNumAddOns or GetNumAddOns)()
  for i = 1, n do
    local name = (A and A.GetAddOnInfo or GetAddOnInfo)(i)
    if name and (A and A.IsAddOnLoaded or IsAddOnLoaded)(name) then
      out[#out + 1] = name
    end
  end
  return out
end

---------------------------------------------------------------------------------------------------------------------
-- a measurement: Begin, Frame (every frame), Finish -> report

function Lag.Begin(label)
  local source, why = Lag.Source()
  if not source then
    return nil, why
  end
  local m = {
    label = label,
    source = source,
    at = GetServerTime(),
    started = debugprofilestop(),
    addons = loadedAddOns(),
    total = {},
    worst = {},
    over5 = {},
    over50 = {},
    frames = 0,
    slow = 0,
    worstFrame = 0,
    addonMs = 0,
  }
  if source == "cpu" then
    UpdateAddOnCPUUsage()
    m.cpu0 = {}
    for _, name in ipairs(m.addons) do
      m.cpu0[name] = GetAddOnCPUUsage(name) or 0
    end
  else
    -- the game counts frames each addon held up by over 5 / 50 ms: the fight's share is the difference
    local P = C_AddOnProfiler
    m.count5, m.count50 = {}, {}
    for _, name in ipairs(m.addons) do
      m.count5[name] = P.GetAddOnMetric(name, metric("CountTimeOver5Ms")) or 0
      m.count50[name] = P.GetAddOnMetric(name, metric("CountTimeOver50Ms")) or 0
    end
  end
  return m
end

function Lag.Frame(m, elapsed)
  local ms = (elapsed or 0) * 1000
  m.frames = m.frames + 1
  if ms > Lag.SLOW_FRAME_MS then
    m.slow = m.slow + 1
  end
  if ms > m.worstFrame then
    m.worstFrame = ms
  end
  if m.source ~= "profiler" then
    return
  end
  local P, last = C_AddOnProfiler, metric("LastTime")
  local all = 0
  for _, name in ipairs(m.addons) do
    local t = P.GetAddOnMetric(name, last) or 0
    if t > 0 then
      m.total[name] = (m.total[name] or 0) + t
      if t > (m.worst[name] or 0) then
        m.worst[name] = t
      end
      all = all + t
    end
  end
  m.addonMs = m.addonMs + all
end

-- the report: { label, at, seconds, frames, slow, worstFrame, addonMs, source, top = { { name, ms, perFrame, worst,
-- over5, over50 }, ... } }, the addons that took the most first
function Lag.Finish(m)
  local seconds = (debugprofilestop() - m.started) / 1000
  local rows = {}
  if m.source == "cpu" then
    UpdateAddOnCPUUsage()
    for _, name in ipairs(m.addons) do
      local ms = (GetAddOnCPUUsage(name) or 0) - (m.cpu0[name] or 0)
      if ms > 0 then
        rows[#rows + 1] = { name = name, ms = ms }
        m.addonMs = m.addonMs + ms
      end
    end
  else
    local P = C_AddOnProfiler
    for _, name in ipairs(m.addons) do
      local ms = m.total[name] or 0
      local over5 = (P.GetAddOnMetric(name, metric("CountTimeOver5Ms")) or 0) - (m.count5[name] or 0)
      local over50 = (P.GetAddOnMetric(name, metric("CountTimeOver50Ms")) or 0) - (m.count50[name] or 0)
      if ms > 0 or over5 > 0 then
        rows[#rows + 1] = { name = name, ms = ms, worst = m.worst[name], over5 = over5, over50 = over50 }
      end
    end
  end
  table.sort(rows, function(a, b)
    return a.ms > b.ms
  end)
  for _, r in ipairs(rows) do
    r.perFrame = m.frames > 0 and r.ms / m.frames or 0
    r.share = m.addonMs > 0 and r.ms / m.addonMs or 0
  end
  for i = Lag.TOP + 1, #rows do
    rows[i] = nil
  end
  return {
    label = m.label,
    at = m.at,
    seconds = seconds,
    frames = m.frames,
    slow = m.slow,
    worstFrame = m.worstFrame,
    addonMs = m.addonMs,
    source = m.source,
    top = rows,
  }
end

function Lag.Print(r)
  if not r then
    return say("no report yet: /amedev lag to measure your next fights")
  end
  local fps = r.seconds > 0 and r.frames / r.seconds or 0
  say(
    "%s (%s, %.0f s): %d frames, %.0f fps, %d slow (under 30 fps), worst %.0f ms; addons %.1f ms a frame",
    r.label,
    date("%H:%M", r.at),
    r.seconds,
    r.frames,
    fps,
    r.slow,
    r.worstFrame,
    r.frames > 0 and r.addonMs / r.frames or 0
  )
  if #r.top == 0 then
    return say("no addon took measurable time")
  end
  for i, row in ipairs(r.top) do
    if r.source == "cpu" then
      say("%d. %s  %.0f ms in all (%.0f%%), %.2f ms a frame", i, row.name, row.ms, row.share * 100, row.perFrame)
    else
      say(
        "%d. %s  %.0f ms in all (%.0f%%), %.2f ms a frame, worst %.1f ms, %d frames over 5 ms, %d over 50 ms",
        i,
        row.name,
        row.ms,
        row.share * 100,
        row.perFrame,
        row.worst or 0,
        row.over5 or 0,
        row.over50 or 0
      )
    end
  end
end

---------------------------------------------------------------------------------------------------------------------
-- driving it: fights while armed, or the next 15 seconds

local current
local frame = CreateFrame("Frame")

local function store()
  AME_DB.dev = AME_DB.dev or {}
  AME_DB.dev.lag = AME_DB.dev.lag or {}
  return AME_DB.dev.lag
end

local function finish()
  if not current then
    return
  end
  local m = current
  current = nil
  frame:SetScript("OnUpdate", nil)
  if m.frames < Lag.MIN_FRAMES then
    return
  end
  local report = Lag.Finish(m)
  local db = store()
  db.reports = db.reports or {}
  table.insert(db.reports, 1, report)
  for i = Lag.KEEP + 1, #db.reports do
    db.reports[i] = nil
  end
  Lag.Print(report)
end

local function begin(label, seconds)
  if current then
    return
  end
  local m, why = Lag.Begin(label)
  if not m then
    return say("can't measure: %s", why)
  end
  current = m
  local left = seconds
  frame:SetScript("OnUpdate", function(_, elapsed)
    Lag.Frame(m, elapsed)
    if left then
      left = left - elapsed
      if left <= 0 then
        finish()
      end
    end
  end)
end

frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
  if not (AME_DB and AME_DB.dev and AME_DB.dev.lag and AME_DB.dev.lag.armed) then
    return
  end
  if event == "PLAYER_REGEN_DISABLED" then
    begin("fight")
  elseif current and current.label == "fight" then
    finish()
  end
end)

function Dev.LagCommand(rest)
  local sub = (rest or ""):match("^%s*(%S*)"):lower()
  local db = store()
  if sub == "now" then
    say("measuring the next %d seconds...", Lag.NOW_SECONDS)
    begin("the last " .. Lag.NOW_SECONDS .. " s", Lag.NOW_SECONDS)
  elseif sub == "last" then
    Lag.Print(db.reports and db.reports[1])
  else
    db.armed = not db.armed
    local source, why = Lag.Source()
    if db.armed then
      say(
        "lag: measuring every fight from now on (%s); a report when each ends. /amedev lag again to stop.",
        source and (source == "profiler" and "the game's addon profiler" or "CPU counters") or ("can't: " .. why)
      )
    else
      say("lag: stopped measuring fights")
      if current and current.label == "fight" then
        current = nil
        frame:SetScript("OnUpdate", nil)
      end
    end
  end
end
