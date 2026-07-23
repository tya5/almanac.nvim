-- almanac.nvim entrypoint. See docs/DESIGN.md for the full API/IF spec.
--
-- Usage:
--   local cal = require("almanac")({ events = my_provider })
--   cal:show()
--
-- `require("almanac").setup(opts)` optionally changes the *global*
-- defaults every subsequent Calendar() picks up (snacks.win-style: not
-- required, just a convenience for users who want one config for every
-- call site).

local config = require("almanac.config")
local dateutil = require("almanac.dateutil")
local events_util = require("almanac.events")
local winmod = require("almanac.win")
local highlights = require("almanac.highlights")

local RENDERERS = {
  month = require("almanac.render.month"),
  week = require("almanac.render.week"),
  day = require("almanac.render.day"),
}

local VIEWS = { "month", "week", "day" }

local ns = vim.api.nvim_create_namespace("almanac")

---@class almanac.Calendar
local Calendar = {}
Calendar.__index = Calendar

local function range_for(view, date, week_start)
  if view == "month" then
    return dateutil.month_range(date, week_start)
  elseif view == "week" then
    return dateutil.week_range(date, week_start)
  end
  return dateutil.day_range(date)
end

local function emit(self, event, ...)
  local handlers = self._handlers[event]
  if not handlers then
    return
  end
  for _, cb in ipairs(handlers) do
    cb(self, ...)
  end
end

--- Resolve opts.events (sync table or async function(range, cb)) and
--- invoke `cb(events)` once results are available.
local function fetch_events(self, cb)
  local provider = self.opts.events
  if not provider then
    cb({})
    return
  end
  if type(provider) == "table" then
    cb(provider)
    return
  end
  provider(self.range, cb)
end

function Calendar:_recompute_range()
  self.range = range_for(self.view, self.date, self.opts.week_start)
end

--- @param event string
--- @param cb fun(self: almanac.Calendar, ...)
function Calendar:on(event, cb)
  self._handlers[event] = self._handlers[event] or {}
  table.insert(self._handlers[event], cb)
  return self
end

--- Register/override a single keymap (same value shapes as opts.keys; 3.4).
function Calendar:map(lhs, action)
  self.opts.keys[lhs] = action
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    self:_setup_keymaps()
  end
  return self
end

--- @return integer the currently focused day (epoch, local midnight)
function Calendar:selected_day()
  return self.date
end

--- @return almanac.Event[] events on the currently focused day
function Calendar:selected_events()
  local by_day = self._events_by_day or {}
  return by_day[dateutil.day_key(self.date)] or {}
end

function Calendar:render()
  local renderer = RENDERERS[self.view]
  fetch_events(self, function(events)
    if not (self.buf and vim.api.nvim_buf_is_valid(self.buf)) then
      return
    end
    self._events_by_day = events_util.group_by_day(events)
    local lines, hl, line_map =
      renderer.render(self.date, events, { week_start = self.opts.week_start, selected = self.date })
    self._line_map = line_map or {}
    -- A fresh render means fresh data (paging/view switch/refresh); any
    -- previous event-level focus no longer corresponds to anything on
    -- screen, so fall back to day-level focus (self.date) here. Within-
    -- view navigation (move_down/next_event/etc.) never calls render(),
    -- so it's free to set focused_event without it being clobbered.
    self._focused_event = nil
    winmod.set_lines(self.buf, lines)
    winmod.set_highlights(self.buf, hl, ns)
    self:_sync_cursor_to_date()
  end)
end

--- Move the real Vim cursor onto self.date's cell/line in the
--- just-rendered buffer. Without this, hjkl-driven navigation only
--- moved which cell was *highlighted* while the actual text cursor sat
--- wherever it happened to be — the buffer visibly changed under a
--- stationary cursor instead of the cursor moving through the view,
--- which is what h/j/k/l are supposed to feel like.
function Calendar:_sync_cursor_to_date()
  if not (self.win and vim.api.nvim_win_is_valid(self.win)) then
    return
  end
  for line, entry in pairs(self._line_map) do
    if entry.type == "day_segments" then
      for _, seg in ipairs(entry.segments) do
        if dateutil.is_same_day(seg.epoch, self.date) then
          pcall(vim.api.nvim_win_set_cursor, self.win, { line, seg.col_start })
          return
        end
      end
    elseif entry.type == "day" and dateutil.is_same_day(entry.epoch, self.date) then
      pcall(vim.api.nvim_win_set_cursor, self.win, { line, 0 })
      return
    end
  end
end

function Calendar:_ensure_win()
  self.win, self.buf = winmod.open({
    position = self.opts.position,
    size = self.opts.size,
    filetype = "almanac",
    wo = self.opts.wo,
    bo = self.opts.bo,
  }, self.win, self.buf)
  self:_setup_keymaps()
