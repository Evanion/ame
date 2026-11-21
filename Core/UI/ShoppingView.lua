-- Shopping lists on the Market tab: pick one in the sidebar and the screener gives way to what the list still needs
-- - how many, what your characters already hold, what's left to buy and what it costs at market. Lists are made
-- with "+ New shopping list", from a recipe ("Add reagents" with the profession window open) or from any item's
-- right-click menu. See Core/Shopping.lua.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

local function shopping()
  return ns.AME.shopping
end

-- the selected list: { list = { name, items, shared? }, own = index or nil, guild = key or nil }
function UI:ShoppingSelected()
  local q = self.mq
  local which = q and type(q.list) == "string" and q.list
  if not which then
    return nil
  end
  local own = which:match("^s:(%d+)$")
  if own then
    local l = shopping():Lists()[tonumber(own)]
    return l and { list = l, own = tonumber(own) } or nil
  end
  local guild = which:match("^sg:(.+)$")
  if guild then
    local g = shopping().db.guild[guild]
    return g and { list = g, guild = guild } or nil
  end
  return nil
end

---------------------------------------------------------------------------------------------------------------------
-- the panel

local function rowMoney(v)
  return v and W.Money(v) or W.Dim("-")
end

local COLS = {
  { key = "name", label = L["Item"], width = 220, item = true, ascendingFirst = true },
  { key = "need", label = L["Need"], width = 54, format = "count" },
  {
    key = "have",
    label = L["Have"],
    width = 54,
    text = function(r)
      return r.have >= r.need and W.Color("good", W.Count(r.held)) or W.Count(r.held)
    end,
  },
  {
    key = "missing",
    label = L["To buy"],
    width = 60,
    text = function(r)
      return r.missing > 0 and W.Count(r.missing) or W.Color("good", L["done"])
    end,
  },
  {
    key = "market",
    label = L["Market"],
    width = 90,
    text = function(r)
      local m = rowMoney(r.market)
      if r.cheap then
        m = m .. " " .. W.Color("good", "*") -- at or under your top price
      end
      return m
    end,
  },
  {
    key = "max",
    label = L["Top price"],
    width = 86,
    drop = 2,
    text = function(r)
      return rowMoney(r.max)
    end,
  },
  {
    key = "cost",
    label = L["Cost"],
    width = 96,
    text = function(r)
      return r.missing > 0 and rowMoney(r.cost) or ""
    end,
  },
}

function UI:CreateShoppingPanel(v)
  local p = CreateFrame("Frame", nil, v.main)
  p:SetAllPoints()
  p:Hide()
  v.shop = p
  p.title = W.Text(p, "GameFontNormal")
  p.title:SetPoint("TOPLEFT", 0, -3)
  p.title:SetWordWrap(false)
  p.search = W.Button(p, L["Search the AH"], 110, 20, function()
    UI:SearchShoppingList()
  end)
  p.search:SetPoint("TOPRIGHT", 0, 0)
  W.Tooltip(p.search, function(tip)
    W.TipText(tip, L["Search the AH"], L["Searches the open auction house for everything the list still needs."])
  end)
  p.reagents = W.Button(p, L["Add reagents"], 100, 20, function()
    UI:AddRecipeReagents()
  end)
  p.reagents:SetPoint("RIGHT", p.search, "LEFT", -6, 0)
  W.Tooltip(p.reagents, function(tip)
    W.TipText(
      tip,
      L["Add reagents"],
      L["With your profession window open, adds the reagents of the selected recipe - as many times as you'll craft it."]
    )
  end)
  p.title:SetPoint("RIGHT", p.reagents, "LEFT", -10, 0)
  p.table = ns.DataTable.New(p, {
    columns = COLS,
    rows = 14,
    fill = true,
    top = -28,
    itemID = function(r)
      return r.itemID
    end,
    sort = { key = "missing", ascending = false },
    itemMenu = {
      extra = function(key)
        return UI:ShoppingItemEntries(key)
      end,
    },
    tooltip = function(tip, r)
      local any = false
      for char, qty in pairs(r.chars or {}) do
        if not any then
          tip:AddLine(" ")
          tip:AddLine(L["Held by"])
          any = true
        end
        W.TipPair(tip, (char:gsub("^[^:]*:", "")), qty)
      end
    end,
  })
end

-- show / hide the screener's own controls while a shopping list is shown
-- (each control comes back as it was: the compact layout hides some of them)
local function screenerControls(v, on)
  if v.shopMode == not on then
    return
  end
  v.shopMode = not on
  local controls =
    { v.search, v.quality, v.minBox, v.maxBox, v.views, v.columns, v.signals, v.filtersLabel, v.chips, v.table.frame }
  for _, f in ipairs(controls) do
    if on then
      f:SetShown(f.shownBeforeShop ~= false)
    else
      f.shownBeforeShop = f:IsShown()
      f:Hide()
    end
  end
