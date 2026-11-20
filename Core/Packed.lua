-- Big saved tables of small entries (posting price models, random-suffix variant names and item strings: ~120k
-- entries) saved as one string each. WoW reads SavedVariables during the loading screen, and a table of many small
-- entries is the slowest thing it reads: on a real 20 MB file, packing these took the load from ~240 ms to ~30 ms
-- (Lua 5.1, the same file). After login they're unpacked back into their tables a slice at a time, out of combat, at
-- low priority (Start); anything that needs one sooner calls Ready(name), which unpacks the rest at once.
--
--   Packed.Pack(t)                         -> "key\tvalue\n..." (number keys as "#123"; string values only)
--   Packed.Later(name, text, into, onEntry, onDone)   unpack into `into` in the background (keeps entries it has)
--   Packed.Ready(name)                     -> unpacks what's left of `name` now
--   Packed.ReadyAll()                      everything now (at logout, before saving)
local _, ns = ...

local Packed = { tasks = {}, order = {} }
ns.Packed = Packed

Packed.SLICE = 1500 -- entries per step
Packed.EVERY = 0.05 -- seconds between steps
Packed.DELAY = 2 -- seconds after login before the first step

function Packed.Pack(t)
  local parts, n = {}, 0
  for k, v in pairs(t or {}) do
    local key = type(k) == "number" and ("#" .. ("%.0f"):format(k)) or (type(k) == "string" and k or nil)
    if key and type(v) == "string" and not key:find("[\t\n]") and not v:find("[\t\n]") then
      n = n + 1
      parts[n] = key .. "\t" .. v
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
