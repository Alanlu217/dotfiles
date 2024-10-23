-- Read the docs: https://www.lunarvim.org/docs/configuration
-- Example configs: https://github.com/LunarVim/starter.lvim
-- Video Tutorials: https://www.youtube.com/watch?v=sFA9kX-Ud_c&list=PLhoH5vyxr6QqGu0i7tt_XoVK9v-KvZ3m6
-- Forum: https://www.reddit.com/r/lunarvim/
-- Discord: https://discord.com/invite/Xb9B4Ny

vim.opt.shiftwidth = 2 -- the number of spaces inserted for each indentation
vim.opt.tabstop = 2    -- insert 2 spaces for a tab
vim.opt.wrap = true    -- wrap lines

lvim.format_on_save.enabled = true

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

lvim.plugins = {
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 }
}

-- Set colorscheme
vim.cmd.colorscheme "catppuccin-mocha"

-- Configure nvim-tree
lvim.builtin.nvimtree.setup.actions.open_file.quit_on_open = true

local formatters = require "lvim.lsp.null-ls.formatters"
formatters.setup {
  { name = "goimports" },
}
