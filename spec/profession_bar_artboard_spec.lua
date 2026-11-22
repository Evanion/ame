-- The profession bar's and "Who can make it"'s artboard features (design canvas ProfBar, Crafters): the bar's
-- Sells/day and signal on line 1, "no price" and the footnote on the recipe list, the recipe item on the AH with its
-- price, and the header's "recipes from N players".
local addon = require("spec.helpers.addon")
local wow = require("spec.helpers.wow")

local function plain(text)
  return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

describe("profession bar pieces", function()
  local ns, PB
  before_each(function()
    ns = addon.load({ "Core/Init.lua", "Core/UI/Widgets.lua", "Core/UI/ProfessionBar.lua" })
    PB = ns.ProfessionBar
  end)

  it("writes the sales rate as a number for the Sells/day label", function()
    assert.are.equal("0.8", PB.RateText(0.8))
    assert.are.equal("12", PB.RateText(12.4))
    assert.are.equal("0", PB.RateText(0.01))
    assert.are.equal("-", plain(PB.RateText(nil)))
  end)

  it("shows a recipe row's profit, no price when it has none, and nothing for an enchant", function()
    assert.truthy(plain(PB.RowText({ profit = 800 })):find("8s", 1, true))
    assert.are.equal("no price", plain(PB.RowText({ why = "unpriced" })))
    assert.are.equal("", PB.RowText(false)) -- an enchant makes no item
    assert.are.equal("", PB.RowText(nil)) -- no market data yet
  end)

  it("takes the product's sales rate and signal into the summary", function()
    local craft = {}
    function craft:Evaluate()
      return { cost = 100, revenue = 300, profit = 200 }
    end
    function craft:SalesPerDay(id)
      return id == 7 and 0.8 or nil
    end
    local quote = {}
    function quote:Summary(id)
      return id == 7 and { signal = "buy" } or nil
    end
    local s = PB.Summary({ product = 7, reagents = {} }, craft, 1, nil, quote)
    assert.are.equal(0.8, s.sellRate)
    assert.are.equal("buy", s.signal)
    local none = PB.Summary({ product = 8, reagents = {} }, craft, 1, nil, quote)
    assert.are.equal("none", none.signal)
  end)
end)

describe("Who can make it pieces", function()
  it("counts the players the recipes came from, once per sender", function()
    local ns = addon.load({ "Core/Init.lua", "Core/Codec.lua", "Core/Crafters.lua" })
    local c = ns.Crafters.New({
      Brakka = { owner = "Brakka", t = 1, profs = {} },
      Brakkalt = { owner = "Brakka", t = 1, profs = {} },
      Sela = { owner = "Sela", t = 1, profs = {} },
    })
    assert.are.equal(2, c:Players())
  end)

  it("puts the recipe item that teaches a recipe under it, with its price", function()
    local ns = addon.load({ "Core/Init.lua", "Core/UI/Widgets.lua" })
    ns.UI = {}
    ns.Recipes = {
      Get = function()
        return nil
      end,
      TaughtBy = function(spell)
        return spell == 100 and { { item = 7975, rank = 200 } } or {}
      end,
    }
    addon.load({ "Core/UI/CraftersView.lua" }, ns)
    local V = ns.CraftersView
    local lines = V.Lines({
      { recipe = 100, name = "Enchant Weapon - Crusader", who = { { name = "Sela", online = true, skill = 300 } } },
    }, function(id)
      return id == 7975 and 520000 or nil
    end)
    assert.are.equal("recipe", lines[1].kind)
    assert.are.equal("formula", lines[2].kind)
    assert.are.equal(7975, lines[2].item)
    assert.are.equal(520000, lines[2].price)
    assert.are.equal(7975, V.ItemOf(lines[2])) -- an item link row
    assert.are.equal("crafter", lines[3].kind)
    assert.are.equal("", V.Meta(0))
    assert.are.equal("recipes from 38 players · guild and trusted", V.Meta(38))

    -- Whisper: the game's own "whisper this player", with the whole name (Forever's names have two words), then the
    -- link; never "/w First Last", which whispers First with Last as the message
    local told, typed, linked
    rawset(_G, "ChatFrame_SendTell", function(name)
      told = name
    end)
    rawset(_G, "ChatFrame_OpenChat", function(text)
      typed = text
    end)
    rawset(_G, "ChatEdit_InsertLink", function(link)
      linked = link
    end)
    finally(function()
      rawset(_G, "ChatFrame_SendTell", nil)
      rawset(_G, "ChatFrame_OpenChat", nil)
      rawset(_G, "ChatEdit_InsertLink", nil)
    end)
    ns.Crafters = ns.Crafters or {}
    ns.Crafters.RecipeName = function()
      return "Enchant Weapon - Crusader"
    end
    V.Whisper("Roach Earthshaker", 100)
    assert.are.equal("Roach Earthshaker", told)
    assert.is_nil(typed)
    assert.is_not_nil(linked)
    -- an old client without it: "/w" for a one-word name, nothing for two words
    rawset(_G, "ChatFrame_SendTell", nil)
    V.Whisper("Sela", 100)
    assert.are.equal("/w Sela ", typed)
    typed = nil
    V.Whisper("Roach Earthshaker", 100)
    assert.is_nil(typed)
  end)
