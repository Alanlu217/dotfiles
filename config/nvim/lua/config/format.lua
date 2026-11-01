local M = {}
local autocmd = vim.api.nvim_create_autocmd
local augroup = require("config.util").augroup

local function can_format(client, bufnr)
  return client:supports_method("textDocument/formatting", bufnr)
end

local function has_formatter(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if can_format(client, bufnr) then
      return true
    end
  end
  return false
end

local function attach(bufnr)
  if vim.b[bufnr].autoformat_attached then
    return
  end
  vim.b[bufnr].autoformat_attached = true

  autocmd("BufWritePre", {
    group = augroup("LspFormat" .. bufnr),
    buffer = bufnr,
    callback = function()
      if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
        return
      end
      if not has_formatter(bufnr) then
        return
      end
      vim.lsp.buf.format({
        bufnr = bufnr,
        timeout_ms = 2000,
        filter = function(client)
          return can_format(client, bufnr)
        end,
      })
    end,
  })
end

autocmd("LspAttach", {
  group = augroup("LspFormatOnSave"),
  callback = function(ev)
    attach(ev.buf)
  end,
})

-- Catch buffers whose LSP attached before this module was loaded
for _, client in ipairs(vim.lsp.get_clients()) do
  for bufnr in pairs(client.attached_buffers) do
    attach(bufnr)
  end
end

-- Statusline component (empty string where formatting doesn't apply)
function M.status()
  if not has_formatter(0) then
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

vim.keymap.set("n", "<leader>uf", "<cmd>FormatToggle<CR>", { desc = "Toggle format on save" })

return M
