local dateutil = require("almanac.dateutil")
local events_util = require("almanac.events")
local header = require("almanac.render.header")

local M = {}

--- @param date integer the day to show
--- @param events almanac.Event[]
--- @param _opts { selected: integer? } (unused for now; day view has no cursor-selectable sub-unit yet)
--- @return string[] lines
--- @return table[] highlights
--- @return table<integer, table> line_map 1-indexed line -> {type="event", event=...} | {type="day", epoch=...}
function M.render(date, events, _opts)
  local day = dateutil.start_of_day(date)
  local by_day = events_util.group_by_day(events)
  local day_events = by_day[dateutil.day_key(day)] or {}

  local lines, highlights = header.render("Day", dateutil.format_day_header(day))
  local line_map = {}

  local by_hour = {}
  for _, ev in ipairs(day_events) do
    if ev.all_day then
      lines[#lines + 1] = ("  %s"):format(ev.title)
      highlights[#highlights + 1] =
        { line = #lines - 1, col_start = 0, col_end = -1, hl_group = ev.hl_group or "AlmanacEventTitle" }
      line_map[#lines] = { type = "event", event = ev }
    else
      local h = dateutil.hm(ev.start)
      by_hour[h] = by_hour[h] or {}
      table.insert(by_hour[h], ev)
    end
  end

  for hour = 0, 23 do
    local label = ("%02d:00"):format(hour)
    local hour_events = by_hour[hour]
    if hour_events then
      for i, ev in ipairs(hour_events) do
        local prefix = i == 1 and (label .. " -- ") or "      -- "
        lines[#lines + 1] = prefix .. ev.title
        local line_idx = #lines - 1
        highlights[#highlights + 1] = { line = line_idx, col_start = 0, col_end = #label, hl_group = "AlmanacTimeAxis" }
        highlights[#highlights + 1] =
          { line = line_idx, col_start = #prefix, col_end = -1, hl_group = ev.hl_group or "AlmanacEventTitle" }
        line_map[#lines] = { type = "event", event = ev }
        if ev.location then
          lines[#lines + 1] = ("      |  Location: %s"):format(ev.location)
          highlights[#highlights + 1] =
            { line = #lines - 1, col_start = 0, col_end = -1, hl_group = "AlmanacEventTitle" }
          line_map[#lines] = { type = "event", event = ev }
        end
      end
    else
      lines[#lines + 1] = label .. " " .. string.rep("-", 13)
      highlights[#highlights + 1] = { line = #lines - 1, col_start = 0, col_end = -1, hl_group = "AlmanacTimeAxis" }
      line_map[#lines] = { type = "day", epoch = day }
    end
  end

  return lines, highlights, line_map
end

return M
