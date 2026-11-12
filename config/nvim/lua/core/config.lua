-- Framework defaults. Override any of these from lua/user/config.lua.
local util = require("core.util")

local M = {}

---@type table
M.defaults = {
  native = {
    auto_build = true, -- run `make` (incremental, in the background) before first use
  },

  picker = {
    width = 0.6, -- fraction of the editor
    height = 0.6,
    border = "solid",
    prompt = "> ",
    max_results = 200,
    max_files = 100000,
    hidden = true,
    ignore = { ".git", "node_modules", "target", ".direnv", "result", "__pycache__" },
    override_ui_select = true, -- route vim.ui.select (LSP code actions, etc.) through the picker
    keys = {
      next = { "<C-n>", "<Down>", "<C-j>" },
      prev = { "<C-p>", "<Up>", "<C-k>" },
      page_down = { "<C-d>" },
      page_up = { "<C-u>" },
      close = { "<Esc>", "<C-c>" },
      split = { "<C-s>" },
      vsplit = { "<C-v>" },
      tab = { "<C-t>" },
    },
  },

  terminal = {
    -- Fractions (0 < x < 1) of the editor, or absolute lines/columns (>= 1).
    bottom_height = 0.4, -- <leader>x
    right_width = 0.5, -- <leader>X
    autoinsert = true, -- enter terminal-mode when focusing a live terminal
    close_on_exit = true, -- close on exit status 0; failures stay visible
    hide_numbers = true,
    float = { width = 0.8, height = 0.8, border = "solid" },
  },

  lsp = {
    -- Passed to vim.diagnostic.config().
    diagnostics = {
      severity_sort = true,
      underline = true,
      update_in_insert = false,
      signs = true,
      virtual_text = { spacing = 2, prefix = ">" },
      float = { border = "solid", source = true },
    },
  },
}

local cached

---@return table
function M.get()
  if not cached then
    local ok, user = pcall(require, "user.config")
    cached = util.deep_merge(M.defaults, (ok and type(user) == "table") and user or {})
  end
  return cached
end

function M.reset()
  cached = nil
end

return M
