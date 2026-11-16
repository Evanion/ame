local addon = require("spec.helpers.addon")

describe("Trust", function()
  local Trust, t

  before_each(function()
    Trust = addon.load({ "Core/Init.lua", "Core/Trust.lua" }).Trust
    t = Trust.New({})
  end)

  it("adds players case-insensitively, one-sided until they confirm", function()
    local e = t:Add("  Tyken Evanion ", 100)
    assert.are.equal("Tyken Evanion", e.name)
    assert.is_false(e.mutual)
    assert.is_true(t:IsTrusted("tyken evanion"))
    t:MarkMutual("TYKEN EVANION")
    assert.is_true(e.mutual)
    assert.is_nil((t:Add("   ", 1)))
  end)

  it("turns a hello from a stranger into a pending request, once", function()
    assert.is_true(t:Request("Ada Lovelace", 10))
    assert.is_false(t:Request("Ada Lovelace", 20))
    assert.are.equal(1, #t:PendingList())
    local e = t:Approve("ada lovelace", 30)
    assert.is_true(e.mutual)
    assert.are.equal(0, #t:PendingList())
    assert.is_false(t:Request("Ada Lovelace", 40)) -- already trusted
  end)

  it("adding someone who already asked approves them", function()
    t:Request("Ada Lovelace", 10)
    local e = t:Add("Ada Lovelace", 20)
    assert.is_true(e.mutual)
    assert.are.equal(0, #t:PendingList())
  end)

  it("keeps declined players quiet for a day", function()
    t:Request("Spam Bot", 0)
    t:Decline("Spam Bot", 0)
    assert.is_false(t:Request("Spam Bot", 3600))
    assert.is_true(t:Request("Spam Bot", 25 * 3600))
  end)

  it("whispers only trusted players that are online or heard from recently", function()
    t:Add("Ada Lovelace", 0)
    t:Add("Bob Builder", 0)
    t:Add("Cy Offline", 0)
    t:Heard("ada lovelace", 1000, "WHISPER")
    t:Heard("Stranger Danger", 1000, "GUILD") -- not trusted: never a target
    local targets = t:OnlineTargets(1000 + 60, function(name)
      return name == "Bob Builder"
    end)
    assert.are.same({ "Ada Lovelace", "Bob Builder" }, targets)
    assert.are.same(
      { "Bob Builder" },
      t:OnlineTargets(1000 + 3600, function(name)
        return name == "Bob Builder"
      end)
    )
  end)

  it("tracks peers and what they sent", function()
    t:Heard("Ada Lovelace", 5, "GUILD")
    t:Received("ada lovelace")
    t:Heard("Bob Builder", 9, "WHISPER")
    local peers = t:PeerList()
    assert.are.equal("Bob Builder", peers[1].name)
    assert.are.equal(1, peers[2].received)
  end)

  it("removes trust", function()
    t:Add("Ada Lovelace", 0)
    t:Remove("ADA LOVELACE")
    assert.is_false(t:IsTrusted("Ada Lovelace"))
  end)

  it("blocks personally (dropping trust and requests) and by guild list", function()
    t:Add("Ada Lovelace", 0)
    t:Request("Spam Bot", 0)
    t:Block("ada lovelace", 5)
    t:Block("Spam Bot", 5)
    assert.are.equal("me", t:IsBlocked("Ada Lovelace"))
    assert.is_false(t:IsTrusted("Ada Lovelace"))
    assert.are.equal(0, #t:PendingList())
    assert.is_false(t:Request("Spam Bot", 99999)) -- blocked players can't ask again
    t:SetGuildBlocklist({ ["price fixer"] = "Price Fixer" })
    assert.are.equal("guild", t:IsBlocked("PRICE FIXER"))
    t:Unblock("Ada Lovelace")
    assert.is_nil(t:IsBlocked("Ada Lovelace"))
    assert.are.equal(1, #t:BlockedList())
  end)
end)
