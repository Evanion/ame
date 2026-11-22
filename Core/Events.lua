-- Events (pure): one change signal. Core fires what changed; views subscribe and redraw. It replaces the single-slot
-- onChange fields (the last view to assign one won) and Core calling into the UI by name.
--
--   ns.Events.On(name, fn) -> handle          fn(...) on every Fire(name, ...), in the order subscribed
--   ns.Events.Off(handle)
--   ns.Events.Fire(name, ...)                  now, synchronously (an error in a subscriber surfaces, as it would have)
--
-- Names: IndexReady(shard), RecipesChanged(skillLine), ShoppingChanged(shopping), SyncChanged.
local _, ns = ...

local Events = { subs = {} }
ns.Events = Events

function Events.On(name, fn)
  local list = Events.subs[name] or {}
  Events.subs[name] = list
  local handle = { name = name, fn = fn }
  list[#list + 1] = handle
  return handle
end

function Events.Off(handle)
  local list = handle and Events.subs[handle.name]
  for i = #(list or {}), 1, -1 do
    if list[i] == handle then
      table.remove(list, i)
    end
  end
end

function Events.Fire(name, ...)
  local list = Events.subs[name]
  if not list then
    return
  end
  -- a copy: a subscriber may subscribe or unsubscribe while this runs
  local copy = {}
  for i, h in ipairs(list) do
    copy[i] = h
  end
  for _, h in ipairs(copy) do
    h.fn(...)
  end
end
