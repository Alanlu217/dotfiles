local map = vim.keymap.set
local autocmd = vim.api.nvim_create_autocmd
local augroup = require("config.util").augroup

map("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
map("n", "<leader>t", ":botright 15split | terminal<CR>", { desc = "Terminal (bottom)" })
map("n", "<leader>T", ":botright vsplit | terminal<CR>", { desc = "Terminal (vertical)" })

local term_group = augroup("TerminalBehaviour")

autocmd({ "TermOpen", "BufEnter", "WinEnter" }, {
  group = term_group,
  pattern = "term://*",
  command = "startinsert",
})

autocmd("TermClose", {
  group = term_group,
  callback = function(args)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(args.buf) then
        vim.api.nvim_buf_delete(args.buf, { force = true })
      end
    end)
  end,
})

-- Floating terminal: <C-\> toggles; the shell persists while hidden
local float = { buf = nil, win = nil }

local function float_open()
  if not (float.buf and vim.api.nvim_buf_is_valid(float.buf)) then
    float.buf = vim.api.nvim_create_buf(false, true)
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  float.win = vim.api.nvim_open_win(float.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2) - 1,
    style = "minimal",
    border = "rounded",
  })

  -- Start a shell only the first time (or after the previous one exited)
  if vim.bo[float.buf].buftype ~= "terminal" then
    vim.fn.jobstart(vim.o.shell, { term = true })
  end
  vim.cmd.startinsert()
end

local function float_toggle()
  if float.win and vim.api.nvim_win_is_valid(float.win) then
    vim.api.nvim_win_hide(float.win)
    float.win = nil
  else
    float_open()
  end
end

map({ "n", "t" }, "<C-\\>", float_toggle, { desc = "Terminal (floating)" })
