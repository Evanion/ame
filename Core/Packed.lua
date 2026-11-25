-- Big saved tables of small entries (posting price models, random-suffix variant names and item strings: ~120k
-- entries) saved as one string each. WoW reads SavedVariables during the loading screen, and a table of many small
-- entries is the slowest thing it reads: on a real 20 MB file, packing these took the load from ~240 ms to ~30 ms
-- (Lua 5.1, the same file). After login they're unpacked back into their tables a slice at a time, out of combat, at
-- low priority (Start); anything that needs one sooner calls Ready(name), which unpacks the rest at once.
--
--   Packed.Pack(t)                         -> "key\tvalue\n..." (number keys as "#123"; string values only)
--   Packed.Later(name, text, into, onEntry, onDone)   unpack into `into` in the background (keeps entries it has)
--   Packed.Ready(name)                     -> unpacks what's left of `name` now
--   Packed.ReadyAll()                      everything now
--
-- Saving without packing in the logout frame (packing ~120k entries there took a noticeable part of it): a table keeps
-- the text it was read from, and a change marks it so a low-priority background job packs it again a little later.
-- Logout packs only a table whose text isn't current (changed since, and its job not done yet).
--   Packed.Keep(key, text, t)              the text `t` was read from, at login
--   Packed.Touch(key, t)                   `t` changed: its text is stale; packed again in the background later
--   Packed.Text(key, t, name) -> text      what to save: the kept text if current, else `t` packed now (after
--                                          unpacking what's left of `name`, the Later task that fills `t`)
local _, ns = ...

local Packed = { tasks = {}, order = {} }
ns.Packed = Packed

Packed.SLICE = 1500 -- entries per step
Packed.EVERY = 0.05 -- seconds between steps
Packed.DELAY = 2 -- seconds after login before the first step

-- one entry's line, or nil when it can't be packed
local function line(k, v)
  local key = type(k) == "number" and ("#" .. ("%.0f"):format(k)) or (type(k) == "string" and k or nil)
  if key and type(v) == "string" and not key:find("[\t\n]") and not v:find("[\t\n]") then
    return key .. "\t" .. v
  end
  return nil
end

function Packed.Pack(t)
  local parts, n = {}, 0
  for k, v in pairs(t or {}) do
    local l = line(k, v)
    if l then
      n = n + 1
      parts[n] = l
    end
  end
  return table.concat(parts, "\n")
end

local function keyOf(k)
  if k:sub(1, 1) == "#" then
    return tonumber(k:sub(2))
  end
  return k
end

-- a whole packed text into a table at once (tests, small texts)
function Packed.Unpack(text, into)
  into = into or {}
  for k, v in (text or ""):gmatch("([^\t\n]+)\t([^\n]*)") do
    local key = keyOf(k)
    if key ~= nil and into[key] == nil then
      into[key] = v
    end
  end
  return into
end

-- step a task by up to n entries; true when it's done
local function step(task, n)
  local next = task.next
  for _ = 1, n do
    local k, v = next()
    if not k then
      task.done = true
      if task.onDone then
        task.onDone()
      end
      return true
    end
    local key = keyOf(k)
    if key ~= nil and task.into[key] == nil then
      task.into[key] = v
      if task.onEntry then
        task.onEntry(key, v)
      end
    end
  end
  return false
end

function Packed.Later(name, text, into, onEntry, onDone)
  if type(text) ~= "string" or text == "" then
    if onDone then
      onDone()
    end
    return
  end
  -- several texts under one name (one per auction house) unpack one after another
  local task = {
    next = text:gmatch("([^\t\n]+)\t([^\n]*)"),
    into = into,
    onEntry = onEntry,
    onDone = onDone,
  }
  local list = Packed.tasks[name]
  if list then
    list[#list + 1] = task
  else
    Packed.tasks[name] = { task }
    Packed.order[#Packed.order + 1] = name
  end
end

function Packed.Pending(name)
  return Packed.tasks[name] ~= nil
end

function Packed.Ready(name)
  local list = Packed.tasks[name]
  if not list then
    return
  end
  Packed.tasks[name] = nil
  for _, task in ipairs(list) do
    while not step(task, 100000) do
    end
  end
end

function Packed.ReadyAll()
  for _, name in ipairs(Packed.order) do
    Packed.Ready(name)
  end
end

-- the background steps: after login, a slice at a time, never in combat
function Packed.Start()
  local function tick()
    for _, name in ipairs(Packed.order) do
      local list = Packed.tasks[name]
      if list then
        if not (InCombatLockdown and InCombatLockdown()) then
          local task = list[1]
          if step(task, Packed.SLICE) then
            table.remove(list, 1)
            if #list == 0 then
              Packed.tasks[name] = nil
            end
          end
        end
        C_Timer.After(Packed.EVERY, tick)
        return
      end
    end
  end
  C_Timer.After(Packed.DELAY, tick)
end

-- ------------------------------------------------------------------------------------------------ kept texts

Packed.kept = {}
Packed.REPACK_DELAY = 30 -- seconds after the last change before packing again (a full scan changes thousands)
Packed.REPACK_BUDGET_MS = 2
Packed.REPACK_SLICE = 2000 -- entries per pause

local function kept(key)
  local k = Packed.kept[key]
  if not k then
    k = { gen = 0 }
    Packed.kept[key] = k
  end
  return k
end

function Packed.Keep(key, text, t)
  local k = kept(key)
  k.t, k.text, k.textGen = t, type(text) == "string" and text or nil, k.gen
end

-- pack t in a background job (paused in combat, as every job is); a change while it runs makes its text stale, so
-- it's dropped, and the job that change scheduled packs again
function Packed.Repack(key)
  local k = Packed.kept[key]
  local jobs = ns.AME and ns.AME.jobs
  if not (k and k.t and jobs) or (k.text and k.textGen == k.gen) then
    return
  end
  local gen, t = k.gen, k.t
  local name = "pack-" .. key
  jobs:Cancel(name)
  jobs:Add(name, function(job)
    -- the keys first, in one go: entries added while it pauses must not be met mid-traversal
    local keys, n = {}, 0
    for id in pairs(t) do
      n = n + 1
      keys[n] = id
    end
    job:Checkpoint()
    local parts, m = {}, 0
    for i = 1, n do
      local l = line(keys[i], t[keys[i]])
      if l then
        m = m + 1
        parts[m] = l
      end
      if i % Packed.REPACK_SLICE == 0 then
        job:Checkpoint()
      end
    end
    return table.concat(parts, "\n")
  end, function(ok, text)
    if ok and type(text) == "string" and k.gen == gen and k.t == t then
      k.text, k.textGen = text, gen
    end
  end, Packed.REPACK_BUDGET_MS)
end

function Packed.Touch(key, t)
  local k = kept(key)
  k.t = t or k.t
  k.gen = k.gen + 1
  local gen = k.gen
  if C_Timer and C_Timer.After then
    C_Timer.After(Packed.REPACK_DELAY, function()
      if k.gen == gen then
        Packed.Repack(key)
      end
    end)
  end
end

function Packed.Text(key, t, name)
  local k = Packed.kept[key]
  if k and k.text and k.textGen == k.gen and k.t == t then
    return k.text
  end
  if name then
    Packed.Ready(name)
  end
  return Packed.Pack(t)
end
