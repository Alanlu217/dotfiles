vim.pack.add { "https://github.com/echasnovski/mini.files" }

local map = vim.keymap.set
local augroup = require("util").augroup

require("mini.files").setup({
  windows = { preview = true, width_focus = 30, width_preview = 50 },
})

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

-- Search
local function files_search_here()
  local state = MiniFiles.get_explorer_state()
  if not state then return end
  local cwd = state.branch[state.depth_focus]
  MiniFiles.close()

  require('mini.pick').builtin.files(nil, {
    source = {
      cwd = cwd,
      choose = function(item)
        local path = vim.fs.joinpath(cwd, item)
        vim.schedule(function() MiniFiles.open(path) end)
      end,
    },
  })
end

-- Explorer buffer-local keys
vim.api.nvim_create_autocmd("User", {
  group = augroup("MiniFilesKeys"),
  pattern = "MiniFilesBufferCreate",
  callback = function(args)
    local function bmap(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = args.data.buf_id, desc = desc })
    end

    local show_dotfiles = true
    local function toggle_dotfiles()
      show_dotfiles = not show_dotfiles
      MiniFiles.refresh({ content = { filter = show_dotfiles
        and function() return true end
        or function(e) return not vim.startswith(e.name, ".") end } })
    end

    local function open_split(direction)
      local entry = MiniFiles.get_fs_entry()
      if not entry or entry.fs_type ~= "file" then return end
      local win = vim.api.nvim_win_call(MiniFiles.get_explorer_state().target_window, function()
        vim.cmd("belowright " .. direction .. " split")
        return vim.api.nvim_get_current_win()
      end)
      MiniFiles.set_target_window(win)
      MiniFiles.go_in({ close_on_file = true })
    end

    bmap("g.", toggle_dotfiles, "Toggle dotfiles")
    bmap("<C-w>s", function() open_split("horizontal") end, "Open in split")
    bmap("<C-w>v", function() open_split("vertical") end, "Open in vsplit")
    bmap("gy", function()
      local e = MiniFiles.get_fs_entry()
      if e then vim.fn.setreg(vim.v.register, e.path) end
    end, "Yank path")
    bmap("gx", function()
      local e = MiniFiles.get_fs_entry()
      if e then vim.ui.open(e.path) end
    end, "Open externally")
    bmap("<CR>", function() MiniFiles.go_in({ close_on_file = true }) end, "Open and close on file")
    bmap("<Right>", MiniFiles.go_in, "Go in")
    bmap("<Left>", MiniFiles.go_out, "Go out")
    bmap("<leader>C", set_cwd, "Set cwd")
  end,
})
