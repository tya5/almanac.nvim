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
    -- Abbreviated (3-letter) and a fixed-width day number so every
    -- day's label lines up at the same width ("Mon  3", "Wed 22") —
    -- full names ("Monday"/"Wednesday") vary enough in length to look
    -- ragged stacked vertically. "Today" is conveyed purely by the
    -- AlmanacToday highlight below, not by wrapping the text in
    -- brackets — bracketing would itself re-introduce the same
    -- ragged-width problem for exactly one row.
    local weekday_abbr = dateutil.WEEKDAY_ABBR[dateutil.iso_weekday(day)]
    local _, _, d = dateutil.ymd(day)
    local is_today = dateutil.is_same_day(day, today)
    local label = ("%s %2d"):format(weekday_abbr, d)
    lines[#lines + 1] = label
    local line_idx = #lines - 1
    line_map[#lines] = { type = "day", epoch = day }

    -- Every day label always gets a highlight distinct from the
    -- AlmanacEventTitle/Normal used by the event lines below it, so
    -- the two are never the same color; today/selected/weekend take
    -- priority over the plain-day default.
    local hl = "AlmanacWeekdayLabel"
    if is_today then
      hl = "AlmanacToday"
    elseif opts.selected and dateutil.is_same_day(day, opts.selected) then
      hl = "AlmanacSelected"
    elseif dateutil.is_weekend(day) then
      hl = "AlmanacWeekend"
    end
    highlights[#highlights + 1] = { line = line_idx, col_start = 0, col_end = -1, hl_group = hl }

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
