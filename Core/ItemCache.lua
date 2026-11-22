-- Item facts for every module, by item key (see ns.ItemKey): class/subclass come from GetItemInfoInstant (always
-- available); name, link and quality from GetItemInfo once the client has the item cached. Warm() asks the client to
-- load names for many items in small batches so name search and quality filters cover the whole market.
--
-- Random-suffix variants (keyed by the auction house's item key suffix, see ns.ItemKey): class, quality, icon and
-- vendor price are the base item's. The client's GetItemInfo gives the base name, so a variant's full name ("Raider
-- Shortsword of Magic") and link come from C_TooltipInfo.GetItemKey (the item key's tooltip carries its hyperlink) or
-- from links that arrive together with an item key (bags, the sell slot, searches, your auctions). Each such pair also
-- teaches ns.suffixMap how links name that suffix, so any link (tooltips, chat) finds its variant. Names and the map
-- are saved (AME_DB.variants, AME_DB.suffixMap).
local _, ns = ...
local L = ns.L

local C = { info = {}, listeners = {}, variants = {}, byName = {}, keysOf = {}, tried = {} }
ns.ItemCache = C

local function api(name)
  return (C_Item and C_Item[name]) or _G[name]
end

-- saved variant names { [key] = "name" }, suffix map (see ns.suffixMap) and variant item strings
-- { [key] = "item:..." }; call at ADDON_LOADED
function C.Init(saved, map, strings)
  C.variants = saved or {}
  C.byName = {}
  for key, name in pairs(C.variants) do
    C.byName[name] = key
  end
  ns.suffixMap = map or ns.suffixMap or {}
  ns.itemStrings = strings or ns.itemStrings or {}
  C.tried = {}
end

-- Variant names and item strings saved packed (Core/Packed.lua): unpacked in the background after login, keeping
-- what was learned meanwhile. Until then a variant shows its base name; looking a key up by name waits for them.
function C.UnpackLater(names, strings)
  ns.Packed.Later("variants", names, C.variants, function(key, name)
    if C.byName[name] == nil then
      C.byName[name] = key
    end
  end)
  ns.Packed.Later("variantStrings", strings, ns.itemStrings)
end

-- at logout: names, item strings, packed
function C.PackForSave()
  ns.Packed.Ready("variants")
  ns.Packed.Ready("variantStrings")
  return ns.Packed.Pack(C.variants), ns.Packed.Pack(ns.itemStrings)
end

-- a link that belongs to the auction item key (itemID, suffix): learn how links name that suffix, and the variant's
-- name and item string. Returns the item key.
function C.Pair(link, itemID, suffix)
  suffix = tonumber(suffix) or 0
  local key = ns.ItemKey(itemID, suffix)
  local id, field, bonuses, itemString = ns.ParseItemString(link)
  if not (id and id == itemID) then
    return key
  end
  if field == 0 and bonuses then
    ns.suffixMap[id .. ":" .. bonuses] = suffix
    if ns.suffixMap[bonuses] == nil then
      ns.suffixMap[bonuses] = suffix
    end
  end
  if suffix ~= 0 then
    ns.itemStrings = ns.itemStrings or {}
    ns.itemStrings[key] = itemString
    C.setName(key, link:match("|h%[(.-)%]|h"))
  end
  return key
end

function C.setName(key, name)
  if name and name ~= "" and C.variants[key] ~= name then
    C.variants[key], C.byName[name] = name, key
    local e = C.info[key]
    if e then
      e.name = name
    end
    return true
  end
  return false
end

-- a variant's link from the game: the tooltip of its auction item key carries it (C_TooltipInfo.GetItemKey)
function C.Resolve(key)
  local tip = C_TooltipInfo and C_TooltipInfo.GetItemKey
  if not (tip and ns.IsVariant(key)) or C.tried[key] then
    return nil
  end
  C.tried[key] = true -- once per session (it can return nothing until the item's data is loaded: see OnItemData)
  local itemID, suffix = ns.SplitKey(key)
  local getInfo = api("GetItemInfo")
  local level = getInfo and select(4, getInfo(itemID)) or 0
  local ok, data = pcall(tip, itemID, level or 0, suffix)
  data = ok and type(data) == "table" and data or nil
  local line = data and data.lines and data.lines[1]
  local link = line and line.hyperlink or data and data.hyperlink
  if type(link) == "string" and not (_G.issecretvalue and _G.issecretvalue(link)) then
    C.Pair(link, itemID, suffix)
    return link
  end
  -- no link (WoW Forever's item key tooltips carry none): the first line still names the variant
  -- (only a real one: the base name plus a suffix, not "Retrieving item information" while it loads)
  local name = line and line.leftText
  local baseName = getInfo and getInfo(itemID)
  if
    type(name) == "string"
    and not (_G.issecretvalue and _G.issecretvalue(name))
    and baseName
    and #name > #baseName
    and name:sub(1, #baseName) == baseName
  then
    C.setName(key, name)
  end
  return nil
end

-- A variant's tooltip costs the game a few ms: looking up thousands at once (the market list's quality filter,
-- warming names after a rebuild) made 300 ms frames. Each frame resolves up to RESOLVE_MS right away - one item
-- on screen still gets its name at once - and the rest wait in a queue worked off the same way in the next frames
-- (names arriving refresh the window, like item data does).
C.RESOLVE_MS = 4
local spentAt, spent = nil, 0
local queue, queued = {}, {}
local driver

local function clock()
  return debugprofilestop and debugprofilestop() or nil
end

local function budgetLeft()
  local now = GetTime and GetTime() or 0
  if now ~= spentAt then
    spentAt, spent = now, 0
  end
  return spent < C.RESOLVE_MS
end

local function timed(key)
  local t0 = clock()
  C.Resolve(key)
  local t1 = clock()
  spent = spent + ((t0 and t1) and (t1 - t0) or 0)
  return C.variants[key] ~= nil
end

local function drain()
  local got = false
  while #queue > 0 and budgetLeft() do
    local key = table.remove(queue, 1)
    queued[key] = nil
    got = timed(key) or got
  end
  if got then
    C.NamesArrived()
  end
  if #queue == 0 and driver then
    driver:SetScript("OnUpdate", nil)
  end
end

function C.ResolveSoon(key)
  if C.tried[key] or queued[key] then
    return
  end
  if budgetLeft() then
    timed(key)
    return
  end
  queued[key] = true
  queue[#queue + 1] = key
  if not driver and CreateFrame then
    driver = CreateFrame("Frame")
  end
  if driver then
    driver:SetScript("OnUpdate", drain)
  end
end

-- remember a variant's name from its link; returns the key. Plain items need nothing (the client knows their name).
function C.Learn(link)
  local key = ns.ItemIDFrom(link)
  if key and ns.IsVariant(key) and not C.variants[key] then
    C.setName(key, type(link) == "string" and link:match("|h%[(.-)%]|h"))
  end
  return key
end

-- item key for a full item name (an invoice or chat line): a variant whose name was learned, else the client's item
-- ID for that name (plain items it has cached)
function C.KeyByName(name)
  if not name then
    return nil
  end
  ns.Packed.Ready("variants")
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
  ns.Packed.Ready("variants")
  local key = name and C.byName[name]
  if key and ns.BaseID(key) == itemID then
    return key
  end
  return itemID
end

-- item key of the item at an item location (bags, sell frames): the auction house's item key for it (with the
-- suffix), which also pairs its link with that suffix; else from its link
function C.KeyAt(location)
  local ok, key = pcall(function()
    local link = C_Item.GetItemLink and C_Item.GetItemLink(location)
    local ah = C_AuctionHouse and C_AuctionHouse.GetItemKeyFromItem
    local itemKey = ah and ah(location)
    if itemKey and itemKey.itemID then
      if link then
        return C.Pair(link, itemKey.itemID, itemKey.itemSuffix)
      end
      return ns.ItemKey(itemKey.itemID, itemKey.itemSuffix)
    end
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
  -- read until the client has it: a variant's name can arrive first (setName), its facts with GetItemInfo
  if not e.name or e.quality == nil then
    local getInfo = api("GetItemInfo")
    local name, quality, level, icon, bind
    if getInfo then
      local n, _, q, lvl, _, _, _, _, _, tex, sell, _, _, b = getInfo(ns.BaseID(key))
      name, quality, level, icon, bind = n, q, lvl, tex, b
      e.sellPrice = sell
    end
    if name and ns.IsVariant(key) then
      if not C.variants[key] then
        C.ResolveSoon(key) -- ask the game for the variant's link and name
      end
      -- the base name until the variant's own is known
      name = C.variants[key] or name
    end
    if name then
      -- the client's facts, read once with the name: quality, item level, icon, bind type (1: binds when picked up)
      e.name, e.quality, e.level, e.icon, e.bind = name, quality, level, icon, bind
    end
  end
  return e
end

-- name, link, quality, icon of an item key straight from the client (nil until it has it cached); a variant has its
-- own name and link, the rest is its base item's
function C.Info(key)
  local itemID = ns.BaseID(key)
  local getInfo = api("GetItemInfo")
  if not getInfo then
    return nil
  end
  local name, link, quality, _, _, _, _, _, _, icon = getInfo(itemID)
  if not icon and C_Item and C_Item.GetItemIconByID then
    icon = C_Item.GetItemIconByID(itemID)
  end
  if name and ns.IsVariant(key) then
    name, link = C.Name(key) or name, C.Link(key) or link
  end
  return name, link, quality, icon
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

-- names learned in the background (queued variant tooltips): the window refreshes as for item data
function C.NamesArrived()
  notify()
end

-- GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT: the payload is a base item ID; its variants fill in too
function C.OnItemData(itemID)
  if not itemID then
    return
  end
  local got = false
  local function fill(key)
    local e = C.info[key]
    if e and ns.IsVariant(key) and not C.variants[key] then
      C.tried[key] = nil -- the base item's data is here: its variants' tooltips can resolve now
      e.name = nil
    end
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
