-- Framework defaults. Override any of these from lua/user/config.lua.
local util = require("core.util")

local M = {}

---@type table
M.defaults = {
  native = {
    auto_build = true, -- run `make` (incremental) before first use
  },

  picker = {
    width = 0.6,
    height = 0.6,
    border = "solid",
    prompt = "> ",
    max_results = 200,
    max_files = 100000,
    hidden = true,
    ignore = { ".git", "node_modules", "target", ".direnv", "result", "__pycache__" },
    override_ui_select = true,
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
    bottom_height = 0.4,
    right_width = 0.5,
    autoinsert = true,
    close_on_exit = true,
    hide_numbers = true,
    float = { width = 0.8, height = 0.8, border = "solid" },
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
