-- Leader
vim.g.mapleader = " "
vim.g.maplocalleader = " "

for _, mod in ipairs({
  "options",

  -- Plugins
  "plugins.gitsigns",
  "plugins.catppuccin",
  "plugins.mini-pick",
  "plugins.mini-extra",
  "plugins.mini-files",
  "plugins.mini-bracketed",
  "plugins.mini-clue",
  "plugins.lspconfig",
  "plugins.blink-lib",
  "plugins.blink-cmp",
  "plugins.blink-pairs",
  "plugins.blink-indent",

  -- Core
  "lsp",
  "format",
  "statusline",
  "terminal",
  "keymaps",
  "sessions"
}) do
  require(mod)
end
