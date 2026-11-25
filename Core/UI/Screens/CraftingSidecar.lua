-- Opening a profession (setting "professionMode": "ame" | "game", docs/ux/redesign-review.md "Crafting has two modes"):
--   takeover (the default): the AME window opens on Crafting with that profession picked; the game's window stays
--     open (the game answers profession questions only while it is) but out of sight, and closing AME closes it.
--     "Use the game's window" in the Crafting toolbar (and on the error panel if a screen fails) swaps to the sidecar.
--   sidecar: the game's window stays the recipe list (with AME's profit column, Core/UI/ProfessionBar.lua) and one
--     AME frame sits beside it (boards CraftQueue, ProfBar): the picked recipe's cost, sells for, profit, Make N and
--     Queue, then the queue itself. "Open in AME" on the frame swaps to the takeover.
-- Only while the new window is on (App.Enabled, /ame new); otherwise the current profession bar is left as it is.
-- The frame is drawn by its own Layout.Renderer with the crafting widgets; its actions are the Crafting screen's.
local _, ns = ...
local L = ns.L

local Layout, Kit, W, CP = ns.Layout, ns.Kit, ns.Widgets, ns.CraftingPage
local Screen = ns.CraftingScreen

local Side = { W = 380, took = false, count = 1 }
ns.CraftingSidecar = Side

function Side.Mode()
  local mode = ns.Settings and ns.Settings:Get("professionMode")
  return mode == "game" and "sidecar" or "takeover"
end

function Side.On()
  return ns.App and ns.App.Enabled and ns.App.Enabled() or false
end

function Side.TookOver()
  return Side.took
end

local function gameFrame()
  return _G.ProfessionsFrame
end

local function api()
  return _G.C_TradeSkillUI
end

-- the profession the game's window has open (skill line), or nil
function Side.OpenProfession()
  local a = api()
  local ok, p = pcall(a and a.GetBaseProfessionInfo or error)
  return ok and type(p) == "table" and p.professionID ~= 0 and p.professionID or nil
end

-- ------------------------------------------------------------------------------------------------ takeover

-- out of sight but open: invisible and off the screen, put back where it was when it's wanted again
function Side.HideGame()
  local pf = gameFrame()
  if not pf or Side.hidden then
    return
  end
  local h = { alpha = pf.GetAlpha and pf:GetAlpha() or 1, points = {} }
  for i = 1, (pf.GetNumPoints and pf:GetNumPoints() or 0) do
    h.points[i] = { pf:GetPoint(i) }
  end
  Side.hidden = h
  pf:SetAlpha(0)
  pf:ClearAllPoints()
  pf:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -4000, 0)
end

function Side.ShowGame()
  local pf, h = gameFrame(), Side.hidden
  if not (pf and h) then
    return
  end
  Side.hidden = nil
  pf:SetAlpha(h.alpha or 1)
  pf:ClearAllPoints()
  for _, pt in ipairs(h.points) do
    pf:SetPoint(unpack(pt))
  end
  if #h.points == 0 and _G.UpdateUIPanelPositions then
    pcall(_G.UpdateUIPanelPositions, pf)
  end
end

function Side.TakeOver()
  Side.took = true
  Side.HideGame()
  if Side.frame then
    Side.frame:Hide()
  end
  if Screen then
    Screen.Dirty()
  end
  local App = ns.App
  local here = App.frame and App.frame:IsShown() and App.screens and App:Current() and App.screens[App:Current()]
  if here and here.tab == "crafting" then
    -- opened from AME itself (Craft next, Create): stay where you are - on the queue the next click crafts
    App:Render()
  else
    App:Go("crafting", { profession = Side.OpenProfession(), filter = "all", selected = false })
  end
  Side.HookApp()
end

-- closing AME in the takeover closes the profession too (it was open only for AME)
function Side.HookApp()
  local App = ns.App
  if Side.appHooked or not (App and App.frame) then
    return
  end
  Side.appHooked = true
  App.frame:HookScript("OnHide", function()
    if not Side.took then
      return
    end
    Side.took = false
    local pf = gameFrame()
    if pf and pf:IsShown() and _G.HideUIPanel then
      pcall(_G.HideUIPanel, pf)
    elseif api() and api().CloseTradeSkill then
      pcall(api().CloseTradeSkill)
    end
    Side.ShowGame()
  end)
end

-- "Use the game's window": the game's window and the frame beside it, remembered for next time
function Side.UseGameWindow()
  if ns.Settings then
    ns.Settings:Set("professionMode", "game")
  end
  Side.took = false
  Side.ShowGame()
  if ns.App then
    ns.App:Hide()
  end
  Side.ShowFrame()
end