end

function UI:RenderShopping()
  local v = self.marketView
  local sel = self:ShoppingSelected()
  local p = v.shop
  if not sel then
    p:Hide()
    screenerControls(v, true)
    return false
  end
  screenerControls(v, false)
  p:Show()
  local index = ns.AME:FactionIndex()
  local rows, totals = ns.Shopping.Progress(sel.list.items, ns.Trading:Holdings(), index and index.items or {})
  self.shopRows, self.shopTotals = rows, totals
  p.title:SetText(sel.list.name .. (sel.guild and W.Dim("  (" .. tostring(sel.list.owner) .. ")") or ""))
  p.reagents:SetShown(sel.own ~= nil)
  p.table:SetData(rows)
  p.table:Render()
  local status
  if totals.items == 0 then
    p.table:SetMessage(
      sel.own
          and L["Empty. Add items from any item's right-click menu, or open your profession window, pick a recipe and click Add reagents."]
        or L["This list is empty."]
    )
    status = ""
  elseif totals.done then
    p.table:SetMessage(nil)
    status = W.Color("good", L["Everything on this list is covered."])
      .. (sel.own and (W.SEP .. L["Right-click it in the sidebar to delete it."]) or "")
  else
    p.table:SetMessage(nil)
    status =
      L["%d of %d items still to buy: %s at market price"]:format(totals.missing, totals.items, W.Money(totals.cost))
    if totals.unpriced > 0 then
      status = status .. W.SEP .. L["%d without a price yet"]:format(totals.unpriced)
    end
    status = status .. W.SEP .. L["counts what your characters hold in bags and bank"]
  end
  v.status:SetText(status)
  return true
end

---------------------------------------------------------------------------------------------------------------------
-- actions

