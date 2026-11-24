-- Craft requests between players (docs/ux/redesign-review.md, "Social crafting"; boards GuildRequests, RequestForm,
-- RequestAnswer, RequestReview). One player asks another's character to make something; the terms travel with the
-- request as data, the message as text.
--
--   record = { id, asker, crafter, recipe, item?, count, reagents = { { item, need, bring, soulbound? }, ... },
--              offer (copper, for the crafter's mats), tip (copper), message, state, by ("asker" | "crafter": who
--              wrote the terms as they stand), rev (the terms' revision), seq (every change), at, changed,
--              prev = { offer, tip, bring = { n, ... } }? (the terms before the last revision: what changed is lit),
--              note? (the last answer's message), side ("asker" | "crafter": which one you are; local) }
--   states: new > answered (only when someone changes the terms) > accepted > crafted > handed; or declined (the
--   crafter says no) / withdrawn (the asker). Either side can keep answering; it is agreed when one accepts the
--   other's last terms as they stand.
--
-- Pure (times and game facts passed in): New, Answer, Accept, Decline, Crafted, Handed, ToAct, Changed, Supply,
-- Encode / Decode, Merge, Draft / Refresh (the form), SuggestTip, Message, WhisperText.
-- In game: CraftRequests.DB() (AME_DB.craftRequests), Send (an outbox, resent until the counterpart's AME
-- acknowledges), OnMessage (SyncService hands it the "X" messages), Incoming() (Home's REQUEST rows).
local _, ns = ...
local L = ns.L

local R = {}
ns.CraftRequests = R

R.RESEND = 120 -- seconds between sends of an unacknowledged change
R.MAX_TRIES = 30 -- then it waits for the counterpart to be online again (a whisper when they are heard)
R.KEEP = 7 * 86400 -- handed over, declined and withdrawn requests clear after a week
R.MAX_MESSAGE = 200
R.MAX_REAGENTS = 12

R.ORDER = { "new", "answered", "accepted", "crafted", "handed" }
R.RANK = { new = 1, answered = 2, accepted = 3, crafted = 4, handed = 5, declined = 6, withdrawn = 6 }
R.ENDED = { handed = true, declined = true, withdrawn = true }

local function b36(n)
  return ns.Codec.ToBase36(math.max(0, math.floor(tonumber(n) or 0)))
end

local function n36(s)
  if s == nil or s == "" then
    return nil
  end
  return ns.Codec.FromBase36(s)
end

local function clean(s)
  return (tostring(s or ""):gsub("[|;\r\n]", " "))
end

-- the message: it rides last, so only the chat escape and line breaks go
local function cleanText(s)
  return (tostring(s or ""):gsub("[|\r\n]", " "))
end

local function other(side)
  return side == "asker" and "crafter" or "asker"
end
R.Other = other

-- ------------------------------------------------------------------------------------------------ the record

function R.NewId(me, now, n)
  return clean(me):gsub("[%s%-:]", "") .. "-" .. b36(now) .. "-" .. b36(n or 0)
end

-- f: { id, asker, crafter, recipe, item?, count, reagents, offer, tip, message }
function R.New(f, now)
  local reagents = {}
  for i, g in ipairs(f.reagents or {}) do
    if i > R.MAX_REAGENTS then
      break
    end
    reagents[i] = {
      item = g.item,
      need = g.need or 0,
      bring = g.soulbound and 0 or math.max(0, math.min(g.bring or 0, g.need or 0)),
      soulbound = g.soulbound or nil,
    }
  end
  return {
    id = f.id,
    asker = f.asker,
    crafter = f.crafter,
    recipe = f.recipe,
    item = f.item,
    count = math.max(1, f.count or 1),
    reagents = reagents,
    offer = math.max(0, f.offer or 0),
    tip = math.max(0, f.tip or 0),
    message = cleanText(f.message):sub(1, R.MAX_MESSAGE),
    state = "new",
    by = "asker",
    rev = 1,
    seq = 1,
    at = now,
    changed = now,
    side = "asker",
  }
end

function R.Terms(r)
  local bring = {}
  for i, g in ipairs(r.reagents or {}) do
    bring[i] = g.bring or 0
  end
  return { offer = r.offer or 0, tip = r.tip or 0, bring = bring }
end

function R.SameTerms(a, b)
  if (a.offer or 0) ~= (b.offer or 0) or (a.tip or 0) ~= (b.tip or 0) then
    return false
  end
  local ab, bb = a.bring or {}, b.bring or {}
  for i = 1, math.max(#ab, #bb) do
    if (ab[i] or 0) ~= (bb[i] or 0) then
      return false
    end
  end
  return true
end

-- what the last revision changed: { offer = bool, tip = bool, bring = { [i] = bool }, any = bool }
function R.Changed(r)
  local out = { bring = {}, any = false }
  local p = r.prev
  if not p then
    return out
  end
  out.offer = (p.offer or 0) ~= (r.offer or 0)
  out.tip = (p.tip or 0) ~= (r.tip or 0)
  out.any = out.offer or out.tip
  for i, g in ipairs(r.reagents or {}) do
    out.bring[i] = (p.bring and p.bring[i] or 0) ~= (g.bring or 0)
    out.any = out.any or out.bring[i]
  end
  return out
end

-- who has to do something next: "crafter", "asker", "both" (hand it over) or nil (it's over)
function R.ToAct(r)
  if r.state == "new" or r.state == "answered" then
    return other(r.by)
  elseif r.state == "accepted" then
    return "crafter"
  elseif r.state == "crafted" then
    return "both"
  end
  return nil
end

-- is it yours to act on? (side: which one you are)
function R.Mine(r, side)
  local who = R.ToAct(r)
  return who == "both" or who == (side or r.side)
end

local function touch(r, now)
  r.seq = (r.seq or 0) + 1
  r.changed = now
end

-- answer with terms { offer?, tip?, bring? }: the same terms as they stand accept them; any change goes back to the
-- other side. -> "accepted" | "answered" | nil, why
function R.Answer(r, side, terms, message, now)
  local open = r.state == "new" or r.state == "answered"
  local cur = R.Terms(r)
  local new = { offer = terms.offer or cur.offer, tip = terms.tip or cur.tip, bring = terms.bring or cur.bring }
  if side == "crafter" then
    new.bring = cur.bring -- the crafter prices their part; the split is the asker's
  end
  if open and r.by == side and R.ToAct(r) ~= side then
    -- your own terms, not answered yet: changed in place (they still wait on the other side)
    if R.SameTerms(cur, new) and not message then
      return nil, "nothing changed"
    end
    r.offer, r.tip = math.max(0, new.offer), math.max(0, new.tip)
    for i, g in ipairs(r.reagents) do
      if not g.soulbound then
        g.bring = math.max(0, math.min(new.bring[i] or 0, g.need or 0))
      end
    end
    if message and message ~= "" then
      if side == "asker" then
        r.message = cleanText(message):sub(1, R.MAX_MESSAGE)
      else
        r.note = clean(message):sub(1, R.MAX_MESSAGE)
      end
    end
    r.rev = (r.rev or 1) + 1
    touch(r, now)
    return "revised"
  end
  if not open or R.ToAct(r) ~= side then
    return nil, "not yours to answer"
  end
  if R.SameTerms(cur, new) then
    R.Accept(r, side, now)
    r.note = message and message ~= "" and clean(message):sub(1, R.MAX_MESSAGE) or r.note
    return "accepted"
  end
  r.prev = cur
  r.offer, r.tip = math.max(0, new.offer), math.max(0, new.tip)
  for i, g in ipairs(r.reagents) do
    if not g.soulbound then
      g.bring = math.max(0, math.min(new.bring[i] or 0, g.need or 0))
    end
  end
  r.by, r.rev, r.state = side, (r.rev or 1) + 1, "answered"
  local said = message and message ~= "" and message or nil
  if side == "asker" then
    -- the crafter reads the asker's message, the asker the crafter's note
    r.message = said and cleanText(said):sub(1, R.MAX_MESSAGE) or r.message
  else
    r.note = said and clean(said):sub(1, R.MAX_MESSAGE) or nil
  end
  touch(r, now)
  return "answered"
end

-- agree to the other side's last terms as they stand
function R.Accept(r, side, now)
  if R.ToAct(r) ~= side or not (r.state == "new" or r.state == "answered") then
    return false
  end
  r.state = "accepted"
  touch(r, now)
  return true
end

-- the crafter declines, the asker withdraws: it ends either way
function R.Decline(r, side, now)
  if R.ENDED[r.state] then
    return false
  end
  r.state = side == "crafter" and "declined" or "withdrawn"
  touch(r, now)
  return true
end

function R.Crafted(r, now)
  if r.state ~= "accepted" then
    return false
  end
  r.state = "crafted"
  touch(r, now)
  return true
end

function R.Handed(r, now)
  if r.state ~= "crafted" and r.state ~= "accepted" then
    return false
  end
  r.state = "handed"
  touch(r, now)
  return true
end

-- what the crafter supplies: { { item, n, soulbound }, ... }
function R.Supply(r)
  local out = {}
  for _, g in ipairs(r.reagents or {}) do
    local n = (g.need or 0) - (g.soulbound and 0 or (g.bring or 0))
    if n > 0 then
      out[#out + 1] = { item = g.item, n = n, soulbound = g.soulbound }
    end
  end
  return out
end

-- who brings the mats, in a word: "all" | "most" | "some" | "none"
function R.Brings(r)
  local need, bring = 0, 0
  for _, g in ipairs(r.reagents or {}) do
    need, bring = need + (g.need or 0), bring + (g.soulbound and 0 or (g.bring or 0))
  end
  if need == 0 or bring >= need then
    return "all"
  elseif bring == 0 then
    return "none"
  end
  return bring * 2 >= need and "most" or "some"
end

-- ------------------------------------------------------------------------------------------------ on the wire

-- the record as text (no "|": it rides in a sync message). "R;<fields>;<message>" - the message last, as it is
local FIELDS = 16 -- after the "R": id .. note; the message is the 18th
function R.Encode(r)
  local reagents = {}
  for i, g in ipairs(r.reagents or {}) do
    reagents[i] = table.concat({ b36(g.item), b36(g.need), b36(g.bring), g.soulbound and "1" or "0" }, ":")
  end
  local prevBring = {}
  for i, n in ipairs(r.prev and r.prev.bring or {}) do
    prevBring[i] = b36(n)
  end
  return table.concat({
    "R",
    clean(r.id),
    b36(r.seq),
    b36(r.rev),
    r.state,
    r.by,
    clean(r.asker),
    clean(r.crafter),
    b36(r.recipe),
    r.item and b36(r.item) or "",
    b36(r.count),
    b36(r.offer),
    b36(r.tip),
    table.concat(reagents, ","),
    r.prev and (b36(r.prev.offer) .. ":" .. b36(r.prev.tip) .. ":" .. table.concat(prevBring, ",")) or "",
    b36(r.at),
    clean(r.note or ""):sub(1, R.MAX_MESSAGE),
    cleanText(r.message):sub(1, R.MAX_MESSAGE),
  }, ";")
end

function R.EncodeAck(id, seq)
  return table.concat({ "A", clean(id), b36(seq) }, ";")
end

local function split(s, sep, limit)
  local out, start = {}, 1
  while true do
    if limit and #out == limit - 1 then
      out[#out + 1] = s:sub(start)
      return out
    end
    local at = s:find(sep, start, true)
    if not at then
      out[#out + 1] = s:sub(start)
      return out
    end
    out[#out + 1] = s:sub(start, at - 1)
    start = at + 1
  end
end

-- -> { kind = "ack", id, seq } | { kind = "record", record } | nil
function R.Decode(body)
  if type(body) ~= "string" then
    return nil
  end
  local ok, out = pcall(function()
    local kind = body:sub(1, 2)
    if kind == "A;" then
      local f = split(body, ";")
      if #f == 3 and f[2] ~= "" then
        return { kind = "ack", id = f[2], seq = n36(f[3]) }
      end
      return nil
    elseif kind ~= "R;" then
      return nil
    end
    local f = split(body, ";", FIELDS + 2)
    if #f ~= FIELDS + 2 or not R.RANK[f[5]] or (f[6] ~= "asker" and f[6] ~= "crafter") then
      return nil
    end
    local reagents = {}
    for g in f[14]:gmatch("[^,]+") do
      local item, need, bring, sb = g:match("^(%w+):(%w+):(%w+):([01])$")
      if item and #reagents < R.MAX_REAGENTS then
        reagents[#reagents + 1] =
          { item = n36(item), need = n36(need), bring = n36(bring), soulbound = sb == "1" or nil }
      end
    end
    local prev
    if f[15] ~= "" then
      local po, pt, pb = f[15]:match("^(%w+):(%w+):([%w,]*)$")
      if po then
        prev = { offer = n36(po), tip = n36(pt), bring = {} }
        for n in pb:gmatch("[^,]+") do
          prev.bring[#prev.bring + 1] = n36(n)
        end
      end
    end
    local r = {
      id = f[2],
      seq = n36(f[3]) or 1,
      rev = n36(f[4]) or 1,
      state = f[5],
      by = f[6],
      asker = f[7],
      crafter = f[8],
      recipe = n36(f[9]),
      item = n36(f[10]),
      count = math.max(1, n36(f[11]) or 1),
      offer = n36(f[12]) or 0,
      tip = n36(f[13]) or 0,
      reagents = reagents,
      prev = prev,
      at = n36(f[16]),
      note = f[17] ~= "" and f[17] or nil,
      message = f[18],
    }
    if r.id == "" or r.asker == "" or r.crafter == "" or not r.recipe then
      return nil
    end
    return { kind = "record", record = r }
  end)
  return ok and out or nil
end

-- take in a record that arrived: new ones are stored, a known one is replaced when the copy is newer (more changes),
-- a stale copy is ignored. side: which one you are. -> stored, "new" | "changed" | nil
function R.Merge(list, incoming, side, now)
  local cur = list[incoming.id]
  if cur then
    if (incoming.seq or 0) <= (cur.seq or 0) then
      return cur, nil
    end
    -- an ended request stays ended (a late copy of an older change can't revive it)
    if R.ENDED[cur.state] and not R.ENDED[incoming.state] then
      return cur, nil
    end
  end
  incoming.side = side
  incoming.changed = now
  list[incoming.id] = incoming
  return incoming, cur and "changed" or "new"
end

-- handed over, declined and withdrawn requests go after a while
function R.Prune(list, now)
  for id, r in pairs(list) do
    if R.ENDED[r.state] and now - (r.changed or 0) > R.KEEP then
      list[id] = nil
    end
  end
end

-- ------------------------------------------------------------------------------------------------ the form

-- a round tip: to the gold above one, the silver below
function R.Round(copper)
  copper = math.max(0, math.floor((copper or 0) + 0.5))
  if copper >= 10000 then
    return math.floor(copper / 10000 + 0.5) * 10000
  elseif copper >= 100 then
    return math.floor(copper / 100 + 0.5) * 100
  end
  return copper
end

R.TIP_SHARE = 0.1 -- a fair tip: about a tenth of what the craft adds
function R.SuggestTip(adds)
  if not adds or adds <= 0 then
    return 0
  end
  return R.Round(adds * R.TIP_SHARE)
end

-- what the craft is worth: sells (each, or nil: an enchant), mats at market -> { sells, mats, adds }
function R.Worth(count, each, mats)
  local sells = each and each * count or nil
  return { sells = sells, mats = mats, adds = sells and mats and (sells - mats) or nil }
end

-- A draft request (the form). opts = { recipe = Recipes.Get's, count, crafter, held = fn(item) -> n,
-- price = fn(item) -> copper?, soulbound = fn(item) -> bool, sells = fn(item) -> copper?, tip = copper? (the
-- crafter's own tip for it) }. The rows start ticked at what you hold, capped at the need.
function R.Draft(opts)
  local recipe = opts.recipe or {}
  local d = {
    recipe = recipe.id,
    item = recipe.product,
    made = recipe.made or 1,
    count = math.max(1, opts.count or 1),
    crafter = opts.crafter,
    rows = {},
    fixedTip = opts.tip,
  }
  for i, g in ipairs(recipe.reagents or {}) do
    if i > R.MAX_REAGENTS then
      break
    end
    local id = g[1] or g.item
    local sb = opts.soulbound and opts.soulbound(id) or false
    local hold = opts.held and opts.held(id) or 0
    d.rows[i] = { item = id, per = g[2] or g.n or 1, hold = hold, soulbound = sb or nil, checked = not sb and hold > 0 }
  end
  R.Refresh(d, opts)
  return d
end

-- work the draft out again after a change (count, a tick, a bring count, the offer or tip typed in)
function R.Refresh(d, opts)
  opts = opts or {}
  local crafts = math.ceil(d.count / math.max(1, d.made or 1))
  local supplyValue, mats, priced = 0, 0, true
  for _, row in ipairs(d.rows) do
    row.need = row.per * crafts
    if row.soulbound then
      row.bring, row.checked = 0, false
    elseif not row.checked then
      row.bring = 0
    else
      -- ticked: what you set, else what you hold (all of it when you hold none: you will get it)
      local want = row.bringSet or ((row.hold or 0) > 0 and row.hold or row.need)
      row.bring = math.max(0, math.min(want, row.need))
    end
    row.supply = row.need - row.bring
    local p = opts.price and opts.price(row.item)
    row.copper = p and p * row.supply or nil
    if p then
      supplyValue = supplyValue + p * row.supply
      mats = mats + p * row.need
    elseif row.supply > 0 then
      priced = false
    end
  end
  d.market = supplyValue
  d.priced = priced
  if not d.offerSet then
    d.offer = R.Round(supplyValue)
  end
  local each = d.item and opts.sells and opts.sells(d.item) or nil
  d.worth = R.Worth(d.count, each, mats)
  local base = d.worth.adds or (not d.item and mats) or nil -- an enchant: a tenth of its mats
  d.suggested = d.fixedTip or R.SuggestTip(base)
  if not d.tipSet then
    d.tip = d.suggested
  end
  d.total = (d.offer or 0) + (d.tip or 0)
  if not d.messageSet then
    d.message = R.Message(d, opts.name)
  end
  return d
end

local function g(copper)
  return ns.Widgets and ns.Widgets.Money and ns.Widgets.Money(copper, true) or tostring(copper)
end
local function plain(text)
  return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end
R.Plain = plain

-- the message, written from the terms (plain text: it is yours to edit, and the item link goes in front of it)
function R.Message(d, name)
  name = name or function(id)
    return ns.ItemCache and ns.ItemCache.Name(id) or ("item:" .. tostring(id))
  end
  local parts = { d.count > 1 and L["Could you make these for me?"] or L["Could you make this for me?"] }
  local brings, supplies = {}, false
  for _, row in ipairs(d.rows or d.reagents or {}) do
    local b = row.bring or 0
    if b > 0 then
      brings[#brings + 1] = (b >= (row.need or 0) and L["the %s"]:format(name(row.item) or "?"))
        or ("%d %s"):format(b, name(row.item) or "?")
    end
    if (row.need or 0) - b > 0 then
      supplies = true
    end
  end
  if #brings > 0 then
    local list = #brings == 1 and brings[1]
      or table.concat(brings, ", ", 1, #brings - 1) .. " " .. L["and"] .. " " .. brings[#brings]
    parts[#parts + 1] = L["I bring %s."]:format(list)
  end
  local offer, tip = d.offer or 0, d.tip or 0
  if supplies and offer > 0 and tip > 0 then
    parts[#parts + 1] = L["%s for the rest, and a %s tip."]:format(plain(g(offer)), plain(g(tip)))
  elseif supplies and offer > 0 then
    parts[#parts + 1] = L["%s for the rest."]:format(plain(g(offer)))
  elseif supplies then
    parts[#parts + 1] = L["Could you cover the rest?"]
    if tip > 0 then
      parts[#parts + 1] = L["A %s tip."]:format(plain(g(tip)))
    end
  elseif tip > 0 then
    parts[#parts + 1] = L["A %s tip."]:format(plain(g(tip)))
  end
  return table.concat(parts, " ")
end

-- the whisper a crafter without AME reads: the count and the item link in front of the message
function R.WhisperText(r, link)
  local text = ("%d × %s: %s"):format(r.count or 1, link or "?", plain(r.message or ""))
  return text:sub(1, 255)
end

-- ------------------------------------------------------------------------------------------------ in game

function R.DB()
  if not AME_DB then
    return nil
  end
  local db = AME_DB.craftRequests or {}
  AME_DB.craftRequests = db
  db.list = db.list or {} -- [id] = record
  db.outbox = db.outbox or {} -- [id] = { to, seq, tries, next }
  db.tips = db.tips or {} -- [recipeID] = copper: your own tip, what the form suggests to others
  db.taking = db.taking or {} -- ["<charName>:<skillLine>"] = true: taking orders
  db.n = db.n or 0
  return db
end

local function me()
  return UnitName and UnitName("player") or "?"
end

local function nameKey(name)
  local c = tostring(name or ""):match("^%s*([^%-%s]+)")
  return c and c:lower() or ""
end
R.NameKey = nameKey

local function isMine(name)
  if nameKey(name) == nameKey(me()) then
    return true
  end
  local svc = ns.SyncService
  return svc and svc.IsMine and svc:IsMine(name) or false
end
R.IsMine = isMine

function R.List()
  local db = R.DB()
  local out = {}
  for _, r in pairs(db and db.list or {}) do
    out[#out + 1] = r
  end
  table.sort(out, function(a, b)
    return (a.changed or 0) > (b.changed or 0)
  end)
  return out
end

function R.Get(id)
  local db = R.DB()
  return db and db.list[id]
end

local function changed()
  if ns.Events and ns.Events.Fire then
    ns.Events.Fire("CraftRequestsChanged")
  end
  if ns.Home and ns.Home.Forget then
    ns.Home.Forget()
  end
  local app = ns.App
  if app and app.frame and app.frame.IsShown and app.frame:IsShown() and app.Redraw then
    app:Redraw()
  end
end
R.Notify = changed

-- guild members (the roster) by character name
local roster, rosterAt
function R.InGuild(name)
  local now = GetTime and GetTime() or 0
  if not roster or now - (rosterAt or 0) > 30 then
    roster, rosterAt = {}, now
    local count = _G.GetNumGuildMembers and _G.GetNumGuildMembers() or 0
    for i = 1, count do
      local ok, full, _, _, _, _, _, _, _, online = pcall(_G.GetGuildRosterInfo, i)
      if ok and full then
        roster[nameKey(full)] = online and "online" or "offline"
      end
    end
  end
  return roster[nameKey(name)] ~= nil, roster[nameKey(name)] == "online"
end

function R.Online(name)
  if isMine(name) then
    return true
  end
  local _, online = R.InGuild(name)
  return online
end

local function transport()
  local svc = ns.SyncService
  return svc and svc.enabled and svc.transport or nil
end

local function shard()
  local AME = ns.AME
  return AME and AME.CurrentShard and AME:CurrentShard() or nil
end

-- send a record's current state to the counterpart, now and again until their AME acknowledges it
function R.Send(r, now)
  local db = R.DB()
  if not db then
    return
  end
  local to = r.side == "crafter" and r.asker or r.crafter
  db.outbox[r.id] = { to = to, seq = r.seq, tries = 0, next = 0 }
  R.Flush(now)
end

function R.Flush(now)
  local db, t = R.DB(), transport()
  local s = shard()
  if not (db and t and s and ns.Sync and ns.Sync.EncodeCraft) then
    return 0
  end
  now = now or GetServerTime()
  local sent = 0
  for id, o in pairs(db.outbox) do
    local r = db.list[id]
    if not r then
      db.outbox[id] = nil
    elseif o.tries < R.MAX_TRIES and now >= (o.next or 0) then
      o.tries, o.next, o.seq = o.tries + 1, now + R.RESEND, r.seq
      local ok = pcall(t.Send, t, ns.SyncService.PREFIX, ns.Sync.EncodeCraft(s, R.Encode(r)), "WHISPER", o.to)
      if ok then
        sent = sent + 1
      end
    end
  end
  return sent
end

-- the counterpart was heard from (any message): what waits for them goes again
function R.Heard(sender)
  local db = R.DB()
  for _, o in pairs(db and db.outbox or {}) do
    if nameKey(o.to) == nameKey(sender) and o.tries >= R.MAX_TRIES then
      o.tries, o.next = R.MAX_TRIES - 1, 0
    end
  end
end

local function notice(r, text)
  local notices = ns.AME and ns.AME.notices
  if notices and notices.Add then
    notices:Add({ kind = "craft", text = text, itemID = r.item, who = r.side == "crafter" and r.asker or r.crafter },
      GetServerTime())
  end
end

-- a craft message from SyncService (the "X" kind, whispered, from a guild member or a trusted player)
function R.OnMessage(body, sender)
  local m = R.Decode(body)
  local db = R.DB()
  if not (m and db) then
    return false
  end
  local now = GetServerTime()
  if m.kind == "ack" then
    local o = db.outbox[m.id]
    if o and (m.seq or 0) >= (o.seq or 0) then
      db.outbox[m.id] = nil
    end
    return true
  end
  local r = m.record
  -- it must be between the sender and one of my characters
  local side
  if isMine(r.crafter) and nameKey(sender) == nameKey(r.asker) then
    side = "crafter"
  elseif isMine(r.asker) and nameKey(sender) == nameKey(r.crafter) then
    side = "asker"
  else
    return false
  end
  local stored, what = R.Merge(db.list, r, side, now)
  local t = transport()
  local s = shard()
  if t and s and ns.Sync.EncodeCraft then
    pcall(t.Send, t, ns.SyncService.PREFIX, ns.Sync.EncodeCraft(s, R.EncodeAck(stored.id, stored.seq)), "WHISPER", sender)
  end
  local o = db.outbox[stored.id]
  if o and (stored.seq or 0) >= (o.seq or 0) then
    db.outbox[stored.id] = nil -- theirs is newer than what we were sending
  end
  if what then
    local name = stored.item and ns.ItemCache and ns.ItemCache.Name(stored.item)
      or (ns.Crafters and ns.Crafters.RecipeName and ns.Crafters.RecipeName(stored.recipe))
      or "?"
    if what == "new" then
      notice(stored, L["%s asks for %d %s"]:format(stored.asker, stored.count, name))
    elseif stored.state == "answered" then
      notice(stored, L["%s answered the request for %s"]:format(side == "asker" and stored.crafter or stored.asker, name))
    elseif stored.state == "accepted" then
      notice(stored, L["%s agreed to make %s"]:format(stored.crafter, name))
      if side == "crafter" then
        R.Queue(stored)
      end
    elseif stored.state == "declined" or stored.state == "withdrawn" then
      notice(stored, L["The request for %s ended: %s"]:format(name, stored.state == "declined" and L["declined"] or L["withdrawn"]))
    end
    changed()
  end
  return true
end

-- agreed: it goes on the crafter's queue
function R.Queue(r)
  if not (AME_DB and ns.CraftQueue and r.recipe) then
    return false
  end
  AME_DB.craftQueue = AME_DB.craftQueue or {}
  local made = 1
  local rec = ns.Recipes and ns.Recipes.Get(r.recipe)
  if rec and rec.made and rec.made > 0 then
    made = rec.made
  end
  local ok = pcall(function()
    ns.CraftQueue.New(AME_DB.craftQueue):Add(r.recipe, math.ceil(r.count / made))
  end)
  return ok
end

-- ask: the draft becomes a request, sent through sync and as a whisper (for a crafter without AME)
function R.Create(d, crafter, now)
  local db = R.DB()
  if not db then
    return nil
  end
  now = now or GetServerTime()
  db.n = db.n + 1
  local reagents = {}
  for i, row in ipairs(d.rows or {}) do
    reagents[i] = { item = row.item, need = row.need, bring = row.bring, soulbound = row.soulbound }
  end
  local r = R.New({
    id = R.NewId(me(), now, db.n),
    asker = me(),
    crafter = crafter,
    recipe = d.recipe,
    item = d.item,
    count = d.count,
    reagents = reagents,
    offer = d.offer,
    tip = d.tip,
    message = d.message,
  }, now)
  db.list[r.id] = r
  R.Send(r, now)
  R.Whisper(r)
  changed()
  return r
end

-- the link a whisper puts in front: the product, else the recipe's spell
function R.Link(r)
  local link = r.item and ns.ItemCache and ns.ItemCache.Link and ns.ItemCache.Link(r.item)
  if link then
    return link
  end
  local spell = (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(r.recipe))
    or (_G.GetSpellLink and _G.GetSpellLink(r.recipe))
  return spell or (ns.Crafters and ns.Crafters.RecipeName and ns.Crafters.RecipeName(r.recipe)) or "?"
end

function R.Whisper(r)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
  if not send then
    return false
  end
  return pcall(send, R.WhisperText(r, R.Link(r)), "WHISPER", nil, r.crafter)
end

-- a change made here (answer, accept, decline, crafted, handed over): store and send it
function R.Act(id, fn, ...)
  local r = R.Get(id)
  if not r then
    return nil
  end
  local now = GetServerTime()
  local before = r.seq
  local result = fn(r, ...)
  if r.seq ~= before then
    if r.state == "accepted" and r.side == "crafter" then
      R.Queue(r)
    end
    R.Send(r, now)
    changed()
  end
  return result
end

function R.DoAnswer(id, terms, message)
  return R.Act(id, function(r)
    return R.Answer(r, r.side, terms, message, GetServerTime())
  end)
end

function R.DoAccept(id)
  return R.Act(id, function(r)
    return R.Accept(r, r.side, GetServerTime())
  end)
end

function R.DoDecline(id)
  return R.Act(id, function(r)
    return R.Decline(r, r.side, GetServerTime())
  end)
end

function R.DoCrafted(id)
  return R.Act(id, function(r)
    return R.Crafted(r, GetServerTime())
  end)
end

function R.DoHanded(id)
  return R.Act(id, function(r)
    return R.Handed(r, GetServerTime())
  end)
end

-- forget one (an ended request, or one the other side never answered)
function R.Remove(id)
  local db = R.DB()
  if db then
    db.list[id], db.outbox[id] = nil, nil
    changed()
  end
end

-- Home's REQUEST rows: requests asked of your characters that wait on you: { id, from, count, item, sub }
function R.Incoming()
  local out = {}
  for _, r in ipairs(R.List()) do
    if r.side == "crafter" and (r.state == "new" or r.state == "answered") and R.ToAct(r) == "crafter" then
      local brings = R.Brings(r)
      local sub = brings == "all" and L["brings the mats"] or brings == "none" and L["you provide the mats"]
        or L["brings some of the mats"]
      if (r.tip or 0) > 0 then
        sub = sub .. " · " .. L["%s tip"]:format(g(r.tip))
      end
      if not r.item then -- an enchant makes no item: its name leads the line under
        local name = ns.Crafters and ns.Crafters.RecipeName and ns.Crafters.RecipeName(r.recipe)
        sub = (name and (name .. " · ") or "") .. sub
      end
      out[#out + 1] = { id = r.id, from = r.asker, count = r.count, item = r.item, sub = sub }
    end
  end
  return out
end

-- how many wait on you (the Guild nav's count)
function R.Waiting()
  local n = 0
  for _, r in ipairs(R.List()) do
    if not R.ENDED[r.state] and R.ToAct(r) == r.side then
      n = n + 1
    end
  end
  return n
end

-- the resend clock, once logged in
function R.Start()
  if R.started or not (C_Timer and C_Timer.NewTicker) then
    return
  end
  R.started = true
  local db = R.DB()
  if db then
    R.Prune(db.list, GetServerTime())
  end
  C_Timer.NewTicker(R.RESEND / 4, function()
    pcall(R.Flush)
  end)
end

if CreateFrame then
  local f = CreateFrame("Frame")
  if f.RegisterEvent then
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
  end
  if f.SetScript then
    f:SetScript("OnEvent", function(self)
      if self.UnregisterEvent then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
      end
      if C_Timer and C_Timer.After then
        C_Timer.After(20, R.Start)
      end
    end)
  end
end
