-- Cooperative background jobs with a per-frame time budget. Pure: the clock is injected, the caller drives Tick()
-- (in WoW: from an OnUpdate script).
--
--   local runner = ns.Jobs.New({ budgetMs = 8, clock = debugprofilestop })
--   runner:Add("ingest", function(job) ... job:Checkpoint() ... return result end, function(ok, result) end)
--   frame:SetScript("OnUpdate", function() runner:Tick() end)
--
-- job:Checkpoint() yields only once the frame's budget is spent, so it's cheap to call often.
local _, ns = ...

local Jobs = {}
Jobs.__index = Jobs
ns.Jobs = Jobs

local Job = {}
Job.__index = Job

function Job:Checkpoint()
  if self.runner.clock() - self.runner.tickStart >= (self.budgetMs or self.runner.budgetMs) then
    coroutine.yield()
  end
end

-- pcall that a background job can pause inside. WoW's Lua 5.1 can't yield across pcall: a job that paused (a
-- Checkpoint) inside one failed with "attempt to yield across metamethod/C-call boundary", and pcall reported that
-- as the call failing - big objects received over sync were rejected as undecodable. Here fn runs in a coroutine of
-- its own; its pauses are passed on to the job running it (or just run on, outside a job). Returns as pcall does.
function Jobs.Try(fn, ...)
  local co = coroutine.create(fn)
  local res = { coroutine.resume(co, ...) }
  while coroutine.status(co) ~= "dead" do
    if coroutine.running() then
      coroutine.yield()
    end
    res = { coroutine.resume(co) }
  end
  return unpack(res)
end
ns.Try = Jobs.Try

function Jobs.New(opts)
  return setmetatable({
    budgetMs = opts.budgetMs or 8,
    clock = assert(opts.clock, "clock required"),
    queue = {},
    tickStart = 0,
  }, Jobs)
end

-- budgetMs (optional): this job's time per frame instead of the runner's - smaller for low-priority work
function Jobs:Add(name, fn, onDone, budgetMs)
  local job = setmetatable({ name = name, runner = self, onDone = onDone, budgetMs = budgetMs }, Job)
  job.co = coroutine.create(function()
    return fn(job)
  end)
  self.queue[#self.queue + 1] = job
  return job
end

function Jobs:Busy()
  return #self.queue > 0
end

function Jobs:Cancel(name)
  for i = #self.queue, 1, -1 do
    if self.queue[i].name == name then
      table.remove(self.queue, i)
    end
  end
end

-- Run one job per tick (keeps frames predictable) until it yields (budget spent) or finishes: the first normal job,
-- or, when there is none, the first low-priority one (a budgetMs of its own) - so a long background rebuild never
-- holds up what you just asked for (a chart, storing a search).
function Jobs:Tick()
  local pick = 1
  for i, j in ipairs(self.queue) do
    if not j.budgetMs then
      pick = i
      break
    end
  end
  local job = self.queue[pick]
  if not job then
    return
  end
  self.tickStart = self.clock()
  self.lastName = job.name -- what this tick ran (the dev profiler's CPU table)
  self.current = job -- the job running now (yield hooks shared between jobs use it)
  local ok, result = coroutine.resume(job.co)
  self.current = nil
  if not ok or coroutine.status(job.co) == "dead" then
    table.remove(self.queue, pick)
    if job.onDone then
      job.onDone(ok, result)
    end
  end
end
