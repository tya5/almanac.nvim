local dateutil = require("almanac.dateutil")

local function ymd(y, m, d, h, mi)
  return os.time({ year = y, month = m, day = d, hour = h or 0, min = mi or 0, sec = 0 })
end

describe("almanac.dateutil", function()
  it("computes ISO weekday (1=Monday..7=Sunday)", function()
    -- 2026-08-07 is a Friday.
    assert.equals(5, dateutil.iso_weekday(ymd(2026, 8, 7)))
    -- 2026-08-09 is a Sunday.
    assert.equals(7, dateutil.iso_weekday(ymd(2026, 8, 9)))
    -- 2026-08-03 is a Monday.
    assert.equals(1, dateutil.iso_weekday(ymd(2026, 8, 3)))
  end)

  it("start_of_day zeroes the time-of-day", function()
    local t = os.date("*t", dateutil.start_of_day(ymd(2026, 8, 7, 13, 45)))
    assert.equals(2026, t.year)
    assert.equals(8, t.month)
    assert.equals(7, t.day)
    assert.equals(0, t.hour)
    assert.equals(0, t.min)
  end)

  it("add_days/add_months normalize across month and year boundaries", function()
    local y, m, d = dateutil.ymd(dateutil.add_days(ymd(2026, 8, 30), 3))
    assert.same({ 2026, 9, 2 }, { y, m, d })

    y, m, d = dateutil.ymd(dateutil.add_months(ymd(2026, 12, 15), 1))
    assert.same({ 2027, 1, 1 }, { y, m, d }) -- add_months resets to day 1 by design
  end)

  it("start_of_week respects week_start", function()
    local friday = ymd(2026, 8, 7)

    local mon = dateutil.start_of_week(friday, "monday")
    assert.same({ 2026, 8, 3 }, { dateutil.ymd(mon) })

    local sun = dateutil.start_of_week(friday, "sunday")
    assert.same({ 2026, 8, 2 }, { dateutil.ymd(sun) })
  end)

  it("week_range covers exactly 7 days", function()
    local range = dateutil.week_range(ymd(2026, 8, 7), "monday")
    assert.same({ 2026, 8, 3 }, { dateutil.ymd(range.from) })
    assert.same({ 2026, 8, 9 }, { dateutil.ymd(range.to) })
  end)

  it("day_range covers a single day", function()
    local range = dateutil.day_range(ymd(2026, 8, 7, 13, 0))
    assert.equals(range.from, range.to)
    assert.same({ 2026, 8, 7 }, { dateutil.ymd(range.from) })
  end)

  it("month_range pads to whole weeks on both ends (monday start)", function()
    -- August 2026: Aug 1 is a Saturday, Aug 31 is a Monday.
    local range = dateutil.month_range(ymd(2026, 8, 15), "monday")
    -- Week containing Aug 1 (Sat) starts Monday 2026-07-27.
    assert.same({ 2026, 7, 27 }, { dateutil.ymd(range.from) })
    -- Week containing Aug 31 (Mon) ends Sunday 2026-09-06.
    assert.same({ 2026, 9, 6 }, { dateutil.ymd(range.to) })
  end)

  it("month_grid produces whole weeks of 7 days, flagging in-month days", function()
    local weeks = dateutil.month_grid(ymd(2026, 8, 15), "monday")
    for _, week in ipairs(weeks) do
      assert.equals(7, #week)
    end
    -- First day of the grid (2026-07-27) is not in August.
    assert.is_false(weeks[1][1].in_month)
    -- Aug 1 is the 6th day of the first week (Mon 27..Sat 1).
    assert.is_true(weeks[1][6].in_month)
    assert.same({ 2026, 8, 1 }, { dateutil.ymd(weeks[1][6].epoch) })
  end)

  it("formats headers in English regardless of locale (hand-rolled name tables)", function()
    assert.equals("August 2026", dateutil.format_month_header(ymd(2026, 8, 15)))
    assert.equals("Aug 3 - 9", dateutil.format_week_header(ymd(2026, 8, 3), ymd(2026, 8, 9)))
    assert.equals("Fri, Aug 7 2026", dateutil.format_day_header(ymd(2026, 8, 7)))
  end)

  it("formats a cross-month week header", function()
    assert.equals("Aug 31 - Sep 6", dateutil.format_week_header(ymd(2026, 8, 31), ymd(2026, 9, 6)))
  end)

  it("day_key produces a stable zero-padded grouping key", function()
    assert.equals("2026-08-07", dateutil.day_key(ymd(2026, 8, 7, 23, 59)))
    assert.equals("2026-01-05", dateutil.day_key(ymd(2026, 1, 5)))
  end)

  it("is_weekend flags Saturday/Sunday only", function()
    assert.is_true(dateutil.is_weekend(ymd(2026, 8, 8))) -- Saturday
    assert.is_true(dateutil.is_weekend(ymd(2026, 8, 9))) -- Sunday
    assert.is_false(dateutil.is_weekend(ymd(2026, 8, 7))) -- Friday
  end)
end)