end)

describe("profession bar and Who can make it in a stubbed client", function()
  local f = io.open("Libs/LibDeflate/LibDeflate.lua", "r")
  if not f then
    pending("Libs missing; run scripts/fetch-libs.sh")
    return
  end
  f:close()

  local env, ns

  local function boot()
    env = wow.install()
    ns = wow.loadAddon("AzerothMercantileExchange.toc", "AzerothMercantileExchange")
    env:fire("ADDON_LOADED", "AzerothMercantileExchange")
    env:fire("PLAYER_LOGIN")
  end

  local function drainJobs()
    for _ = 1, 5000 do
      if not ns.AME.jobs:Busy() then
        return
      end
      env:update(1)
    end
    error("jobs did not finish")
  end

  local function fullScan(rows)
    env.npcFaction = "Horde"
    env:fire("AUCTION_HOUSE_SHOW")
    env.ah.rows = rows
    C_AuctionHouse.ReplicateItems()
    for _ = 1, 30 do
      env:fire("REPLICATE_ITEM_LIST_UPDATE")
    end
    drainJobs()
    env:fire("AUCTION_HOUSE_CLOSED")
    env:advance(4)
    drainJobs()
  end

  after_each(function()
    if env then
      env:restore()
    end
  end)

  it("the bar's line 1 ends in Sells/day and the signal; the list says no price and has its footnote", function()
    boot()
    -- bars, cloth and gauntlets at the Horde AH; nothing for the grinding stone (101) or its stone
    fullScan({ { 3860, 6000, 50 }, { 4338, 3600, 80 }, { 7919, 10000, 5 } })
    local recipes = {
      [100] = { out = 7919, r = { { 3860, 6 }, { 4338, 4 } } },
      [101] = { out = 12644, r = { { 12365, 4 } } },
    }
    rawset(_G, "C_TradeSkillUI", {
      IsTradeSkillReady = function()
        return true
      end,
      GetBaseProfessionInfo = function()
        return { professionID = 164, professionName = "Blacksmithing", skillLevel = 230, maxSkillLevel = 300 }
      end,
      GetAllRecipeIDs = function()
        return { 100, 101 }
      end,
      GetRecipeSchematic = function(id)
        local r = recipes[id]
        if r then
          local slots = {}
          for _, g in ipairs(r.r) do
            slots[#slots + 1] = { reagentType = 1, quantityRequired = g[2], reagents = { { itemID = g[1] } } }
          end
          return { outputItemID = r.out, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = slots }
        end
      end,
      GetRecipeInfo = function(id)
        return recipes[id] and { recipeID = id, learned = true, numAvailable = 0 } or nil
      end,
    })
    local list = CreateFrame("Frame")
    local page = { SelectRecipe = function() end, SchematicForm = { Init = function() end }, RecipeList = list }
    local frame = CreateFrame("Frame")
    rawset(frame, "CraftingPage", page)
    rawset(_G, "ProfessionsFrame", frame)
    rawset(_G, "ProfessionsRecipeListRecipeMixin", { Init = function() end })
    finally(function()
      rawset(_G, "C_TradeSkillUI", nil)
      rawset(_G, "ProfessionsFrame", nil)
      rawset(_G, "ProfessionsRecipeListRecipeMixin", nil)
    end)
    ns.CraftingData.data = { vendor = {}, recipes = {}, items = {} }
    env:fire("ADDON_LOADED", "Blizzard_Professions")
    local PB = ns.ProfessionBar
    ns.Professions:Record()
    -- the gauntlets sell 0.8 a day and say BUY
    local s = ns.AME:FactionIndex().items[7919]
    s.sellRate, s.signal = 0.8, "buy"
    page:SelectRecipe({ recipeID = 100 })
    assert.are.equal("Sells/day 0.8", plain(PB.bar.rate:GetText()))
    assert.is_true(PB.bar.signal:IsShown())
    assert.are.equal("buy", PB.bar.signal.signal)
    -- without a signal: no badge
    s.signal = "none"
    PB:RenderBar()
    assert.is_false(PB.bar.signal:IsShown())
    -- the recipe list: profit on one, no price on the other, the footnote under it
    local function row(id)
      local r = CreateFrame("Frame")
      rawget(_G, "ProfessionsRecipeListRecipeMixin").Init(r, {
        GetData = function()
          return { recipeInfo = { recipeID = id } }
        end,
      })
      return rawget(r, "ameProfit"), r
    end
    local priced, pricedRow = row(100)
    assert.truthy(priced:GetText():find("s"), priced:GetText())
    assert.are.equal("no price", plain((row(101)):GetText()))
    assert.are.equal("Profit after the AH cut, reagents at market. Hover for the breakdown.", PB.listNote:GetText())
    -- hovering a row: the breakdown
    local lines = {}
    local tip = {
      AddDoubleLine = function(_, l, r)
        lines[#lines + 1] = plain(l) .. "=" .. plain(r)
      end,
      AddLine = function() end,
    }
    assert.is_not_false(PB.RowTip(tip, pricedRow))
    assert.truthy(lines[1]:find("^Cost to craft="), lines[1])
    assert.truthy(lines[4]:find("^Sells/day="), lines[4])
  end)

  it("who can make it: the recipe item on the AH with its price, and how many players the recipes came from", function()
    boot()
    fullScan({ { 7975, 520000, 1 } })
    rawset(_G, "GetSpellInfo", function(id)
      return ({ [100] = "Enchant Weapon - Crusader" })[id]
    end)
    finally(function()
      rawset(_G, "GetSpellInfo", nil)
    end)
    ns.CraftingData.data = { vendor = {}, recipes = {}, items = { [7975] = { 333, 290, 100 } } }
    local body = ns.Crafters.Encode({ [333] = { skill = 300, ids = { [100] = true } } })
    AME_DB.crafters = {
      Sela = { owner = "Sela", t = GetServerTime(), profs = ns.Crafters.Decode(body) },
      Gromm = { owner = "Gromm", t = GetServerTime(), profs = ns.Crafters.Decode(body) },
    }
    ns.CraftersView:Open("crusader")
    local v = ns.CraftersView.frame
    assert.are.equal("recipes from 2 players · guild and trusted", v.meta:GetText())
    local formula = v.lines[2]
    assert.are.equal("formula", formula.kind)
    assert.are.equal(7975, formula.item)
    assert.are.equal(520000, formula.price)
  end)
end)
