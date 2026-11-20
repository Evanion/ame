-- A Full scan button over the auction house window, for players with no scanning addon: AME asks the game for the
-- whole auction house itself (C_AuctionHouse.ReplicateItems - the same full scan scanning addons run, recorded the
-- same way). With a scanning addon loaded (Auctionator, TradeSkillMaster) it stays hidden: scan there. /ame scan works
-- either way.
--
-- The game allows one full scan every 15 minutes (per account, whoever asks); AME counts from the last one asked
-- for by anyone (AME:ScanDiag().lastReplicateAt) and says when the next can go.
local _, ns = ...
local L = ns.L

local W = ns.Widgets

local Scan = {}
ns.ScanButton = Scan

Scan.COOLDOWN = 15 * 60
Scan.TIMEOUT = 120 -- asked this long ago with nothing read: the game didn't answer (throttled)

-- seconds as m:ss
local function clock(s)
  s = math.max(0, math.floor(s))
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

function Scan.OtherScanner()
  return _G.Auctionator ~= nil or _G.TSM_API ~= nil
end

-- "ready", "scanning" or "wait" (with the seconds left)
function Scan:State()
  local d = ns.AME:ScanDiag()
  local asked, read = d.lastReplicateAt, d.readDoneAt
  local now = GetServerTime()
  if not asked then
    return "ready"
  end
  if (not read or read < asked) and now - asked < Scan.TIMEOUT then
    return "scanning"
  end
  local left = asked + Scan.COOLDOWN - now
  if left > 0 then
    return "wait", left
  end
  return "ready"
end

-- start a full scan; true, or nil and why
function Scan:Start()
  local AME = ns.AME
  local api = C_AuctionHouse and C_AuctionHouse.ReplicateItems
  if not api then
    return nil, L["This game version has no full scan."]
  end
  if not AME.ahOpen then
    return nil, L["Open the auction house first."]
  end
  local state, left = self:State()
  if state == "scanning" then
    return nil, L["A full scan is already running."]
  elseif state == "wait" then
    return nil, L["The game allows one full scan every 15 minutes: the next in %s."]:format(clock(left))
  end
  local ok, err = pcall(api)
  if not ok then
    return nil, tostring(err)
  end
  self:Refresh()
  return true
end

function Scan:Refresh()
  local b = self.button
  if not b then
    return
  end
  b:SetShown(not Scan.OtherScanner())
  local state, left = self:State()
  if state == "scanning" then
    b:SetText(L["Scanning..."])
    b:SetEnabled(false)
  elseif state == "wait" then
    b:SetText(L["Full scan in %s"]:format(clock(left)))
    b:SetEnabled(false)
  else
    b:SetText(L["Full scan"])
    b:SetEnabled(true)
  end
  b:SetWidth(math.ceil(b.label:GetStringWidth() or 60) + 20)
end

-- over the top-right corner of the auction house window (the sell bar is under it); once
function Scan.Frame()
  return AuctionHouseFrame or AuctionFrame -- the game's auction house window, or the old one
end

function Scan:Attach()
  local ah = Scan.Frame()
  if self.button or not ah then
    return
  end
  local b = W.Button(ah, L["Full scan"], 90, 20, function()
    local ok, why = Scan:Start()
    if not ok then
      ns.AME.Say(why)
    end
  end)
  b:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", -4, 2)
  W.Tooltip(b, function(tip)
    W.TipText(
      tip,
      L["Full scan"],
      L["Reads every auction on this auction house at once (AME records it like any scan). The game allows one every 15 minutes. Shown because no scanning addon is loaded."]
    )
  end)
  self.button = b
  -- the countdown, while the auction house is open
  local elapsed = 0
  local ticker = CreateFrame("Frame", nil, ah)
  ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= 1 then
      elapsed = 0
      Scan:Refresh()
    end
  end)
  self:Refresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event)
  -- the window's addon may load after this event reaches AME: try now, and again a moment later
  if event == "ADDON_LOADED" and not Scan.Frame() then
    return
  end
  Scan:Attach()
  Scan:Refresh()
  if event == "AUCTION_HOUSE_SHOW" and C_Timer then
    C_Timer.After(0.5, function()
      Scan:Attach()
      Scan:Refresh()
    end)
  end
end)
