local map = vim.keymap.set
local augroup = require("util").augroup

-- Server configuration
vim.lsp.config("tinymist", {
  settings = { formatterMode = "typstyle" },
})

-- Servers to enable; any whose executable isn't installed is skipped
local servers = {
  "tinymist",       -- Typst
  "clangd",         -- C / C++
  "rust_analyzer",  -- Rust
  "gopls",          -- Go
  "lua_ls",         -- Lua
  "ty",             -- Python (types)
  "ruff",           -- Python (lint + format)
  "ts_ls",          -- TypeScript / JavaScript
  "bashls",         -- Bash
  "jsonls",         -- JSON
  "yamlls",         -- YAML
  "taplo",          -- TOML
}

local enabled = {}
for _, name in ipairs(servers) do
  local cmd = vim.lsp.config[name] and vim.lsp.config[name].cmd
  if type(cmd) ~= "table" or vim.fn.executable(cmd[1]) == 1 then
    table.insert(enabled, name)
  end
end
vim.lsp.enable(enabled)

-- Show attached lsp
vim.api.nvim_create_user_command("LspBuf", function()
  local names = vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({ bufnr = 0 }))
  vim.notify(#names > 0 and table.concat(names, ", ") or "No LSP attached")
end, { desc = "LSP clients for current buffer" })

-- Configure keybinds on attach
vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup("LspKeymaps"),
  callback = function(ev)
    local function lmap(keys, fn, desc)
      map("n", keys, fn, { buffer = ev.buf, desc = desc })
    end
    lmap("gd", vim.lsp.buf.definition, "Go to definition")
    lmap("gr", vim.lsp.buf.references, "References")
    lmap("K", vim.lsp.buf.hover, "Hover")
    lmap("<leader>r", vim.lsp.buf.rename, "Rename")
    lmap("<leader>a", vim.lsp.buf.code_action, "Code action")
    lmap("<leader>d", vim.diagnostic.open_float, "Line diagnostics")
    lmap("<leader>=", function() vim.lsp.buf.format({ async = true }) end, "Format")
  end,
})

-- Diagnostics
vim.keymap.set("n", "<leader>ui", function()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end, { desc = "Toggle inlay hints" })
