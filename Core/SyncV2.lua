-- Sync v2 engine (pure: sending, clock, timers, randomness and the data side are injected). docs/plans/sync-v2.md.
--
-- Objects - a full scan ("s", ref = its time), an hourly point ("h", ref = the hour) or a stored day ("d", ref = the
-- day) of one auction house - go to the whole guild at once, cut into numbered blocks of one addon message each, so
-- a lost message costs one block, not the object, and everyone missing an object gets it from one send.
--
--   manifest "2|M|<shard>|<scanT>|<hour0>|<hours hex>|<day0>|<days hex>"  what I hold (bit i: hour0 - i, day0 - i)
--   request  "2|R|<shard>|<kind>|<ref>"                                     anyone holding it may answer
--   offer    "2|O|<shard>|<oid>|<kind>|<ref>|<t>|<n>|<len>|<sum>|<src>|<key>" an object's blocks follow
--   block    "2|B|<oid>|<i>|<bytes>"                                       block i of n (bytes: rest of the message)
--   missing  "2|N|<sender>|<oid>|<ranges>"                                 "resend these blocks of your object oid"
--
-- Numbers are base 36; shard "|" travels as "~". Requests are answered by one holder: each waits a random moment and
-- stays quiet when another's offer comes first (two offers at once: the name sorting first keeps sending). Receivers
-- whose blocks stop coming ask for the missing ones after a random moment, unless someone else asked first (they'll
-- get that resend too) - the way reliable multicast keeps one loss from causing a storm of requests.
--
-- One message goes out per PACE: the game allows each player ~1 addon message per second per prefix after a burst of
-- ~10 (docs/design.md), and drops the rest without saying so.
local _, ns = ...

local Codec = ns.Codec
local b36, from36 = Codec.ToBase36, Codec.FromBase36
local floor, min = math.floor, math.min
local concat = table.concat

local V2 = {}
V2.__index = V2
ns.SyncV2 = V2

local PRIORITY = { s = 1, h = 2, d = 3 }