-- the frame's "Open in AME": the takeover, remembered
function Side.OpenInAME()
  if ns.Settings then
    ns.Settings:Set("professionMode", "ame")
  end
  Side.TakeOver()
end

-- the game's window opened (a profession, on any character)
function Side.Opened()
  if not Side.On() then
    return
  end
  if Screen then
    Screen.Dirty()
  end
  Side.HideOldBar()
  if Side.Mode() == "takeover" then
    Side.TakeOver()
  else
    Side.ShowFrame()
  end
end

-- the game's window closed: put it back for next time, and let the screen know Create is gone
function Side.Closed()
  if Side.frame then
    Side.frame:Hide()
  end
  if Side.took then
    Side.took = false
    Side.ShowGame()
  end
  if Screen then
    Screen.Dirty()
  end
  if ns.App and ns.App.Redraw then
    ns.App:Redraw()
  end
end

-- ------------------------------------------------------------------------------------------------ the frame

-- the bar under the window and the old queue panel give way to the frame
function Side.HideOldBar()
  local PB = ns.ProfessionBar
  if not (Side.On() and PB) then
    return
  end
  if PB.bar then
    PB.bar:Hide()
  end
  if PB.panel then
    PB.panel:Hide()
  end
end

-- the Crafting screen's actions, run against this frame (it answers what they ask of an app)
local handlers = setmetatable({}, {
  __index = function(_, name)
    local fn = Side.actions[name] or (Screen and Screen.actions[name])
    return fn and function(payload)
      fn(Side, payload)
    end
  end,
})

function Side:Render()
  if self.frame and self.frame:IsShown() then
    self.renderer:Render(Side.Tree())
  end
end

function Side:Redraw()
  if self.pending then
    return
  end
  self.pending = true
  local function go()
    self.pending = false
    self:Render()
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, go)
  else
    go()
  end
end

function Side:AtAH()
  return ns.AME and ns.AME.ahOpen and true or false
end

function Side:Go(id, params)
  ns.App:Go(id, params)
end

function Side:Source(name, rows)
  self.ctx.sources[name] = rows
end

function Side.Create()
  if Side.frame then
    return Side.frame
  end
  local f = CreateFrame("Frame", "AMECraftingFrame", UIParent, "BackdropTemplate")
  Kit.Box(f, "bg", "frame")
  f:SetFrameStrata("HIGH")
  f:SetWidth(Side.W)
  f:SetHeight(600)
  f:EnableMouse(true)
  f:Hide()
  Side.frame = f
  Side.ctx = Layout.Context(handlers, { app = Side, sources = {} })
  Side.renderer = Layout.Renderer(f, Side.ctx)
  return f
end

function Side.Place()
  local f, pf = Side.frame, gameFrame()
  if not (f and pf) then
    return
  end
  local PB = ns.ProfessionBar
  if PB and PB.PlaceQueue then
    PB.PlaceQueue(f, pf) -- beside it, clear of its side tabs
  else
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", pf, "TOPRIGHT", 4, 0)
    f:SetPoint("BOTTOMLEFT", pf, "BOTTOMRIGHT", 4, 0)
  end
end

function Side.ShowFrame()
  Side.Create()
  Side.Place()
  Side.frame:Show()
  Side:Render()
end

-- the recipe picked in the game's window (the profession bar follows the selection)
local function picked()
  local PB = ns.ProfessionBar
  local id = PB and PB.selected
  return id and ns.Recipes.Get(id) or nil
end

local function moneyText(label, copper, signedIt)
  local v = copper and (signedIt and W.SignedMoney(copper) or W.Money(copper, true)) or Kit.Color("dim", "—")
  return Kit.Color("dim", label .. " ") .. v
end

local STEP_COLS = {
  { key = "n", label = "#", width = 20, format = "count" },
  { key = "item", label = L["Craft"], width = 170, item = true },
  { key = "profitText", label = L["Profit"], width = 90 },
  { key = "act", label = "", width = 40, button = { label = "✕", action = "stepAct" } },
}
local MAT_COLS = {
  { key = "item", label = L["Material"], width = 120, item = true },
  { key = "need", label = L["Need"], width = 40 },
  { key = "source", label = L["Source"], width = 150, format = "tag" },
}

