-- Core/CraftRequests.lua: the request exchange (ask, answer, approve), its states, the terms per reagent, the wire
-- format, merging what arrives, the form's draft, and the "X" sync message (Core/Sync.lua, Core/SyncService.lua).
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("CraftRequests", function()
  local env, ns, R

  before_each(function()
    env = wow.install()
    ns = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/Sync.lua", "Core/CraftRequests.lua" })
    R = ns.CraftRequests
    _G.AME_DB = { settings = {} }
  end)

  after_each(function()
    env:restore()
  end)

  local function request(now)
    return R.New({
      id = "Zakzu-1-1",
      asker = "Zakzu",
      crafter = "Kke",
      recipe = 17580,
      item = 13444,
      count = 5,
      reagents = {
        { item = 13463, need = 15, bring = 15 },
        { item = 13467, need = 10, bring = 6 },
        { item = 18256, need = 5, bring = 0 },
        { item = 99999, need = 1, bring = 1, soulbound = true },
      },
      offer = 4500,
      tip = 50000,
      message = "Could you make these? | with a pipe",
    }, now or 100)
  end

  describe("the record", function()
    it("starts new, waiting on the crafter; a soulbound reagent is always the crafter's", function()
      local r = request()
      assert.equals("new", r.state)
      assert.equals("crafter", R.ToAct(r))
      assert.equals(0, r.reagents[4].bring)
      assert.is_nil(r.message:find("|", 1, true))
      assert.same(
        { { item = 13467, n = 4 }, { item = 18256, n = 5 }, { item = 99999, n = 1, soulbound = true } },
        R.Supply(r)
      )
      assert.equals("most", R.Brings(r))
    end)

    it("the crafter accepts as asked: the same terms agree", function()
      local r = request()
      assert.equals("accepted", R.Answer(r, "crafter", { offer = 4500, tip = 50000 }, nil, 200))
      assert.equals("accepted", r.state)
      assert.equals("crafter", R.ToAct(r))
    end)

    it("a changed figure goes back to the asker, with what changed", function()
      local r = request()
      assert.equals("answered", R.Answer(r, "crafter", { offer = 6000 }, "Vials are short", 200))
      assert.equals("asker", R.ToAct(r))
      assert.equals("crafter", r.by)
      assert.equals(2, r.rev)
      local c = R.Changed(r)
      assert.is_true(c.offer)
      assert.is_false(c.tip)
      assert.is_true(c.any)
      assert.equals("Vials are short", r.note)
      -- the crafter can change their answer again before the asker answers: it still waits on the asker
      assert.equals("revised", R.Answer(r, "crafter", { offer = 7000 }, nil, 210))
      assert.equals("asker", R.ToAct(r))
      assert.equals(4500, r.prev.offer)
      -- and can't accept their own terms
      assert.is_false(R.Accept(r, "crafter", 220))
      -- the asker agrees to the crafter's last terms
      assert.is_true(R.Accept(r, "asker", 300))
      assert.equals("accepted", r.state)
    end)

    it("the crafter prices their part; only the asker changes the split", function()
      local r = request()
      R.Answer(r, "crafter", { offer = 6000, bring = { 0, 0, 0, 0 } }, nil, 200)
      assert.equals(15, r.reagents[1].bring)
      assert.equals("answered", R.Answer(r, "asker", { bring = { 15, 10, 0, 0 } }, nil, 300))
      assert.equals(10, r.reagents[2].bring)
      assert.equals("crafter", R.ToAct(r))
    end)

    it("the asker can change their own terms before the crafter answers", function()
      local r = request()
      assert.equals("revised", R.Answer(r, "asker", { tip = 60000 }, nil, 150))
      assert.equals("new", r.state)
      assert.equals(60000, r.tip)
      assert.equals("crafter", R.ToAct(r))
    end)

    it("crafted, handed over; declined and withdrawn end it", function()
      local r = request()
      R.Accept(r, "crafter", 200)
      assert.is_true(R.Crafted(r, 300))
      assert.equals("both", R.ToAct(r))
      assert.is_true(R.Handed(r, 400))
      assert.is_nil(R.ToAct(r))
      assert.is_false(R.Decline(r, "crafter", 500))
      local w = request()
      assert.is_true(R.Decline(w, "asker", 200))
      assert.equals("withdrawn", w.state)
    end)
  end)

  describe("on the wire", function()
    it("encodes and decodes a record, the previous terms and the message (semicolons too)", function()
      local r = request()
      r.message = "I bring the herbs; 45s for the rest"
      R.Answer(r, "crafter", { offer = 6000 }, "ok", 200)
      local body = R.Encode(r)
      assert.is_nil(body:find("|", 1, true))
      local m = R.Decode(body)
      assert.equals("record", m.kind)
      local d = m.record
      assert.equals(r.id, d.id)
      assert.equals("answered", d.state)
      assert.equals("crafter", d.by)
      assert.equals(6000, d.offer)
      assert.equals(4500, d.prev.offer)
      assert.same({ 15, 6, 0, 0 }, d.prev.bring)
      assert.is_true(d.reagents[4].soulbound)
      assert.equals("I bring the herbs; 45s for the rest", d.message)
      assert.equals("ok", d.note)
      assert.equals(13444, d.item)
    end)

    it("decodes an acknowledgement, and rejects junk", function()
      assert.same({ kind = "ack", id = "Zakzu-1-1", seq = 3 }, R.Decode(R.EncodeAck("Zakzu-1-1", 3)))
      assert.is_nil(R.Decode("R;x;y"))
      assert.is_nil(R.Decode("nonsense"))
      assert.is_nil(R.Decode(nil))
    end)

    it("rides in a sync message of its own kind", function()
      local msg = ns.Sync.EncodeCraft("Forever|Horde", R.EncodeAck("a-b-c", 2))
      local m = ns.Sync.Decode(msg)
      assert.equals("craft", m.type)
      assert.equals("Forever|Horde", m.shard)
      assert.equals("A;a-b-c;2", m.body)
    end)

    it("merges: new, newer replaces, stale and late copies of an ended one are ignored", function()
      local list = {}
      local r = request()
      local stored, what = R.Merge(list, R.Decode(R.Encode(r)).record, "crafter", 100)
      assert.equals("new", what)
      assert.equals("crafter", stored.side)
      R.Answer(r, "crafter", { offer = 1 }, nil, 200)
      local _, again = R.Merge(list, R.Decode(R.Encode(r)).record, "crafter", 200)
      assert.equals("changed", again)
      local _, stale = R.Merge(list, R.Decode(R.Encode(request())).record, "crafter", 300)
      assert.is_nil(stale)
      list[r.id].state = "declined"
      r.seq = 99
      local _, late = R.Merge(list, R.Decode(R.Encode(r)).record, "crafter", 400)
      assert.is_nil(late)
    end)

    it("the whisper puts the count and the link in front", function()
      local r = request()
      assert.equals(
        "5 × [Major Mana Potion]: Could you make these?   with a pipe",
        R.WhisperText(r, "[Major Mana Potion]")
      )
    end)
  end)

  describe("the form", function()
    local recipe = { id = 1, product = 50, made = 1, reagents = { { 10, 3 }, { 11, 2 }, { 12, 1 } } }
    local prices = { [10] = 100, [11] = 1000, [12] = 50000, [50] = 200000 }
    local held = { [10] = 30, [11] = 1 }
    local function opts()
      return {
        recipe = recipe,
        count = 5,
        held = function(id)
          return held[id] or 0
        end,
        price = function(id)
          return prices[id]
        end,
        sells = function(id)
          return prices[id]
        end,
        soulbound = function(id)
          return id == 12
        end,
        name = function(id)
          return "I" .. id
        end,
      }
    end

    it("ticks what you hold, capped at the need; the crafter's share at market is the offer", function()
      local d = R.Draft(opts())
      assert.equals(15, d.rows[1].need)
      assert.equals(15, d.rows[1].bring)
      assert.equals(1, d.rows[2].bring)
      assert.equals(9, d.rows[2].supply)
      assert.is_true(d.rows[3].soulbound)
      assert.equals(0, d.rows[3].bring)
      -- 9 x 10s + 5 x 5g = 259000
      assert.equals(259000, d.market)
      assert.equals(260000, d.offer) -- rounded to the gold
      -- sells 5 x 20g = 100g, mats 15x1s + 10x10s + 5x5g = 26.5g; a tenth of what it adds
      assert.equals(70000, d.suggested)
      assert.equals(d.offer + d.tip, d.total)
      assert.truthy(d.message:find("I bring the I10 and 1 I11.", 1, true))
    end)

    it("an offer or tip you type stays; the message follows the terms until you type in it", function()
      local d = R.Draft(opts())
      d.rows[2].bringSet = 10
      d.tip, d.tipSet = 1, true
      R.Refresh(d, opts())
      assert.equals(10, d.rows[2].bring)
      assert.equals(1, d.tip)
      assert.truthy(d.message:find("the I11", 1, true))
      d.message, d.messageSet = "mine", true
      d.count = 1
      R.Refresh(d, opts())
      assert.equals("mine", d.message)
      assert.equals(3, d.rows[1].need)
    end)

    it("rounds a tip: gold above one, silver below", function()
      assert.equals(50000, R.Round(48700))
      assert.equals(4500, R.Round(4512))
      assert.equals(0, R.SuggestTip(-5))
    end)
  end)

  describe("in game", function()
    local sent

    before_each(function()
      sent = {}
      _G.UnitName = function()
        return "Kke"
      end
      ns.AME = {
        CurrentShard = function()
          return "Forever|Horde"
        end,
        notices = {
          list = {},
          Add = function(self, e)
            self.list[#self.list + 1] = e
          end,
        },
      }
      ns.SyncService = {
        PREFIX = "AME1",
        enabled = true,
        transport = {
          Send = function(_, prefix, msg, dist, to)
            sent[#sent + 1] = { msg = msg, dist = dist, to = to }
          end,
        },
        IsMine = function(_, name)
          return name == "Kke"
        end,
      }
      ns.ItemCache = {
        Name = function()
          return "Major Mana Potion"
        end,
      }
    end)

    it("a request for one of my characters is stored, acknowledged and noticed; Home lists it", function()
      local r = request()
      assert.is_true(R.OnMessage(R.Encode(r), "Zakzu"))
      assert.equals("new", R.Get(r.id).state)
      assert.equals("crafter", R.Get(r.id).side)
      assert.equals(1, #sent)
      assert.equals("WHISPER", sent[1].dist)
      assert.equals("Zakzu", sent[1].to)
      assert.equals("craft", ns.Sync.Decode(sent[1].msg).type)
      assert.equals("craft", ns.AME.notices.list[1].kind)
      local incoming = R.Incoming()
      assert.equals(1, #incoming)
      assert.equals("Zakzu", incoming[1].from)
      assert.equals(5, incoming[1].count)
      assert.equals(13444, incoming[1].item)
      assert.equals(1, R.Waiting())
    end)

    it("ignores a request that isn't between the sender and my characters", function()
      assert.is_false(R.OnMessage(R.Encode(request()), "Someoneelse"))
      assert.is_nil(R.Get("Zakzu-1-1"))
    end)

    it("answering sends the change and keeps it in the outbox until acknowledged", function()
      R.OnMessage(R.Encode(request()), "Zakzu")
      sent = {}
      R.DoAnswer("Zakzu-1-1", { offer = 6000 }, "")
      assert.equals(1, #sent)
      local o = R.DB().outbox["Zakzu-1-1"]
      assert.equals("Zakzu", o.to)
      -- not again before it's due
      R.Flush(env.now + 1)
      assert.equals(1, #sent)
      R.Flush(env.now + R.RESEND + 1)
      assert.equals(2, #sent)
      R.OnMessage(R.EncodeAck("Zakzu-1-1", R.Get("Zakzu-1-1").seq), "Zakzu")
      assert.is_nil(R.DB().outbox["Zakzu-1-1"])
    end)

    it("accepting as asked puts it on the crafter's queue", function()
      local queued
      ns.CraftQueue = {
        New = function()
          return {
            Add = function(_, recipe, n)
              queued = { recipe, n }
            end,
          }
        end,
      }
      ns.Recipes = {
        Get = function()
          return { made = 1 }
        end,
      }
      R.OnMessage(R.Encode(request()), "Zakzu")
      R.DoAccept("Zakzu-1-1")
      assert.same({ 17580, 5 }, queued)
    end)
  end)

  describe("the sync service", function()
    it("takes craft whispers from trusted players and guild members only", function()
      addon.load({ "Core/Trust.lua", "Core/SyncService.lua" }, ns)
      local svc = ns.SyncService
      local trusted = {}
      svc.enabled = true
      svc.trust = {
        IsTrusted = function(_, name)
          return trusted[name] or false
        end,
      }
      ns.Settings = {
        Get = function()
          return true
        end,
      }
      _G.IsInGuild = function()
        return true
      end
      _G.GetNumGuildMembers = function()
        return 1
      end
      _G.GetGuildRosterInfo = function()
        return "Zakzu-Forever", nil, nil, nil, nil, nil, nil, nil, true
      end
      local m = { type = "craft" }
      assert.is_true(svc:Allowed(m, "WHISPER", "Zakzu"))
      assert.is_false(svc:Allowed(m, "WHISPER", "Stranger"))
      trusted.Stranger = true
      assert.is_true(svc:Allowed(m, "WHISPER", "Stranger"))
    end)
  end)
end)
