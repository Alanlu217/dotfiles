vim.pack.add {
  "https://github.com/echasnovski/mini.pick",
  "https://github.com/echasnovski/mini.extra",
  "https://github.com/echasnovski/mini.files",
  "https://github.com/echasnovski/mini.clue",
}

local miniclue = require("mini.clue")
require("mini.pick").setup()
require("mini.extra").setup()
require("mini.files").setup()

-- Use the picker for vim.ui.select (code actions, rename prompts, etc.)
vim.ui.select = MiniPick.ui_select

local map = vim.keymap.set
local pick = MiniPick.builtin
local extra = MiniExtra.pickers

-- Pickers
map("n", "<leader>f", pick.files,     { desc = "Files" })
map("n", "<leader>b", pick.buffers,   { desc = "Buffers" })
map("n", "<leader>g", pick.grep_live, { desc = "Live grep" })

map("n", "<leader>s", function() extra.lsp({ scope = "document_symbol" }) end,  { desc = "Symbols (buffer)" })
map("n", "<leader>S", function() extra.lsp({ scope = "workspace_symbol" }) end, { desc = "Symbols (workspace)" })

map("n", "<leader>x", function() extra.diagnostic({ scope = "current" }) end, { desc = "Diagnostics (buffer)" })
map("n", "<leader>X", function() extra.diagnostic({ scope = "all" }) end,     { desc = "Diagnostics (workspace)" })

-- File explorer: <leader>e toggles at the current file, <leader>E opens at the cwd
map("n", "<leader>e", function()
  local buf = vim.api.nvim_buf_get_name(0)
  local path = (buf ~= "" and vim.uv.fs_stat(buf)) and buf or nil
  if not MiniFiles.close() then
    MiniFiles.open(path, false)
  end
end, { desc = "File explorer (current file)" })

map("n", "<leader>E", function()
  MiniFiles.open(nil, false)
end, { desc = "File explorer (cwd)" })

-- Set cwd from the explorer
local function set_cwd()
  local entry = MiniFiles.get_fs_entry()
  if entry == nil then
    return vim.notify("Cursor is not on a valid entry", vim.log.levels.WARN)
  end
  -- On a directory: cd into it. On a file: cd to its parent.
  local dir = entry.fs_type == "directory" and entry.path or vim.fs.dirname(entry.path)
  vim.fn.chdir(dir)
  vim.notify("cwd: " .. vim.fn.getcwd())
end

-- Explorer buffer-local keys
vim.api.nvim_create_autocmd("User", {
  group = require("config.util").augroup("MiniFilesKeys"),
  pattern = "MiniFilesBufferCreate",
  callback = function(args)
    local function bmap(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = args.data.buf_id, desc = desc })
    end

    bmap("<CR>", function() MiniFiles.go_in({ close_on_file = true }) end, "Open and close on file")
    bmap("<Right>", MiniFiles.go_in, "Go in")
    bmap("<Left>", MiniFiles.go_out, "Go out")
    bmap("<leader>C", set_cwd, "Set cwd")
  end,
})

miniclue.setup({
  triggers = {
    -- Leader
    { mode = "n", keys = "<Leader>" },
    { mode = "x", keys = "<Leader>" },

    -- Built-in prefixes
    { mode = "n", keys = "g" },    { mode = "x", keys = "g" },
    { mode = "n", keys = "z" },    { mode = "x", keys = "z" },
    { mode = "n", keys = "[" },    { mode = "n", keys = "]" },
    { mode = "n", keys = "<C-w>" },
    { mode = "n", keys = "'" },    { mode = "n", keys = "`" },
    { mode = "n", keys = '"' },    { mode = "x", keys = '"' },
    { mode = "i", keys = "<C-r>" }, { mode = "c", keys = "<C-r>" },
    { mode = "i", keys = "<C-x>" },
  },

  clues = {
    -- Label for the <leader>u group (you have <leader>uf)
    { mode = "n", keys = "<Leader>u", desc = "+UI" },

    miniclue.gen_clues.builtin_completion(),
    miniclue.gen_clues.g(),
    miniclue.gen_clues.marks(),
    miniclue.gen_clues.registers(),
    miniclue.gen_clues.windows(),
    miniclue.gen_clues.z(),
  },

  window = { delay = 100 },
})

-- Fuzzy-search every keymap (mini.extra picker)
vim.keymap.set("n", "<leader>?", function()
  MiniExtra.pickers.keymaps({ mode = "all", scope = "all" })
end, { desc = "Search keymaps" })
