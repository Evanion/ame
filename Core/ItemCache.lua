-- Item facts for every module: class/subclass come from GetItemInfoInstant (always available); name, link and
-- quality from GetItemInfo once the client has the item cached. Warm() asks the client to load names for many items
-- in small batches so name search and quality filters cover the whole market.
local _, ns = ...
local L = ns.L

local C = { info = {}, listeners = {} }
ns.ItemCache = C

local function api(name)
  return (C_Item and C_Item[name]) or _G[name]
end

function C.Get(itemID)
  local e = C.info[itemID]
  if not e then
    e = {}
    local instant = api("GetItemInfoInstant")
    if instant then
      local _, _, _, _, _, classID, subClassID = instant(itemID)
      e.classID, e.subClassID = classID, subClassID
    end
    C.info[itemID] = e
  end
  if not e.name then
    local getInfo = api("GetItemInfo")
    local name, quality
    if getInfo then
      local n, _, q, _, _, _, _, _, _, _, sell = getInfo(itemID)
      name, quality = n, q
      e.sellPrice = sell
    end
    if name then
      e.name, e.quality = name, quality
    end
  end
  return e
end

-- name / link straight from the client: nil until it has the item cached (one lookup for every module)
function C.Name(itemID)
  local f = api("GetItemInfo")
  return f and itemID and (f(itemID)) or nil
end

function C.Link(itemID)
  local f = api("GetItemInfo")
  if f and itemID then
    local _, link = f(itemID)
    return link
  end
  return nil
end

function C.ClassName(classID)
  local f = api("GetItemClassInfo")
  return f and f(classID) or L["Class %d"]:format(classID)
end

function C.SubClassName(classID, subClassID)
  local f = api("GetItemSubClassInfo")
  return f and f(classID, subClassID) or L["Type %d"]:format(subClassID)
end

-- fn() runs (debounced) after names arrive
function C.OnNamesChanged(fn)
  C.listeners[#C.listeners + 1] = fn
end

local pendingNotify = false
local function notify()
  if pendingNotify then
    return
  end
  pendingNotify = true
  C_Timer.After(0.5, function()
    pendingNotify = false
    for _, fn in ipairs(C.listeners) do
      fn()
    end
  end)
end

-- GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT
function C.OnItemData(itemID)
  local e = itemID and C.info[itemID]
  if e and not e.name then
    C.Get(itemID)
    if e.name then
      notify()
    end
  end
end

-- request names for ids (array) in batches; C.warmDone / C.warmTotal track progress
function C.Warm(ids)
  local request = api("RequestLoadItemDataByID")
  local i = 0
  C.warmTotal, C.warmDone = #ids, 0
  local gen = (C.warmGen or 0) + 1
  C.warmGen = gen
  local function step()
    if gen ~= C.warmGen then
      return
    end
    local n = 0
    while i < #ids and n < 150 do
      i = i + 1
      local e = C.Get(ids[i])
      if not e.name and request then
        request(ids[i])
      end
      n = n + 1
    end
    C.warmDone = i
    if i < #ids then
      C_Timer.After(0.1, step)
    else
      notify()
    end
  end
  step()
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do
  pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, _, itemID)
  C.OnItemData(itemID)
end)
