-- Things to pick from. Each source builds a matcher and says what to do with a pick.
local config = require("core.config")
local matcher = require("core.picker.matcher")
local ui = require("core.picker.ui")
local util = require("core.util")

local M = {}

---@param path string
---@param action string
local function open_file(path, action)
  vim.cmd(("%s %s"):format(action, vim.fn.fnameescape(path)))
end

---@param opts? { root?: string }
function M.files(opts)
  local cfg = config.get().picker
  local root = (opts and opts.root) or vim.uv.cwd()
  ui.open({
    title = "Files",
    matcher = matcher.from_scan(root, { ignore = cfg.ignore, hidden = cfg.hidden, max_files = cfg.max_files }),
    on_select = function(item, action)
      open_file(vim.fs.joinpath(root, item), action)
    end,
  })
end

function M.buffers()
  local infos = vim.fn.getbufinfo({ buflisted = 1 })
  table.sort(infos, function(a, b)
    return a.lastused > b.lastused
  end)
  local current, items = vim.api.nvim_get_current_buf(), {}
  for _, info in ipairs(infos) do
    if info.bufnr ~= current then
      local name = info.name ~= "" and vim.fn.fnamemodify(info.name, ":~:.") or "[No Name]"
      items[#items + 1] = ("[%d] %s%s"):format(info.bufnr, name:gsub("[\r\n]", " "), info.changed == 1 and " +" or "")
    end
  end

  local cmds = { edit = "buffer", split = "sbuffer", vsplit = "vertical sbuffer", tabedit = "tab sbuffer" }
  ui.open({
    title = "Buffers",
    matcher = matcher.from_list(items),
    on_select = function(item, action)
      local nr = tonumber(item:match("^%[(%d+)%]"))
      if nr and vim.api.nvim_buf_is_valid(nr) then
        vim.cmd(("%s %d"):format(cmds[action], nr))
      end
    end,
  })
end

function M.recent()
  local items = {}
  for _, file in ipairs(vim.v.oldfiles) do
    if vim.fn.filereadable(file) == 1 then
      items[#items + 1] = (vim.fn.fnamemodify(file, ":~"):gsub("[\r\n]", " "))
    end
  end
  ui.open({
    title = "Recent files",
    matcher = matcher.from_list(items),
    on_select = function(item, action)
      open_file(vim.fn.fnamemodify(item, ":p"), action)
    end,
  })
end

--- Every tag from the doc/tags files on the runtimepath (core docs and plugins).
--- getcompletion("", "help") can't be used: for an empty pattern Neovim
--- substitutes "help" to keep :help <Tab> fast, so it returns only a few tags.
---@return string[]
local function help_tags()
  local seen, tags = {}, {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file("doc/tags", true)) do
    local f = io.open(path, "r")
    if f then
      for line in f:lines() do
        local tag = line:match("^([^\t]+)\t")
        if tag and not seen[tag] and tag:sub(1, 6) ~= "!_TAG_" then
          seen[tag] = true
          tags[#tags + 1] = tag
        end
      end
      f:close()
    end
  end
  table.sort(tags)
  return tags
end

function M.help()
  -- :help always opens its own window, so "edit" and "split" are the same.
  local cmds = { edit = "help", split = "help", vsplit = "vertical help", tabedit = "tab help" }
  ui.open({
    title = "Help",
    matcher = matcher.from_list(help_tags()),
    on_select = function(tag, action)
      local ok, err = pcall(vim.cmd, ("%s %s"):format(cmds[action], tag))
      if not ok then
        util.notify(("No help for '%s':\n%s"):format(tag, err), vim.log.levels.WARN)
      end
    end,
  })
end

return M
