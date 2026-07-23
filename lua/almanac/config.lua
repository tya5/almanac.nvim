-- Config module, following the folke/lazy.nvim ecosystem convention
-- (lazy.nvim, snacks.nvim): a `defaults` table, an optional global
-- `setup()` to change the baseline, and `resolve(opts)` to merge the
-- current defaults with a per-instance opts table (almanac.Calendar
-- instances are constructed individually, snacks.win-style, so config
-- is resolved per-call rather than being a single global `options`).

local M = {}

---@class almanac.Config
M.defaults = {
  -- Initial displayed date (epoch seconds). nil = today, resolved at
  -- construction time (see almanac.init).
  date = nil,
  -- "month" | "week" | "day" (3.8).
  view = "month",
  -- "sunday" | "monday".
  week_start = "monday",
  -- "left" | "right" | "top" | "bottom" | "float" (4).
  position = "left",
  -- Sidebar width (left/right) in columns, or height (top/bottom) in
  -- rows. A value <= 1 is treated as a fraction of the editor size.
  size = 30,
  -- "auto" | "always". "auto": if edgy.nvim is present, cycle_position()
  -- is disabled and position management is left to edgy (6).
  manage_position = "auto",
  ---@type vim.wo|{}
  wo = {},
  ---@type vim.bo|{}
  bo = {},
  ---@type table<string, false|string|fun(self:almanac.Calendar)|{[1]:string, desc:string}>
  keys = {
    -- Screen-driven navigation: h/j/k/l move focus to whatever is
    -- actually rendered next to the cursor right now (per the
    -- renderer's line_map), never by computing a new date first and
    -- deriving a screen position from it. Date arithmetic only runs as
    -- a fallback once navigation reaches the edge of what's currently
    -- drawn (e.g. j on the last rendered line pages to the next
    -- week/month/day via next()).
    --  h/l (left/right): move within the current grid row (month
    --  view's day cells); a no-op on single-item-per-row views
    --  (week/day), since there's nothing to the side to move to.
    --  j/k (down/up): move to the next/previous rendered line — a day
    --  cell, an agenda day label, or an event line, whichever is
    --  actually there. This is why month view's grid flows straight
    --  into its trailing per-day agenda, and why week/day view stops
    --  on event lines instead of always moving a fixed one day.
    h = "move_left",
    l = "move_right",
    j = "move_down",
    k = "move_up",
    -- Jump directly between event lines in the currently rendered
    -- content only (no paging; wraps at the first/last event).
    ["]e"] = "next_event",
    ["[e"] = "prev_event",
    -- Page forward/backward by the *current view's* own unit — a
    -- month at a time in month view, a week at a time in week view, a
    -- day at a time in day view (Calendar:next()/:prev()). One pair of
    -- keys regardless of view, instead of a different next_month/
    -- next_week/next_day binding per view.
    ["<C-f>"] = "next",
    ["<C-b>"] = "prev",
    gt = "today",
    gm = "view_month",
    gw = "view_week",
    gd = "view_day",
    ["<Tab>"] = "cycle_view",
    ["<CR>"] = "select",
    ["<C-w><C-w>"] = "cycle_position",
    q = "close",
  },
  ---@type almanac.EventProvider?
  events = nil,
  ---@type fun(self: almanac.Calendar)?
  on_open = nil,
  ---@type fun(self: almanac.Calendar)?
  on_close = nil,
}

--- Change the global defaults (optional; almanac works fine without
--- ever calling this — each Calendar() call can pass its own opts).
---@param opts? almanac.Config
function M.setup(opts)
  M.defaults = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

--- Merge the current defaults with a per-instance opts table. Does not
--- mutate M.defaults.
---@param opts? almanac.Config
---@return almanac.Config
function M.resolve(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
