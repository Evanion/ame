-- Dev-only: /amedev recipes. Answers what the crafting feature needs to know about the client's profession APIs, and
-- saves it to AME_DB.dev.recipeProbe (read from the SavedVariables file after /reload). Run it once with a
-- profession window open, and once with it closed. Never ships (Core/Dev is stripped from packages).
--   - which profession / tooltip / item functions exist
--   - GetAllRecipeIDs: does it exist, how many recipes, how many learned (unlearned ones included?)
--   - per recipe: output item, yield min / max, recipe type (enchants), reagents - for learned and unlearned recipes
--   - recipe items in your bags: GetItemSpell, and every tooltip line (type and text)
local _, ns = ...

local Dev = ns.Dev

local function safe(v)
  local secret = _G.issecretvalue
  if secret and secret(v) then
    return "<secret>"
  end
  if type(v) == "table" or type(v) == "function" or type(v) == "userdata" then
    return "<" .. type(v) .. ">"
  end
  return v
end

local function has(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then
      return false
    end
    t = t[part]
  end
  return type(t) == "function"
end

local FUNCTIONS = {
  "C_TradeSkillUI.GetAllRecipeIDs",
  "C_TradeSkillUI.GetFilteredRecipeIDs",
  "C_TradeSkillUI.GetRecipeInfo",
  "C_TradeSkillUI.GetRecipeSchematic",
  "C_TradeSkillUI.GetRecipeOutputItemData",
  "C_TradeSkillUI.GetBaseProfessionInfo",
  "C_TradeSkillUI.GetChildProfessionInfo",
  "C_TradeSkillUI.GetProfessionInfoBySkillLineID",
  "C_TradeSkillUI.GetTradeSkillLine",
  "C_TradeSkillUI.IsTradeSkillReady",
  "C_TradeSkillUI.IsTradeSkillLinked",
  "C_TradeSkillUI.GetShowUnlearned",
  "C_TradeSkillUI.GetRecipeCooldown",
  "C_TradeSkillUI.OpenTradeSkill",
  "C_TradeSkillUI.CanTradeSkillShowCraftingUI",
  "C_TradeSkillUI.HasNoReagentCost",
  "C_TooltipInfo.GetItemByID",
  "C_TooltipInfo.GetBagItem",
  "C_TooltipInfo.GetRecipeResultItem",
  "C_Item.GetItemSpell",
  "C_Item.GetItemInfoInstant",
  "C_Container.GetContainerItemInfo",
  "C_Spell.GetSpellInfo",
  "GetTradeSkillInfo",
  "GetNumTradeSkills",
  "GetProfessions",
  "GetProfessionInfo",
}

-- one recipe: its info and schematic, as plain values
local frames, spellbookProfessions

local function recipe(id)
  local T = C_TradeSkillUI
  local out = { id = id }
  local ok, info = pcall(T.GetRecipeInfo, id)
  if ok and type(info) == "table" then
    out.name, out.learned, out.category = safe(info.name), safe(info.learned), safe(info.categoryID)
    out.difficulty, out.skillUps = safe(info.relativeDifficulty), safe(info.numSkillUps)
    out.sla = safe(info.skillLineAbilityID)
    if not info.learned then
      -- unlearned: every plain field the client returns (looking for a required skill), and its source text
      out.info = {}
      for k, val in pairs(info) do
        if type(val) ~= "table" and type(val) ~= "function" then
          out.info[k] = safe(val)
        end
      end
      if T.GetRecipeSourceText then
        local okSource, text = pcall(T.GetRecipeSourceText, id)
        out.source = okSource and safe(text) or nil
      end
    end
  else
    out.infoError = tostring(info)
  end
  if T.GetRecipeSchematic then
    local ok2, s = pcall(T.GetRecipeSchematic, id, false)
    if ok2 and type(s) == "table" then
      out.output, out.min, out.max = safe(s.outputItemID), safe(s.quantityMin), safe(s.quantityMax)
      out.type, out.schematicName = safe(s.recipeType), safe(s.name)
      out.reagents = {}
      for _, slot in ipairs(s.reagentSlotSchematics or {}) do
        local items = {}
        for _, r in ipairs(slot.reagents or {}) do
          items[#items + 1] = safe(r.itemID)
        end
        out.reagents[#out.reagents + 1] =
          { items = items, qty = safe(slot.quantityRequired), kind = safe(slot.reagentType) }
      end
    else
      out.schematicError = tostring(s)
    end
  end
  if T.GetRecipeOutputItemData then
    local ok3, o = pcall(T.GetRecipeOutputItemData, id)
    if ok3 and type(o) == "table" then
      out.outputData = { itemID = safe(o.itemID), link = safe(o.hyperlink) }
    end
  end
  return out
end

local function tooltipLines(data)
  local lines = {}
  for i, line in ipairs(data and data.lines or {}) do
    lines[i] = { type = safe(line.type), left = safe(line.leftText), right = safe(line.rightText) }
  end
  return lines
end

-- every recipe item (class 9) in the bags: what GetItemSpell says, and its whole tooltip
local function recipeItems()
  local out = { scanned = 0 }
  if not (C_Container and C_Container.GetContainerItemInfo) then
    return out
  end
  for bag = 0, 4 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local itemID = info and info.itemID
      if itemID then
        out.scanned = out.scanned + 1
      end
      local classID = itemID and select(6, C_Item.GetItemInfoInstant(itemID))
      if classID == 9 then
        local e = { itemID = itemID, link = safe(info.hyperlink) }
        if C_Item.GetItemSpell then
          local ok, name, spellID = pcall(C_Item.GetItemSpell, itemID)
          e.itemSpell = ok and { name = safe(name), id = safe(spellID) } or tostring(name)
        end
        if C_TooltipInfo and C_TooltipInfo.GetBagItem then
          local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
          e.tooltip = ok and tooltipLines(data) or tostring(data)
        end
        out[#out + 1] = e
      end
    end
  end
  return out
end

function Dev.ProbeRecipes(say, trigger)
  local probe = {
    at = GetServerTime(),
    trigger = trigger or "/amedev recipes",
    functions = {},
    build = select(4, GetBuildInfo()),
    frames = frames(),
    spellbook = spellbookProfessions(),
  }
  for _, f in ipairs(FUNCTIONS) do
    probe.functions[f] = has(f)
  end
  local T = C_TradeSkillUI
  if T and T.GetBaseProfessionInfo then
    local ok, p = pcall(T.GetBaseProfessionInfo)
    if ok and type(p) == "table" then
      probe.profession = {
        name = safe(p.professionName),
        skillLine = safe(p.professionID),
        skill = safe(p.skillLevel),
        max = safe(p.maxSkillLevel),
      }
    end
  end
  if T and T.GetAllRecipeIDs then
    local ok, ids = pcall(T.GetAllRecipeIDs)
    probe.allRecipes = ok and type(ids) == "table" and #ids or tostring(ids)
    if ok and type(ids) == "table" then
      local learned, types, recipes = 0, {}, {}
      for i, id in ipairs(ids) do
        local r = recipe(id)
        if r.learned == true then
          learned = learned + 1
        end
        local t = tostring(r.type)
        types[t] = (types[t] or 0) + 1
        if i <= 400 then
          recipes[i] = r
        end
      end
      probe.learned, probe.recipeTypes, probe.recipes = learned, types, recipes
    end
  end
  if T and T.GetFilteredRecipeIDs then
    local ok, ids = pcall(T.GetFilteredRecipeIDs)
    probe.filteredRecipes = ok and type(ids) == "table" and #ids or tostring(ids)
    if T.GetShowUnlearned then
      local ok2, show = pcall(T.GetShowUnlearned)
      probe.showUnlearned = ok2 and safe(show) or tostring(show)
    end
  end
  probe.recipeItems = recipeItems()
  -- open window: the client reports a profession (the frame's global name differs between clients)
  probe.windowShown = probe.profession ~= nil and probe.profession.skillLine ~= 0
  if T and T.IsTradeSkillReady then
    local ok, ready = pcall(T.IsTradeSkillReady)
    probe.ready = ok and safe(ready) or tostring(ready)
  end
  -- every run is kept (the last 8), so open and closed runs don't overwrite each other
  local runs = AME_DB.dev.recipeProbe
  if type(runs) ~= "table" or not runs[1] then
    runs = {}
    AME_DB.dev.recipeProbe = runs
  end
  table.insert(runs, probe)
  while #runs > 8 do
    table.remove(runs, 1)
  end
  local key = probe.windowShown and "window open" or "window closed"
  say(
    "recipe probe (%s): %s recipes, %s learned, %d recipe items of %d bag items - saved; /reload to save to disk",
    key,
    tostring(probe.allRecipes or "no GetAllRecipeIDs"),
    tostring(probe.learned or "?"),
    #probe.recipeItems,
    probe.recipeItems.scanned
  )
end

-- Automatic runs: the recipe list may only fill in after the client's profession events, so a run is taken a second
-- after each of them (debounced), and every event is logged (AME_DB.dev.recipeEvents, the last 40).
local PROBE_EVENTS = {
  "TRADE_SKILL_SHOW",
  "TRADE_SKILL_CLOSE",
  "TRADE_SKILL_LIST_UPDATE",
  "TRADE_SKILL_DATA_SOURCE_CHANGED",
  "TRADE_SKILL_DATA_SOURCE_CHANGING",
  "CRAFT_SHOW",
  "CRAFT_UPDATE",
  "NEW_RECIPE_LEARNED",
}
local FRAMES = { "ProfessionsFrame", "TradeSkillFrame", "CraftFrame", "ProfessionsCustomerOrdersFrame" }

function frames()
  local out = {}
  for _, name in ipairs(FRAMES) do
    local f = _G[name]
    out[name] = f and (f.IsShown and f:IsShown() and "shown" or "hidden") or "missing"
  end
  return out
end

function spellbookProfessions()
  local out = {}
  if not (GetProfessions and GetProfessionInfo) then
    return out
  end
  local ok, a, b, c, d, e = pcall(GetProfessions)
  if not ok then
    return { error = tostring(a) }
  end
  for _, index in ipairs({ a or false, b or false, c or false, d or false, e or false }) do
    if index then
      local ok2, name, _, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, index)
      out[#out + 1] = ok2 and { name = safe(name), rank = safe(rank), max = safe(maxRank), skillLine = safe(skillLine) }
        or tostring(name)
    end
  end
  return out
end

local pending = false
local watcher = CreateFrame("Frame")
for _, event in ipairs(PROBE_EVENTS) do
  pcall(watcher.RegisterEvent, watcher, event) -- an event this client doesn't have is skipped
end
watcher:SetScript("OnEvent", function(_, event)
  local dev = AME_DB and AME_DB.dev
  if not dev then
    return
  end
  dev.recipeEvents = dev.recipeEvents or {}
  table.insert(dev.recipeEvents, { event = event, at = GetTime(), frames = frames() })
  while #dev.recipeEvents > 40 do
    table.remove(dev.recipeEvents, 1)
  end
  if pending or event == "TRADE_SKILL_CLOSE" then
    return
  end
  pending = true
  C_Timer.After(1, function()
    pending = false
    pcall(Dev.ProbeRecipes, function() end, event)
  end)
end)

-- /amedev ui: where the Market screener's toolbar controls really are (position, size, shown / visible, layer), saved
-- to AME_DB.dev.uiProbe - for layout bugs the stubbed client can't show.
function Dev.ProbeUI(say)
  local UI = ns.UI
  local v = UI and UI.marketView
  if not v then
    return say("open the AME window on the Market tab first")
  end
  local out =
    { at = GetServerTime(), compact = v.slots and v.slots.compact, overview = ns.Settings:Get("marketOverview") }
  -- each anchor: point, what it's relative to (by name in the view), its point, offsets
  local function nameOf(r)
    if r == nil then
      return "nil"
    end
    for k, w in pairs(v) do
      if w == r then
        return k
      end
    end
    if v.slots and r == v.slots.toolbar then
      return "toolbar"
    end
    return tostring(r.GetName and r:GetName() or r)
  end
  local function anchors(f)
    local list = {}
    for i = 1, (f.GetNumPoints and f:GetNumPoints() or 0) do
      local point, rel, relPoint, x, y = f:GetPoint(i)
      list[i] = ("%s -> %s.%s (%s,%s)"):format(
        tostring(point),
        nameOf(rel),
        tostring(relPoint),
        tostring(x),
        tostring(y)
      )
    end
    return table.concat(list, "; ")
  end
  local function rect(f)
    if not f then
      return "missing"
    end
    local ok, l, b, w, h = pcall(f.GetRect, f)
    return {
      shown = f:IsShown(),
      visible = f:IsVisible(),
      rect = ok and l and ("%.0f,%.0f %.0fx%.0f"):format(l, b, w or 0, h or 0) or "no rect",
      alpha = f.GetEffectiveAlpha and f:GetEffectiveAlpha() or nil,
      level = f.GetFrameLevel and f:GetFrameLevel() or nil,
      strata = f.GetFrameStrata and f:GetFrameStrata() or nil,
      parent = f.GetParent and f:GetParent() and tostring(f:GetParent():GetName() or f:GetParent()) or nil,
      points = f.GetNumPoints and f:GetNumPoints() or nil,
      anchors = anchors(f),
      size = f.GetSize and ("%.0fx%.0f"):format(f:GetSize()) or nil,
    }
  end
  for _, k in ipairs({
    "mode",
    "modeDrop",
    "category",
    "search",
    "quality",
    "minBox",
    "maxBox",
    "views",
    "columns",
    "signals",
  }) do
    out[k] = rect(v[k])
  end
  out.toolbar = rect(v.slots and v.slots.toolbar)
  out.screener = rect(v)
  local area = UI.views and UI.views.market
  out.area = rect(area)
  out.overviewFrame = rect(area and area.overview)
  -- the mode switch's own buttons, and whether the client considers its rect valid
  out.modeValid = v.mode and v.mode.IsRectValid and v.mode:IsRectValid() or "n/a"
  out.modeButtons = {}
  for i, b in ipairs(v.mode and v.mode.buttons or {}) do
    out.modeButtons[i] = rect(b)
  end
  AME_DB.dev.uiProbe = out
  -- experiment: anchor the switch to the toolbar explicitly, then measure again next frame
  if v.mode then
    v.mode:ClearAllPoints()
    v.mode:SetPoint("LEFT", v.slots.toolbar, "LEFT", 0, 0)
    C_Timer.After(0.2, function()
      out.after = { mode = rect(v.mode), search = rect(v.search), valid = v.mode.IsRectValid and v.mode:IsRectValid() }
      say("ui probe: measured again after re-anchoring - /reload to write it to disk")
    end)
  end
  say("ui probe saved - wait a moment, then /reload")
end