-- search the open auction house for what's still needed (Auctionator's shopping search when it's there)
function UI:SearchShoppingList()
  if not ns.AME.ahOpen then
    print("|cff33ccffAME|r " .. L["open the auction house first"])
    return
  end
  local keys = {}
  for _, r in ipairs(self.shopRows or {}) do
    if r.missing > 0 and ns.ItemCache.Name(ns.BaseID(r.itemID)) then -- loaded: something to search for
      keys[#keys + 1] = r.itemID
    end
  end
  if #keys == 0 or ns.AME:AuctionatorSearch(keys) then
    return
  end
  -- without Auctionator: AME's own tab on the auction house window searches them one after another
  local tab, sel = ns.AHShopping, self:ShoppingSelected()
  if tab and tab.tab and sel and sel.own then
    tab.temp, tab.list, tab.selected = nil, sel.own, nil
    tab:Open()
    tab:SearchAll()
    return
  end
  ns.AME:SearchAuctionHouse(keys[1])
end

-- The profession window's selected recipe, through the classic trade skill / craft API (whichever window is open).
local function recipeApi()
  if CraftFrame and CraftFrame:IsShown() and GetCraftSelectionIndex then
    return {
      selected = GetCraftSelectionIndex,
      numReagents = GetCraftNumReagents,
      reagentLink = GetCraftReagentItemLink,
      reagentCount = function(i, r)
        return select(3, GetCraftReagentInfo(i, r))
      end,
      name = function(i)
        return (GetCraftInfo(i))
      end,
    }
  end
  if GetTradeSkillSelectionIndex and GetTradeSkillNumReagents then
    return {
      selected = GetTradeSkillSelectionIndex,
      numReagents = GetTradeSkillNumReagents,
      reagentLink = GetTradeSkillReagentItemLink,
      reagentCount = function(i, r)
        return select(3, GetTradeSkillReagentInfo(i, r))
      end,
      name = function(i)
        return (GetTradeSkillInfo(i))
      end,
    }
  end
  return nil
end

function UI:AddRecipeReagents(listIndex)
  local sel = self:ShoppingSelected()
  listIndex = listIndex or (sel and sel.own)
  local ok, recipe = pcall(ns.Shopping.Recipe, recipeApi())
  -- the modern profession window (WoW Forever, retail): the recipe picked in it
  local picked = ns.ProfessionBar and ns.ProfessionBar:SelectedRecipe()
  if (not (ok and recipe)) and picked and #picked.reagents > 0 then
    ok, recipe = true, { name = ns.ItemCache.Name(picked.product), reagents = picked.reagents }
  end
  if not (ok and recipe) then
    print("|cff33ccffAME|r " .. L["open your profession window and select a recipe first"])
    return
  end
  W.Prompt("AME_SHOP_CRAFT", L["How many %s will you craft?"]:format(recipe.name or "?"), function(text)
    local times = math.floor(tonumber(text) or 1)
    if times < 1 then
      return
    end
    local i = listIndex
    if not i then -- no list yet: one named after the recipe
      i = shopping():AddList(recipe.name or L["Shopping list"]) or #shopping():Lists()
    end
    for _, r in ipairs(recipe.reagents) do
      shopping():AddItem(i, r[1], r[2] * times)
    end
    UI:ShoppingChanged(i)
  end)
end

-- after a change: redraw the sidebar and the list, share it if it's shared
function UI:ShoppingChanged(selectIndex)
  local q = self.mq
  if selectIndex and q then
    q.list = "s:" .. selectIndex
  end
  local any = false
  for _, l in ipairs(shopping():Lists()) do
    any = any or l.shared
  end
  if any and ns.SyncService.QueueShare then
    ns.SyncService:QueueShare()
  end
  if self.marketView then
    self:RenderCategories()
    self:RefreshMarket(true)
  end
end

function UI:PromptNewShoppingList(key)
  W.Prompt("AME_NEW_SHOP", L["Name for the new shopping list (what it's for):"], function(name, data)
    local i, why = shopping():AddList(name)
    if not i then
      if why then
        print("|cff33ccffAME|r " .. why)
      end
      return
    end
    if data then
      UI:PromptQuantity(i, data)
    end
    UI:ShoppingChanged(i)
  end, key)
end

function UI:PromptQuantity(i, key)
  local l = shopping():Lists()[i]
  local cur = l and l.items[key]
  W.Prompt("AME_SHOP_QTY", L["How many do you need?"], function(text)
    shopping():SetItem(i, key, tonumber(text) or 0)
    UI:ShoppingChanged()
  end)
  if cur and StaticPopup_FindVisible then
    local dialog = StaticPopup_FindVisible("AME_SHOP_QTY")
    local box = dialog and (dialog.editBox or dialog.EditBox)
    if box then
      box:SetText(tostring(cur.need))
      box:HighlightText()
    end
  end
end

function UI:PromptTopPrice(i, key)
  W.Prompt("AME_SHOP_MAX", L["The most you'd pay for one, in gold (empty: no limit):"], function(text)
    local g = tonumber(text)
    local l = shopping():Lists()[i]
    local cur = l and l.items[key]
    if cur then
      shopping():SetItem(i, key, cur.need, g and g > 0 and g * 10000 or false)
    end
    UI:ShoppingChanged()
  end)
end

-- the item menu's extra entries on a shopping list's rows
function UI:ShoppingItemEntries(key)
  local sel = self:ShoppingSelected()
  if not (sel and sel.own) then
    return {}
  end
  local i = sel.own
  return {
    {
      text = L["Set quantity..."],
      func = function()
        UI:PromptQuantity(i, key)
      end,
    },
    {
      text = L["Set top price..."],
      func = function()
        UI:PromptTopPrice(i, key)
      end,
    },
    {
      text = L["Remove from list"],
      func = function()
        shopping():SetItem(i, key, 0)
        UI:ShoppingChanged()
      end,
    },
  }
end

-- "Add to shopping list...": your lists, then a new one
function UI:ShoppingAddMenu(anchor, key)
  local entries = {}
  for i, l in ipairs(shopping():Lists()) do
    entries[#entries + 1] = {
      text = l.name,
      checked = l.items[key] ~= nil,
      func = function()
        UI:PromptQuantity(i, key)
      end,
    }
  end
  entries[#entries + 1] = {
    text = W.Dim(L["New shopping list..."]),
    func = function()
      UI:PromptNewShoppingList(key)
    end,
  }
  W.Menu(anchor, entries, { cursor = true })
end

-- right-click one of your shopping lists in the sidebar
function UI:ShoppingListMenu(anchor, i)
  local l = shopping():Lists()[i]
  if not l then
    return
  end
  W.Menu(anchor, {
    {
      text = L["Add reagents"],
      func = function()
        UI:AddRecipeReagents(i)
      end,
    },
    {
      text = L["Rename..."],
      func = function()
        W.Prompt("AME_SHOP_RENAME", L["New name:"], function(name)
          local old = l.name
          if shopping():RenameList(i, name) and l.shared then
            ns.SyncService:QueueShare(nil, { old })
          end
          UI:ShoppingChanged()
        end)
      end,
    },
    {
      text = l.shared and L["Stop sharing with my guild"] or L["Share with my guild"],
      func = function()
        shopping():SetShared(i, not l.shared)
        ns.SyncService:QueueShare(nil, not l.shared and { l.name } or nil)
        UI:ShoppingChanged()
      end,
    },
    {
      text = W.Color("bad", L["Delete"]),
      func = function()
        local wasShared = l.shared and l.name
        shopping():RemoveList(i)
        if wasShared then
          ns.SyncService:QueueShare(nil, { wasShared })
        end
        UI.mq.list = nil
        UI:ShoppingChanged()
      end,
    },
  })
end
