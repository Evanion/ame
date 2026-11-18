-- Price checks: anyone typing "!pc <item>" (an item link or name) in guild, party or raid chat - or whispering it to
-- you - gets one line with the item's prices at your faction's auction house. Off by default: it sends chat in your
-- name. Your own "!pc" is answered in your chat window only.
--
-- One answer per request, however many AME users hear it: each waits a moment (less with fresher data), then claims
-- the request over the addon channel and listens for CLAIM_WINDOW seconds. Every client picks the same winner from the
-- claims it saw - the freshest data, then the alphabetically first name - and only the winner answers. A client that
-- sees someone else's claim before its own wait ends stays quiet. If no answer shows up within ANSWER_TIMEOUT, the
-- others try once more without that player.
local _, ns = ...
local L = ns.L

local PC = { requests = {}, claims = {}, handled = {}, askers = {}, sent = {} }
ns.PriceCheck = PC

PC.PREFIX = "AMEPC1"
PC.MARK = "[AME]" -- every answer starts with this: the others spot it in chat
PC.CLAIM_WINDOW = 0.5
PC.ANSWER_TIMEOUT = 3
PC.NO_DATA = 99 -- the "age" of a client without a price: it answers only when nobody with data does
PC.UNKNOWN = 100 -- a client that doesn't recognise the item name: last resort
PC.REPEAT = 60 -- the same request (asker and item) is answered once within this many seconds
PC.ASKER_COOLDOWN = 5 -- one request per asker this often
PC.PER_MINUTE = 6 -- answers sent per minute, at most
PC.MAX_QUERY = 80

-- chat event -> where its requests are answered (chat channel) and claimed (addon channel)
PC.CHANNELS = {
  CHAT_MSG_GUILD = "GUILD",
  CHAT_MSG_PARTY = "PARTY",
  CHAT_MSG_PARTY_LEADER = "PARTY",
  CHAT_MSG_RAID = "RAID",
  CHAT_MSG_RAID_LEADER = "RAID",
  CHAT_MSG_WHISPER = "WHISPER",
}

---------------------------------------------------------------------------------------------------------------------
-- pure

-- the item asked for in a chat line ("!pc Linen Cloth", "!PC [link]"), or nil
function PC.Parse(msg)
  if type(msg) ~= "string" then
    return nil
  end
  local q = msg:match("^%s*![pP][cC]%s+(.-)%s*$")
  if not q or q == "" or #q > PC.MAX_QUERY * 3 then
    return nil
  end
  return q
end

-- a sender's character name ("Name", "Name-Realm", or WoW Forever's "Name Suffix")
local function charName(sender)
  return type(sender) == "string" and sender:match("^%s*([^%-%s]+)") or nil
end
PC.CharName = charName

-- item ID in a query: from a link, or a bare number
function PC.QueryID(query)
  return ns.ItemIDFrom(query)
end

-- the same text on every client that heard a request: asker and item (links by item ID; names lowercased)
function PC.Key(asker, query)
  local id = PC.QueryID(query)
  local what = id and ("i" .. id) or query:lower():gsub("[|:]", ""):sub(1, PC.MAX_QUERY)
  return (charName(asker) or "?"):lower() .. ":" .. what
end

-- seconds to wait before claiming: fresher data claims first; random spreads clients with the same age apart
--   age: days since the price was seen (PC.NO_DATA / PC.UNKNOWN without one); r: 0..1
function PC.Wait(age, r)
  local base = age >= PC.NO_DATA and 1.6 or 0.2 + 0.15 * math.min(age, 7)
  return base + 0.3 * (r or 0)
end

-- does claim a beat claim b? { age, name }
function PC.Wins(a, b)
  if a.age ~= b.age then
    return a.age < b.age
  end
  return a.name:lower() < b.name:lower()
end

function PC.EncodeClaim(key, age)
  return "C|" .. key .. "|" .. math.floor(age)
end

function PC.DecodeClaim(msg)
  local key, age = tostring(msg):match("^C|(.+)|(%d+)$")
  if key then
    return key, tonumber(age)
  end
  return nil
end

