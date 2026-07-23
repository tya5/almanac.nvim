local dateutil = require("almanac.dateutil")
local events_util = require("almanac.events")
local header = require("almanac.render.header")

local M = {}

--- @param date integer any day within the target week
--- @param events almanac.Event[]
--- @param opts { week_start: "sunday"|"monday", selected: integer? }
--- @return string[] lines
--- @return table[] highlights
--- @return table<integer, table> line_map 1-indexed line -> {type="day", epoch=...} | {type="event", event=...}
function M.render(date, events, opts)
  local week_start = opts.week_start or "monday"
  local range = dateutil.week_range(date, week_start)
  local by_day = events_util.group_by_day(events)
  local today = dateutil.start_of_day(os.time())

  local lines, highlights = header.render("Week", dateutil.format_week_header(range.from, range.to))
  local line_map = {}

  local day = range.from
  for _ = 1, 7 do
    local weekday_name = dateutil.WEEKDAY_NAMES[dateutil.iso_weekday(day)]
    local _, _, d = dateutil.ymd(day)
    local is_today = dateutil.is_same_day(day, today)
    local label = is_today and ("[%s %d]"):format(weekday_name, d) or ("%s %d"):format(weekday_name, d)
    lines[#lines + 1] = label
    local line_idx = #lines - 1
    line_map[#lines] = { type = "day", epoch = day }

    if is_today then
      highlights[#highlights + 1] = { line = line_idx, col_start = 0, col_end = -1, hl_group = "AlmanacToday" }
    elseif opts.selected and dateutil.is_same_day(day, opts.selected) then
      highlights[#highlights + 1] = { line = line_idx, col_start = 0, col_end = -1, hl_group = "AlmanacSelected" }
    elseif dateutil.is_weekend(day) then
      highlights[#highlights + 1] = { line = line_idx, col_start = 0, col_end = -1, hl_group = "AlmanacWeekend" }
    end

    local day_events = by_day[dateutil.day_key(day)]
    if day_events then
      for _, ev in ipairs(day_events) do
        local time = events_util.format_time(ev)
        local text = time ~= "" and ("  %s %s"):format(time, ev.title) or ("  %s"):format(ev.title)
        lines[#lines + 1] = text
        local ev_line = #lines - 1
        if time ~= "" then
          highlights[#highlights + 1] =
            { line = ev_line, col_start = 2, col_end = 2 + #time, hl_group = "AlmanacEventTime" }
        end
        highlights[#highlights + 1] =
          { line = ev_line, col_start = 0, col_end = -1, hl_group = ev.hl_group or "AlmanacEventTitle" }
        line_map[#lines] = { type = "event", event = ev }
      end
    end

    day = dateutil.add_days(day, 1)
  end

  return lines, highlights, line_map
end

return M
