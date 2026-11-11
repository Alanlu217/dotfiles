-- Format-on-save itself is handled by conform (lua/plugins/conform.lua).
-- This module only adds the toggle, the manual-format key and a statusline component.
local M = {}
local map = vim.keymap.set

-- Statusline component (empty string where formatting doesn't apply)
function M.status()
  local formatters, lsp_fallback = require("conform").list_formatters_to_run(0)
  if #formatters == 0 and not lsp_fallback then
    return ""
  end
  if vim.g.disable_autoformat then
    return "FMT off"
  elseif vim.b.disable_autoformat then
    return "FMT off (buf)"
  end
  return "FMT on"
end

-- :FormatToggle (global) or :FormatToggle! (current buffer only)
vim.api.nvim_create_user_command("FormatToggle", function(opts)
  if opts.bang then
    vim.b.disable_autoformat = not vim.b.disable_autoformat
  else
    vim.g.disable_autoformat = not vim.g.disable_autoformat
  end
  vim.cmd.redrawstatus()
  local status = M.status()
  vim.notify("Format on save: " .. (status ~= "" and status or "n/a"))
end, { bang = true, desc = "Toggle format on save" })

map("n", "<leader>uf", "<cmd>FormatToggle<CR>", { desc = "Toggle format on save" })

-- Manual format (works on a visual selection too); not tied to an LSP being attached
map({ "n", "v" }, "<leader>=", function()
  require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "Format" })

return M
