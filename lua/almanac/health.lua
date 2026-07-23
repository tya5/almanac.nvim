-- :checkhealth almanac
local M = {}

function M.check()
  vim.health.start("almanac.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.warn("Neovim >= 0.10 recommended")
  end

  if pcall(require, "edgy") then
    vim.health.ok("edgy.nvim detected — position management can be delegated to it (see :h almanac, section 6)")
  else
    vim.health.info("edgy.nvim not found — almanac manages its own sidebar position")
  end

  if pcall(require, "snacks") then
    vim.health.ok("snacks.nvim detected")
  else
    vim.health.info("snacks.nvim not found — not required, almanac has no hard dependency on it")
  end
end

return M
