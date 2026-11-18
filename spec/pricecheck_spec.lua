local addon = require("spec.helpers.addon")

describe("PriceCheck", function()
  local function load()
    return addon.load({ "Core/Init.lua", "Core/PriceCheck.lua" })
  end

  describe("pure", function()
    local PC
    before_each(function()
      PC = load().PriceCheck
    end)

    it("parses !pc requests and nothing else", function()
      assert.are.equal("Linen Cloth", PC.Parse("!pc Linen Cloth"))
      assert.are.equal("Linen Cloth", PC.Parse("  !PC   Linen Cloth  "))
      local link = "|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r"
      assert.are.equal(link, PC.Parse("!pc " .. link))
      assert.is_nil(PC.Parse("!pc"))
      assert.is_nil(PC.Parse("!pc   "))
      assert.is_nil(PC.Parse("pc Linen Cloth"))
      assert.is_nil(PC.Parse("hey !pc Linen Cloth"))
      assert.is_nil(PC.Parse(nil))
    end)

    it("keys a request the same on every client: asker and item", function()
      local link = "|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r"
      assert.are.equal("gruk:i2589", PC.Key("Gruk-Realm", link))
      assert.are.equal("gruk:i2589", PC.Key("Gruk Suffix", "2589"))
      assert.are.equal("gruk:linen cloth", PC.Key("Gruk", "Linen Cloth"))
    end)

    it("fresher data claims sooner; no data claims last", function()
      assert.is_true(PC.Wait(0, 1) < PC.Wait(3, 0))
      assert.is_true(PC.Wait(7, 1) < PC.Wait(PC.NO_DATA, 0))
      assert.is_true(PC.Wait(30, 1) < PC.Wait(PC.NO_DATA, 0))
    end)

    it("picks the same winner everywhere: freshest data, then name", function()
      assert.is_true(PC.Wins({ age = 0, name = "Zed" }, { age = 1, name = "Abe" }))
      assert.is_true(PC.Wins({ age = 1, name = "abe" }, { age = 1, name = "Zed" }))
      assert.is_false(PC.Wins({ age = 1, name = "Zed" }, { age = 1, name = "abe" }))
    end)

    it("claims round-trip", function()
      local key, age = PC.DecodeClaim(PC.EncodeClaim("gruk:linen cloth", 2))
      assert.are.equal("gruk:linen cloth", key)
      assert.are.equal(2, age)
      assert.is_nil(PC.DecodeClaim("garbage"))
    end)

    it("writes money as plain chat text", function()
      assert.are.equal("1g 20s 5c", PC.Coins(12005))
      assert.are.equal("1s", PC.Coins(100))
      assert.are.equal("3g", PC.Coins(30000))
      assert.are.equal("0c", PC.Coins(0))
    end)

    it("answers in one line with prices, age and auction house", function()
      local s = { market = 120, min = 105, avg7 = 115, day = 100 }
      local line = PC.Reply("[Linen Cloth]", s, "Horde AH", 102)
      assert.are.equal(
        "[AME] [Linen Cloth]: market 1s 20c · lowest 1s 5c · 7-day avg 1s 15c · seen 2 days ago (Horde AH)",
        line
      )
      assert.is_true(#line < 255)
      assert.truthy(PC.Reply("[Linen Cloth]", nil, "Horde AH", 102):find("no prices yet", 1, true))
      assert.truthy(PC.Reply("Linnen", nil, "Horde AH", 102, false):find("item link", 1, true))
    end)
  end)

  -- several clients in one guild, wired through a fake network with addon-message latency
  describe("one answer per request", function()
    local saved, timers, clock, said, network, me
    local G = {
      "GetTime",
      "GetServerTime",
      "C_Timer",
      "UnitName",
      "UnitFactionGroup",
      "SendChatMessage",
      "C_ChatInfo",
      "C_Item",
      "AME_DB",
      "IsInGuild",
      "C_FriendList",
    }

    local function run(untilT)
      while true do
        table.sort(timers, function(a, b)
          return a.at < b.at
        end)
        local t = timers[1]
        if not t or t.at > untilT then
          clock = untilT
          return
        end
        table.remove(timers, 1)
        clock = t.at
        local prev = me
        me = t.who
        t.fn()
        me = prev
      end
    end

    local function client(name, age, opts)
      opts = opts or {}
      local ns = load()
      local today = 20000
      ns.Settings = {
        Get = function(_, k)
          if k == "priceCheck" then
            return opts.off ~= true
          end
          return k == "priceCheckWhisper" and opts.whisper or false
        end,
      }
      ns.ItemCache = {
        Link = function(id)
          return "[Item " .. id .. "]"
        end,
        Name = function(id)
          return "Item " .. id
        end,
      }
      local items = {}
      if age then
        items[2589] = { market = 120, min = 100, avg7 = 110, day = today - age }
      end
      ns.AME = {
        FactionIndex = function()
          return { items = items }
        end,
        Say = function() end,
      }
      local c = { name = name, PC = ns.PriceCheck }
      network[#network + 1] = c
      return c
    end

    -- deliver a chat line / claim to every client, as that client
    local function chat(event, msg, sender)
      for _, c in ipairs(network) do
        me = c
        c.PC:OnChat(event, msg, sender)
      end
      me = nil
    end

    before_each(function()
      saved, timers, clock, said, network = {}, {}, 1000, {}, {}
      for _, k in ipairs(G) do
        saved[k] = _G[k]
      end
      _G.GetTime = function()
        return clock
      end
      _G.GetServerTime = function()
        return 20000 * 86400 + 3600
      end
      _G.C_Timer = {
        After = function(s, fn)
          timers[#timers + 1] = { at = clock + s, fn = fn, who = me }
        end,
      }
      _G.UnitName = function()
        return me and me.name
      end
      _G.UnitFactionGroup = function()
        return "Horde"
      end
      _G.C_Item = {
        GetItemInfoInstant = function(q)
          return q == "Linen Cloth" and 2589 or nil
        end,
      }
      _G.SendChatMessage = function(text, channel, _, target)
        said[#said + 1] = { who = me.name, text = text, channel = channel, target = target }
        -- everyone sees it in chat
        local sender = me.name
        timers[#timers + 1] = {
          at = clock + 0.1,
          fn = function()
            chat("CHAT_MSG_" .. channel, text, sender)
          end,
        }
      end
      _G.C_ChatInfo = {
        SendAddonMessage = function(prefix, msg)
          local from = me
          for _, c in ipairs(network) do
            if c ~= from then
              timers[#timers + 1] = {
                at = clock + 0.15,
                who = c,
                fn = function()
                  c.PC:OnClaim(msg, from.name)
                end,
              }
            end
          end
          assert.are.equal("AMEPC1", prefix)
        end,
      }
      _G.AME_DB = { stats = {} }
    end)

    after_each(function()
      for _, k in ipairs(G) do
        _G[k] = saved[k]
      end
    end)

    it("three AME users hear !pc: only the one with the freshest data answers", function()
      client("Mira", 3)
      client("Abe", 1)
      client("Zed", 0)
      chat("CHAT_MSG_GUILD", "!pc Linen Cloth", "Gruk")
      run(clock + 10)
      assert.are.equal(1, #said)
      assert.are.equal("Zed", said[1].who)
      assert.are.equal("GUILD", said[1].channel)
      assert.truthy(said[1].text:find("market 1s 20c", 1, true))
    end)

    it("same data age: the alphabetically first name answers", function()
      client("Mira", 0)
      client("Abe", 0)
      client("Zed", 0)
      chat("CHAT_MSG_GUILD", "!pc Linen Cloth", "Gruk")
      run(clock + 10)
      assert.are.equal(1, #said)
      -- whoever claims first, the others either stayed quiet or lost the tie-break
      assert.truthy(({ Abe = true, Mira = true, Zed = true })[said[1].who])
    end)

    it("a player without data answers only when nobody has any", function()
      client("Abe") -- no data
      client("Zed", 5)
      chat("CHAT_MSG_GUILD", "!pc Linen Cloth", "Gruk")
      run(clock + 10)
      assert.are.equal(1, #said)
      assert.are.equal("Zed", said[1].who)
    end)

    it("when the winner never answers, someone else does", function()
      local zed = client("Zed", 0)
      client("Abe", 2)
      zed.PC.CanSend = function()
        return false -- Zed claims, wins, then can't send (rate limit, disconnect...)
      end
      chat("CHAT_MSG_GUILD", "!pc Linen Cloth", "Gruk")
      run(clock + 20)
      assert.are.equal(1, #said)
      assert.are.equal("Abe", said[1].who)
    end)

    it("stays quiet when off, and for repeats", function()
      client("Abe", 0, { off = true })
      chat("CHAT_MSG_GUILD", "!pc Linen Cloth", "Gruk")
      run(clock + 10)
      assert.are.equal(0, #said)

      network = {}
      client("Abe", 0)
      chat("CHAT_MSG_GUILD", "!pc Linen Cloth", "Gruk")
      run(clock + 10)
      chat("CHAT_MSG_GUILD", "!pc Linen Cloth", "Gruk")
      run(clock + 10)
      assert.are.equal(1, #said)
    end)

    it("your own !pc is answered in the channel you asked in, even with price checks off", function()
      client("Abe", 0, { off = true })
      chat("CHAT_MSG_PARTY", "!pc Linen Cloth", "Abe")
      run(clock + 10)
      assert.are.equal(1, #said)
      assert.are.equal("PARTY", said[1].channel)
      assert.are.equal("Abe", said[1].who)
    end)

    it("your own !pc: a party member with fresher data answers instead", function()
      client("Abe", 4, { off = true })
      client("Zed", 0)
      chat("CHAT_MSG_PARTY", "!pc Linen Cloth", "Abe")
      run(clock + 10)
      assert.are.equal(1, #said)
      assert.are.equal("Zed", said[1].who)
    end)

    it("whispers are answered directly, for players it knows, when whispers are on", function()
      _G.IsInGuild = function()
        return false
      end
      _G.C_FriendList = {
        GetFriendInfo = function(n)
          return n == "Pal" and { connected = true } or nil
        end,
      }
      client("Abe", 0)
      chat("CHAT_MSG_WHISPER", "!pc Linen Cloth", "Pal")
      run(clock + 5)
      assert.are.equal(0, #said) -- whispers off

      network = {}
      client("Abe", 0, { whisper = true })
      chat("CHAT_MSG_WHISPER", "!pc Linen Cloth", "Stranger")
      run(clock + 5)
      assert.are.equal(0, #said) -- not a guild member, friend or trusted player
      chat("CHAT_MSG_WHISPER", "!pc Linen Cloth", "Pal")
      run(clock + 5)
      assert.are.equal(1, #said)
      assert.are.equal("WHISPER", said[1].channel)
      assert.are.equal("Pal", said[1].target)
    end)
  end)
end)
