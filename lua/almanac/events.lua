-- Helpers shared by all three renderers for grouping/sorting Events by day.
local dateutil = require("almanac.dateutil")

local M = {}

--- @param events almanac.Event[]
--- @return table<string, almanac.Event[]> events grouped by dateutil.day_key(event.start), each list sorted by start time
function M.group_by_day(events)
  local by_day = {}
  for _, event in ipairs(events) do
    local key = dateutil.day_key(event.start)
    by_day[key] = by_day[key] or {}
    table.insert(by_day[key], event)
  end
  for _, day_events in pairs(by_day) do
    table.sort(day_events, function(a, b)
      return a.start < b.start
    end)
  end
  return by_day
end

--- @param event almanac.Event
--- @return string e.g. "10:00" or "" for an all-day event
function M.format_time(event)
  if event.all_day then
    return ""
  end
  local h, m = dateutil.hm(event.start)
  return ("%02d:%02d"):format(h, m)
end

return M
