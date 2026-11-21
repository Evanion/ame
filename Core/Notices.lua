-- Notifications: what AME told you in passing (alerts that fired, sharing requests), kept so it can be read later
-- in the window's notification center (the bell by the tabs) - a chat line scrolls away, a message on screen fades.
-- Pure: state lives in a plain table (AME_DB.notices), times are passed in.
--
--   db = { list = { { kind, text, itemID?, who?, at }, ... } (oldest first), readAt = time last opened }
--
-- kinds: "alert" (text: what happened, itemID: the item), "request" (who: the player asking to share)
local _, ns = ...

local Notices = {}
Notices.__index = Notices
ns.Notices = Notices

Notices.MAX = 100 -- the oldest go
Notices.REPEAT = 300 -- the same notice again within this long: the earlier one moves up instead of a second copy

function Notices.New(db)
  db.list = db.list or {}
  db.readAt = db.readAt or 0
  return setmetatable({ db = db, listeners = {} }, Notices)
end

-- e: { kind, text, itemID?, who? }; at: server time
function Notices:Add(e, at)
  local list = self.db.list
  for i = #list, 1, -1 do
    local old = list[i]
    if at - old.at > Notices.REPEAT then
      break
    end
    if old.kind == e.kind and old.text == e.text and old.itemID == e.itemID and old.who == e.who then
      table.remove(list, i)
      break
    end
  end
  list[#list + 1] = { kind = e.kind, text = e.text, itemID = e.itemID, who = e.who, at = at }
  while #list > Notices.MAX do
    table.remove(list, 1)
  end
  self:changed()
end

-- newest first
function Notices:List()
  local out = {}
  for i = #self.db.list, 1, -1 do
    out[#out + 1] = self.db.list[i]
  end
  return out
end

function Notices:Unread()
  local n = 0
  for _, e in ipairs(self.db.list) do
    if e.at > self.db.readAt then
      n = n + 1
    end
  end
  return n
end

function Notices:IsUnread(e)
  return e.at > self.db.readAt
end

function Notices:MarkRead(at)
  self.db.readAt = math.max(self.db.readAt, at)
  self:changed()
end

function Notices:Clear()
  self.db.list = {}
  self:changed()
end

function Notices:OnChange(fn)
  self.listeners[#self.listeners + 1] = fn
end

function Notices:changed()
  for _, fn in ipairs(self.listeners) do
    fn()
  end
end
