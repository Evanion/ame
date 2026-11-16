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
  if self.runner.clock() - self.runner.tickStart >= self.runner.budgetMs then
    coroutine.yield()
  end
end

function Jobs.New(opts)
  return setmetatable({
    budgetMs = opts.budgetMs or 8,
    clock = assert(opts.clock, "clock required"),
    queue = {},
    tickStart = 0,
  }, Jobs)
end

function Jobs:Add(name, fn, onDone)
  local job = setmetatable({ name = name, runner = self, onDone = onDone }, Job)
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

-- Run the head job until it yields (budget spent) or finishes. One job per tick keeps frames predictable.
function Jobs:Tick()
  local job = self.queue[1]
  if not job then
    return
  end
  self.tickStart = self.clock()
  local ok, result = coroutine.resume(job.co)
  if not ok or coroutine.status(job.co) == "dead" then
    table.remove(self.queue, 1)
    if job.onDone then
      job.onDone(ok, result)
    end
  end
end
