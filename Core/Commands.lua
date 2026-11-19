-- Slash commands: /ame, /ame item, /ame status, /ame scan...
local _, ns = ...
local L = ns.L

local AME = ns.AME
local say, money = AME.Say, AME.Money

---------------------------------------------------------------------------------------------------------------------
-- slash commands

local function itemIDFrom(text) -- an item key, learning a variant's name from its link
  return ns.ItemCache.Learn(text)
end

local function cmdItem(arg)
  local id = itemIDFrom(arg)
  if not id then
    say(L["usage: /ame item <item link or itemID>"])
    return
  end
  local store = AME:Store()
  if not store then
    return
  end
  local l = store:Latest(id)
  if l then
    say(
      L["%s latest (%s): min %s, market %s, %d units in %d auctions"],
      arg,
      date("%H:%M", l.t),
      money(l.min),
      money(l.market),
      l.qty,
      l.auctions
    )
  end
  local series = store:Series(id)
  if #series == 0 then
    say(L["no history for %s in %s"], arg, ns.ShardLabel(AME:CurrentShard()))
    return
  end
  for k = math.max(1, #series - 13), #series do
    local p = series[k]
    say(
      "  " .. L["%s %s: min %s, market %s, qty %d (%d samples)"],
      p.res,
      date("!%Y-%m-%d", p.day * 86400),
      money(p.min),
      money(p.market),
      p.qty,
      p.scans
    )
  end
end

local function cmdStatus()
  local shard = AME:CurrentShard()
  say(L["market %s, history %s"], ns.ShardLabel(shard), AME:HistoryLoaded() and L["loaded"] or L["not loaded"])
  local s = AME_DB.stats
  if s.lastFull then
    say(
      L["last full scan: %d items, %s ago"],
      s.lastFull.items,
      SecondsToTime and SecondsToTime(GetServerTime() - s.lastFull.at) or "?"
    )
  else
    say(L["no full scan recorded yet: open the AH and run a full scan (your scanning addon's or the game's)"])
  end
  if AME:HistoryLoaded() then
    local data = AME.history.shards[shard]
    if data then
      local days, bytes = ns.Store.Footprint(data)
      say(L["history: %d raw scans, %d days, %.0f KB"], #(data.raw or {}), days, bytes / 1024)
    end
  end
  local d = AME:ScanDiag()
  say(
    L["scan pipeline: %d requests, %d events (%d since last request), read %s, aborted %d; ingest requested=%s reading=%s"],
    d.requests or 0,
    d.events or 0,
    d.eventsSinceRequest or 0,
    d.readItems and L["%d items"]:format(d.readItems) or L["none"],
    d.aborted or 0,
    tostring(AME.ingest.requested),
    tostring(AME.ingest.reading)
  )
  local names = {}
  for _, job in ipairs(AME.jobs.queue) do
    names[#names + 1] = job.name
  end
  say(L["background jobs: %s"], #names > 0 and table.concat(names, ", ") or L["idle"])
  say(
    L["guild sync: %s, announced %d, served %d, received %d, rejected %d"],
    ns.SyncService:Active() and L["on"] or L["off"],
    s.syncAnnounced or 0,
    s.syncServed or 0,
    s.syncReceived or 0,
    s.syncRejected or 0
  )
  if (s.syncErrors or 0) > 0 then
    say(ns.Color("bad", L["sync errors: %d (last: %s)"]), s.syncErrors, tostring(s.lastSyncError))
  end
  local err = AME_DB.stats.lastError
  if err then
    say(ns.Color("bad", L["last error (%s, %s): %s"]), err.context, date("%b %d %H:%M", err.at), err.error)
  end
end

SLASH_AZEROTHMERCANTILEEXCHANGE1 = "/ame"
SlashCmdList.AZEROTHMERCANTILEEXCHANGE = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "item" then
    cmdItem(rest)
  elseif cmd == "status" then
    cmdStatus()
  elseif cmd == "selftest" then
    ns.SelfTest.Run(AME)
  elseif cmd == "backfill" then
    AME:Backfill(true)
  elseif cmd == "config" or cmd == "settings" or cmd == "options" then
    ns.Settings:Open()
  elseif cmd == "sync" or cmd == "sharing" then
    ns.UI:Create()
    ns.UI.frame:Show()
    ns.UI:ShowTab("sync") -- Settings, Sharing
  elseif cmd == "" then
    ns.UI:Toggle()
  elseif cmd == "help" then
    say(
      L["/ame - open the window  ·  /ame <item link> - chart an item  ·  Shift-click an item on the Item tab - chart it"]
    )
    say(
      L["/ame item <link> - print history  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config  ·  /ame sync"]
    )
  elseif itemIDFrom(msg) then
    ns.UI:ShowItem(itemIDFrom(msg))
  else
    say(L["unknown command, try /ame help"])
  end
end
