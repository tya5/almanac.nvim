-- Shared 2-line header used by all three views (3.8):
--   [Month]
--   « August 2026 »
local M = {}

--- @param view_label string "Month"|"Week"|"Day"
--- @param period_text string e.g. "August 2026", "Aug 3 - 9", "Fri, Aug 7 2026"
--- @return string[] lines
--- @return table[] highlights {line, col_start, col_end, hl_group} (0-indexed line/col, col_end=-1 means end of line)
function M.render(view_label, period_text)
  local lines = {
    ("[%s]"):format(view_label),
    ("« %s »"):format(period_text),
    "",
  }
  local highlights = {
    { line = 0, col_start = 0, col_end = -1, hl_group = "AlmanacHeader" },
    { line = 1, col_start = 0, col_end = -1, hl_group = "AlmanacHeader" },
  }
  return lines, highlights
end

return M
