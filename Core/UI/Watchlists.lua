-- Watchlists: the star / Watch menus, new / delete list popups, alerts on the item page.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

---------------------------------------------------------------------------------------------------------------------
-- Watchlists

-- menu of lists with checkmarks for an item, plus "New list..."
function UI:WatchMenu(anchor, itemID)
  if not itemID then
    return
  end
  local watch = ns.AME.watch
  local entries = {}
  for i, l in ipairs(watch:Lists()) do
    entries[#entries + 1] = {
      text = l.name,
      checked = watch:Has(i, itemID),
      func = function()
        watch:Toggle(i, itemID)
        UI:WatchChanged()
      end,
    }
  end
  entries[#entries + 1] = {
    text = W.Dim(L["New list..."]),
    func = function()
      UI:PromptNewList(itemID)
    end,
  }
  W.Menu(anchor, entries)
end

-- star click: with one list toggle directly, otherwise choose from the menu
function UI:StarClicked(anchor, itemID)
  local watch = ns.AME.watch
  if #watch:Lists() == 1 then
    watch:Toggle(1, itemID)
    self:WatchChanged()
  else
    self:WatchMenu(anchor, itemID)
  end
end

---------------------------------------------------------------------------------------------------------------------
-- the item menu: right-click an item row in any table. opts.hide: offer Hide / Unhide (Market, Arbitrage and
-- Portfolio positions)

