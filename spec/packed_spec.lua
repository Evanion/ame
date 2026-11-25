local addon = require("spec.helpers.addon")

describe("Packed", function()
  local Packed

  before_each(function()
    Packed = addon.load({ "Core/Init.lua", "Core/Packed.lua" }).Packed
  end)

  it("round-trips number and string keys (item keys with suffixes too)", function()
    local t = { [2589] = "1;2;3", [14473015985] = "Raider Shortsword of the Monkey", name = "x", [7] = "" }
    local text = Packed.Pack(t)
    assert.are.equal("string", type(text))
    assert.are.same(t, Packed.Unpack(text))
  end)

  it("leaves out what it can't carry: tabs or newlines, values that aren't strings", function()
    local back = Packed.Unpack(Packed.Pack({ [1] = "a\tb", [2] = "c\nd", [3] = 5, [4] = "ok" }))
    assert.are.same({ [4] = "ok" }, back)
  end)

  it("unpacks later into a table, keeping entries it got meanwhile, and Ready finishes it at once", function()
    local src = {}
    for i = 1, 5000 do
      src[i] = "v" .. i
    end
    local into, seen, done = { [3] = "newer" }, 0, false
    Packed.Later("names", Packed.Pack(src), into, function()
      seen = seen + 1
    end, function()
      done = true
    end)
    assert.is_true(Packed.Pending("names"))
    assert.is_nil(into[10])
    Packed.Ready("names")
    assert.is_false(Packed.Pending("names"))
    assert.is_true(done)
    assert.are.equal("newer", into[3]) -- learned since: not overwritten
    assert.are.equal("v10", into[10])
    assert.are.equal(4999, seen)
    Packed.Ready("names") -- nothing left: fine
  end)

  it("several texts under one name all unpack; nothing packed is done at once", function()
    local a, b = {}, {}
    Packed.Later("pricing", Packed.Pack({ [1] = "x" }), a)
    Packed.Later("pricing", Packed.Pack({ [2] = "y" }), b)
    local called = false
    Packed.Later("empty", nil, {}, nil, function()
      called = true
    end)
    assert.is_true(called)
    assert.is_false(Packed.Pending("empty"))
    Packed.ReadyAll()
    assert.are.same({ [1] = "x" }, a)
    assert.are.same({ [2] = "y" }, b)
  end)

  describe("kept texts (what logout saves without packing)", function()
    local jobs, timers

    before_each(function()
      -- a job runner that runs a job to its end when asked, and timers that fire when asked
      jobs = { queue = {} }
      function jobs:Add(name, fn, done)
        self.queue[#self.queue + 1] = { name = name, fn = fn, done = done }
      end
      function jobs:Cancel(name)
        for i = #self.queue, 1, -1 do
          if self.queue[i].name == name then
            table.remove(self.queue, i)
          end
        end
      end
      function jobs:Run()
        local list = self.queue
        self.queue = {}
        for _, j in ipairs(list) do
          local job = { Checkpoint = function() end }
          j.done(true, j.fn(job))
        end
      end
      timers = {}
      _G.C_Timer = {
        After = function(_, fn)
          timers[#timers + 1] = fn
        end,
      }
      Packed.REPACK_DELAY = 30
    end)

    after_each(function()
      _G.C_Timer = nil
    end)

    local function fire()
      local list = timers
      timers = {}
      for _, fn in ipairs(list) do
        fn()
      end
    end

    it("saves the text it was read from while nothing changed, even before it's all unpacked", function()
      local ns = addon.load({ "Core/Init.lua", "Core/Packed.lua" })
      Packed = ns.Packed
      local text = Packed.Pack({ [1] = "a", [2] = "b" })
      local t = {}
      Packed.Keep("k", text, t)
      Packed.Later("k", text, t)
      assert.is_true(Packed.Pending("k"))
      assert.are.equal(text, Packed.Text("k", t, "k")) -- the same string: nothing packed
      assert.is_true(Packed.Pending("k")) -- nor unpacked
    end)

    it("a change makes logout pack it now, with the change; a background job packs it again before that", function()
      local ns = addon.load({ "Core/Init.lua", "Core/Packed.lua" })
      Packed = ns.Packed
      ns.AME = { jobs = jobs }
      local text = Packed.Pack({ [1] = "a", [2] = "b" })
      local t = {}
      Packed.Keep("k", text, t)
      Packed.Later("k", text, t)
      t[3] = "c"
      Packed.Touch("k", t)
      -- logout before the job: packed now, after unpacking the rest
      assert.are.same({ [1] = "a", [2] = "b", [3] = "c" }, Packed.Unpack(Packed.Text("k", t, "k")))
      assert.is_false(Packed.Pending("k"))
      -- the job, once the changes are quiet: its text is what logout saves
      fire()
      assert.are.equal(1, #jobs.queue)
      jobs:Run()
      local saved = Packed.Text("k", t, "k")
      assert.are.equal(Packed.kept.k.text, saved)
      assert.are.same({ [1] = "a", [2] = "b", [3] = "c" }, Packed.Unpack(saved))
    end)

    it("a change while the job runs throws its text away: logout packs again", function()
      local ns = addon.load({ "Core/Init.lua", "Core/Packed.lua" })
      Packed = ns.Packed
      ns.AME = { jobs = jobs }
      local t = { [1] = "a" }
      Packed.Touch("k", t)
      fire()
      local job = jobs.queue[1]
      jobs.queue = {}
      local text = job.fn({ Checkpoint = function() end })
      t[2] = "b"
      Packed.Touch("k", t) -- changed before the job finished
      job.done(true, text)
      assert.are.same({ [1] = "a", [2] = "b" }, Packed.Unpack(Packed.Text("k", t)))
    end)

    it("a table that isn't the kept one (replaced since) is packed", function()
      local ns = addon.load({ "Core/Init.lua", "Core/Packed.lua" })
      Packed = ns.Packed
      Packed.Keep("k", Packed.Pack({ [1] = "old" }), {})
      assert.are.same({ [1] = "new" }, Packed.Unpack(Packed.Text("k", { [1] = "new" })))
    end)
  end)
end)
