vim.pack.add { "https://github.com/echasnovski/mini.files" }

local map = vim.keymap.set
local augroup = require("util").augroup

require("mini.files").setup()

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
  group = augroup("MiniFilesKeys"),
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
