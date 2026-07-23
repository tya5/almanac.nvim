local dateutil = require("almanac.dateutil")
local events_util = require("almanac.events")
local header = require("almanac.render.header")

local M = {}

--- @param date integer any day within the target month
--- @param events almanac.Event[]
--- @param opts { week_start: "sunday"|"monday", selected: integer? }
--- @return string[] lines
--- @return table[] highlights
--- @return table<integer, table> line_map 1-indexed line -> {type="day_segments", segments={{col_start,col_end,epoch}, ...}} | {type="event", event=...}
function M.render(date, events, opts)
  local week_start = opts.week_start or "monday"
  local by_day = events_util.group_by_day(events)
  local today = dateutil.start_of_day(os.time())

  local lines, highlights = header.render("Month", dateutil.format_month_header(date))
  local line_map = {}

  local cell_width = 3 -- 2-digit day number + 1 marker char

  local order = week_start == "sunday" and { 7, 1, 2, 3, 4, 5, 6 } or { 1, 2, 3, 4, 5, 6, 7 }
  local names = {}
  for _, idx in ipairs(order) do
    -- Padded to cell_width so the header lines up with the day-number
    -- grid below (each grid cell is a 2-digit day + 1 marker char,
    -- i.e. 3 wide; the 2-char weekday abbreviation alone drifted out
    -- of alignment by one column per week — not a font issue).
    names[#names + 1] = ("%-" .. cell_width .. "s"):format(dateutil.WEEKDAY_ABBR2[idx])
  end
  lines[#lines + 1] = table.concat(names, " ")
  highlights[#highlights + 1] = { line = #lines - 1, col_start = 0, col_end = -1, hl_group = "AlmanacHeader" }

  local weeks = dateutil.month_grid(date, week_start)

  for _, week in ipairs(weeks) do
    local cell_texts = {}
    for _, day in ipairs(week) do
      local _, _, d = dateutil.ymd(day.epoch)
      local marker = by_day[dateutil.day_key(day.epoch)] and "\u{2022}" or " " -- "•"
      cell_texts[#cell_texts + 1] = ("%2d%s"):format(d, marker)
    end
    lines[#lines + 1] = table.concat(cell_texts, " ")
    local line_idx = #lines - 1
    local segments = {}

    local col = 0
    for _, day in ipairs(week) do
      local hl
      if dateutil.is_same_day(day.epoch, today) then
        hl = "AlmanacToday"
      elseif opts.selected and dateutil.is_same_day(day.epoch, opts.selected) then
        hl = "AlmanacSelected"
      elseif not day.in_month then
        hl = "AlmanacOtherMonth"
      elseif dateutil.is_weekend(day.epoch) then
        hl = "AlmanacWeekend"
      end
      if hl then
        highlights[#highlights + 1] = { line = line_idx, col_start = col, col_end = col + cell_width, hl_group = hl }
      end
      if by_day[dateutil.day_key(day.epoch)] then
        highlights[#highlights + 1] =
          { line = line_idx, col_start = col + 2, col_end = col + cell_width, hl_group = "AlmanacHasEvent" }
      end
      segments[#segments + 1] = { col_start = col, col_end = col + cell_width, epoch = day.epoch }
      col = col + cell_width + 1
    end
    line_map[#lines] = { type = "day_segments", segments = segments }
  end

  if opts.selected then
    local sel_events = by_day[dateutil.day_key(opts.selected)] or {}
    lines[#lines + 1] = ""
    lines[#lines + 1] = dateutil.format_day_header(opts.selected)
    highlights[#highlights + 1] = { line = #lines - 1, col_start = 0, col_end = -1, hl_group = "AlmanacHeader" }
    for _, ev in ipairs(sel_events) do
      local time = events_util.format_time(ev)
      lines[#lines + 1] = (time ~= "" and ("  %s %s"):format(time, ev.title) or ("  %s"):format(ev.title))
      highlights[#highlights + 1] =
        { line = #lines - 1, col_start = 0, col_end = -1, hl_group = ev.hl_group or "AlmanacEventTitle" }
      line_map[#lines] = { type = "event", event = ev }
    end
  end

  return lines, highlights, line_map
end

return M
