-- /amedev send [name] and /amedev receive. A tester who turned the profiler on (/amedev on) sends what their profiler
-- recorded - the lag reports, the hud log (its hitches, and its seconds summed up per minute), the slowest jobs and
-- events, AME's own frame spikes, sync counts - to a developer's AME, which keeps it in AME_DB.dev.received[sender]
-- (read from the SavedVariables file).
--
-- It travels as addon whispers on its own prefix: packed (LibDeflate), cut into 240-character pieces, one a second
-- (the game drops whispers beyond a short burst without saying so). The receiver only takes reports while
-- /amedev receive is on (until /amedev receive again), and at most MAX_PIECES pieces from one sender.
local _, ns = ...

local Dev = ns.Dev
local Report = {}
Dev.Report = Report

Report.PREFIX = "AMEDEV"
Report.PIECE = 240
Report.EVERY = 1.05
Report.MAX_PIECES = 600 -- ~140 KB packed: far more than a report
-- who /amedev send whispers when no name is given: AME's developer (the guide's footer names them too)
Report.DEFAULT_TO = "Tyken Evanion"

local function say(fmt, ...)
  print("|cff33ccffAME dev|r " .. fmt:format(...))
end

---------------------------------------------------------------------------------------------------------------------
-- a small, safe serializer: numbers, strings, booleans and tables of them (no code is ever loaded)