-- the frame's tree (board CraftQueue)
function Side.Tree()
  local f = Screen.Facts()
  local kids = {
    { id = "side.title", type = "frametitle", props = { title = L["Crafting"], note = L["beside the game's profession window"] }, meta = { h = 22 } },
    {
      id = "side.pickedHead",
      type = "row",
      props = { gap = 6, align = "center" },
      meta = { h = 24 },
      children = {
        { id = "side.pickedTitle", type = "text", props = { text = L["Picked in the window"], font = "display", size = 14 }, meta = { grow = 1 } },
        { id = "side.open", type = "button", props = { label = L["Open in AME"], action = "openInAME" } },
      },
    },
  }
  local recipe = picked()
  local PB = ns.ProfessionBar
  if recipe and PB and PB.Summary and f.craft then
    local count = Side.count or 1
    local ok, s = pcall(PB.Summary, recipe, f.craft, count, PB.Unclaimed and PB.Unclaimed() or nil, f.quote)
    s = ok and s or {}
    kids[#kids + 1] = {
      id = "side.item",
      type = "row",
      props = { gap = 6, align = "center" },
      meta = { h = 18 },
      children = {
        { id = "side.link", type = "itemlink", props = { item = recipe.product, size = 13 }, meta = { grow = 1 } },
        { id = "side.rate", type = "text", props = { text = L["%s sold/day"]:format(PB.RateText and PB.RateText(s.sellRate) or "?"), color = "dim" } },
        { id = "side.signal", type = "signal", props = { signal = s.signal ~= "none" and s.signal or nil } },
      },
    }
    kids[#kids + 1] = {
      id = "side.money",
      type = "text",
      props = {
        text = moneyText(L["Cost to craft"], s.cost) .. "   " .. moneyText(L["Sells for"], s.sells) .. "   " .. moneyText(L["Profit"], s.profit, true),
        size = 12,
      },
      meta = { h = 18 },
    }
    local buttons = {
      { key = "sideQueue", label = L["Queue %d"]:format(count), variant = "primary" },
      { key = "sideList", label = L["Reagents to a list"] .. (W.ARROW_DOWN or "") },
    }
    if Side:AtAH() then
      buttons[#buttons + 1] = { key = "sideSearch", label = L["Search the AH"] }
    end
    buttons[#buttons + 1] = { key = "sideItem", label = L["Open item"] }
    kids[#kids + 1] = { id = "side.make", type = "makebar", props = { count = count, recipe = recipe.id, buttons = buttons, action = "sideMake" }, meta = { h = 24 } }
    kids[#kids + 1] = {
      id = "side.batch",
      type = "text",
      props = {
        text = Kit.Color("dim", ("×%d: "):format(count)) .. moneyText(L["profit"], s.profit and s.profit * count, true) .. Kit.Color("dim", " · ") .. moneyText(L["to buy"], s.toBuy),
      },
      meta = { h = 18 },
    }
    kids[#kids + 1] = {
      id = "side.note",
      type = "text",
      props = { text = L["Profit after the AH cut, reagents at market. Search the AH shows only at the auction house."], color = "dim", size = 11, wrap = true },
      meta = { h = 28 },
    }
  else
    kids[#kids + 1] = {
      id = "side.none",
      type = "text",
      props = { text = L["Pick a recipe in the game's window."], color = "dim" },
      meta = { h = 18 },
    }
  end
  kids[#kids + 1] = { id = "side.rule", type = "divider", meta = { h = 1 } }

  local q = CP.Queue(f)
  kids[#kids + 1] = {
    id = "side.queueHead",
    type = "row",
    props = { gap = 6, align = "center" },
    meta = { h = 22 },
    children = {
      { id = "side.queueTitle", type = "text", props = { text = L["Craft queue"], font = "display", size = 15 }, meta = { grow = 1 } },
      { id = "side.queueTotals", type = "text", props = { text = moneyText(L["profit"], q.profit, true) .. Kit.Color("dim", " · ") .. moneyText(L["to buy"], q.toBuy) } },
    },
  }
  if #q.steps == 0 then
    kids[#kids + 1] = {
      id = "side.empty",
      type = "text",
      props = { text = L["Nothing queued. Pick a recipe and click Queue."], color = "dim", wrap = true },
      meta = { h = 30 },
    }
  else
    Side:Source("side.steps", Screen.StepRows(q))
    Side:Source("side.mats", q.mats)
    local nextStep = PB and PB.NextStep and select(2, pcall(PB.NextStep, PB))
    local nextName = type(nextStep) == "table" and (nextStep.item and f.itemName(nextStep.item) or f.recipeName(nextStep.recipe)) or nil
    kids[#kids + 1] = { id = "side.order", type = "text", props = { text = L["In order"], font = "display", size = 14 }, meta = { h = 18 } }
    kids[#kids + 1] = { id = "side.steps", type = "crafttable", props = { source = "side.steps", columns = STEP_COLS, bare = true, flex = "item" }, meta = { h = 6 + 20 * #q.steps } }
    kids[#kids + 1] = { id = "side.matsTitle", type = "text", props = { text = L["Materials"], font = "display", size = 14 }, meta = { h = 18 } }
    kids[#kids + 1] = {
      id = "side.mats",
      type = "crafttable",
      props = { source = "side.mats", columns = MAT_COLS, action = "matRow", flex = "source" },
      meta = { h = math.min(200, 26 + 20 * #q.mats) },
    }
    kids[#kids + 1] = { id = "side.todo", type = "partslines", props = { title = L["To do"], lines = q.todo } }
    kids[#kids + 1] = {
      id = "side.buttons",
      type = "row",
      props = { gap = 6 },
      meta = { h = 24 },
      children = {
        {
          id = "side.next",
          type = "craftbutton",
          props = {
            label = nextName and L["Craft next: %s"]:format(nextName) or L["Craft next"],
            variant = nextName and "primary" or "disabled",
            call = "craftNext",
            action = "craftedNext",
          },
        },
        { id = "side.missing", type = "button", props = { label = L["Missing to a list"], action = "buyMissing" } },
        { id = "side.clear", type = "button", props = { label = L["Clear"], action = "clear" } },
      },
    }
    kids[#kids + 1] = {
      id = "side.queueNote",
      type = "text",
      props = {
        text = L["Craft next skips steps this character can't do, and steps still missing materials. The queue is kept per account."],
        color = "dim",
        size = 11,
        wrap = true,
      },
      meta = { h = 28 },
    }
  end
  return { id = "side", type = "column", props = { gap = 6, pad = 10 }, children = kids }
end

Side.actions = {
  close = function()
    if Side.frame then
      Side.frame:Hide()
    end
  end,
  openInAME = function()
    Side.OpenInAME()
  end,
  sideMake = function(_, p)
    local recipe = p.recipe and ns.Recipes.Get(p.recipe)
    local PB = ns.ProfessionBar
    if p.key == "count" then
      Side.count = p.count
    elseif p.key == "sideQueue" and recipe then
      Side.count = p.count
      AME_DB.craftQueue = AME_DB.craftQueue or {}
      ns.CraftQueue.New(AME_DB.craftQueue):Add(recipe.id, p.count)
      Screen.Dirty()
    elseif p.key == "sideList" and recipe and PB and PB.RecipeToShopping then
      PB:RecipeToShopping(recipe, p.count, Side.renderer:Frame("side.make") or Side.frame)
    elseif p.key == "sideSearch" and recipe and PB and PB.Search then
      PB:Search(recipe)
    elseif p.key == "sideItem" and recipe and recipe.product then
      ns.App:Go("item", { item = recipe.product })
    end
    Side:Render()
  end,
}

-- ------------------------------------------------------------------------------------------------ wiring

local function hookPB()
  local PB = ns.ProfessionBar
  if Side.pbHooked or not PB then
    return
  end
  Side.pbHooked = true
  -- the picked recipe changed, or what you hold did: the frame follows; the bar stays hidden
  if PB.RenderBar then
    hooksecurefunc(PB, "RenderBar", function()
      Side.HideOldBar()
      if Side.frame and Side.frame:IsShown() then
        Side:Redraw()
      end
    end)
  end
  if PB.ShowQueue then
    hooksecurefunc(PB, "ShowQueue", function()
      Side.HideOldBar()
    end)
  end
  if PB.Refresh then
    hooksecurefunc(PB, "Refresh", function()
      if Screen then
        Screen.Dirty()
      end
      if Side.frame and Side.frame:IsShown() then
        Side:Redraw()
      end
    end)
  end
end

local function hookGame()
  local pf = gameFrame()
  if Side.gameHooked or not pf then
    return
  end
  Side.gameHooked = true
  pf:HookScript("OnShow", function()
    Side.Opened()
  end)
  pf:HookScript("OnHide", function()
    Side.Closed()
  end)
  if pf:IsShown() then
    Side.Opened()
  end
end

-- what changes what's ready: the recipes the open window lists, your bags
local function changed()
  if Screen then
    Screen.Dirty()
  end
  local App = ns.App
  local id = App and App.Current and App:Current()
  local s = id and App.screens[id]
  if s and s.tab == "crafting" and App.frame and App.frame:IsShown() then
    App:Redraw()
  end
  if Side.frame and Side.frame:IsShown() then
    Side:Redraw()
  end
end

function Side.Start()
  if Side.events then
    return
  end
  local f = CreateFrame("Frame")
  Side.events = f
  pcall(f.RegisterEvent, f, "ADDON_LOADED")
  pcall(f.RegisterEvent, f, "TRADE_SKILL_LIST_UPDATE")
  pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
  f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
      if name == "Blizzard_Professions" then
        hookPB()
        hookGame()
      end
    else
      changed()
    end
  end)
  hookPB()
  hookGame()
  Side.HideOldBar()
end

-- after every file has loaded (ProfessionBar comes later in the TOC)
local boot = CreateFrame("Frame")
pcall(boot.RegisterEvent, boot, "PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  Side.Start()
end)
