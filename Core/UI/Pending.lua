-- What waits on you, outside the window (board MinimapPending): the minimap button and AME's data broker entry show
-- that something is waiting. They count what the bell counts (unread notifications, Core/Notices.lua) and clear with
-- it. The minimap button gets a mark (a glow and a count badge); the broker entry's text is "AME" or "AME 3" and its
-- icon is lit; hovering either lists what waits; a left-click opens AME on it.
--
--   Pending.Count() -> n                       unread notifications (0 while the mark is turned off)
--   Pending.Text(n) -> "AME" | "AME |cff..3|r"  the broker entry's text
--   Pending.TooltipRows(list, n, now, facts) -> rows   the hover tooltip (Tooltip.AddRows rows), or nil: nothing
--                                              waits, and the launcher's own tooltip shows
--   Pending.Attach()                           hook up the broker object and the minimap button (Launcher:Init)
--   Pending.Update()                           redraw the mark, the text and the icon
--   Pending.Click(button)                      the launcher's click: open AME on what waits
--   Pending.FillTooltip(tt)                    the launcher's tooltip
local ADDON, ns = ...
local L = ns.L

local Kit = ns.Kit

local Pending = { TIP = 5, KEY_DEFAULTS = { pendingMark = true } }
ns.Pending = Pending

local function notices()
  return ns.AME and ns.AME.notices
end

local function markOn()
  local v = ns.Settings and ns.Settings:Get("pendingMark")
  if v == nil then
    v = Pending.KEY_DEFAULTS.pendingMark
  end
  return v and true or false
end

function Pending.Count()
  local n = notices()
  if not (n and markOn()) then
    return 0
  end
  return n:Unread()
end

function Pending.Text(n)
  if (n or 0) > 0 then
    return "AME " .. Kit.Color("warn", tostring(n))
  end
  return "AME"
end

-- what each kind is called on a tooltip line
local KIND = {
  alert = L["alert"],
  request = L["sharing"],
  update = L["update"],
  craft = L["request"],
  sold = L["sold"],
  undercut = L["auctions"],
  cooldown = L["cooldown"],
  scan = L["scan"],
}