-- money as chat text: "1g 20s 5c" (chat can't show coin icons in sent messages)
function PC.Coins(copper)
  copper = math.floor((copper or 0) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if g > 0 then
    parts[#parts + 1] = g .. "g"
  end
  if s > 0 then
    parts[#parts + 1] = s .. "s"
  end
  if c > 0 or #parts == 0 then
    parts[#parts + 1] = c .. "c"
  end
  return table.concat(parts, " ")
end

local function daysAgo(day, today)
  local d = today - day
  if d <= 0 then
    return L["today"]
  elseif d == 1 then
    return L["yesterday"]
  end
  return L["%d days ago"]:format(d)
end

-- The answer line.
--   label: the item (link or name); s: its market summary (nil: no data); house: "Horde AH"...; today: day number
--   found: false when the name wasn't recognised
function PC.Reply(label, s, house, today, found)
  if found == false then
    return PC.MARK .. " " .. L['Don\'t know "%s" - try an item link']:format(label)
  end
  if not (s and s.market) then
    return PC.MARK .. " " .. L["%s: no prices yet"]:format(label)
  end
  local parts = { L["market %s"]:format(PC.Coins(s.market)) }
  if s.min then
    parts[#parts + 1] = L["lowest %s"]:format(PC.Coins(s.min))
  end
  if s.avg7 then
    parts[#parts + 1] = L["7-day avg %s"]:format(PC.Coins(s.avg7))
  end
  if s.day and today then
    parts[#parts + 1] = L["seen %s"]:format(daysAgo(s.day, today))
  end
  return PC.MARK .. " " .. label .. ": " .. table.concat(parts, " · ") .. " (" .. house .. ")"
end

---------------------------------------------------------------------------------------------------------------------
-- WoW glue

local function now()
  return GetTime and GetTime() or 0
end

local function after(s, fn)
  C_Timer.After(s, fn)
end

local function isMe(sender)
  local me, name = UnitName("player"), charName(sender)
  return me ~= nil and name ~= nil and name:lower() == me:lower()
end

-- the item a query names, from a link or number, else the client's cache by name
local function resolve(query)
  local id = PC.QueryID(query)
  if id then
    return id
  end
  local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if instant then
    local ok, found = pcall(instant, query)
    if ok and type(found) == "number" then
      return found
    end
  end
  return nil
end

-- what this client would answer: the line and how fresh its data is
function PC:Answer(query)
  local id = resolve(query)
  local house = UnitFactionGroup("player")
  local houseLabel = ns.HOUSE_LABEL[house] or house or ""
  if not id then
    return PC.Reply(query, nil, houseLabel, nil, false), PC.UNKNOWN
  end
  local label = ns.ItemCache.Link(id) or ns.ItemCache.Name(id) or query
  local index = ns.AME and ns.AME:FactionIndex()
  local s = index and index.items[id]
  local today = ns.Today(GetServerTime())
  local age = s and s.market and s.day and math.max(0, today - s.day) or PC.NO_DATA
  return PC.Reply(label, s, houseLabel, today), age
end

-- whispers are answered for guild members, friends and trusted players only
function PC:Known(sender)
  local name = (charName(sender) or ""):lower()
  if name == "" then
    return false
  end
  local sync = ns.SyncService
  if sync and sync.trust and sync.trust:IsTrusted(sender) then
    return true
  end
  if C_FriendList and C_FriendList.GetFriendInfo then
    local ok, info = pcall(C_FriendList.GetFriendInfo, charName(sender))
    if ok and info then
      return true
    end
  end
  if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
    for i = 1, GetNumGuildMembers() or 0 do
      local member = GetGuildRosterInfo(i)
      if member and (charName(member) or ""):lower() == name then
        return true
      end
    end
  end
  return false
end

local function blocked(sender)
  local sync = ns.SyncService
  return sync and sync.trust and sync.trust:IsBlocked(sender) or false
end

-- the per-minute cap on answers sent
function PC:CanSend()
  local t, kept = now(), {}
  for _, at in ipairs(self.sent) do
    if t - at < 60 then
      kept[#kept + 1] = at
    end
  end
  self.sent = kept
  return #kept < PC.PER_MINUTE
end

function PC:Say(text, channel, target)
  self.sent[#self.sent + 1] = now()
  self.stats = AME_DB and AME_DB.stats
  if self.stats then
    self.stats.priceChecks = (self.stats.priceChecks or 0) + 1
  end
  SendChatMessage(text, channel, nil, target)
end

function PC:SendClaim(req)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(PC.PREFIX, PC.EncodeClaim(req.key, req.age), req.channel)
  end
end

function PC:OnChat(event, msg, sender)
  local channel = PC.CHANNELS[event]
  if not channel or type(msg) ~= "string" then
    return
  end
  if msg:sub(1, #PC.MARK) == PC.MARK then
    self:Answered(channel, sender)
    return
  end
  local query = PC.Parse(msg)
  if not query then
    return
  end
  -- your own !pc is answered in the channel you asked in (by you, or by whoever has fresher data), setting or not:
  -- you asked there, so it's for the group
  local mine = isMe(sender)
  if mine and channel == "WHISPER" then
    return
  end
  local on = mine or ns.Settings:Get(channel == "WHISPER" and "priceCheckWhisper" or "priceCheck")
  if not on or blocked(sender) or (channel == "WHISPER" and not self:Known(sender)) then
    return
  end
  local t = now()
  local who = (charName(sender) or ""):lower()
  if self.askers[who] and t - self.askers[who] < PC.ASKER_COOLDOWN then
    return
  end
  local key = PC.Key(sender, query)
  if self.handled[key] and t - self.handled[key] < PC.REPEAT then
    return
  end
  self.askers[who], self.handled[key] = t, t
  local text, age = self:Answer(query)
  if channel == "WHISPER" then
    if self:CanSend() then
      self:Say(text, "WHISPER", sender)
    end
    return
  end
  local req = { key = key, channel = channel, text = text, age = age, failed = {}, round = 0 }
  self.requests[key] = req
  if self.claims[key] then
    self:Watch(req) -- someone claimed it before the chat line reached us
  end
  self:Race(req)
end

-- one round: wait, claim unless someone already has, then see who won
function PC:Race(req)
  req.round = req.round + 1
  local round = req.round
  after(PC.Wait(req.age, math.random()), function()
    if req.done or req.round ~= round or self:Rival(req) then
      return
    end
    req.claimed = true
    self:SendClaim(req)
    after(PC.CLAIM_WINDOW, function()
      if req.done or req.round ~= round then
        return
      end
      local rival = self:Rival(req)
      if rival and PC.Wins(rival, { age = req.age, name = UnitName("player") or "" }) then
        return -- theirs; the timeout covers them going quiet
      end
      req.done = true
      if self:CanSend() then
        self:Say(req.text, req.channel)
      end
    end)
  end)
end

-- the best claim by someone else (not failed) for a request
function PC:Rival(req)
  local best
  for name, age in pairs(self.claims[req.key] or {}) do
    if not req.failed[name] then
      local c = { name = name, age = age }
      if not best or PC.Wins(c, best) then
        best = c
      end
    end
  end
  return best
end

function PC:OnClaim(msg, sender)
  if isMe(sender) then
    return
  end
  local key, age = PC.DecodeClaim(msg)
  if not key then
    return
  end
  local name = charName(sender) or sender
  self.claims[key] = self.claims[key] or {}
  self.claims[key][name] = age
  local req = self.requests[key]
  if req then
    self:Watch(req)
  end
end

-- someone claimed a request: if no answer shows up, try once more without the winner (the other claims are dropped:
-- their senders stayed quiet and race again too)
function PC:Watch(req)
  if req.done or req.watching or req.retried then
    return
  end
  req.watching = true
  after(PC.ANSWER_TIMEOUT, function()
    req.watching = false
    if req.done or req.retried then
      return
    end
    local rival = self:Rival(req)
    if rival then
      req.failed[rival.name] = true
      req.retried = true
      local failed = self.claims[req.key] and self.claims[req.key][rival.name]
      self.claims[req.key] = { [rival.name] = failed }
      self:Race(req)
    end
  end)
end

-- someone posted an answer on this channel: requests they claimed there are settled
function PC:Answered(channel, sender)
  local name = charName(sender)
  for key, req in pairs(self.requests) do
    if req.channel == channel and name and self.claims[key] and self.claims[key][name] then
      req.done = true
    end
  end
end

-- forget settled requests and old claims
function PC:Prune()
  local t = now()
  for key, at in pairs(self.handled) do
    if t - at > PC.REPEAT then
      self.handled[key], self.requests[key], self.claims[key] = nil, nil, nil
    end
  end
end

function PC:Start()
  if self.frame or not CreateFrame then
    return
  end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PC.PREFIX)
  end
  local f = CreateFrame("Frame")
  for event in pairs(PC.CHANNELS) do
    pcall(f.RegisterEvent, f, event)
  end
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:SetScript("OnEvent", function(_, event, a, b, _, d)
    local ok, err = pcall(function()
      if event == "CHAT_MSG_ADDON" then
        if a == PC.PREFIX then
          self:OnClaim(b, d)
        end
      else
        self:Prune()
        self:OnChat(event, a, b)
      end
    end)
    if not ok and ns.AME and ns.AME.ReportError then
      ns.AME:ReportError("price check", err)
    end
  end)
  self.frame = f
end