function UI:ItemMenu(anchor, key, opts)
  opts = opts or {}
  local watch = ns.AME.watch
  -- grouped as the design has them: the item (a link), looking at it, keeping track of it, sharing or hiding it
  local entries = {
    { item = key },
    {
      text = L["Open chart"],
      func = function()
        UI:ShowItem(key)
      end,
    },
  }
  if ns.AME.ahOpen then
    entries[#entries + 1] = {
      text = L["Search the AH"],
      func = function()
        ns.AME:SearchAuctionHouse(key)
      end,
    }
  end
  entries[#entries + 1] = { separator = true }
  if #watch:Lists() == 1 then
    local on = watch:Has(1, key)
    entries[#entries + 1] = {
      text = on and L["Remove from watchlist"] or L["Add to watchlist"],
      func = function()
        watch:Toggle(1, key)
        UI:WatchChanged()
      end,
    }
  else
    entries[#entries + 1] = {
      text = L["Watchlists..."],
      submenu = true,
      func = function()
        UI:WatchMenu(anchor, key)
      end,
    }
  end
  entries[#entries + 1] = {
    text = L["Add to shopping list..."],
    submenu = true,
    func = function()
      UI:ShoppingAddMenu(anchor, key)
    end,
  }
  entries[#entries + 1] = {
    text = L["Who can make it"],
    func = function()
      UI:WhoCanMake(key)
    end,
  }
  entries[#entries + 1] = {
    text = L["Set an alert..."],
    func = function()
      UI:ShowItem(key)
      local v = UI.itemView
      if v and v.alertBelow and v.alertBelow.SetFocus then
        v.alertBelow:SetFocus()
      end
    end,
  }
  entries[#entries + 1] = { separator = true }
  entries[#entries + 1] = {
    text = L["Link in chat"],
    func = function()
      local link = ns.ItemCache.Link(key)
      if not link then
        return
      end
      if not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) and ChatFrame_OpenChat then
        ChatFrame_OpenChat(link)
      end
    end,
  }
  for _, e in ipairs(opts.extra and opts.extra(key) or {}) do
    entries[#entries + 1] = e
  end
  if opts.hide then
    local hidden = watch:IsHidden(key)
    entries[#entries + 1] = {
      text = hidden and L["Unhide"] or L["Hide from lists"],
      func = function()
        UI:SetHidden(key, not hidden)
      end,
    }
  end
  W.Menu(anchor, entries, { cursor = true })
end

-- hide or unhide an item: out of the Market, Arbitrage and Portfolio lists and their counts (it's still recorded)
function UI:SetHidden(key, on)
  local watch = ns.AME.watch
  watch:SetHidden(key, on)
  if self.index then
    self.categories = ns.MarketFilter.Categories(self.index, function(id)
      return ns.ItemCache.Get(id)
    end, watch:Hidden())
  end
  self:WatchChanged()
  if self.arbView and self.arbView:IsShown() and self.RefreshArbitrage then
    self:RefreshArbitrage()
  end
  if self.RefreshPortfolio then
    self:RefreshPortfolio()
  end
  if self.UpdateHiddenControls then
    self:UpdateHiddenControls()
  end
  if ns.AHSelling and ns.AHSelling.HiddenChanged then
    ns.AHSelling:HiddenChanged() -- the auction house's Selling tab lists your bags without hidden items
  end
end

-- the Market tab, on its Hidden list
function UI:ShowHidden()
  self:ShowTab("market")
  if ns.AME.watch:HiddenCount() > 0 then
    self:SelectCategory({ hidden = true })
  end
end

function UI:UnhideAll()
  ns.AME.watch:UnhideAll()
  self:SetHidden(nil, false)
end

function UI:PromptNewList(itemID)
  W.Prompt("AME_NEW_LIST", L["Name for the new watchlist:"], function(name, data)
    local i = ns.AME.watch:AddList(name)
    if i and data then
      ns.AME.watch:Toggle(i, data)
    end
    UI:WatchChanged()
  end, itemID)
end

-- right-click on one of your lists: share with the guild, delete
function UI:ListMenu(anchor, i)
  local watch = ns.AME.watch
  local l = watch:Lists()[i]
  if not l then
    return
  end
  W.Menu(anchor, {
    {
      text = L["Share with guild"],
      checked = l.shared == true,
      func = function()
        watch:SetShared(i, not l.shared)
        ns.SyncService:QueueShare(not l.shared and { l.name } or nil)
        UI:WatchChanged()
      end,
    },
    { separator = true }, -- deleting apart from the rest, as in the design
    {
      text = L["Delete list..."],
      disabled = #watch:Lists() <= 1,
      func = function()
        UI:PromptDeleteList(i)
      end,
    },
  })
end

function UI:PromptDeleteList(i)
  local l = ns.AME.watch:Lists()[i]
  if not l then
    return
  end
  W.Confirm("AME_DELETE_LIST", L['Delete the watchlist "%s"?'], DELETE or L["Delete"], function(data)
    local doomed = ns.AME.watch:Lists()[data]
    local wasShared = doomed and doomed.shared and doomed.name
    if ns.AME.watch:RemoveList(data) then
      if wasShared then
        ns.SyncService:QueueShare({ wasShared })
      end
      local q = UI.mq
      if q and q.list then
        q.list, q.only = nil, nil
      end
      UI:WatchChanged()
    end
  end, l.name, i)
end

-- after any watchlist change: re-filter a shown watchlist, redraw stars, sidebar and item controls
function UI:WatchChanged()
  local q = self.mq
  if q and q.list then
    local l
    if q.list == "hidden" then
      l = ns.AME.watch:HiddenCount() > 0 and { items = ns.AME.watch:Hidden() } or nil
    elseif type(q.list) == "string" then
      l = ns.AME.watch.db.guild[q.list:sub(3)]
    else
      l = ns.AME.watch:Lists()[q.list]
    end
    q.only = l and l.items or nil
    if not l then
      q.list = nil
    end
  end
  if #ns.AME.watch:SharedLists() > 0 and ns.SyncService.QueueShare then
    ns.SyncService:QueueShare()
  end
  if self.marketView then
    self:RenderCategories()
    self:RefreshMarket(true)
  end
  self:UpdateWatchControls()
end

function UI:UpdateWatchControls(keepInputs)
  local v, id = self.itemView, self.itemID
  if not (v and id and ns.AME.watch) then
    return
  end
  local watch = ns.AME.watch
  local inList = false
  for i in ipairs(watch:Lists()) do
    inList = inList or watch:Has(i, id)
  end
  local listName
  for i, l in ipairs(watch:Lists()) do
    if not listName and watch:Has(i, id) then
      listName = l.name
    end
  end
  v.watch.label:SetText(inList and (L["Watching"] .. (listName and "  ·  " .. listName or "")) or L["Watch"])
  v.watch:SetSelected(inList)
  W.SetStar(v.watch.star, inList)
  local a = watch:Alert(id) or {}
  if not keepInputs then
    v.alertBelow:SetCopper(a.below)
    v.alertAbove:SetCopper(a.above)
  end
  v.alertSignal:SetChecked(a.signal)
  self:UpdateHiddenControls()
end

function UI:UpdateHiddenControls()
  local v, id = self.itemView, self.itemID
  if not (v and v.hide and id) then
    return
  end
  local hidden = ns.AME.watch:IsHidden(id)
  v.hide.label:SetText(hidden and (L["Hidden from lists"] .. "  ·  " .. L["Unhide"]) or L["Hide from lists"])
  v.hide:SetSelected(hidden)
end
