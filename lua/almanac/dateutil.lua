-- Pure date-math helpers. No window/buffer/vim.* UI calls here, so this
-- module is trivially unit-testable headlessly.
--
-- All dates are epoch seconds (integer), always at local midnight for
-- "day" values (see start_of_day). Callers (almanac.init, render/*) never
-- touch os.date/os.time directly — everything goes through here so the
-- locale-independence guarantee (2.1: English-only UI) has one place to
-- hold: month/weekday *names* are looked up from our own tables, never
-- from os.date's locale-dependent %A/%B/%a/%b specifiers.

local M = {}

M.MONTH_NAMES = {
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
}

M.MONTH_ABBR = {
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
}

-- Index 1 = Monday .. 7 = Sunday (ISO-8601 weekday numbering).
M.WEEKDAY_NAMES = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
M.WEEKDAY_ABBR = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
M.WEEKDAY_ABBR2 = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }

--- @param epoch integer
--- @return osdate
local function to_table(epoch)
  return os.date("*t", epoch)
end

--- ISO weekday: 1 = Monday .. 7 = Sunday. os.date's own `wday` field is
--- 1 = Sunday .. 7 = Saturday (Lua reference manual; not locale-dependent,
--- it's a plain integer count, unlike %A/%a).
--- @param epoch integer
--- @return integer
function M.iso_weekday(epoch)
  local wday = to_table(epoch).wday -- 1=Sun..7=Sat
  return ((wday + 5) % 7) + 1
end

--- @param epoch integer
--- @return integer
function M.start_of_day(epoch)
  local t = to_table(epoch)
  return os.time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
end

--- @param epoch integer
--- @param n integer
--- @return integer
function M.add_days(epoch, n)
  local t = to_table(epoch)
  return os.time({ year = t.year, month = t.month, day = t.day + n, hour = t.hour, min = t.min, sec = t.sec })
end

--- @param epoch integer
--- @param n integer
--- @return integer
function M.add_months(epoch, n)
  local t = to_table(epoch)
  return os.time({ year = t.year, month = t.month + n, day = 1, hour = 0, min = 0, sec = 0 })
end

--- @param epoch integer
--- @return integer year
--- @return integer month 1-12
--- @return integer day
function M.ymd(epoch)
  local t = to_table(epoch)
  return t.year, t.month, t.day
end

--- @param epoch integer
--- @return integer hour
--- @return integer min
function M.hm(epoch)
  local t = to_table(epoch)
  return t.hour, t.min
end

--- Canonical "YYYY-MM-DD" key for grouping events by day, independent
--- of any display formatting.
--- @param epoch integer
--- @return string
function M.day_key(epoch)
  local y, m, d = M.ymd(epoch)
  return ("%04d-%02d-%02d"):format(y, m, d)
end

--- @param epoch integer
--- @return boolean
function M.is_same_day(a, b)
  local ta, tb = to_table(a), to_table(b)
  return ta.year == tb.year and ta.month == tb.month and ta.day == tb.day
end

--- @param epoch integer
--- @return boolean
function M.is_weekend(epoch)
  local w = M.iso_weekday(epoch)
  return w == 6 or w == 7
end

--- @param week_start "sunday"|"monday"
--- @param epoch integer
--- @return integer offset days to subtract to reach the first day of this week
local function days_since_week_start(week_start, epoch)
  if week_start == "sunday" then
    return to_table(epoch).wday - 1 -- 0..6, Sunday=0
  end
  return M.iso_weekday(epoch) - 1 -- 0..6, Monday=0
end

--- First day (local midnight) of the week containing `epoch`.
--- @param epoch integer
--- @param week_start "sunday"|"monday"
--- @return integer
function M.start_of_week(epoch, week_start)
  local day = M.start_of_day(epoch)
  return M.add_days(day, -days_since_week_start(week_start, day))
end

--- @param epoch integer
--- @param week_start "sunday"|"monday"
--- @return almanac.Range range covering Mon..Sun (or Sun..Sat)
function M.week_range(epoch, week_start)
  local from = M.start_of_week(epoch, week_start)
  return { from = from, to = M.add_days(from, 6) }
end

--- @param epoch integer
--- @return almanac.Range range covering just this one day
function M.day_range(epoch)
  local day = M.start_of_day(epoch)
  return { from = day, to = day }
end

--- Range covering the full month grid: the displayed month plus any
--- leading/trailing days from adjacent months needed to fill whole weeks.
--- @param epoch integer any day within the target month
--- @param week_start "sunday"|"monday"
--- @return almanac.Range
function M.month_range(epoch, week_start)
  local t = to_table(epoch)
  local first_of_month = os.time({ year = t.year, month = t.month, day = 1, hour = 0, min = 0, sec = 0 })
  local first_of_next_month = os.time({ year = t.year, month = t.month + 1, day = 1, hour = 0, min = 0, sec = 0 })
  local last_of_month = M.add_days(first_of_next_month, -1)

  local from = M.add_days(first_of_month, -days_since_week_start(week_start, first_of_month))
  local to = M.add_days(last_of_month, 6 - days_since_week_start(week_start, last_of_month))
  return { from = from, to = to }
end

--- Build the month grid as weeks of 7 days each, for rendering.
--- @param epoch integer any day within the target month
--- @param week_start "sunday"|"monday"
--- @return { epoch: integer, in_month: boolean }[][] weeks, each 7 days
function M.month_grid(epoch, week_start)
  local t = to_table(epoch)
  local range = M.month_range(epoch, week_start)
  local weeks = {}
  local day = range.from
  while day <= range.to do
    local week = {}
    for _ = 1, 7 do
      week[#week + 1] = { epoch = day, in_month = to_table(day).month == t.month }
      day = M.add_days(day, 1)
    end
    weeks[#weeks + 1] = week
  end
  return weeks
end

--- @param epoch integer
--- @return string e.g. "August 2026"
function M.format_month_header(epoch)
  local t = to_table(epoch)
  return ("%s %d"):format(M.MONTH_NAMES[t.month], t.year)
end

--- @param from integer
--- @param to integer
--- @return string e.g. "Aug 3 - Aug 9" (same month) or "Aug 31 - Sep 6"
function M.format_week_header(from, to)
  local tf, tt = to_table(from), to_table(to)
  if tf.month == tt.month then
    return ("%s %d - %d"):format(M.MONTH_ABBR[tf.month], tf.day, tt.day)
  end
  return ("%s %d - %s %d"):format(M.MONTH_ABBR[tf.month], tf.day, M.MONTH_ABBR[tt.month], tt.day)
end

--- @param epoch integer
--- @return string e.g. "Fri, Aug 7 2026"
function M.format_day_header(epoch)
  local t = to_table(epoch)
  local weekday = M.WEEKDAY_ABBR[M.iso_weekday(epoch)]
  return ("%s, %s %d %d"):format(weekday, M.MONTH_ABBR[t.month], t.day, t.year)
end

return M
