-- Default highlight groups (3.6): all linked, none hardcoded, so any
-- colorscheme can override them by re-linking the group name.
local M = {}

local DEFAULTS = {
  AlmanacHeader = { link = "Title" },
  AlmanacToday = { link = "CursorLine" },
  AlmanacWeekend = { link = "Comment" },
  AlmanacSelected = { link = "Visual" },
  AlmanacHasEvent = { link = "DiagnosticInfo" },
  AlmanacOtherMonth = { link = "NonText" },
  -- Distinct from AlmanacEventTitle (Normal) so a plain weekday label
  -- (week view) never renders in the same color as the event lines
  -- listed under it.
  AlmanacWeekdayLabel = { link = "Statement" },
  AlmanacEventTitle = { link = "Normal" },
  AlmanacEventTime = { link = "Number" },
  AlmanacTimeAxis = { link = "Comment" },
}

local defined = false

--- Idempotent: safe to call from every Calendar construction.
function M.setup()
  if defined then
    return
  end
  defined = true
  for name, opts in pairs(DEFAULTS) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", { default = true }, opts))
  end
end

return M
