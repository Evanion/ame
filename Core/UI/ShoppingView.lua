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
    money = true, -- exported as gold
    text = function(r)
      local m = W.Money(r.market, true)
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
    format = "money",
  },
  {
    key = "cost",
    label = L["Cost"],
    width = 96,
    money = true,
    text = function(r) -- nothing left to buy: nothing to pay
      return r.missing > 0 and W.Money(r.cost, true) or W.NONE
    end,
  },
}

UI.SHOPPING_COLUMNS = COLS -- the auction house's Shopping tab shows lists with these too

function UI:CreateShoppingPanel(v)
  local p = CreateFrame("Frame", nil, v.main)
  p:SetAllPoints()
  p:Hide()
  v.shop = p
  -- the list's name, and a dim reminder of where its own menu is
  p.heading = W.PageHeading(p)
  p.heading:SetPoint("TOPLEFT", 0, -2)
  p.title = p.heading.title
  p.search = W.Button(p, L["Search the AH"], 110, 20, function()
    UI:SearchShoppingList()
  end)
  p.search:SetPoint("TOPRIGHT", 0, 0)
  W.Primary(p.search)
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
  p.heading:SetPoint("RIGHT", p.reagents, "LEFT", -10, 0)
  p.table = ns.DataTable.New(p, {
    columns = COLS,
    rows = 14,
    fill = true,
    top = -28,
    itemID = function(r)
      return r.itemID
    end,
    sort = { key = "missing", ascending = false },
    note = L["Hover a row for which characters and guild banks hold it. Right-click an item to change the quantity, set a top price or remove it."],
    itemMenu = {
      extra = function(key)
        return UI:ShoppingItemEntries(key)
      end,
    },
    -- which characters hold it, as a section of the item's tooltip
    tooltip = function(tip, r)
      local chars = {}
      for char in pairs(r.chars or {}) do
        chars[#chars + 1] = char
      end
      local guilds = {}
      for g in pairs(r.guilds or {}) do
        guilds[#guilds + 1] = g
      end
      if #chars + #guilds == 0 then
        return
      end
      table.sort(chars)
      table.sort(guilds)
      local rows = {}
      for i, char in ipairs(chars) do
        rows[i] = { label = (char:gsub("^[^:]*:", "")), cells = { W.Thousands(r.chars[char]) } }
      end
      for _, g in ipairs(guilds) do
        rows[#rows + 1] = { label = "<" .. g:gsub("^[^:]*:", "") .. ">", cells = { W.Thousands(r.guilds[g]) } }
      end
      tip:AddLine(" ")
      ns.Tooltip.AddRows(tip, { { section = { heading = L["Held by"], rows = rows } } })
    end,
  })
end

-- The screener's own controls (search, filters, the table) give way to a shopping list: every one of them, the
-- narrow window's short signal filter and More included. The category dropdown stays, since it picks the list.
-- Back to the screener, each comes back as the window's width has it.
local SCREENER_CONTROLS = {
  "search",
  "quality",
  "minBox",
  "maxBox",
  "views",
  "columns",
  "signals",
  "signalsShort",
  "more",
  "filtersLabel",
  "chips",
}
function UI:ScreenerControls(on)
  local v = self.marketView
  if on then
    if v.shopMode then
      v.shopMode = false
      for _, key in ipairs({ "search", "quality", "chips" }) do -- the rest follow the width (SetCompact)
        v[key]:Show()
      end
      v.table.frame:Show()
      v:SetCompact(v.slots.compact)
    end
    return
  end
  v.shopMode = true
  for _, key in ipairs(SCREENER_CONTROLS) do
    v[key]:Hide()
  end
  v.table.frame:Hide()
end

function UI:RenderShopping()
  local v = self.marketView
  local sel = self:ShoppingSelected()
  local p = v.shop
  if not sel then
    p:Hide()
    self:ScreenerControls(true)
    return false
  end
  self:ScreenerControls(false)
  p:Show()
  local index = ns.AME:FactionIndex()
  local rows, totals = ns.Shopping.Progress(sel.list.items, ns.Holdings.Of("usable"), index and index.items or {})
  self.shopRows, self.shopTotals = rows, totals
  p.heading:Set(
    sel.list.name .. (sel.guild and W.Dim("  (" .. tostring(sel.list.owner) .. ")") or ""),
    sel.own and L["right-click the list in the sidebar to rename, share or delete it"]
      or L["right-click the list in the sidebar to copy it"]
  )
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
    status = status .. W.SEP .. L["counts bags, bank, mailbox and guild banks"]
  end
  v.status:SetText(status)
  return true
end

---------------------------------------------------------------------------------------------------------------------
-- actions

-- search the open auction house for what's still needed (Auctionator's shopping search when it's there)
function UI:SearchShoppingList()
  if not ns.AME.ahOpen then
    ns.AME.Say(L["open the auction house first"])
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
  if tab and tab.tab and sel then -- a guild list: its items as a list of their own, every one searched
    tab:ShowKeys(keys, sel.list and sel.list.name, sel.list and sel.list.items)
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
      product = function(i) -- what it makes (an enchant makes no item)
        return GetCraftItemLink and ns.ItemIDFrom(GetCraftItemLink(i) or "")
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
      product = function(i)
        return GetTradeSkillItemLink and ns.ItemIDFrom(GetTradeSkillItemLink(i) or "")
      end,
    }
  end
  return nil
end

function UI:AddRecipeReagents(listIndex)
  local sel = self:ShoppingSelected()
  listIndex = listIndex or (sel and sel.own)
  local api = recipeApi()
  local ok, recipe = pcall(ns.Shopping.Recipe, api)
  local product
  if ok and recipe and api.product then
    local got, key = pcall(api.product, api.selected())
    product = got and key or nil
  end
  -- the modern profession window (WoW Forever, retail): the recipe picked in it
  local picked = ns.ProfessionBar and ns.ProfessionBar:SelectedRecipe()
  if (not (ok and recipe)) and picked and #picked.reagents > 0 then
    ok, recipe = true, { name = ns.ItemCache.Name(picked.product), reagents = picked.reagents }
    product = picked.product
  end
  if not (ok and recipe) then
    ns.AME.Say(L["open your profession window and select a recipe first"])
    return
  end
  local what = product and W.LinkText(product) or recipe.name or "?"
  W.Prompt("AME_SHOP_CRAFT", L["How many %s will you craft?"]:format(what), function(text)
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
  UI.PromptLinks("AME_SHOP_CRAFT")
end

-- The game's popup shows the item's name as a link: its tooltip on hover, Shift-click links it. The popup frames are
-- the game's own, shared by every popup, so the hover and clicks only act while one of AME's is shown.
function UI.PromptLinks(id)
  local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(id)
  if not dialog or dialog.ameLinks then
    return
  end
  dialog.ameLinks = true
  if dialog.SetHyperlinksEnabled then
    dialog:SetHyperlinksEnabled(true)
  end
  local function ours(self)
    return type(self.which) == "string" and self.which:find("^AME_") ~= nil
  end
  dialog:HookScript("OnHyperlinkEnter", function(self, link)
    local key = ours(self) and W.LinkKey(link)
    if key then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      W.SetItemTip(GameTooltip, key)
      GameTooltip:Show()
    end
  end)
  dialog:HookScript("OnHyperlinkLeave", function(self)
    if ours(self) then
      GameTooltip:Hide()
    end
  end)
  dialog:HookScript("OnHyperlinkClick", function(self, link)
    local key = ours(self) and W.LinkKey(link)
    if key then
      W.ItemLinkClicked(key)
    end
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
        ns.AME.Say("%s", why)
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
    { text = W.Color("gold", l.name), disabled = true }, -- which list, as the design heads it
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
    { separator = true },
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
