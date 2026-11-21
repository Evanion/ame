local addon = require("spec.helpers.addon")

describe("Jobs", function()
  local Jobs, runner, clock

  before_each(function()
    Jobs = addon.load({ "Core/Init.lua", "Core/Jobs.lua" }).Jobs
    clock = 0
    runner = Jobs.New({
      budgetMs = 8,
      clock = function()
        return clock
      end,
    })
  end)

  it("runs what you just asked for before a long low-priority job, then finishes that one", function()
    local order = {}
    runner:Add("rebuild", function(job)
      for step = 1, 20 do
        clock = clock + 1
        order[#order + 1] = "rebuild" .. step
        job:Checkpoint()
      end
    end, nil, 2) -- low priority: 2 ms per tick
    runner:Tick() -- the rebuild starts
    assert.are.equal(runner.queue[1].name, "rebuild")
    local chart = false
    runner:Add("chart", function()
      chart = true
      order[#order + 1] = "chart"
    end)
    runner:Tick()
    assert.is_true(chart) -- jumped the queue
    while runner:Busy() do
      runner:Tick()
    end
    assert.are.equal("rebuild20", order[#order])
    assert.is_nil(runner.current)
  end)

  it("runs a job to completion over several ticks, respecting the frame budget", function()
    local done = false
    runner:Add("work", function(job)
      for _ = 1, 10 do
        clock = clock + 3 -- each unit of work costs 3 ms
        job:Checkpoint()
      end
      done = true
    end)
    local ticks = 0
    while runner:Busy() do
      runner:Tick()
      ticks = ticks + 1
      assert.is_true(ticks < 100)
    end
    assert.is_true(done)
    assert.is_true(ticks >= 4, "ticks " .. ticks) -- 30 ms of work at 8 ms/frame
  end)

  it("Checkpoint does not yield while under budget", function()
    local checkpoints = 0
    runner:Add("cheap", function(job)
      for _ = 1, 100 do
        job:Checkpoint()
        checkpoints = checkpoints + 1
      end
    end)
    runner:Tick()
    assert.are.equal(100, checkpoints)
    assert.is_false(runner:Busy())
  end)

  it("runs jobs in order and calls onDone with the result", function()
    local log = {}
    runner:Add("a", function()
      log[#log + 1] = "a"
      return 1
    end, function(ok, result)
      log[#log + 1] = "a done " .. tostring(ok) .. " " .. tostring(result)
    end)
    runner:Add("b", function()
      log[#log + 1] = "b"
    end)
    runner:Tick()
    runner:Tick()
    assert.are.same({ "a", "a done true 1", "b" }, log)
  end)

  it("reports errors to onDone instead of killing the runner", function()
    local got
    runner:Add("bad", function()
      error("boom")
    end, function(ok, err)
      got = { ok, err }
    end)
    runner:Add("good", function() end)
    runner:Tick()
    runner:Tick()
    assert.is_false(got[1])
    assert.truthy(tostring(got[2]):find("boom"))
    assert.is_false(runner:Busy())
  end)

  it("can cancel a running job", function()
    local finished = false
    runner:Add("long", function(job)
      for _ = 1, 100 do
        clock = clock + 5
        job:Checkpoint()
      end
      finished = true
    end)
    runner:Tick()
    runner:Cancel("long")
    runner:Tick()
    assert.is_false(finished)
    assert.is_false(runner:Busy())
  end)

  it("Try: a job can pause inside it (pcall can't), and errors come back as from pcall", function()
    local result, ticks = nil, 0
    runner:Add("decode", function(job)
      local ok, value = Jobs.Try(function(a)
        for _ = 1, 30 do
          clock = clock + 1
          job:Checkpoint() -- over budget: pauses inside Try
        end
        return a * 2
      end, 21)
      local bad, why = Jobs.Try(function()
        error("broken")
      end)
      return { ok, value, bad, why }
    end, function(_, r)
      result = r
    end)
    while runner:Busy() do
      runner:Tick()
      ticks = ticks + 1
    end
    assert.is_true(ticks > 1) -- it really paused
    assert.are.same({ true, 42, false }, { result[1], result[2], result[3] })
    assert.truthy(tostring(result[4]):find("broken"))
    -- outside a job, it just runs
    assert.are.same({ true, 5 }, { Jobs.Try(function()
      return 5
    end) })
  end)
end)
