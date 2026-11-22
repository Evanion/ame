local addon = require("spec.helpers.addon")

-- Sync v2's engine in a simulated guild: a shared clock and timers, a guild channel that delivers every message to
-- everyone else (optionally losing some), and in-memory data on each player.
describe("Sync v2 (engine)", function()
  local ns, V2
  local SHARD = "PvP|Horde"

  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/SyncV2.lua" })
    V2 = ns.SyncV2
  end)

  -- a deterministic random number generator
  local function rng(seed)
    local x = seed or 1
    return function()
      x = (x * 1103515245 + 12345) % 2147483648
      return x / 2147483648
    end
  end

  local function guild(names, opts)
    opts = opts or {}
    local g = { t = 0, timers = {}, peers = {}, log = {}, seq = 0 }
    local lose = opts.lose or function()
      return false
    end
    local function after(sec, fn)
      g.seq = g.seq + 1
      g.timers[#g.timers + 1] = { at = g.t + sec, seq = g.seq, fn = fn }
    end
    g.after = after
    function g:run(seconds)
      local stop = self.t + seconds
      while true do
        table.sort(self.timers, function(a, b)
          return a.at < b.at or (a.at == b.at and a.seq < b.seq)
        end)
        local nxt = self.timers[1]
        if not nxt or nxt.at > stop then
          break
        end
        table.remove(self.timers, 1)
        self.t = nxt.at
        nxt.fn()
      end
      self.t = stop
    end
    for i, name in ipairs(names) do
      local p = { name = name, have = {}, accepted = {}, sent = {} }
      p.host = {
        Allowed = function()
          return true
        end,
        Shards = function()
          return { SHARD }
        end,
        Manifest = function()
          local m = { scanT = 0, hour0 = 1000, hours = {}, day0 = 40, days = {} }
          for k in pairs(p.have) do
            local kind, ref = k:match("#(%a)#(%d+)$")
            ref = tonumber(ref)
            if kind == "h" then
              m.hours[ref] = true
            elseif kind == "d" then
              m.days[ref] = true
            elseif kind == "s" then
              m.scanT = math.max(m.scanT, ref)
            end
          end
          return m
        end,
        Has = function(_, shard, kind, ref)
          return p.have[V2.ObjKey(shard, kind, ref)] ~= nil
        end,
        Wanted = function(_, shard, kind, ref)
          return p.have[V2.ObjKey(shard, kind, ref)] == nil
        end,
        Wants = function(_, shard, m)
          local out = {}
          for hour in pairs(m.hours) do
            if not p.have[V2.ObjKey(shard, "h", hour)] then
              out[#out + 1] = { kind = "h", ref = hour }
            end
          end
          table.sort(out, function(a, b)
            return a.ref > b.ref
          end)
          return out
        end,
        Object = function(_, shard, kind, ref, done)
          local payload = p.have[V2.ObjKey(shard, kind, ref)]
          done(
            payload and { kind = kind, ref = ref, t = ref * 3600, src = "Scanner", key = "k" .. ref, payload = payload }
          )
        end,
        Accept = function(_, shard, obj, sender)
          p.have[V2.ObjKey(shard, obj.kind, obj.ref)] = obj.payload
          p.accepted[#p.accepted + 1] = { obj = obj, from = sender }
        end,
      }
      p.engine = V2.New({
        name = name,
        send = function(msg)
          p.sent[#p.sent + 1] = msg
          g.log[#g.log + 1] = { from = name, msg = msg }
          for _, other in ipairs(g.peers) do
            if other ~= p and not lose(msg, other.name) then
              after(0.05, function()
                other.engine:OnMessage(msg, name)
              end)
            end
          end
        end,
        now = function()
          return g.t
        end,
        after = after,
        random = rng(i * 7919),
        host = p.host,
      })
      g.peers[#g.peers + 1] = p
      g[name] = p
    end
    return g
  end

  -- a payload of n bytes, with every byte value but NUL in it (as Compress Wire's output can have)
  local function payload(n, seed)
    local r, out = rng(seed or 3), {}
    for i = 1, n do
      out[i] = string.char(1 + math.floor(r() * 255))
    end
    return table.concat(out)
  end

  local function count(log, kind, from)
    local n = 0
    for _, e in ipairs(log) do
      if e.msg:sub(3, 3) == kind and (not from or e.from == from) then
        n = n + 1
      end
    end
    return n
  end

  describe("messages", function()
    it("round-trip, and blocks carry any bytes (pipes and newlines too) under the 255-byte limit", function()
      local m = V2.Decode(V2.EncodeManifest(SHARD, {
        scanT = 123456,
        hour0 = 1000,
        hours = { [1000] = true, [997] = true, [833] = true, [832] = true },
        day0 = 40,
        days = { [40] = true, [34] = true },
      }))
      assert.are.equal("manifest", m.type)
      assert.are.equal(SHARD, m.shard)
      assert.are.equal(123456, m.scanT)
      assert.are.same({ [1000] = true, [997] = true, [833] = true }, m.hours) -- 832 is beyond 168 hours
      assert.are.same({ [40] = true, [34] = true }, m.days)
      assert.truthy(#V2.EncodeManifest(SHARD, { hour0 = 1, hours = {}, day0 = 1, days = {} }) < 255)

      local bytes = "a|b\nc" .. payload(V2.BLOCK - 5)
      local raw = V2.EncodeBlock("zz9k", 1234, bytes)
      assert.truthy(#raw <= 255, #raw)
      local b = V2.Decode(raw)
      assert.are.same({ type = "block", oid = "zz9k", i = 1234, bytes = bytes }, b)

      local o = V2.Decode(V2.EncodeOffer(SHARD, {
        oid = "abc1",
        kind = "h",
        ref = 491234,
        t = 1768442400,
        n = 120,
        len = 27500,
        sum = 4294967295,
        src = "Tyken Evanion",
        key = "1768442400:Tyken Evanion:full:6400:2:288206",
      }))
      assert.are.equal("offer", o.type)
      assert.are.equal(SHARD, o.shard)
      assert.are.equal("Tyken Evanion", o.src)
      assert.are.equal("1768442400:Tyken Evanion:full:6400:2:288206", o.key)
      assert.are.equal(4294967295, o.sum)
      assert.are.equal(491234, o.ref)

      local n = V2.Decode(V2.EncodeMissing("Guild Mate", "abc1", { 1, 2, 3, 7, 9, 10 }))
      assert.are.equal("Guild Mate", n.target)
      assert.are.same({ 1, 2, 3, 7, 9, 10 }, n.blocks)
      local many = {}
      for i = 1, 4000, 2 do
        many[#many + 1] = i
      end
      assert.truthy(#V2.EncodeMissing("Guild Mate", "abc1", many) < 255)

      assert.is_nil(V2.Decode("1|A|PvP|Horde|"))
      assert.is_nil(V2.Decode("2|O|short"))
    end)

    it("checksums tell payloads apart", function()
      local a = payload(5000, 1)
      local b = a:sub(1, 2499) .. string.char((a:byte(2500) % 254) + 1) .. a:sub(2501)
      assert.are_not.equal(V2.Checksum(a), V2.Checksum(b))
      assert.are.equal(V2.Checksum(a), V2.Checksum(a))
    end)
  end)

  describe("in a guild", function()
    it("a pushed object reaches everyone online from one send", function()
      local g = guild({ "Ann", "Bob", "Cid", "Dee" })
      local data = payload(10 * V2.BLOCK + 17)
      g.Ann.have[V2.ObjKey(SHARD, "s", 500)] = data
      g.Ann.engine:Push(SHARD, "s", 500)
      g:run(30)
      for _, name in ipairs({ "Bob", "Cid", "Dee" }) do
        assert.is_true(g[name].have[V2.ObjKey(SHARD, "s", 500)] == data, name)
        assert.are.equal("Ann", g[name].accepted[1].from)
      end
      assert.are.equal(1, count(g.log, "O"))
      assert.are.equal(11, count(g.log, "B")) -- each block once, for everyone
    end)

    it("sends one message per PACE, never a burst", function()
      local g = guild({ "Ann", "Bob" })
      g.Ann.have[V2.ObjKey(SHARD, "s", 500)] = payload(30 * V2.BLOCK)
      local times = {}
      local send = g.Ann.engine.send
      g.Ann.engine.send = function(msg)
        times[#times + 1] = g.t
        send(msg)
      end
      g.Ann.engine:Push(SHARD, "s", 500)
      g:run(60)
      assert.are.equal(31, #times)
      for i = 2, #times do
        assert.truthy(times[i] - times[i - 1] >= V2.PACE - 1e-9)
      end
    end)

    it(
      "missing hours are asked for after a manifest; one holder answers, and everyone missing them gets them",
      function()
        local g = guild({ "Ann", "Bob", "Cid", "Dee" })
        local h1, h2 = payload(800, 1), payload(600, 2)
        for _, name in ipairs({ "Ann", "Bob" }) do
          g[name].have[V2.ObjKey(SHARD, "h", 999)] = h1
          g[name].have[V2.ObjKey(SHARD, "h", 998)] = h2
        end
        g.Ann.engine:Announce()
        g:run(60)
        for _, name in ipairs({ "Cid", "Dee" }) do
          assert.is_true(g[name].have[V2.ObjKey(SHARD, "h", 999)] == h1, name)
          assert.is_true(g[name].have[V2.ObjKey(SHARD, "h", 998)] == h2, name)
        end
        assert.are.equal(2, count(g.log, "O")) -- one offer per hour, not one per holder or per asker
        assert.truthy(count(g.log, "R") <= 2, count(g.log, "R")) -- Dee doesn't repeat what Cid asked
      end
    )

    it("lost blocks are asked for again by number, without a storm of requests", function()
      local r = rng(42)
      local g = guild({ "Ann", "Bob", "Cid", "Dee", "Eve" }, {
        lose = function(msg)
          return msg:sub(3, 3) == "B" and r() < 0.15
        end,
      })
      local data = payload(60 * V2.BLOCK + 3)
      g.Ann.have[V2.ObjKey(SHARD, "s", 500)] = data
      g.Ann.engine:Push(SHARD, "s", 500)
      g:run(600)
      for _, name in ipairs({ "Bob", "Cid", "Dee", "Eve" }) do
        assert.is_true(g[name].have[V2.ObjKey(SHARD, "s", 500)] == data, name)
      end
      local nacks = count(g.log, "N")
      assert.truthy(nacks >= 1)
      assert.truthy(nacks <= 4 * V2.MAX_NACKS, nacks)
      assert.truthy(count(g.log, "B") < 61 * 2, count(g.log, "B")) -- resends, not whole copies per player
    end)

    it("arrives intact at heavy loss, whatever the dice say", function()
      for seed = 1, 60 do
        local r = rng(seed * 101)
        local g = guild({ "Ann", "Bob", "Cid", "Dee" }, {
          lose = function()
            return r() < 0.3 -- any message, offers and requests too
          end,
        })
        local data = payload(25 * V2.BLOCK + 9, seed)
        g.Ann.have[V2.ObjKey(SHARD, "h", 999)] = data
        for _ = 1, 6 do -- everyone's manifest every 10 minutes
          for _, p in ipairs(g.peers) do
            p.engine:Announce()
          end
          g:run(600)
        end
        for _, name in ipairs({ "Bob", "Cid", "Dee" }) do
          assert.is_true(g[name].have[V2.ObjKey(SHARD, "h", 999)] == data, name .. " seed " .. seed)
          assert.are.equal(1, #g[name].accepted, name .. " seed " .. seed) -- once, checksum-verified
        end
      end
    end)

    it("someone who logs in mid-transfer asks for its offer and catches up on the blocks they missed", function()
      local g = guild({ "Ann", "Bob", "Cid" })
      local data = payload(30 * V2.BLOCK)
      g.Ann.have[V2.ObjKey(SHARD, "h", 999)] = data
      local cid = table.remove(g.peers) -- offline
      g.Ann.engine:Announce()
      g:run(15)
      g.peers[#g.peers + 1] = cid -- logs in: missed the offer and the first blocks
      g:run(120)
      assert.is_true(g.Bob.have[V2.ObjKey(SHARD, "h", 999)] == data)
      assert.is_true(g.Cid.have[V2.ObjKey(SHARD, "h", 999)] == data)
      assert.truthy(count(g.log, "B", "Ann") < 50, count(g.log, "B", "Ann")) -- the missed blocks, not all again
    end)

    it("sends fresh scans before hours, and hours before whole days, never cutting into one under way", function()
      local g = guild({ "Ann", "Bob" })
      g.Ann.have[V2.ObjKey(SHARD, "d", 40)] = payload(10 * V2.BLOCK, 1)
      g.Ann.have[V2.ObjKey(SHARD, "d", 39)] = payload(10 * V2.BLOCK, 2)
      g.Ann.have[V2.ObjKey(SHARD, "h", 999)] = payload(5 * V2.BLOCK, 3)
      g.Ann.have[V2.ObjKey(SHARD, "s", 500)] = payload(5 * V2.BLOCK, 4)
      g.Ann.engine:Push(SHARD, "d", 40)
      g:run(3) -- under way
      g.Ann.engine:Push(SHARD, "d", 39)
      g.Ann.engine:Push(SHARD, "h", 999)
      g.Ann.engine:Push(SHARD, "s", 500)
      g:run(120)
      local kindOf, order = {}, {}
      for _, e in ipairs(g.log) do
        local m = V2.Decode(e.msg)
        if m.type == "offer" then
          kindOf[m.oid] = m.kind .. m.ref
        elseif m.type == "block" and order[#order] ~= kindOf[m.oid] then
          order[#order + 1] = kindOf[m.oid]
        end
      end
      assert.are.same({ "d40", "s500", "h999", "d39" }, order)
    end)

    it("two holders answering at once: the name sorting first keeps sending, and it still arrives", function()
      local g = guild({ "Ann", "Bob", "Cid" })
      V2.ANSWER_DELAY = 0
      local data = payload(20 * V2.BLOCK)
      g.Ann.have[V2.ObjKey(SHARD, "h", 999)] = data
      g.Bob.have[V2.ObjKey(SHARD, "h", 999)] = data
      g.Cid.engine:OnMessage(
        V2.EncodeManifest(SHARD, { hour0 = 1000, hours = { [999] = true }, day0 = 40, days = {} }),
        "Ann"
      )
      g:run(120)
      assert.is_true(g.Cid.have[V2.ObjKey(SHARD, "h", 999)] == data)
      assert.are.equal(2, count(g.log, "O")) -- both offered
      assert.truthy(count(g.log, "B", "Bob") < 20, count(g.log, "B", "Bob")) -- Bob backed off
      assert.are.equal(20, count(g.log, "B", "Ann"))
    end)

    it("a transfer cut by a /reload resumes: the blocks so far are kept, the rest asked for", function()
      local g = guild({ "Ann", "Bob" })
      local data = payload(40 * V2.BLOCK)
      g.Ann.have[V2.ObjKey(SHARD, "s", 500)] = data
      g.Ann.engine:Push(SHARD, "s", 500)
      g:run(20)
      local status = g.Bob.engine:Status()
      assert.are.equal(1, #status.receiving)
      local got = status.receiving[1].got
      assert.truthy(got > 5 and got < 40, got)
      assert.are.equal("s", g.Ann.engine:Status().sending.kind)
      -- Bob reloads: a new engine from what was saved; the blocks sent meanwhile are lost to him
      local saved = g.Bob.engine:Save()
      local old = g.Bob.engine
      g.Bob.engine = V2.New({
        name = "Bob",
        send = old.send,
        now = old.now,
        after = g.after,
        random = rng(5),
        host = g.Bob.host,
      })
      g:run(10)
      g.Bob.engine:Restore(saved)
      g:run(600)
      assert.is_true(g.Bob.have[V2.ObjKey(SHARD, "s", 500)] == data)
      assert.truthy(count(g.log, "B", "Ann") < 80, count(g.log, "B", "Ann")) -- not sent twice over
    end)

    -- Bob had half an hour from Ann when he disconnected; Ann reloaded meanwhile (that object is gone from her
    -- side) and is busy serving the guild a long day. Bob must not wait on her forever: he gives up on the dead
    -- transfer and asks for the hour again, and gets it.
    it("a transfer its sender lost doesn't hold up that object while the sender keeps sending others", function()
      local g = guild({ "Ann", "Bob" })
      local hour = payload(40 * V2.BLOCK, 1)
      g.Ann.have[V2.ObjKey(SHARD, "h", 999)] = hour
      g.Ann.have[V2.ObjKey(SHARD, "d", 40)] = payload(1500 * V2.BLOCK, 2) -- ~26 minutes of blocks
      g.Ann.engine:Push(SHARD, "h", 999)
      g:run(20)
      local saved = g.Bob.engine:Save()
      assert.are.equal(1, #saved)
      local function fresh(p, seed)
        local old = p.engine
        p.engine =
          V2.New({ name = p.name, send = old.send, now = old.now, after = g.after, random = rng(seed), host = p.host })
      end
      fresh(g.Ann, 11)
      fresh(g.Bob, 12)
      g:run(5)
      g.Bob.engine:Restore(saved)
      g.Ann.engine:Push(SHARD, "d", 40) -- Ann busy for the next half hour
      g.Ann.have[V2.ObjKey(SHARD, "d", 39)] = payload(1500 * V2.BLOCK, 3)
      g.Ann.engine:Push(SHARD, "d", 39) -- and another after it
      for _ = 1, 35 do -- Ann's manifest every minute (Sync now)
        g.Ann.engine:Announce()
        g:run(60)
      end
      -- the hour went right after the day under way, ahead of the next day; Bob didn't pester Ann meanwhile
      assert.is_true(g.Bob.have[V2.ObjKey(SHARD, "h", 999)] == hour)
      assert.truthy(count(g.log, "N", "Bob") <= 2 * V2.MAX_NACKS, count(g.log, "N", "Bob")) -- a handful in 35 min
    end)

    it("blocks resent for an object under way go ahead of a long one being sent", function()
      local lost = false
      local g = guild({ "Ann", "Bob" }, {
        lose = function(msg, to)
          if not lost and to == "Bob" and msg:match("^2|B|[^|]+|a|") then -- block 10, the first time
            lost = true
            return true
          end
          return false
        end,
      })
      local hour = payload(20 * V2.BLOCK, 1)
      g.Ann.have[V2.ObjKey(SHARD, "h", 999)] = hour
      g.Ann.have[V2.ObjKey(SHARD, "d", 40)] = payload(1500 * V2.BLOCK, 2)
      g.Ann.engine:Push(SHARD, "h", 999)
      g:run(3)
      g.Ann.engine:Push(SHARD, "d", 40) -- queued behind the hour
      g:run(90)
      assert.is_true(lost)
      assert.is_true(g.Bob.have[V2.ObjKey(SHARD, "h", 999)] == hour)
    end)
  end)

  describe("what the Sharing page reads", function()
    local e, t
    before_each(function()
      t = 0
      e = V2.New({
        name = "Me",
        send = function() end,
        now = function()
          return t
        end,
        after = function() end,
        random = function()
          return 0
        end,
        host = {
          Allowed = function()
            return true
          end,
          Wants = function()
            return {}
          end,
          Wanted = function()
            return true
          end,
        },
      })
    end)

    it("learns how big each kind of object is, as a running average", function()
      assert.is_nil(e:SizeOf(SHARD, "h"))
      e:LearnSize(SHARD, "h", 1000)
      assert.are.equal(1000, e:SizeOf(SHARD, "h"))
      e:LearnSize(SHARD, "h", 2000)
      assert.are.equal(1300, e:SizeOf(SHARD, "h"))
      assert.is_nil(e:SizeOf(SHARD, "d"))
    end)

    it("keeps each player's last manifest, and knows where an object stands", function()
      local m = { scanT = 0, hour0 = 100, hours = { [99] = true }, day0 = 3, days = {} }
      e:OnMessage(V2.EncodeManifest(SHARD, m), "Bob")
      assert.truthy(e.manifests.Bob[SHARD].m.hours[99])
      assert.is_nil(e:Track(SHARD, "h", 99))
      -- offered: its size is known from the offer
      e:OnMessage(
        V2.EncodeOffer(SHARD, { oid = "x1", kind = "h", ref = 99, t = 0, n = 3, len = 600, sum = 1, src = "Bob" }),
        "Bob"
      )
      local track = e:Track(SHARD, "h", 99)
      assert.are.equal("receiving", track.state) -- wanted: its blocks are expected now
      assert.are.equal(3, track.n)
      assert.are.equal(600, e:SizeOf(SHARD, "h"))
      e:OnMessage(V2.EncodeBlock("x1", 1, string.rep("a", 230)), "Bob")
      assert.are.equal(1, e:Track(SHARD, "h", 99).got)
      -- asked for, nothing offered yet
      e.requested[V2.ObjKey(SHARD, "d", 2)] = t
      assert.are.equal("asked", e:Track(SHARD, "d", 2).state)
      t = t + V2.REQUEST_COOLDOWN + 1
      assert.is_nil(e:Track(SHARD, "d", 2))
    end)
  end)
end)
