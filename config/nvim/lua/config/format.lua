local M = {}
local autocmd = vim.api.nvim_create_autocmd
local augroup = require("config.util").augroup

-- Format on save for any attached LSP that supports formatting
autocmd("LspAttach", {
  group = augroup("LspFormatOnSave"),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client or not client:supports_method("textDocument/formatting") then
      return
    end

    vim.b[ev.buf].autoformat_attached = true

    autocmd("BufWritePre", {
      group = augroup("LspFormat" .. ev.buf),
      buffer = ev.buf,
      callback = function()
        if vim.g.disable_autoformat or vim.b[ev.buf].disable_autoformat then
          return
        end
        vim.lsp.buf.format({ bufnr = ev.buf, id = client.id, timeout_ms = 2000 })
      end,
    })
  end,
})

-- Statusline component (empty string in buffers where formatting doesn't apply)
function M.status()
  if not vim.b.autoformat_attached then
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