end

--- @return almanac.Calendar
function Calendar:show()
  highlights.setup()
  local was_open = self.win and vim.api.nvim_win_is_valid(self.win)
  self:_ensure_win()
  if not was_open and self.opts.on_open then
    self.opts.on_open(self)
  end
  self:render()
  return self
end

function Calendar:_hide()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  self.win = nil
end

--- @return almanac.Calendar
function Calendar:close()
  self:_hide()
  emit(self, "close")
  if self.opts.on_close then
    self.opts.on_close(self)
  end
  return self
end

--- @return almanac.Calendar
function Calendar:toggle()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    self:close()
  else
    self:show()
  end
  return self
end

--- @return almanac.Calendar
function Calendar:refresh()
  self:render()
  return self
end

-- Date navigation ------------------------------------------------------

--- @param date integer epoch; the day to focus
--- @return almanac.Calendar
function Calendar:goto_date(date)
  self.date = dateutil.start_of_day(date)
  local old_range = self.range
  self:_recompute_range()
  if not old_range or old_range.from ~= self.range.from or old_range.to ~= self.range.to then
    emit(self, "range_changed", self.range)
  end
  self:render()
  return self
end

function Calendar:today()
  return self:goto_date(os.time())
end

function Calendar:next_day()
  return self:goto_date(dateutil.add_days(self.date, 1))
end
function Calendar:prev_day()
  return self:goto_date(dateutil.add_days(self.date, -1))
end
function Calendar:next_week()
  return self:goto_date(dateutil.add_days(self.date, 7))
end
function Calendar:prev_week()
  return self:goto_date(dateutil.add_days(self.date, -7))
end

--- Jumps to day 1 of the target month (add_months does not preserve
--- day-of-month — see dateutil.add_months — which sidesteps
--- end-of-month edge cases like Jan 31 + 1 month).
function Calendar:next_month()
  return self:goto_date(dateutil.add_months(self.date, 1))
end
function Calendar:prev_month()
  return self:goto_date(dateutil.add_months(self.date, -1))
end

--- Page forward/backward by whatever unit the *current* view shows a
--- page of — a month at a time in month view, a week at a time in week
--- view, a day at a time in day view. This is deliberately a single
--- pair of actions/keys (default <C-f>/<C-b>) rather than three
--- separate next_month/next_week/next_day bindings: since the view
--- already determines what's on screen, "page forward" should mean the
--- same thing regardless of which view you're in, instead of asking
--- the user to remember a different key per view.
function Calendar:next()
  if self.view == "week" then
    return self:next_week()
  elseif self.view == "day" then
    return self:next_day()
  end
  return self:next_month()
end

function Calendar:prev()
  if self.view == "week" then
    return self:prev_week()
  elseif self.view == "day" then
    return self:prev_day()
  end
  return self:prev_month()
end

-- Screen-driven hjkl navigation ------------------------------------------
--
-- Principle: a keypress moves focus to whatever is actually rendered
-- immediately next to the cursor (per self._line_map), never by
-- computing a new date and re-deriving a screen position from it. Date
-- arithmetic (next_day/next_week/etc., above) only kicks in as a
-- fallback *after* navigation runs off the edge of what's currently
-- drawn — e.g. j on the last rendered line pages to the next
-- week/month/day and lands wherever that page's own render naturally
-- puts focus. This also means month view's grid flows straight into
-- its trailing per-day agenda (agenda rows are just more line_map rows)
-- with no special-casing between "grid" and "agenda".

--- @return integer? row, integer? col current cursor position, or nil
--- if there is no valid sidebar window right now
function Calendar:_cursor_pos()
  if not (self.win and vim.api.nvim_win_is_valid(self.win)) then
    return nil, nil
  end
  local pos = vim.api.nvim_win_get_cursor(self.win)
  return pos[1], pos[2]
end

