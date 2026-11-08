-- Leader
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local modules = {
  "options",

  -- Plugins
  "plugins.gitsigns",
  "plugins.catppuccin",
  "plugins.mini-pick",
  "plugins.mini-extra",
  "plugins.mini-files",
  "plugins.mini-bracketed",
  "plugins.mini-clue",
  "plugins.mini-surround",
  "plugins.mini-notify",
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
  "sessions",
}

local failed = {}

for _, mod in ipairs(modules) do
  local ok, err = pcall(require, mod)
  if not ok then
    table.insert(failed, { mod = mod, err = err })
  end
end

if #failed > 0 then
  vim.schedule(function()
    for _, f in ipairs(failed) do
      vim.notify(
        ("Failed to load '%s':\n%s"):format(f.mod, f.err),
        vim.log.levels.ERROR
      )
    end
  end)
end
