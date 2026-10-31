local augroup = require("config.util").augroup
local opt = vim.opt

opt.number = true
opt.mouse = "a"
opt.timeoutlen = 400
opt.scrollback = 100000
opt.signcolumn = "number"

-- Indentation: 2-space soft tabs
opt.expandtab = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.smartindent = true

vim.api.nvim_create_autocmd("FileType", {
  group = augroup("MakefileTabs"),
  pattern = "make",
  callback = function() vim.opt_local.expandtab = false end,
})
