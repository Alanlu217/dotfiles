local native = require("core.ffi")
local ffi = require("ffi")
local M = {}

function M.files()
  local buf = vim.api.nvim_create_buf(false, true)
  local prompt_buf = vim.api.nvim_create_buf(false, true)

  local width = math.floor(vim.o.columns * 0.7)
  local height = math.floor(vim.o.lines * 0.7)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height - 2,
    row = row + 2,
    col = col,
    style = "minimal",
    border = "single",
  })

  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = "editor",
    width = width,
    height = 1,
    row = row,
    col = col,
    style = "minimal",
    border = "single",
  })

  vim.bo[prompt_buf].buftype = "prompt"
  vim.fn.prompt_setprompt(prompt_buf, "   ")

  local function update_results(query)
    local c_str = native.search_directory(".", query)
    local lines = {}

    if c_str ~= nil then
      local result = ffi.string(c_str)
      native.free_string(c_str)
      lines = vim.split(result, "\n", { trimempty = true })
    end

    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
  end

  -- Initial population
  update_results("")

  -- Live search callback triggered on input
  vim.fn.prompt_setcallback(prompt_buf, function(text)
    update_results(text)
    vim.cmd.startinsert()
  end)

  vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_get_current_line()
    vim.api.nvim_win_close(win, true)
    if vim.api.nvim_win_is_valid(prompt_win) then vim.api.nvim_win_close(prompt_win, true) end
    if line ~= "" then vim.cmd("edit " .. vim.fn.fnameescape(line)) end
  end, { buffer = buf })

  local function close_picker()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_win_is_valid(prompt_win) then vim.api.nvim_win_close(prompt_win, true) end
  end

  vim.keymap.set("n", "<Esc>", close_picker, { buffer = prompt_buf })
  vim.keymap.set("i", "<C-c>", close_picker, { buffer = prompt_buf })
  vim.keymap.set("n", "<Esc>", close_picker, { buffer = buf })

  vim.keymap.set({"n", "i"}, "<C-n>", function() vim.api.nvim_set_current_win(win) end, { buffer = prompt_buf })
  vim.keymap.set("n", "<C-p>", function() vim.api.nvim_set_current_win(prompt_win); vim.cmd.startinsert() end, { buffer = buf })
end

return M