--- @return integer[] line numbers present in self._line_map, ascending
function Calendar:_sorted_line_map_lines()
  local lines = {}
  for line in pairs(self._line_map) do
    lines[#lines + 1] = line
  end
  table.sort(lines)
  return lines
end

--- Move focus (self.date/self._focused_event) and the real cursor onto
--- the given already-rendered line_map row, without a re-render.
--- @param line integer
--- @param preferred_col integer column to prefer when landing on a
--- day_segments row with multiple cells (used to keep the same weekday
--- column when moving vertically through the month grid)
--- @return boolean ok
function Calendar:_focus_line(line, preferred_col)
  local entry = self._line_map[line]
  if not entry then
    return false
  end
  if entry.type == "day_segments" then
    local seg = entry.segments[1]
    for _, s in ipairs(entry.segments) do
      if preferred_col >= s.col_start and preferred_col < s.col_end then
        seg = s
        break
      end
    end
    self.date = seg.epoch
    self._focused_event = nil
    pcall(vim.api.nvim_win_set_cursor, self.win, { line, seg.col_start })
  elseif entry.type == "day" then
    self.date = entry.epoch
    self._focused_event = nil
    pcall(vim.api.nvim_win_set_cursor, self.win, { line, 0 })
  elseif entry.type == "event" then
    self.date = dateutil.start_of_day(entry.event.start)
    self._focused_event = entry.event
    pcall(vim.api.nvim_win_set_cursor, self.win, { line, 0 })
  else
    return false
  end
  return true
end

--- @return almanac.Event? the event under focus, if focus is currently
--- on an event line (nil if focus is on a plain day)
function Calendar:focused_event()
  return self._focused_event
end

function Calendar:_move_vertical(direction)
  local row, col = self:_cursor_pos()
  if not row then
    return
  end
  local lines = self:_sorted_line_map_lines()
  local idx
  for i, l in ipairs(lines) do
    if l == row then
      idx = i
      break
    end
  end
  if not idx then
    for i, l in ipairs(lines) do
      if l > row then
        idx = i - 1
        break
      end
    end
    idx = idx or #lines
  end

  local target_idx = idx + direction
  if target_idx < 1 or target_idx > #lines then
    -- Ran off the edge of what's currently rendered: only *now* fall
    -- back to date-arithmetic paging (next()/prev() already knows how
    -- to page by the current view's own unit).
    if direction > 0 then
      self:next()
    else
      self:prev()
    end
    return
  end

  self:_focus_line(lines[target_idx], col)
end

--- j: move focus to the next rendered row (day label, grid row, or
--- event line) below the cursor; pages forward only past the last row.
function Calendar:move_down()
  self:_move_vertical(1)
end

--- k: same as move_down(), upward.
function Calendar:move_up()
  self:_move_vertical(-1)
end

function Calendar:_move_horizontal(direction)
  local row, col = self:_cursor_pos()
  if not row then
    return
  end
  local entry = self._line_map[row]
  if not entry or entry.type ~= "day_segments" then
    -- No cells to the left/right on this row (week/day view rows are
    -- one item each) — intentionally a no-op rather than forcing a day
    -- jump that doesn't correspond to anything visible here.
    return
  end
  local current_idx
  for i, seg in ipairs(entry.segments) do
    if col >= seg.col_start and col < seg.col_end then
      current_idx = i
      break
    end
  end
  if not current_idx then
    return
  end
  local target_idx = current_idx + direction
  if target_idx < 1 or target_idx > #entry.segments then
    return
  end
  local seg = entry.segments[target_idx]
  self.date = seg.epoch
  self._focused_event = nil
  pcall(vim.api.nvim_win_set_cursor, self.win, { row, seg.col_start })
end

--- l: move focus one cell right within the current grid row (month
--- view only; no-op on single-item-per-row rows like week/day view).
function Calendar:move_right()
  self:_move_horizontal(1)
end

--- h: same as move_right(), leftward.
function Calendar:move_left()
  self:_move_horizontal(-1)
end

function Calendar:_move_to_event(direction)
  local row = self:_cursor_pos()
  if not row then
    return
  end
  local event_lines = {}
  for line, entry in pairs(self._line_map) do
    if entry.type == "event" then
      event_lines[#event_lines + 1] = line
    end
  end
  if #event_lines == 0 then
    return
  end
  table.sort(event_lines)
  local target
  if direction > 0 then
    for _, line in ipairs(event_lines) do
      if line > row then
        target = line
        break
      end
    end
    target = target or event_lines[1]
  else
    for i = #event_lines, 1, -1 do
      if event_lines[i] < row then
        target = event_lines[i]
        break
      end
    end
    target = target or event_lines[#event_lines]
  end
  self:_focus_line(target, 0)
end

--- ]e: jump directly to the next event line in the currently rendered
--- content (no paging; wraps to the first event past the last one).
function Calendar:next_event()
  self:_move_to_event(1)
end

--- [e: same as next_event(), backward.
function Calendar:prev_event()
  self:_move_to_event(-1)
end

-- View switching (3.8) ---------------------------------------------------

--- @param view "month"|"week"|"day"
--- @return almanac.Calendar
function Calendar:set_view(view)
  self.view = view
  self:_recompute_range()
  emit(self, "view_changed", view)
  emit(self, "range_changed", self.range)
  self:render()
  return self
end

function Calendar:cycle_view()
  local idx = 1
  for i, v in ipairs(VIEWS) do
    if v == self.view then
      idx = i
    end
  end
  return self:set_view(VIEWS[(idx % #VIEWS) + 1])
end

-- Position switching (4, 6) ----------------------------------------------

--- @param position "left"|"right"|"top"|"bottom"|"float"
--- @return almanac.Calendar
function Calendar:set_position(position)
  self.opts.position = position
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
    self.win = nil
  end
  self:show()
  emit(self, "position_changed", position)
  return self
end

--- No-op if edgy.nvim is present and opts.manage_position == "auto" (6):
--- position management is ceded to edgy rather than fighting over the
--- same window.
function Calendar:cycle_position()
  if winmod.edgy_manages_position(self.opts.manage_position) then
    return self
  end
  return self:set_position(winmod.next_position(self.opts.position))
end

-- Selection (<CR>) --------------------------------------------------------

--- Resolve the cursor position to a day or event (via the renderer's
--- line_map, 3.8) and emit day_selected/event_selected accordingly.
function Calendar:select()
  if not (self.win and vim.api.nvim_win_is_valid(self.win)) then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(self.win)
  local row, col = cursor[1], cursor[2]
  local entry = self._line_map[row]
  if not entry then
    return
  end

  if entry.type == "event" then
    emit(self, "event_selected", entry.event)
  elseif entry.type == "day" then
    self.date = entry.epoch
    emit(self, "day_selected", entry.epoch)
    self:render()
  elseif entry.type == "day_segments" then
    for _, seg in ipairs(entry.segments) do
      if col >= seg.col_start and col < seg.col_end then
        self.date = seg.epoch
        emit(self, "day_selected", seg.epoch)
        self:render()
        return
      end
    end
  end
end

-- Keymaps -----------------------------------------------------------------

function Calendar:_action_fns()
  return {
    prev_day = function()
      self:prev_day()
    end,
    next_day = function()
      self:next_day()
    end,
    prev_week = function()
      self:prev_week()
    end,
    next_week = function()
      self:next_week()
    end,
    prev_month = function()
      self:prev_month()
    end,
    next_month = function()
      self:next_month()
    end,
    prev = function()
      self:prev()
    end,
    next = function()
      self:next()
    end,
    move_down = function()
      self:move_down()
    end,
    move_up = function()
      self:move_up()
    end,
    move_left = function()
      self:move_left()
    end,
    move_right = function()
      self:move_right()
    end,
    next_event = function()
      self:next_event()
    end,
    prev_event = function()
      self:prev_event()
    end,
    today = function()
      self:today()
    end,
    view_month = function()
      self:set_view("month")
    end,
    view_week = function()
      self:set_view("week")
    end,
    view_day = function()
      self:set_view("day")
    end,
    cycle_view = function()
      self:cycle_view()
    end,
    select = function()
      self:select()
    end,
    close = function()
      self:close()
    end,
    toggle = function()
      self:toggle()
    end,
    cycle_position = function()
      self:cycle_position()
    end,
  }
end

function Calendar:_setup_keymaps()
  local fns = self:_action_fns()
  for lhs, action in pairs(self.opts.keys or {}) do
    if action == false then
      -- explicitly unbound; nothing to do (maps are buffer-local and
      -- built fresh, so there's no built-in default to remove).
    elseif type(action) == "string" then
      local fn = fns[action]
      if fn then
        vim.keymap.set("n", lhs, fn, { buffer = self.buf, silent = true, desc = "almanac: " .. action })
      end
    elseif type(action) == "function" then
      vim.keymap.set("n", lhs, function()
        action(self)
      end, { buffer = self.buf, silent = true })
    elseif type(action) == "table" then
      local fn = fns[action[1]]
      if fn then
        vim.keymap.set("n", lhs, fn, { buffer = self.buf, silent = true, desc = action.desc })
      end
    end
  end
end

-- Constructor ---------------------------------------------------------------

local M = {}

--- Change the global defaults picked up by every subsequent Calendar()
--- call. Optional.
---@param opts? almanac.Config
function M.setup(opts)
  config.setup(opts)
end

--- @param opts? almanac.Config
--- @return almanac.Calendar
function M.new(opts)
  local resolved = config.resolve(opts)
  local self = setmetatable({}, Calendar)
  self.opts = resolved
  self.view = resolved.view or "month"
  self.date = dateutil.start_of_day(resolved.date or os.time())
  self.win = nil
  self.buf = nil
  self._handlers = {}
  self._line_map = {}
  self._events_by_day = {}
  self._focused_event = nil
  self:_recompute_range()
  return self
end

setmetatable(M, {
  __call = function(_, opts)
    return M.new(opts)
  end,
})

return M
