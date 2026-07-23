-- Sidebar window management: nvim-tree/neo-tree style — a single reused
-- window/buffer per Calendar instance, opened at one of left/right/top/
-- bottom/float, never a floating popup by default and never the current
-- window's buffer (see docs/DESIGN.md section 4).

local M = {}

local function has_edgy()
  return pcall(require, "edgy")
end

--- @param manage_position "auto"|"always"
--- @return boolean true if cycle_position() should be a no-op (edgy owns positioning)
function M.edgy_manages_position(manage_position)
  return manage_position == "auto" and has_edgy()
end

local POSITIONS = { "left", "right", "top", "bottom" }

--- @param position string
--- @return string next position in the left->right->top->bottom->left cycle
function M.next_position(position)
  for i, p in ipairs(POSITIONS) do
    if p == position then
      return POSITIONS[(i % #POSITIONS) + 1]
    end
  end
  return POSITIONS[1]
end

--- @param position "left"|"right"|"top"|"bottom"|"float"
--- @param size number columns (left/right) or rows (top/bottom); <=1 treated as a fraction
--- @return string vim split command to run before creating the window
function M.split_command(position, size)
  if position == "left" then
    local width = size <= 1 and math.floor(vim.o.columns * size) or math.floor(size)
    return ("topleft %dvsplit"):format(width)
  elseif position == "right" then
    local width = size <= 1 and math.floor(vim.o.columns * size) or math.floor(size)
    return ("botright %dvsplit"):format(width)
  elseif position == "top" then
    local height = size <= 1 and math.floor(vim.o.lines * size) or math.floor(size)
    return ("topleft %dsplit"):format(height)
  elseif position == "bottom" then
    local height = size <= 1 and math.floor(vim.o.lines * size) or math.floor(size)
    return ("botright %dsplit"):format(height)
  end
  error("almanac.win.split_command: unsupported position for a split: " .. tostring(position))
end

--- Create (or reuse, if `win` is a still-valid window) the sidebar
--- window/buffer for a Calendar instance.
--- @param opts { position: string, size: number, filetype: string, wo: table, bo: table }
--- @param existing_win integer? a previously created window to reuse if still valid
--- @param existing_buf integer? a previously created buffer to reuse if still valid
--- @return integer win
--- @return integer buf
function M.open(opts, existing_win, existing_buf)
  if existing_win and vim.api.nvim_win_is_valid(existing_win) then
    local buf = existing_buf
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then
      buf = vim.api.nvim_create_buf(false, true)
    end
    vim.api.nvim_win_set_buf(existing_win, buf)
    return existing_win, buf
  end

  local buf = (existing_buf and vim.api.nvim_buf_is_valid(existing_buf)) and existing_buf
    or vim.api.nvim_create_buf(false, true)

  if opts.position == "float" then
    local width = opts.size <= 1 and math.floor(vim.o.columns * opts.size) or math.floor(opts.size)
    local height = math.floor(vim.o.lines * 0.6)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      border = "rounded",
      title = "Calendar",
    })
    M.apply_options(win, buf, opts)
    return win, buf
  end

  -- Focus lands in the new sidebar window (nvim-tree/neo-tree "open"
  -- convention), since almanac is keyboard-navigated (h/l/j/k, <CR>,
  -- view/position cycling) and unusable without focus.
  vim.cmd(M.split_command(opts.position, opts.size))
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  M.apply_options(win, buf, opts)
  return win, buf
end

--- @param win integer
--- @param buf integer
--- @param opts { filetype: string, wo: table, bo: table }
function M.apply_options(win, buf, opts)
  vim.bo[buf].filetype = opts.filetype
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.bo[buf].swapfile = false
  for k, v in pairs(opts.bo or {}) do
    vim.bo[buf][k] = v
  end

  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  for k, v in pairs(opts.wo or {}) do
    vim.wo[win][k] = v
  end
end

--- @param buf integer
--- @param lines string[]
function M.set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- @param buf integer
--- @param highlights { line: integer, col_start: integer, col_end: integer, hl_group: string }[]
--- @param ns integer extmark namespace id
function M.set_highlights(buf, highlights, ns)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns, h.hl_group, h.line, h.col_start, h.col_end)
  end
end

return M
