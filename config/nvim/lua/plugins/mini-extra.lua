-- Extra pickers for mini.pick (load after plugins.mini-pick)
vim.pack.add { "https://github.com/echasnovski/mini.extra" }

local map = vim.keymap.set

require("mini.extra").setup()

local extra = MiniExtra.pickers

map("n", "<leader>s", function() extra.lsp({ scope = "document_symbol" }) end,  { desc = "Symbols (buffer)" })
map("n", "<leader>S", function() extra.lsp({ scope = "workspace_symbol" }) end, { desc = "Symbols (workspace)" })

map("n", "<leader>x", function() extra.diagnostic({ scope = "current" }) end, { desc = "Diagnostics (buffer)" })
map("n", "<leader>X", function() extra.diagnostic({ scope = "all" }) end,     { desc = "Diagnostics (workspace)" })

-- Fuzzy-search every keymap
map("n", "<leader>?", function()
  extra.keymaps({ mode = "all", scope = "all" })
end, { desc = "Search keymaps" })
