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

Scan.DONE_SHOWN = 20 -- "Full scan recorded" stays this long after a scan

-- what a running full scan is doing, for the line beside the button (nil when there's nothing to say):
-- waiting for the server, reading the auctions (a percentage), updating market data, then done
function Scan:Progress()
  local AME = ns.AME
  local ingest = AME.ingest
  local d = AME:ScanDiag()
  local now = GetServerTime()
  local p = ingest and ingest.reading and ingest.progress
  if p and p.total > 0 then
    return L["Reading auctions %d%%"]:format(math.floor(p.done * 100 / p.total))
  end
  local asked, read = d.lastReplicateAt, d.readDoneAt
  if ingest and ingest.requested and asked and now - asked < Scan.TIMEOUT then
    return L["Waiting for the server... %ds"]:format(now - asked)
  end
  if read and asked and read >= asked and now - read < Scan.DONE_SHOWN then
    if AME:IndexBusy() then
      return L["Updating market data..."]
    end
    return L["Full scan recorded"]
  end
  return nil
end

function Scan:Refresh()
  local b = self.button
  if not b then
    return
  end
  local shown = not Scan.OtherScanner()
  b:SetShown(shown)
  local progress = shown and self:Progress()
  self.status:SetText(progress or "")
  self.status:SetShown(progress ~= nil)
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

-- on the auction house window, top right; once
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
  -- in the window's title bar, left of its close button (above the window, other frames covered it); drawn over
  -- the window's own pieces
  local close = rawget(ah, "CloseButton")
  if type(close) == "table" and close.GetObjectType then
    b:SetHeight(18)
    b:SetPoint("RIGHT", close, "LEFT", -4, 0)
  else
    b:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", -4, 2)
  end
  -- the window's border pieces sit at high frame levels (its close button above them): over all of them
  local top = ah:GetFrameLevel() or 0
  if ah.GetChildren then
    for _, child in ipairs({ ah:GetChildren() }) do
      if child ~= b and child.GetFrameLevel then
        top = math.max(top, child:GetFrameLevel() or 0)
      end
    end
  end
  b:SetFrameLevel(top + 5)
  W.Tooltip(b, function(tip)
    W.TipText(
      tip,
      L["Full scan"],
      L["Reads every auction on this auction house at once (AME records it like any scan). The game allows one every 15 minutes. Shown because no scanning addon is loaded."]
    )
  end)
  self.button = b
  -- what the scan is doing, left of the button
  local status = W.Text(b, "GameFontHighlightSmall", "RIGHT")
  status:SetPoint("RIGHT", b, "LEFT", -6, 0)
  self.status = status
  -- the countdown and progress, while the auction house is open (quicker while a scan runs)
  local elapsed = 0
  local ticker = CreateFrame("Frame", nil, ah)
  ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= ((Scan.status:IsShown() or Scan:State() == "scanning") and 0.25 or 1) then
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
