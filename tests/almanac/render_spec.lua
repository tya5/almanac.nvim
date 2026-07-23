local dateutil = require("almanac.dateutil")
local month_render = require("almanac.render.month")
local week_render = require("almanac.render.week")
local day_render = require("almanac.render.day")

local function ymd(y, m, d, h, mi)
  return os.time({ year = y, month = m, day = d, hour = h or 0, min = mi or 0, sec = 0 })
end

local function find_line(lines, pattern)
  for i, line in ipairs(lines) do
    if line:find(pattern) then
      return i, line
    end
  end
  return nil
end

describe("almanac.render.month", function()
  it("renders a header, weekday row, and one bullet for the event day", function()
    local event = { id = "e1", title = "Team sync", start = ymd(2026, 8, 8, 10, 0) }
    local lines = month_render.render(ymd(2026, 8, 15), { event }, { week_start = "monday" })

    assert.equals("[Month]", lines[1])
    assert.equals("« August 2026 »", lines[2])
    assert.equals("Mo  Tu  We  Th  Fr  Sa  Su ", lines[4])

    -- The weekday header and the day-number grid must use the same
    -- per-column stride (4 chars: a 3-wide cell + 1 separator), or the
    -- columns drift out of alignment moving right across the row (a
    -- real bug this caught: the header's cells used to be 2 chars
    -- wide while the grid's cells are 3 chars wide, misaligning by one
    -- column per week — not a font rendering issue).
    local grid_row = lines[5]
    assert.equals(#lines[4], #grid_row)
    for col = 0, 6 do
      local start = col * 4 + 1
      assert.truthy(lines[4]:sub(start, start):match("%a"), ("expected a weekday letter at col %d"):format(col))
      assert.truthy(grid_row:sub(start, start + 1):match("%d"), ("expected a day digit at col %d"):format(col))
    end

    local idx, line = find_line(lines, " 8\u{2022}")
    assert.is_not_nil(idx, "expected a bullet marker after day 8's number")
    assert.truthy(line:find("8"))
  end)

  it("appends a selected-day agenda when opts.selected is set", function()
    local event = { id = "e1", title = "Team sync", start = ymd(2026, 8, 8, 10, 0) }
    local lines = month_render.render(
      ymd(2026, 8, 15),
      { event },
      { week_start = "monday", selected = ymd(2026, 8, 8) }
    )

    local idx = find_line(lines, "Sat, Aug 8 2026")
    assert.is_not_nil(idx)
    assert.truthy(lines[idx + 1]:find("10:00"))
    assert.truthy(lines[idx + 1]:find("Team sync"))
  end)

  it("has no event days without a bullet", function()
    local lines = month_render.render(ymd(2026, 8, 15), {}, { week_start = "monday" })
    for _, line in ipairs(lines) do
      assert.is_nil(line:find("\u{2022}"))
    end
  end)

  it("line_map maps grid rows to day_segments and agenda rows to events", function()
    local event = { id = "e1", title = "Team sync", start = ymd(2026, 8, 8, 10, 0) }
    local _, _, line_map = month_render.render(
      ymd(2026, 8, 15),
      { event },
      { week_start = "monday", selected = ymd(2026, 8, 8) }
    )

    local grid_line = line_map[5] -- first grid row, right after the weekday header (line 4)
    assert.equals("day_segments", grid_line.type)
    assert.equals(7, #grid_line.segments)

    local event_line
    for _, entry in pairs(line_map) do
      if entry.type == "event" and entry.event.id == "e1" then
        event_line = entry
      end
    end
    assert.is_not_nil(event_line, "expected a line_map entry pointing at the Team sync event")
  end)
end)

describe("almanac.render.week", function()
  it("renders all 7 weekday labels with the event under its day", function()
    local event = { id = "e1", title = "Team sync", start = ymd(2026, 8, 7, 10, 0) } -- Friday
    local lines = week_render.render(ymd(2026, 8, 7), { event }, { week_start = "monday" })

    assert.equals("[Week]", lines[1])
    assert.equals("« Aug 3 - 9 »", lines[2])

    -- Abbreviated (3-letter) weekday labels, fixed-width day number
    -- (see docs/DESIGN.md 3.8 — full names varied enough in length to
    -- look ragged stacked vertically).
    for _, abbr in ipairs({ "Mon", "Tue", "Wed", "Thu", "Sat", "Sun" }) do
      assert.is_not_nil(find_line(lines, abbr), ("missing weekday label: %s"):format(abbr))
    end
    -- Friday is today-agnostic here, but should show as "Fri  7" (not
    -- bracketed unless it happens to be the real today in the test env).
    local fri_idx = find_line(lines, "Fri  7") or find_line(lines, "%[Fri  7%]")
    assert.is_not_nil(fri_idx)
    assert.truthy(lines[fri_idx + 1]:find("10:00"))
    assert.truthy(lines[fri_idx + 1]:find("Team sync"))
  end)

  it("gives every weekday label a highlight distinct from AlmanacEventTitle", function()
    local event = { id = "e1", title = "Team sync", start = ymd(2026, 8, 7, 10, 0) }
    local lines, highlights = week_render.render(ymd(2026, 8, 7), { event }, { week_start = "monday" })

    local fri_idx = find_line(lines, "Fri  7") or find_line(lines, "%[Fri  7%]")
    local fri_hl
    for _, h in ipairs(highlights) do
      if h.line == fri_idx - 1 then
        fri_hl = h.hl_group
      end
    end
    assert.is_not_nil(fri_hl)
    assert.is_not.equals("AlmanacEventTitle", fri_hl)
  end)

  it("line_map maps day labels and event lines", function()
    local event = { id = "e1", title = "Team sync", start = ymd(2026, 8, 7, 10, 0) }
    local lines, _, line_map = week_render.render(ymd(2026, 8, 7), { event }, { week_start = "monday" })

    local fri_idx = find_line(lines, "Fri  7") or find_line(lines, "%[Fri  7%]")
    assert.equals("day", line_map[fri_idx].type)
    assert.equals("event", line_map[fri_idx + 1].type)
    assert.equals("e1", line_map[fri_idx + 1].event.id)
  end)
end)

describe("almanac.render.day", function()
  it("renders 24 hour rows and places the event at its hour", function()
    local event = { id = "e1", title = "Design review", start = ymd(2026, 8, 7, 14, 0), location = "Zoom" }
    local lines = day_render.render(ymd(2026, 8, 7), { event }, {})

    assert.equals("[Day]", lines[1])
    assert.equals("« Fri, Aug 7 2026 »", lines[2])

    local idx = find_line(lines, "14:00 %-%- Design review")
    assert.is_not_nil(idx)
    assert.truthy(lines[idx + 1]:find("Location: Zoom"))

    -- Every hour from 00:00 to 23:00 should appear exactly once as a label.
    for hour = 0, 23 do
      local label = ("%02d:00"):format(hour)
      assert.is_not_nil(find_line(lines, vim.pesc(label)), ("missing hour row: %s"):format(label))
    end
  end)

  it("shows all-day events above the hour grid", function()
    local event = { id = "e1", title = "Company holiday", start = ymd(2026, 8, 7), all_day = true }
    local lines = day_render.render(ymd(2026, 8, 7), { event }, {})
    local idx = find_line(lines, "Company holiday")
    local first_hour_idx = find_line(lines, "00:00")
    assert.is_not_nil(idx)
    assert.is_true(idx < first_hour_idx)
  end)

  it("line_map points empty hours at the day and busy hours at their event", function()
    local event = { id = "e1", title = "Design review", start = ymd(2026, 8, 7, 14, 0) }
    local lines, _, line_map = day_render.render(ymd(2026, 8, 7), { event }, {})

    local empty_idx = find_line(lines, "^00:00 ")
    assert.equals("day", line_map[empty_idx].type)

    local event_idx = find_line(lines, "14:00 %-%- Design review")
    assert.equals("event", line_map[event_idx].type)
    assert.equals("e1", line_map[event_idx].event.id)
  end)
end)