function Report.Serialize(v)
  local out = {}
  local function put(x)
    local t = type(x)
    if t == "number" then
      out[#out + 1] = "n" .. tostring(x) .. ";"
    elseif t == "string" then
      out[#out + 1] = "s" .. #x .. ":" .. x
    elseif t == "boolean" then
      out[#out + 1] = x and "T" or "F"
    elseif t == "table" then
      out[#out + 1] = "t"
      for k, val in pairs(x) do
        local kt, vt = type(k), type(val)
        if (kt == "string" or kt == "number") and vt ~= "function" and vt ~= "userdata" and vt ~= "thread" then
          put(k)
          put(val)
        end
      end
      out[#out + 1] = "e"
    else
      out[#out + 1] = "Z" -- nil and anything else
    end
  end
  put(v)
  return table.concat(out)
end

function Report.Deserialize(text)
  local pos = 1
  local depth = 0
  local function get()
    local tag = text:sub(pos, pos)
    pos = pos + 1
    if tag == "n" then
      local stop = text:find(";", pos, true)
      local n = tonumber(text:sub(pos, stop - 1))
      pos = stop + 1
      return n
    elseif tag == "s" then
      local colon = text:find(":", pos, true)
      local len = tonumber(text:sub(pos, colon - 1))
      if colon + len > #text then
        error("truncated")
      end
      local s = text:sub(colon + 1, colon + len)
      pos = colon + len + 1
      return s
    elseif tag == "T" then
      return true
    elseif tag == "F" then
      return false
    elseif tag == "Z" then
      return nil
    elseif tag == "t" then
      depth = depth + 1
      if depth > 20 then
        error("too deep")
      end
      local t = {}
      while text:sub(pos, pos) ~= "e" do
        if pos > #text then
          error("truncated")
        end
        local k = get()
        local val = get()
        if k ~= nil then
          t[k] = val
        end
      end
      pos = pos + 1
      depth = depth - 1
      return t
    end
    error("bad tag " .. tostring(tag))
  end
  local ok, v = pcall(get)
  return ok and pos == #text + 1 and v or nil -- all of it, nothing left over
end

---------------------------------------------------------------------------------------------------------------------
-- what's sent

-- the hud log's seconds, per minute: fps (average), AME's ms (in all), AME's worst frame, the game's worst frame,
-- seconds in combat
local function perMinute(seconds)
  local out, cur = {}, nil
  for _, e in ipairs(seconds or {}) do
    local m = math.floor(e.t / 60)
    if not cur or cur.m ~= m then
      cur = { m = m, t = m * 60, n = 0, fps = 0, ame = 0, worst = 0, frameWorst = 0, combat = 0 }
      out[#out + 1] = cur
    end
    cur.n = cur.n + 1
    cur.fps = cur.fps + (e.fps or 0)
    cur.ame = cur.ame + (e.ame or 0)
    cur.worst = math.max(cur.worst, e.worst or 0)
    cur.frameWorst = math.max(cur.frameWorst, e.frameWorst or 0)
    cur.combat = cur.combat + (e.combat and 1 or 0)
  end
  for _, c in ipairs(out) do
    c.fps = math.floor(c.fps / math.max(1, c.n) + 0.5)
    c.ame = math.floor(c.ame + 0.5)
    c.m = nil
  end
  return out
end

function Report.Build()
  local dev = AME_DB.dev or {}
  local hud = dev.hudLog or {}
  local svc = ns.SyncService
  local addons = 0
  local A = C_AddOns
  if A and A.GetNumAddOns then
    for i = 1, A.GetNumAddOns() do
      local name = A.GetAddOnInfo(i)
      if name and A.IsAddOnLoaded(name) then
        addons = addons + 1
      end
    end
  end
  local version, build
  if GetBuildInfo then
    version, build = GetBuildInfo()
  end
  return {
    v = 1,
    at = GetServerTime(),
    ame = ns.VERSION,
    client = version and (version .. " " .. tostring(build)) or nil,
    addons = addons,
    lag = dev.lag and dev.lag.reports,
    hitches = hud.hitches,
    minutes = perMinute(hud.seconds),
    jobs = Dev.Top(dev.jobs or {}, 25),
    events = Dev.Top(dev.events or {}, 25),
    spikes = dev.spikes,
    frames = dev.frames,
    sync = svc and svc.stats,
    syncV2 = svc and svc.v2 and svc.v2.stats,
    protocol = svc and svc.Protocol and svc:Protocol(),
    -- why sync does or doesn't work here: settings, market, prefixes, who was heard, the last messages in and out
    -- and why any were turned down (SyncService:Diagnostics)
    syncDiag = svc and svc.Diagnostics and svc.AME and svc:Diagnostics() or nil,
  }
end

---------------------------------------------------------------------------------------------------------------------
-- sending

local function deflate()
  return LibStub and LibStub("LibDeflate", true)
end

local function register()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(Report.PREFIX)
  end
end

-- the report as pieces: "<id>|<i>|<n>|<text>"
function Report.Pieces(report, id)
  local lib = deflate()
  local text = lib:EncodeForWoWAddonChannel(lib:CompressDeflate(Report.Serialize(report)))
  local n = math.ceil(#text / Report.PIECE)
  local out = {}
  for i = 1, n do
    out[i] = ("%s|%d|%d|%s"):format(id, i, n, text:sub((i - 1) * Report.PIECE + 1, i * Report.PIECE))
  end
  return out
end

local sending
function Report.Send(target)
  if not target or target == "" then
    target = Report.DEFAULT_TO
  end
  if not target then
    return say("usage: /amedev send <name> - whispers your profiler report to that player (they run /amedev receive)")
  end
  if sending then
    return say("still sending to %s (%d of %d)", sending.target, sending.i, #sending.pieces)
  end
  register()
  local pieces = Report.Pieces(Report.Build(), tostring(GetServerTime() % 100000))
  sending = { target = target, pieces = pieces, i = 0 }
  say("sending your report to %s: %d messages, about %d seconds", target, #pieces, math.ceil(#pieces * Report.EVERY))
  local function step()
    local s = sending
    if not s then
      return
    end
    s.i = s.i + 1
    C_ChatInfo.SendAddonMessage(Report.PREFIX, s.pieces[s.i], "WHISPER", s.target)
    if s.i >= #s.pieces then
      sending = nil
      return say("report sent to %s", s.target)
    end
    C_Timer.After(Report.EVERY, step)
  end
  step()
end

---------------------------------------------------------------------------------------------------------------------
-- receiving

local incoming = {}

local function receiving()
  return AME_DB and AME_DB.dev and AME_DB.dev.receiving
end

function Report.OnMessage(msg, sender)
  if not receiving() then
    return
  end
  local id, i, n, text = msg:match("^(%d+)|(%d+)|(%d+)|(.*)$")
  i, n = tonumber(i), tonumber(n)
  if not (id and i and n) or n > Report.MAX_PIECES or i < 1 or i > n then
    return
  end
  local key = sender .. "#" .. id
  local r = incoming[key]
  if not r then
    r = { n = n, got = 0, parts = {} }
    incoming[key] = r
  end
  if not r.parts[i] then
    r.parts[i] = text
    r.got = r.got + 1
    if r.got % 25 == 0 then
      say("report from %s: %d of %d", sender, r.got, r.n)
    end
  end
  if r.got < r.n then
    return
  end
  incoming[key] = nil
  local lib = deflate()
  local packed = lib:DecodeForWoWAddonChannel(table.concat(r.parts))
  local report = packed and Report.Deserialize(lib:DecompressDeflate(packed) or "")
  if type(report) ~= "table" then
    return say("report from %s arrived damaged", sender)
  end
  AME_DB.dev.received = AME_DB.dev.received or {}
  AME_DB.dev.received[sender] = { at = GetServerTime(), report = report }
  say("report from %s received - /reload to save it", sender)
end

function Report.Receive()
  AME_DB.dev = AME_DB.dev or {}
  local dev = AME_DB.dev
  dev.receiveUntil = nil -- the old 30-minute window
  dev.receiving = not dev.receiving or nil
  if dev.receiving then
    register()
    say("taking profiler reports (/amedev send <your name>) until /amedev receive again")
  else
    say("no longer taking profiler reports")
  end
end

if not CreateFrame then -- loaded outside the game (specs)
  return
end
local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
  if event == "PLAYER_LOGIN" then
    if receiving() then
      register()
    end
    return
  end
  if prefix == Report.PREFIX and channel == "WHISPER" then
    Report.OnMessage(msg, sender)
  end
end)