-- facts: { worth = copper?, pricesAt = time? }
function Pending.TooltipRows(list, n, now, facts)
  if (n or 0) <= 0 then
    return nil
  end
  local Notify, W = ns.NotifyScreen, ns.Widgets
  local rows = {
    { Kit.Color("heading", L["Azeroth Mercantile Exchange"]) },
    { Kit.Color("warn", n == 1 and L["1 waiting on you"] or L["%d waiting on you"]:format(n)) },
  }
  for i = 1, math.min(n, Pending.TIP, #list) do
    local e = list[i]
    local row = Notify and Notify.Row(e, now, true)
    local text = row and Kit.Parts(row.title) or (e.text or "")
    local when = W and W.Ago and W.Ago(e.at, now) or ""
    local kind = KIND[e.kind]
    rows[#rows + 1] = { text .. " " .. Kit.Color("dim", kind and (kind .. " · " .. when) or when) }
  end
  if n > Pending.TIP then
    rows[#rows + 1] = { Kit.Color("dim", L["+ %d more"]:format(n - Pending.TIP)) }
  end
  facts = facts or {}
  local bits = {}
  if facts.worth and W and W.Money then
    bits[#bits + 1] = L["Net worth %s"]:format(W.Money(facts.worth, true))
  end
  if facts.pricesAt and W and W.Age then
    bits[#bits + 1] = L["prices %s old"]:format(W.Age(facts.pricesAt, now))
  end
  if #bits > 0 then
    rows[#rows + 1] = { Kit.Color("dim", table.concat(bits, " · ")) }
  end
  rows[#rows + 1] = { Kit.Color("dim", L["Left-click: open AME on what waits · Right-click: settings"]) }
  return rows
end

-- ------------------------------------------------------------------------------------------------ in game

local function stub(name)
  local s = _G.LibStub
  return s and s(name, true) or nil
end

local function facts()
  local out = {}
  local ok, f = pcall(function()
    return ns.Home and ns.Home.Gather and ns.Home.Gather()
  end)
  if ok and f and f.hasPrices then
    local kpis = ns.Home.Kpis(f)
    out.worth = kpis and kpis[1] and kpis[1].copper
  end
  local last = AME_DB and AME_DB.stats and AME_DB.stats.lastFull
  out.pricesAt = last and last.at
  return out
end

function Pending.FillTooltip(tt)
  local n = notices()
  local count = Pending.Count()
  local now = GetServerTime and GetServerTime() or 0
  local rows = n and Pending.TooltipRows(n:List(), count, now, facts())
  if not rows then
    if ns.Launcher and ns.Launcher.FillTooltip then
      return ns.Launcher.FillTooltip(tt)
    end
    return
  end
  if ns.Tooltip and ns.Tooltip.AddRows then
    ns.Tooltip.AddRows(tt, rows)
  else
    for _, r in ipairs(rows) do
      tt:AddLine(r[1])
    end
  end
end

-- left-click with something waiting: the new window on the notifications; otherwise the launcher's own click
function Pending.Click(button)
  if button ~= "RightButton" and Pending.Count() > 0 and ns.App and ns.App.Enabled and ns.App.Enabled() then
    ns.App:Go("notifications")
    return
  end
  if ns.Launcher and ns.Launcher.Click then
    ns.Launcher.Click(button)
  end
end

-- the mark on the minimap button: a warm glow behind it and a red count on its corner
local function badge(button)
  if button.ameBadge then
    return button.ameBadge
  end
  local b = CreateFrame("Frame", nil, button)
  b:SetSize(15, 15)
  b:SetPoint("TOPRIGHT", button, "TOPRIGHT", 3, 3)
  b:SetFrameLevel((button:GetFrameLevel() or 1) + 5)
  b.dot = b:CreateTexture(nil, "ARTWORK")
  b.dot:SetAllPoints()
  b.dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask") -- a circle
  local c = Kit.C("badge")
  if b.dot.SetVertexColor then
    b.dot:SetVertexColor(c[1], c[2], c[3], 1)
  end
  b.count = Kit.Text(b, { size = 10, color = "white", justify = "CENTER" })
  b.count:SetPoint("CENTER", 0, 0)
  b.glow = button:CreateTexture(nil, "BACKGROUND")
  b.glow:SetPoint("CENTER", button, "CENTER", 0, 0)
  b.glow:SetSize(46, 46)
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  if b.glow.SetBlendMode then
    b.glow:SetBlendMode("ADD")
  end
  local w = Kit.C("warn")
  if b.glow.SetVertexColor then
    b.glow:SetVertexColor(w[1], w[2], w[3], 0.8)
  end
  button.ameBadge = b
  return b
end

function Pending.Update()
  local count = Pending.Count()
  local LDB = stub("LibDataBroker-1.1")
  local obj = LDB and LDB.GetDataObjectByName and LDB:GetDataObjectByName(ADDON)
  if obj then
    obj.text = Pending.Text(count)
    -- the lit icon: no file ships, so the icon is tinted warm while something waits (to check in game)
    if count > 0 then
      obj.iconR, obj.iconG, obj.iconB = 1, 0.85, 0.45
    else
      obj.iconR, obj.iconG, obj.iconB = 1, 1, 1
    end
  end
  local icon = stub("LibDBIcon-1.0")
  local button = icon and icon.GetMinimapButton and icon:GetMinimapButton(ADDON)
  if button then
    local b = badge(button)
    b.count:SetText(count > 9 and "9+" or tostring(count))
    b:SetShown(count > 0)
    b.glow:SetShown(count > 0)
  end
end

function Pending.Attach()
  if Pending.attached then
    return Pending.Update()
  end
  local LDB = stub("LibDataBroker-1.1")
  local obj = LDB and LDB.GetDataObjectByName and LDB:GetDataObjectByName(ADDON)
  if obj then
    obj.OnClick = function(_, button)
      Pending.Click(button)
    end
    obj.OnTooltipShow = Pending.FillTooltip
  end
  local n = notices()
  if n and n.OnChange then
    n:OnChange(Pending.Update)
  end
  Pending.attached = true
  Pending.Update()
end
