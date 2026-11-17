-- Trusted-player sync bookkeeping (pure). Mutual opt-in, like AHDB's trust list:
--   you add a player -> AME whispers them a hello -> they see a request and approve -> both sides trust each other.
-- Also tracks which peers were heard from recently, so AME only whispers players that are online (whispering an
-- offline player prints "No player named ... is currently playing").
--
--   db = {
--     trusted  = { [key] = { name, added, mutual = bool } },   key = lower-cased name
--     pending  = { [key] = { name, at } },                     requests from others waiting for approval
--     declined = { [key] = at },                               ignore their hellos for a day
--     peers    = { [key] = { name, at, via, received } },      anyone heard from (guild or whisper)
--     blocked  = { [key] = { name, at } },                     personal blocklist (plus the guild's, see IsBlocked)
--   }
local _, ns = ...
local L = ns.L

local Trust = {}
Trust.__index = Trust
ns.Trust = Trust

Trust.ONLINE_WINDOW = 15 * 60 -- a peer heard from this recently counts as online
Trust.DECLINE_QUIET = 24 * 3600

local function key(name)
  return type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", ""):lower() or nil
end
Trust.Key = key

function Trust.New(db)
  db.trusted = db.trusted or {}
  db.pending = db.pending or {}
  db.declined = db.declined or {}
  db.peers = db.peers or {}
  db.blocked = db.blocked or {}
  return setmetatable({ db = db, guildBlocked = {} }, Trust)
end

local function clean(name)
  return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- returns the entry, or nil + reason
function Trust:Add(name, now)
  local k = key(name)
  if not k or k == "" then
    return nil, L["enter a character name"]
  end
  local e = self.db.trusted[k]
  if not e then
    e = { name = clean(name), added = now, mutual = false }
    self.db.trusted[k] = e
  end
  -- adding someone who already asked us = approving them
  if self.db.pending[k] then
    e.mutual = true
    self.db.pending[k] = nil
  end
  self.db.declined[k] = nil
  return e
end

function Trust:Remove(name)
  local k = key(name)
  self.db.trusted[k] = nil
  self.db.pending[k] = nil
end

function Trust:IsTrusted(name)
  return self.db.trusted[key(name)] ~= nil
end

function Trust:MarkMutual(name)
  local e = self.db.trusted[key(name)]
  if e then
    e.mutual = true
  end
  return e
end

-- a hello from someone we don't trust yet; returns true if it's a new request to show
function Trust:Request(name, now)
  local k = key(name)
  if self.db.trusted[k] or self:IsBlocked(name) then
    return false
  end
  local d = self.db.declined[k]
  if d and now - d < Trust.DECLINE_QUIET then
    return false
  end
  local isNew = self.db.pending[k] == nil
  self.db.pending[k] = { name = name, at = now }
  return isNew
end

function Trust:Approve(name, now)
  local e = self:Add(name, now)
  if e then
    e.mutual = true
  end
  return e
end

function Trust:Decline(name, now)
  local k = key(name)
  self.db.pending[k] = nil
  self.db.declined[k] = now
end

function Trust:Heard(name, now, via)
  local k = key(name)
  if not k then
    return
  end
  local p = self.db.peers[k] or { name = name, received = 0 }
  p.name, p.at, p.via = name, now, via
  self.db.peers[k] = p
  return p
end

function Trust:Received(name)
  local p = self.db.peers[key(name)]
  if p then
    p.received = (p.received or 0) + 1
  end
end

function Trust:LastHeard(name)
  local p = self.db.peers[key(name)]
  return p and p.at
end

-- trusted players worth whispering now: online friends, or heard from within ONLINE_WINDOW
function Trust:OnlineTargets(now, isFriendOnline)
  local out = {}
  for k, e in pairs(self.db.trusted) do
    local p = self.db.peers[k]
    local recent = p and p.at and now - p.at <= Trust.ONLINE_WINDOW
    if recent or (isFriendOnline and isFriendOnline(e.name)) then
      out[#out + 1] = e.name
    end
  end
  table.sort(out)
  return out
end

local function sorted(t, by)
  local out = {}
  for _, v in pairs(t) do
    out[#out + 1] = v
  end
  table.sort(out, by)
  return out
end

-- personal block: also drops any trust or pending request
function Trust:Block(name, now)
  local k = key(name)
  if not k or k == "" then
    return nil
  end
  self.db.blocked[k] = { name = clean(name), at = now }
  self.db.trusted[k] = nil
  self.db.pending[k] = nil
  return self.db.blocked[k]
end

function Trust:Unblock(name)
  self.db.blocked[key(name)] = nil
end

-- guild officers' list (set of lower-cased names), refreshed from the guild info text
function Trust:SetGuildBlocklist(set)
  self.guildBlocked = set or {}
end

-- blocked by me ("me"), by the guild ("guild"), or nil
function Trust:IsBlocked(name)
  local k = key(name)
  if not k then
    return nil
  end
  if self.db.blocked[k] then
    return "me"
  end
  if self.guildBlocked[k] then
    return "guild"
  end
  return nil
end

function Trust:BlockedList()
  return sorted(self.db.blocked, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
end

function Trust:TrustedList()
  return sorted(self.db.trusted, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
end

function Trust:PendingList()
  return sorted(self.db.pending, function(a, b)
    return a.at > b.at
  end)
end

function Trust:PeerList()
  return sorted(self.db.peers, function(a, b)
    return (a.at or 0) > (b.at or 0)
  end)
end
