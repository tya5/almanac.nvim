local Almanac = require("almanac")
local dateutil = require("almanac.dateutil")

local function ymd(y, m, d, h, mi)
  return os.time({ year = y, month = m, day = d, hour = h or 0, min = mi or 0, sec = 0 })
end

describe("almanac.Calendar", function()
  local cal

  before_each(function()
    vim.cmd("silent! only")
  end)

  after_each(function()
    if cal then
      pcall(function()
        cal:close()
      end)
      cal = nil
    end
    vim.cmd("silent! only")
  end)

  it("show() opens a sidebar window with the almanac filetype", function()
    cal = Almanac({ date = ymd(2026, 8, 15) })
    cal:show()
    assert.is_true(vim.api.nvim_win_is_valid(cal.win))
    assert.equals("almanac", vim.bo[cal.buf].filetype)
  end)

  it("show() reuses the same window on repeated calls", function()
    cal = Almanac({ date = ymd(2026, 8, 15) })
    cal:show()
    local win1 = cal.win
    cal:show()
    assert.equals(win1, cal.win)
  end)

  it("toggle() closes an open calendar and reopens a closed one", function()
    cal = Almanac({ date = ymd(2026, 8, 15) })
    cal:toggle()
    assert.is_true(vim.api.nvim_win_is_valid(cal.win))
    cal:toggle()
    assert.is_nil(cal.win)
    cal:toggle()
    assert.is_true(vim.api.nvim_win_is_valid(cal.win))
  end)

  it("close() fires the close event", function()
    cal = Almanac({ date = ymd(2026, 8, 15) })
    cal:show()
    local fired = false
    cal:on("close", function()
      fired = true
    end)
    cal:close()
    assert.is_true(fired)
  end)

  it("goto/today/next_month/prev_month update selected_day()", function()
    cal = Almanac({ date = ymd(2026, 8, 15) })
    cal:show()

    cal:next_month()
    assert.same({ 2026, 9, 1 }, { dateutil.ymd(cal:selected_day()) })

    cal:prev_month()
    assert.same({ 2026, 8, 1 }, { dateutil.ymd(cal:selected_day()) })

    cal:goto_date(ymd(2026, 8, 15))
    assert.same({ 2026, 8, 15 }, { dateutil.ymd(cal:selected_day()) })
  end)

  it("next()/prev() page by the current view's own unit", function()
    cal = Almanac({ date = ymd(2026, 8, 15), view = "month" })
    cal:show()

    cal:next() -- month view: pages by month
    assert.same({ 2026, 9, 1 }, { dateutil.ymd(cal:selected_day()) })
    cal:prev()
    assert.same({ 2026, 8, 1 }, { dateutil.ymd(cal:selected_day()) })

    cal:goto_date(ymd(2026, 8, 15))
    cal:set_view("week")
    cal:next() -- week view: pages by week (+7 days)
    assert.same({ 2026, 8, 22 }, { dateutil.ymd(cal:selected_day()) })
    cal:prev()
    assert.same({ 2026, 8, 15 }, { dateutil.ymd(cal:selected_day()) })

    cal:set_view("day")
    cal:next() -- day view: pages by day (+1 day)
    assert.same({ 2026, 8, 16 }, { dateutil.ymd(cal:selected_day()) })
    cal:prev()
    assert.same({ 2026, 8, 15 }, { dateutil.ymd(cal:selected_day()) })
  end)

  it("move_down()/move_up() (j/k) follow the rendered line_map, not date arithmetic", function()
    cal = Almanac({ date = ymd(2026, 8, 15), view = "month" })
    cal:show()

    cal:move_down() -- month view: down a grid row = +7 days (next rendered row)
    assert.same({ 2026, 8, 22 }, { dateutil.ymd(cal:selected_day()) })
    cal:move_up()
    assert.same({ 2026, 8, 15 }, { dateutil.ymd(cal:selected_day()) })

    cal:set_view("week")
    cal:move_down() -- week view: down one rendered line = +1 day, not +7
    assert.same({ 2026, 8, 16 }, { dateutil.ymd(cal:selected_day()) })
    cal:move_up()
    assert.same({ 2026, 8, 15 }, { dateutil.ymd(cal:selected_day()) })

    -- Day view's rendered rows (hourly) are all *within the same day*,
    -- so a single move_down() there just steps to the next hour row —
    -- it must NOT change the selected day, since that would mean
    -- falling back to date arithmetic before actually running off the
    -- rendered content's edge.
    cal:set_view("day")
    cal:goto_date(ymd(2026, 8, 15))
    vim.api.nvim_win_set_cursor(cal.win, { 4, 0 }) -- first hour row
    cal:move_down()
    assert.same({ 2026, 8, 15 }, { dateutil.ymd(cal:selected_day()) })
  end)

  it("move_down() pages to the next week only after running off the bottom of week view", function()
    cal = Almanac({ date = ymd(2026, 8, 16), view = "week" }) -- a Sunday: last row of its (Monday-start) week
    cal:show()

    local fire_count = 0
    cal:on("range_changed", function()
      fire_count = fire_count + 1
    end)

    cal:move_down() -- last rendered row: falls back to paging (next())
    assert.same({ 2026, 8, 23 }, { dateutil.ymd(cal:selected_day()) })
    assert.equals(1, fire_count)
  end)

  it("move_down() pages to the next day only after running off the bottom of day view", function()
    cal = Almanac({ date = ymd(2026, 8, 15), view = "day" })
    cal:show()

    vim.api.nvim_win_set_cursor(cal.win, { 27, 0 }) -- last hour row (23:00)
    cal:move_down() -- falls back to paging (next_day() via next())
    assert.same({ 2026, 8, 16 }, { dateutil.ymd(cal:selected_day()) })
  end)

  it("move_left()/move_right() (h/l) move within a month grid row but no-op on week/day view", function()
    cal = Almanac({ date = ymd(2026, 8, 15), view = "month" }) -- Saturday
    cal:show()

    cal:move_right()
    assert.same({ 2026, 8, 16 }, { dateutil.ymd(cal:selected_day()) })
    cal:move_left()
    assert.same({ 2026, 8, 15 }, { dateutil.ymd(cal:selected_day()) })

    cal:set_view("week")
    cal:move_right() -- no cells to move within on a single-item row: no-op
    assert.same({ 2026, 8, 15 }, { dateutil.ymd(cal:selected_day()) })
  end)

  it("move_right() past a dotted day lands the real cursor correctly (byte vs display column)", function()
    -- The "•" event marker is a 3-byte UTF-8 character but a single
    -- display column; segment col_start/col_end are byte offsets
    -- (nvim_win_set_cursor is byte-indexed). A day cell *before* the
    -- one we're moving onto having a dot must not shift where later
    -- cells in the same row are found. selected_day() alone can't
    -- catch this: segments are built in correct day order regardless
    -- of column bugs, so the *epoch* landed on on move is right even
    -- when the real cursor byte column is wrong — check the buffer
    -- byte at the cursor directly.
    cal = Almanac({
      date = ymd(2026, 8, 15), -- Saturday, day cell right after Fri 14 (which gets a dot below)
      view = "month",
      events = { { id = "e1", title = "Standup", start = ymd(2026, 8, 14, 9, 0) } },
    })
    cal:show()

    local function cursor_text_at_col()
      local row, col = unpack(vim.api.nvim_win_get_cursor(cal.win))
      local line = vim.api.nvim_buf_get_lines(cal.buf, row - 1, row, false)[1]
      return line:sub(col + 1, col + 2)
    end

    cal:goto_date(ymd(2026, 8, 14))
    assert.equals("14", cursor_text_at_col())

    cal:move_right() -- from the dotted Fri 14 cell onto Sat 15
    assert.same({ 2026, 8, 15 }, { dateutil.ymd(cal:selected_day()) })
    assert.equals("15", cursor_text_at_col())

    cal:move_right() -- Sat 15 onto Sun 16
    assert.same({ 2026, 8, 16 }, { dateutil.ymd(cal:selected_day()) })
    assert.equals("16", cursor_text_at_col())
  end)

  it("j/k stop on event lines (focused_event()) and next_event()/prev_event() jump directly between them", function()
    local e1 = { id = "e1", title = "Standup", start = ymd(2026, 8, 15, 9, 0) }
    local e2 = { id = "e2", title = "Review", start = ymd(2026, 8, 15, 14, 0) }
    cal = Almanac({ date = ymd(2026, 8, 15), view = "day", events = { e1, e2 } })
    cal:show()

    assert.is_nil(cal:focused_event())

    cal:next_event()
    assert.equals("e1", cal:focused_event().id)
    cal:next_event()
    assert.equals("e2", cal:focused_event().id)
    cal:next_event() -- wraps
    assert.equals("e1", cal:focused_event().id)

    cal:prev_event()
    assert.equals("e2", cal:focused_event().id)

    -- moving down from an event line clears event focus once we leave
    -- its line for a plain hour row
    cal:move_down()
    assert.is_nil(cal:focused_event())
  end)

  it("moves the real cursor onto the focused day after every render (not just the highlight)", function()
    cal = Almanac({ date = ymd(2026, 8, 15), view = "month" })
    cal:show()

    cal:next_day()
    local row, col = unpack(vim.api.nvim_win_get_cursor(cal.win))
    local entry = cal._line_map[row]
    assert.equals("day_segments", entry.type)
    local found
    for _, seg in ipairs(entry.segments) do
      if col >= seg.col_start and col < seg.col_end then
        found = seg.epoch
      end
    end
    assert.is_not_nil(found)
    assert.same({ dateutil.ymd(cal:selected_day()) }, { dateutil.ymd(found) })

    cal:set_view("week")
    row = vim.api.nvim_win_get_cursor(cal.win)[1]
    entry = cal._line_map[row]
    assert.equals("day", entry.type)
    assert.same({ dateutil.ymd(cal:selected_day()) }, { dateutil.ymd(entry.epoch) })
  end)

  it("range_changed fires when the visible range actually changes", function()
    cal = Almanac({ date = ymd(2026, 8, 15) })
    cal:show()

    local fire_count = 0
    cal:on("range_changed", function()
      fire_count = fire_count + 1
    end)

    cal:next_day() -- still within the same month grid range: should NOT fire
    assert.equals(0, fire_count)

    cal:next_month() -- crosses into a new month: should fire
    assert.equals(1, fire_count)
  end)

  it("set_view/cycle_view switch views and fire view_changed", function()
    cal = Almanac({ date = ymd(2026, 8, 15), view = "month" })
    cal:show()

    local seen = {}
    cal:on("view_changed", function(_, view)
      table.insert(seen, view)
    end)

    cal:cycle_view()
    assert.equals("week", cal.view)
    cal:cycle_view()
    assert.equals("day", cal.view)
    cal:cycle_view()
    assert.equals("month", cal.view)
    assert.same({ "week", "day", "month" }, seen)

    local lines = vim.api.nvim_buf_get_lines(cal.buf, 0, 1, false)
    assert.equals("[Month]", lines[1])
  end)

  it("select() on a month-grid day cell emits day_selected with the right date", function()
    cal = Almanac({ date = ymd(2026, 8, 15), view = "month" })
    cal:show()

    local selected_day
    cal:on("day_selected", function(_, epoch)
      selected_day = epoch
    end)

    -- Find the line_map row for the grid (first "day_segments" row) and
    -- put the cursor on its first day-cell column. Captured *before*
    -- calling select(), since select() re-renders (and, for a padding
    -- day from an adjacent month, can rebuild line_map against that
    -- other month) — comparing against the post-select() map would be
    -- comparing against stale/shifted data.
    local row, target_epoch
    for line, entry in pairs(cal._line_map) do
      if entry.type == "day_segments" and (not row or line < row) then
        row = line
        target_epoch = entry.segments[1].epoch
      end
    end
    assert.is_not_nil(row)
    vim.api.nvim_win_set_cursor(cal.win, { row, 0 })
    cal:select()

    assert.is_not_nil(selected_day)
    assert.same({ dateutil.ymd(target_epoch) }, { dateutil.ymd(selected_day) })
  end)

  it("select() on an event line emits event_selected with the event's data payload", function()
    local event = { id = "e1", title = "Team sync", start = ymd(2026, 8, 15, 10, 0), data = { entry_id = "abc" } }
    cal = Almanac({ date = ymd(2026, 8, 15), view = "day", events = { event } })
    cal:show()

    local got
    cal:on("event_selected", function(_, ev)
      got = ev
    end)

    local row
    for line, entry in pairs(cal._line_map) do
      if entry.type == "event" then
        row = line
      end
    end
    assert.is_not_nil(row)
    vim.api.nvim_win_set_cursor(cal.win, { row, 0 })
    cal:select()

    assert.is_not_nil(got)
    assert.equals("e1", got.id)
    assert.equals("abc", got.data.entry_id)
  end)

  it("cycle_position() moves the sidebar through left/right/top/bottom", function()
    cal = Almanac({ date = ymd(2026, 8, 15), position = "left" })
    cal:show()

    local seen = { cal.opts.position }
    cal:on("position_changed", function(_, pos)
      table.insert(seen, pos)
    end)

    cal:cycle_position()
    cal:cycle_position()
    cal:cycle_position()
    cal:cycle_position()

    assert.same({ "left", "right", "top", "bottom", "left" }, seen)
    assert.is_true(vim.api.nvim_win_is_valid(cal.win))
  end)

  it("supports an async EventProvider (function(range, cb))", function()
    local calls = 0
    local provider = function(_range, cb)
      calls = calls + 1
      cb({ { id = "e1", title = "Async event", start = ymd(2026, 8, 15, 9, 0) } })
    end
    cal = Almanac({ date = ymd(2026, 8, 15), view = "day", events = provider })
    cal:show()

    assert.equals(1, calls)
    local lines = vim.api.nvim_buf_get_lines(cal.buf, 0, -1, false)
    local found = false
    for _, line in ipairs(lines) do
      if line:find("Async event") then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it("opts.keys supports false (unbind), function values, and {action, desc} tables", function()
    local called = false
    cal = Almanac({
      date = ymd(2026, 8, 15),
      keys = {
        q = false,
        ["<C-x>"] = function(self)
          called = true
          assert.equals(cal, self)
        end,
        gt = { "today", desc = "Jump to today" },
      },
    })
    cal:show()

    -- q should not be mapped to anything almanac-defined (no error, just
    -- verifying no crash from the `false` branch).
    assert.has_no.errors(function()
      cal:_setup_keymaps()
    end)

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-x>", true, false, true), "x", false)
    assert.is_true(called)
  end)
end)
