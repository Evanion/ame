-- Item facts for every module, by item key (see ns.ItemKey): class/subclass come from GetItemInfoInstant (always
-- available); name, link and quality from GetItemInfo once the client has the item cached. Warm() asks the client to
-- load names for many items in small batches so name search and quality filters cover the whole market.
--
-- Random-suffix variants: class, quality, icon and vendor price are the base item's. The client's GetItemInfo gives
-- the base name, so a variant's full name ("Raider Shortsword of Magic") is learned from the links it arrives with
-- (scans, tooltips, bags, chat) and kept in AME_DB.variants, so it survives a reload.
local _, ns = ...
local L = ns.L

local C = { info = {}, listeners = {}, variants = {}, byName = {}, keysOf = {} }
ns.ItemCache = C

local function api(name)
  return (C_Item and C_Item[name]) or _G[name]
end

-- saved variant names: { [key] = "name" } (call at ADDON_LOADED)
function C.Init(saved)
  C.variants = saved or {}
  C.byName = {}
  for key, name in pairs(C.variants) do
    C.byName[name] = key
  end
end

-- remember a variant's name from its link; returns the key. Plain items need nothing (the client knows their name).
function C.Learn(link)
  local key = ns.ItemIDFrom(link)
  if key and ns.IsVariant(key) and not C.variants[key] then
    local name = type(link) == "string" and link:match("|h%[(.-)%]|h")
    if name and name ~= "" then
      C.variants[key], C.byName[name] = name, key
      local e = C.info[key]
      if e then
        e.name = name
      end
    end
  end
  return key
end

-- item key for a full item name (an invoice or chat line): a variant whose name was learned, else the client's item
-- ID for that name (plain items it has cached)
function C.KeyByName(name)
  if not name then
    return nil
  end
  local key = C.byName[name]
  if key then
    return key
  end
  local instant = api("GetItemInfoInstant")
  return instant and (instant(name)) or nil
end

-- item key for an item ID that came with its full name but no link (the old sell slot): the variant of that name
-- when it was learned, else the item ID
function C.KeyFor(itemID, name)
  local key = name and C.byName[name]
  if key and ns.BaseID(key) == itemID then
    return key
  end
  return itemID
end

-- item key of the item at an item location (bags, sell frames): from its link, so a variant keeps its suffix
function C.KeyAt(location)
  local ok, key = pcall(function()
    local link = C_Item.GetItemLink and C_Item.GetItemLink(location)
    return link and C.Learn(link) or C_Item.GetItemID(location)
  end)
  return ok and key or nil
end

function C.Get(key)
  local e = C.info[key]
  if not e then
    e = {}
    local instant = api("GetItemInfoInstant")
    if instant then
      local _, _, _, _, _, classID, subClassID = instant(ns.BaseID(key))
      e.classID, e.subClassID = classID, subClassID
    end
    C.info[key] = e
    if ns.IsVariant(key) then -- item data events name the base item
      local base = ns.BaseID(key)
      local list = C.keysOf[base] or {}
      C.keysOf[base] = list
      list[#list + 1] = key
    end
  end
  if not e.name then
    local getInfo = api("GetItemInfo")
    local name, quality
    if getInfo then
      local n, _, q, _, _, _, _, _, _, _, sell = getInfo(ns.BaseID(key))
      name, quality = n, q
      e.sellPrice = sell
    end
    if name and ns.IsVariant(key) then
      -- the base name until the variant's own is learned (C.Learn replaces it)
      name = C.variants[key] or name
    end
    if name then
      e.name, e.quality = name, quality
    end
  end
  return e
end

-- name / link straight from the client: nil until it has the item cached (one lookup for every module)
function C.Name(key)
  if not key then
    return nil
  end
  if ns.IsVariant(key) then
    return C.Get(key).name
  end
  local f = api("GetItemInfo")
  return f and (f(key)) or nil
end

-- the base item's link, with the variant's item string and name for a variant
function C.Link(key)
  local f = api("GetItemInfo")
  if not (f and key) then
    return nil
  end
  local _, link = f(ns.BaseID(key))
  if link and ns.IsVariant(key) then
    local name = C.Get(key).name or ""
    link = link:gsub("|H.-|h%[.-%]|h", "|H" .. ns.ItemString(key) .. "|h[" .. name:gsub("%%", "%%%%") .. "]|h", 1)
  end
  return link
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

-- GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT: the payload is a base item ID; its variants fill in too
function C.OnItemData(itemID)
  if not itemID then
    return
  end
  local got = false
  local function fill(key)
    local e = C.info[key]
    if e and not e.name then
      C.Get(key)
      got = got or e.name ~= nil
    end
  end
  fill(itemID)
  for _, key in ipairs(C.keysOf[itemID] or {}) do
    fill(key)
  end
  if got then
    notify()
  end
end

-- request names for keys (array) in batches; C.warmDone / C.warmTotal track progress
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
        request(ns.BaseID(ids[i]))
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
