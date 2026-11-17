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

function UI:PromptNewList(itemID)
  StaticPopupDialogs.AME_NEW_LIST = StaticPopupDialogs.AME_NEW_LIST
    or {
      text = L["Name for the new watchlist:"],
      button1 = ACCEPT or "Accept",
      button2 = CANCEL or "Cancel",
      hasEditBox = true,
      OnAccept = function(popup, data)
        local box = popup.editBox or popup.EditBox
        local i = ns.AME.watch:AddList(box and box:GetText())
        if i and data then
          ns.AME.watch:Toggle(i, data)
        end
        UI:WatchChanged()
      end,
      EditBoxOnEnterPressed = function(box)
        local popup = box:GetParent()
        StaticPopupDialogs.AME_NEW_LIST.OnAccept(popup, popup.data)
        popup:Hide()
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  StaticPopup_Show("AME_NEW_LIST", nil, nil, itemID)
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
  StaticPopupDialogs.AME_DELETE_LIST = StaticPopupDialogs.AME_DELETE_LIST
    or {
      text = L['Delete the watchlist "%s"?'],
      button1 = DELETE or "Delete",
      button2 = CANCEL or "Cancel",
      OnAccept = function(_, data)
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
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  StaticPopup_Show("AME_DELETE_LIST", l.name, nil, i)
end

-- after any watchlist change: re-filter a shown watchlist, redraw stars, sidebar and item controls
function UI:WatchChanged()
  local q = self.mq
  if q and q.list then
    local l
    if type(q.list) == "string" then
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
  v.watch.label:SetText(inList and L["Watching"] or L["Watch"])
  v.watch:SetSelected(inList)
  W.SetStar(v.watch.star, inList)
  local a = watch:Alert(id) or {}
  if not keepInputs then
    v.alertBelow:SetText(a.below and tostring(math.floor(a.below / 10000)) or "")
    v.alertAbove:SetText(a.above and tostring(math.floor(a.above / 10000)) or "")
  end
  v.alertSignal:SetChecked(a.signal)
end