V2.PREFIX = "AME2"
V2.PACE = 1.05 -- seconds between messages
V2.BLOCK = 230 -- bytes per block message (with its header, under the 255-byte limit)
V2.ANSWER_DELAY = 3 -- a holder answers a request after a random 0..3 s
V2.NACK_DELAY = 2 -- a receiver asks for missing blocks after a random 0..2 s
V2.STALL = 12 -- no block of an incoming object for this long: ask for the missing ones
V2.CHECK_EVERY = 4
V2.MAX_NACKS = 6 -- then give up on the object (it's asked for again on a later manifest)
V2.REQUEST_COOLDOWN = 300 -- an object asked for isn't asked for again this soon
V2.MAX_REQUESTS = 3 -- objects asked for per manifest heard
V2.REQUEST_DELAY = 2 -- a manifest's hearers ask after a random 0..2 s (the first ask silences the rest)
V2.OFFER_FRESH = 20 -- an offer whose sender sent something this recently is in progress (a sender is never quiet
-- for long while it has blocks to send): don't ask for or answer that object
V2.KEEP_SENT = 600 -- a sent object answers requests for missing blocks this long
V2.HOURS = 168
V2.DAYS = 7
V2.MAX_RANGES_LEN = 180

local function shardOut(shard)
  return (shard:gsub("|", "~"))
end

local function shardIn(s)
  return (s:gsub("~", "|"))
end

local function clean(s)
  return (tostring(s or ""):gsub("[|\n]", ""))
end

local function objKey(shard, kind, ref)
  return shard .. "#" .. kind .. "#" .. ref
end
V2.ObjKey = objKey

-- Adler-32 style checksum (no bit library needed). pause (optional) runs between 2 KB pieces.
function V2.Checksum(s, pause)
  local a, b = 1, 0
  local byte = string.byte
  for i = 1, #s, 2048 do
    local bytes = { byte(s, i, min(i + 2047, #s)) }
    for k = 1, #bytes do
      a = (a + bytes[k]) % 65521
      b = (b + a) % 65521
    end
    if pause then
      pause()
    end
  end
  return b * 65536 + a
end

-- a set of numbers counted back from base (bit i = base - i) as hex, and back
local function bitsOut(set, base, count)
  local out = {}
  for c = 0, floor((count - 1) / 4) do
    local v = 0
    for j = 0, 3 do
      local i = c * 4 + j
      if i < count and set[base - i] then
        v = v + 2 ^ j
      end
    end
    out[#out + 1] = ("%x"):format(v)
  end
  return concat(out)
end

local function bitsIn(hex, base)
  local set = {}
  for c = 1, #hex do
    local v = tonumber(hex:sub(c, c), 16) or 0
    for j = 0, 3 do
      if v % 2 == 1 then
        set[base - ((c - 1) * 4 + j)] = true
      end
      v = floor(v / 2)
    end
  end
  return set
end

-- manifest: { scanT = t or 0, hour0 =, hours = set, day0 =, days = set }
function V2.EncodeManifest(shard, m)
  return concat({
    "2",
    "M",
    shardOut(shard),
    b36(m.scanT or 0),
    b36(m.hour0),
    bitsOut(m.hours, m.hour0, V2.HOURS),
    b36(m.day0),
    bitsOut(m.days, m.day0, V2.DAYS),
  }, "|")
end

function V2.EncodeRequest(shard, kind, ref)
  return concat({ "2", "R", shardOut(shard), kind, b36(ref) }, "|")
end

-- o: { oid, kind, ref, t, n, len, sum, src, key }
function V2.EncodeOffer(shard, o)
  return concat({
    "2",
    "O",
    shardOut(shard),
    o.oid,
    o.kind,
    b36(o.ref),
    b36(o.t or 0),
    b36(o.n),
    b36(o.len),
    b36(o.sum),
    clean(o.src),
    clean(o.key),
  }, "|")
end

function V2.EncodeBlock(oid, i, bytes)
  return "2|B|" .. oid .. "|" .. b36(i) .. "|" .. bytes
end

-- missing block numbers as "a-b,c,..." (base 36), as many as fit
function V2.EncodeMissing(sender, oid, missing)
  local parts, len = {}, 0
  local i = 1
  while i <= #missing do
    local j = i
    while missing[j + 1] == missing[j] + 1 do
      j = j + 1
    end
    local part = i == j and b36(missing[i]) or (b36(missing[i]) .. "-" .. b36(missing[j]))
    if len + #part + 1 > V2.MAX_RANGES_LEN then
      break
    end
    parts[#parts + 1], len = part, len + #part + 1
    i = j + 1
  end
  return concat({ "2", "N", clean(sender), oid, concat(parts, ",") }, "|")
end

local function ranges(text)
  local out = {}
  for part in text:gmatch("[^,]+") do
    local a, b = part:match("^(%w+)%-(%w+)$")
    a, b = from36(a or part), from36(b or part)
    if a and b and b >= a and b - a < 100000 then
      for i = a, b do
        out[#out + 1] = i
      end
    end
  end
  return out
end

function V2.Decode(msg)
  if type(msg) ~= "string" or msg:sub(1, 2) ~= "2|" then
    return nil
  end
  local ok, m = pcall(function()
    local kind = msg:sub(3, 3)
    if kind == "B" then
      local oid, i, at = msg:match("^2|B|([^|]+)|(%w+)|()")
      return oid and { type = "block", oid = oid, i = from36(i), bytes = msg:sub(at) }
    end
    local f = {}
    for part in (msg .. "|"):gmatch("([^|]*)|") do
      f[#f + 1] = part
    end
    if kind == "M" and #f == 8 then
      local hour0, day0 = from36(f[5]), from36(f[7])
      return {
        type = "manifest",
        shard = shardIn(f[3]),
        scanT = from36(f[4]),
        hour0 = hour0,
        hours = bitsIn(f[6], hour0),
        day0 = day0,
        days = bitsIn(f[8], day0),
      }
    elseif kind == "R" and #f == 5 then
      return { type = "request", shard = shardIn(f[3]), kind = f[4], ref = from36(f[5]) }
    elseif kind == "O" and #f == 12 then
      return {
        type = "offer",
        shard = shardIn(f[3]),
        oid = f[4],
        kind = f[5],
        ref = from36(f[6]),
        t = from36(f[7]),
        n = from36(f[8]),
        len = from36(f[9]),
        sum = from36(f[10]),
        src = f[11],
        key = f[12],
      }
    elseif kind == "N" and #f == 5 then
      return { type = "missing", target = f[3], oid = f[4], blocks = ranges(f[5]) }
    end
  end)
  return ok and m or nil
end

---------------------------------------------------------------------------------------------------------------------
-- the engine

-- o: { name = my name, send = fn(msg) (to the guild), now = fn() seconds, after = fn(seconds, fn),
--      random = fn() 0..1, host = data side (see SyncService:V2Host) }
function V2.New(o)
  return setmetatable({
    name = o.name,
    key = o.nameKey or function(n)
      return n
    end,
    me = (o.nameKey or function(n)
      return n
    end)(o.name),
    send = o.send,
    now = o.now,
    after = o.after,
    random = o.random or math.random,
    host = o.host,
    control = {}, -- small messages, sent before blocks
    order = {}, -- outgoing objects with blocks to send, in turn
    outgoing = {}, -- [oid] = { ... } (kept KEEP_SENT after the last block, for resends)
    offers = {}, -- [objKey] = { sender, oid, at } offers heard (anyone's)
    offerOf = {}, -- [sender .. "\n" .. oid] = objKey
    answering = {}, -- [objKey] = true while waiting to answer
    incoming = {}, -- [sender .. "\n" .. oid] = { ... }
    requested = {}, -- [objKey] = when asked for
    nacked = {}, -- [sender .. "\n" .. oid] = when someone asked for missing blocks
    stats = { sent = 0, blocksSent = 0, objectsSent = 0, objectsReceived = 0, bad = 0 },
    serial = 0,
    heard = {}, -- [sender] = when last heard sending (an offer or a block)
    asking = {}, -- [objKey] = true while waiting to ask for it
    offerAsked = {}, -- [sender .. "\n" .. oid] = true: asked for that offer again
  }, V2)
end

function V2:queue(msg)
  self.control[#self.control + 1] = msg
  self:wake()
end

function V2:wake()
  if self.ticking then
    return
  end
  self.ticking = true
  self.after(0, function()
    self:tick()
  end)
end

-- send one message, and come back in PACE while there's more
function V2:tick()
  local msg = table.remove(self.control, 1)
  if not msg then
    local o = self.order[1]
    while o and (o.cancelled or #o.pending == 0) do
      table.remove(self.order, 1)
      o = self.order[1]
    end
    if o then
      local i = table.remove(o.pending, 1)
      o.pendingSet[i] = nil
      msg = V2.EncodeBlock(o.oid, i, o.blocks[i])
      local mine = self.offers[o.k]
      if mine and mine.oid == o.oid then
        mine.at = self.now()
      end
      self.stats.blocksSent = self.stats.blocksSent + 1
      if #o.pending == 0 then
        o.doneAt = self.now()
        if not o.counted then
          o.counted = true
          self.stats.objectsSent = self.stats.objectsSent + 1
        end
      end
    end
  end
  if not msg then
    self.ticking = false
    return
  end
  self.stats.sent = self.stats.sent + 1
  self.send(msg)
  self.after(V2.PACE, function()
    self:tick()
  end)
end

-- what I hold, to the guild
function V2:Announce()
  for _, shard in ipairs(self.host:Shards()) do
    local m = self.host:Manifest(shard)
    if m then
      self:queue(V2.EncodeManifest(shard, m))
    end
  end
end

-- an object of mine everyone should have (a fresh full scan): offered without being asked for
function V2:Push(shard, kind, ref)
  self:answer(shard, kind, ref)
end

-- someone (maybe me) offered the object and is still sending - that or anything else: an offer waits behind the
-- sender's other objects
function V2:inProgress(k)
  local o = self.offers[k]
  if not o then
    return false
  end
  local last = o.at
  if o.sender == self.name then
    local mine = self.outgoing[o.oid]
    if mine and not mine.cancelled and #mine.pending > 0 then
      return true
    end
  else
    last = math.max(last, self.heard[o.sender] or 0)
  end
  return self.now() - last < V2.OFFER_FRESH
end

-- build the object (the host may take a while: a background job) and queue it
function V2:answer(shard, kind, ref)
  local k = objKey(shard, kind, ref)
  for _, o in pairs(self.outgoing) do
    if o.k == k and not o.cancelled and (#o.pending > 0 or self.now() - (o.doneAt or 0) < V2.OFFER_FRESH) then
      return -- already on its way
    end
  end
  self.host:Object(shard, kind, ref, function(obj)
    if obj then
      self:startSending(shard, obj)
    end
  end)
end

function V2:startSending(shard, obj)
  self.serial = self.serial + 1
  local oid = b36(floor(self.random() * 1679616)) .. b36(self.serial % 36)
  local blocks = {}
  local payload = obj.payload
  for i = 1, #payload, V2.BLOCK do
    blocks[#blocks + 1] = payload:sub(i, i + V2.BLOCK - 1)
  end
  local pending, pendingSet = {}, {}
  for i = 1, #blocks do
    pending[i], pendingSet[i] = i, true
  end
  local o = {
    oid = oid,
    shard = shard,
    k = objKey(shard, obj.kind, obj.ref),
    kind = obj.kind,
    ref = obj.ref,
    t = obj.t,
    src = obj.src,
    key = obj.key,
    n = #blocks,
    len = #payload,
    sum = V2.Checksum(payload),
    blocks = blocks,
    pending = pending,
    pendingSet = pendingSet,
  }
  self.outgoing[oid] = o
  -- in turn by kind (fresh scans, then hours, then whole days: a day takes half an hour), never ahead of the one
  -- under way
  local at = #self.order + 1
  for i = 2, #self.order do
    if (PRIORITY[self.order[i].kind] or 9) > (PRIORITY[o.kind] or 9) then
      at = i
      break
    end
  end
  table.insert(self.order, at, o)
  self.offers[o.k] = { sender = self.name, oid = oid, at = self.now() }
  -- the offer goes out now, ahead of other objects' blocks: it claims the object, so other holders stay quiet
  self.control[#self.control + 1] = V2.EncodeOffer(shard, o)
  self:wake()
end

function V2:wantsTo(shard, kind, ref)
  return self.host:Wanted(shard, kind, ref)
end

function V2:OnMessage(msg, sender)
  local m = V2.Decode(msg)
  local who = self.key(sender)
  if not m or who == self.me then
    return
  end
  local now = self.now()
  if m.type == "block" or m.type == "offer" then
    self.heard[sender] = now -- sending something: what "still sending" and "stalled" go by
  end
  if m.type == "block" then
    local id = sender .. "\n" .. m.oid
    local k = self.offerOf[id]
    if k and self.offers[k] then
      self.offers[k].at = now
    end
    local inc = self.incoming[id]
    if inc and m.i and m.i >= 1 and m.i <= inc.n and not inc.blocks[m.i] then
      inc.blocks[m.i], inc.got, inc.lastAt = m.bytes, inc.got + 1, now
      if inc.got == inc.n then
        self:complete(id, inc)
      end
    end
    if not k and not inc then
      self:askOffer(sender, m.oid, id) -- I missed its offer (lost, or I logged in since)
    end
  elseif m.type == "manifest" then
    if not self.host:Allowed(m.shard, sender) then
      return
    end
    -- ask after a random moment, for what nobody else asked for meanwhile (everyone hears a manifest at once)
    local list = {}
    for _, w in ipairs(self.host:Wants(m.shard, m)) do
      local k = objKey(m.shard, w.kind, w.ref)
      if not self.asking[k] then
        list[#list + 1] = { k = k, kind = w.kind, ref = w.ref }
      end
    end
    if #list == 0 then
      return
    end
    for _, w in ipairs(list) do
      self.asking[w.k] = true
    end
    self.after(self.random() * V2.REQUEST_DELAY, function()
      local t = self.now()
      local asked = 0
      for _, w in ipairs(list) do
        self.asking[w.k] = nil
        local last = self.requested[w.k]
        if
          asked < V2.MAX_REQUESTS
          and not self:inProgress(w.k)
          and not (last and t - last < V2.REQUEST_COOLDOWN)
          and self:wantsTo(m.shard, w.kind, w.ref)
        then
          self.requested[w.k] = t
          self:queue(V2.EncodeRequest(m.shard, w.kind, w.ref))
          asked = asked + 1
        end
      end
    end)
  elseif m.type == "request" then
    if not self.host:Allowed(m.shard, sender) then
      return
    end
    local k = objKey(m.shard, m.kind, m.ref)
    self.requested[k] = now -- someone asked: I needn't ask for it too
    if self.answering[k] or self:inProgress(k) or not self.host:Has(m.shard, m.kind, m.ref) then
      return
    end
    self.answering[k] = true
    self.after(self.random() * V2.ANSWER_DELAY, function()
      self.answering[k] = nil
      if not self:inProgress(k) then
        self:answer(m.shard, m.kind, m.ref)
      end
    end)
  elseif m.type == "offer" then
    if not self.host:Allowed(m.shard, sender) then
      return
    end
    local k = objKey(m.shard, m.kind, m.ref)
    local id = sender .. "\n" .. m.oid
    self.offers[k] = { sender = sender, oid = m.oid, at = now }
    self.offerOf[id] = k
    -- the same object offered by me too: the name sorting first keeps sending
    for _, o in pairs(self.outgoing) do
      if o.k == k and #o.pending > 0 and who < self.me then
        o.cancelled = true
      end
    end
    if self.incoming[id] or not (m.n and m.n >= 1 and m.n <= 100000) then
      return
    end
    local carried
    for other, inc in pairs(self.incoming) do
      if inc.k == k then
        local theirs = self.key(inc.sender)
        if who <= theirs then
          -- a new offer of it from the same sender, or from one sorting first (the other stops): this one counts;
          -- the same content (length and checksum) keeps the blocks we have
          self.incoming[other] = nil
          if inc.len == m.len and inc.sum == m.sum and inc.n == m.n then
            carried = inc
          end
        else
          return -- already getting it from someone
        end
      end
    end
    if self:wantsTo(m.shard, m.kind, m.ref) then
      self.incoming[id] = {
        sender = sender,
        oid = m.oid,
        k = k,
        shard = m.shard,
        kind = m.kind,
        ref = m.ref,
        t = m.t,
        src = m.src,
        key = m.key,
        n = m.n,
        len = m.len,
        sum = m.sum,
        blocks = carried and carried.blocks or {},
        got = carried and carried.got or 0,
        lastAt = now,
        nacks = 0,
      }
      self:watch()
    end
  elseif m.type == "missing" then
    if self.key(m.target) == self.me then
      local o = self.outgoing[m.oid]
      if o and not o.cancelled then
        if #m.blocks == 0 then -- "what is this?": its offer again
          self:queue(V2.EncodeOffer(o.shard, o))
          return
        end
        local added = false
        for _, i in ipairs(m.blocks) do
          if o.blocks[i] and not o.pendingSet[i] then
            o.pending[#o.pending + 1], o.pendingSet[i] = i, true
            added = true
          end
        end
        if added then
          local listed = false
          for _, x in ipairs(self.order) do
            listed = listed or x == o
          end
          if not listed then
            self.order[#self.order + 1] = o
          end
          self:wake()
        end
      end
    else
      self.nacked[m.target .. "\n" .. m.oid] = now
    end
  end
end

-- blocks of an object whose offer I never heard: ask its sender for the offer (an empty missing list), once, after a
-- random moment unless someone else asked (their answer reaches me too)
function V2:askOffer(sender, oid, id)
  if self.offerAsked[id] then
    return
  end
  self.offerAsked[id] = true
  self.after(self.random() * V2.NACK_DELAY, function()
    local other = self.nacked[id]
    if not self.offerOf[id] and not (other and self.now() - other < V2.STALL) then
      self:queue(V2.EncodeMissing(sender, oid, {}))
      self.nacked[id] = self.now()
    end
  end)
end

function V2:complete(id, inc)
  self.incoming[id] = nil
  local payload = concat(inc.blocks)
  if #payload ~= inc.len then
    self.stats.bad = self.stats.bad + 1
    return
  end
  local obj = { kind = inc.kind, ref = inc.ref, t = inc.t, src = inc.src, key = inc.key, payload = payload }
  -- the checksum over a whole object (~170 KB for a full scan) is a few ms of work: a host that does it in its
  -- background work (host.verifiesSum: in combat, that waits) gets the sum to check; otherwise it's checked here
  if self.host.verifiesSum then
    obj.sum = inc.sum
  elseif V2.Checksum(payload) ~= inc.sum then
    self.stats.bad = self.stats.bad + 1
    return
  end
  self.stats.objectsReceived = self.stats.objectsReceived + 1
  self.host:Accept(inc.shard, obj, inc.sender)
end

-- check incoming objects every CHECK_EVERY while there are any: a stalled one asks for its missing blocks
function V2:watch()
  if self.watching then
    return
  end
  self.watching = true
  self.after(V2.CHECK_EVERY, function()
    self.watching = false
    self:check()
  end)
end

function V2:check()
  local now = self.now()
  for id, inc in pairs(self.incoming) do
    -- stalled: nothing of it lately, and the sender has gone quiet (not busy sending something else first)
    if now - math.max(inc.lastAt, self.heard[inc.sender] or 0) >= V2.STALL and not inc.asking then
      local seen = self.nacked[id]
      if inc.nacks >= V2.MAX_NACKS then
        self.incoming[id] = nil -- asked for again on a later manifest
        self.requested[inc.k] = nil
      elseif seen and now - seen < V2.STALL then
        inc.lastAt = now -- someone else asked for the missing blocks: their resend reaches us too
      else
        inc.asking = true
        self.after(self.random() * V2.NACK_DELAY, function()
          inc.asking = nil
          if self.incoming[id] ~= inc then
            return
          end
          local t = self.now()
          local other = self.nacked[id]
          if not (other and t - other < V2.STALL) then
            local missing = {}
            for i = 1, inc.n do
              if not inc.blocks[i] then
                missing[#missing + 1] = i
              end
            end
            self:queue(V2.EncodeMissing(inc.sender, inc.oid, missing))
            self.nacked[id] = t
            inc.nacks = inc.nacks + 1
          end
          inc.lastAt = t
        end)
      end
    end
  end
  -- forget sent objects nobody can still ask about
  for oid, o in pairs(self.outgoing) do
    if (o.cancelled or #o.pending == 0) and now - (o.doneAt or now) > V2.KEEP_SENT then
      self.outgoing[oid] = nil
    end
  end
  if next(self.incoming) then
    self:watch()
  end
end

-- what's going on, for the Sharing status: sending = { kind, ref, sent, n } or nil, queued = objects waiting,
-- receiving = { { kind, ref, got, n, from }, ... }
function V2:Status()
  local s = { queued = 0, receiving = {} }
  for _, o in ipairs(self.order) do
    if not o.cancelled and #o.pending > 0 then
      if not s.sending then
        s.sending = { kind = o.kind, ref = o.ref, sent = o.n - #o.pending, n = o.n }
      else
        s.queued = s.queued + 1
      end
    end
  end
  for _, inc in pairs(self.incoming) do
    s.receiving[#s.receiving + 1] = { kind = inc.kind, ref = inc.ref, got = inc.got, n = inc.n, from = inc.sender }
  end
  return s
end

-- incoming objects, to save at logout (Restore resumes them: the missing blocks are asked for)
function V2:Save()
  local out = {}
  for _, inc in pairs(self.incoming) do
    out[#out + 1] = {
      sender = inc.sender,
      oid = inc.oid,
      shard = inc.shard,
      kind = inc.kind,
      ref = inc.ref,
      t = inc.t,
      src = inc.src,
      key = inc.key,
      n = inc.n,
      len = inc.len,
      sum = inc.sum,
      blocks = inc.blocks,
    }
  end
  return out
end

function V2:Restore(saved)
  local now = self.now()
  for _, s in ipairs(saved or {}) do
    if type(s) == "table" and s.sender and s.oid and type(s.blocks) == "table" and s.n then
      local got = 0
      for i = 1, s.n do
        got = got + (type(s.blocks[i]) == "string" and 1 or 0)
      end
      local id = s.sender .. "\n" .. s.oid
      s.k, s.got, s.lastAt, s.nacks = objKey(s.shard, s.kind, s.ref), got, now - V2.STALL, 0
      self.incoming[id] = s
      self.offerOf[id] = s.k
    end
  end
  if next(self.incoming) then
    self:watch()
  end
end
