vim.pack.add { "https://github.com/echasnovski/mini.pick" }

local map = vim.keymap.set

local function go_up()
  local opts = MiniPick.get_picker_opts() or {}
  local cwd = (opts.source and opts.source.cwd) or vim.fn.getcwd()
  local parent = vim.fs.dirname(cwd)
  MiniPick.stop()
  vim.schedule(function()
    MiniPick.builtin.files(nil, { source = { cwd = parent } })
  end)
end

require("mini.pick").setup({
  mappings = {
    go_up = { char = "<C-o>", func = go_up },
  },
})

-- Use the picker for vim.ui.select (code actions, rename prompts, etc.)
vim.ui.select = MiniPick.ui_select

local pick = MiniPick.builtin

map("n", "<leader>f", pick.files,     { desc = "Files" })
map("n", "<leader>F", function()
  local name = vim.api.nvim_buf_get_name(0)
  local dir = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
  if vim.fn.isdirectory(dir) == 0 then dir = vim.fn.getcwd() end
  pick.files(nil, { source = { cwd = dir } })
end, { desc = "Files (current file's dir)" })
map("n", "<leader>b", pick.buffers,   { desc = "Buffers" })
map("n", "<leader>g", pick.grep_live, { desc = "Live grep" })
