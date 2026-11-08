vim.pack.add { "https://github.com/echasnovski/mini.notify" }

require("mini.notify").setup({
  lsp_progress = { enable = true },
})
vim.notify = require("mini.notify").make_notify()
