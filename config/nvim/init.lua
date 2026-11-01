-- Leader
vim.g.mapleader = " "
vim.g.maplocalleader = " "
 
for _, mod in ipairs({
  "options",
  "plugins",
  "picker",
  "lsp",
  "completion",
  "format",

  "statusline",
  "terminal",
  "keymaps",
}) do
  require("config." .. mod)
end
 

