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

  -- Saved directories and switching between them (core.projects).
  projects = {
    file = vim.fs.joinpath(vim.fn.stdpath("data"), "projects.json"),
    scope = "global",  -- default scope for :Project: "global" (:cd) | "tab" (:tcd) | "window" (:lcd)
    open_files = false, -- open the file picker in the project after switching
  },

  terminal = {
    -- Fractions (0 < x < 1) of the editor, or absolute lines/columns (>= 1).
    bottom_height = 0.4,  -- <leader>x
    right_width = 0.5,    -- <leader>X
    autoinsert = true,    -- enter terminal-mode when focusing a live terminal
    close_on_exit = true, -- close on exit status 0; failures stay visible
    hide_numbers = true,
    float = { width = 0.8, height = 0.8, border = "solid" },
  },

  completion = {
    enabled = true,
    auto = true,                           -- open the menu while typing; false = only on <C-Space>
    delay = 40,                            -- ms to wait after a keystroke before asking the sources
    grace = 120,                           -- ms to wait for slow sources before showing what has arrived
    max_items = 50,
    sources = { "lsp", "path", "buffer" }, -- earlier wins when two sources offer the same word
    trigger_chars = {},                    -- extra characters that open the menu, besides those the servers declare
    docs = true,                           -- documentation popup for the highlighted item (needs "popup" in 'completeopt')
    buffer = {
      min_prefix = 2,                      -- characters typed before buffer words are offered
      max_words = 5000,                    -- per buffer
      max_bytes = 1048576,                 -- buffers larger than this are not scanned
    },
    path = {
      max_entries = 1000,
    },
  },

  -- Parameter viewer: LSP signature help next to the completion menu (core.signature).
  signature = {
    enabled = true,
    auto = true, -- open on the servers' trigger characters (usually "(" and ","); false = only on the keymap
    delay = 30,  -- ms to wait after a keystroke before asking the servers
    docs = true, -- show the active parameter's and the signature's documentation under the label
    max_width = 80,
    max_height = 10,
    border = "solid",
  },

  -- Typst preview through tinymist (core.typst_preview).
  typst_preview = {
    follow = true,        -- scroll the preview as the cursor moves (toggle: :TypstPreviewFollow)
    follow_insert = true, -- also while typing
    debounce = 60,        -- ms between a cursor move and the scroll request
    jump_center = true,   -- centre the line after a click in the preview jumps to it
    theme = "light",      -- preview colours: "auto" (browser), "light" or "dark" (toggle: :TypstPreviewTheme)
    args = {},            -- extra `tinymist preview` arguments (--invert-colors is set by `theme`)
    browser = nil,        -- command (list) to open the url with, e.g. { "firefox", "--new-window" }; nil = system default
  },

  -- Formatting: formatters and the filetype mapping live in lua/user/format.lua.
  format = {
    enabled = true,
    on_save = true,            -- starting value of vim.g.format_on_save (toggled with :FormatToggle)
    timeout_ms = 1000,         -- per formatter; format-on-save blocks for at most this long
    lsp_fallback = "fallback", -- "fallback": LSP only when no formatter is available | "always" | "never"
    max_bytes = 1048576,       -- buffers larger than this are not formatted on save
  },

  -- Treesitter highlighting (core.treesitter). Parsers are not built here: Neovim
  -- uses any parser/<lang>.so + queries/<lang>/highlights.scm on the 'runtimepath'.
  treesitter = {
    enabled = true,
    disable = {},                                       -- filetypes that keep regex syntax
    max_bytes = 1048576,                                -- buffers larger than this keep regex syntax
    languages = { "lua", "c", "cpp", "rust", "typst" }, -- what :checkhealth core reports on
  },

  -- Git status in the statusline and inline blame (core.git).
  git = {
    enabled = true,
    refresh_ms = 200,                                                    -- debounce for status refreshes
    untracked = true,                                                    -- count untracked files (turn off in huge repos)
    symbols = { ahead = "^", behind = "v", staged = "+", modified = "~", untracked = "?", conflict = "!" },
    signs = {                                                            -- added / changed / deleted lines in the sign column (core.gitsigns)
      enabled = true,                                                    -- starting value of vim.g.git_signs (toggled with :GitSignsToggle)
      delay = 100,                                                       -- ms after the last edit before the diff is recomputed
      priority = 6,                                                      -- below diagnostics (10), so an error still wins the column
      symbols = false,                                                   -- false: no sign-column symbols, only colour the line number (implies numhl)
      numhl = true,                                                      -- true also colours the line number of changed lines
      untracked = true,                                                  -- show every line of an untracked (not ignored) file as added
      max_bytes = 1048576,                                               -- buffers larger than this get no signs
      text = { add = "+", change = "~", delete = "_", topdelete = "-" }, -- 1-2 cells each
    },
    blame = {
      enabled = false,                         -- starting value of vim.g.git_blame (toggled with :GitBlameToggle)
      delay = 150,                             -- ms the cursor must rest on a line before blame is requested
      prefix = "  ",                           -- put in front of the virtual text
      format = "{author}, {time} - {summary}", -- also {sha}
      uncommitted = "Not committed yet",
      max_bytes = 1048576,                     -- buffers larger than this are not blamed (they are piped to git)
    },
  },

  -- Statusline (core.statusline); layout is in render() there.
  statusline = {
    enabled = true,
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
