-- Saved directories ("projects") and switching between them.
--
-- Switching is a plain :cd / :tcd / :lcd, so the scope is Neovim's own: a window
-- directory beats a tab directory, which beats the global one. The file picker
-- and new terminals follow whichever applies. Only directories are stored (no
-- buffers or layouts); keys live in lua/user/keymaps.lua.
--
--   :Project [global|tab|window]   pick a project and switch to it
--   :ProjectAdd [path]             save a directory (default: the current one)
--   :ProjectRemove / :ProjectRename / :ProjectPrune
--
-- In the project picker <CR> uses the scope you asked for, <C-t> opens the
-- project in a new tab (:tcd) and <C-s> / <C-v> in a new split (:lcd).
local config = require("core.config")
local util = require("core.util")

local M = {}

---@class core.Project
---@field name string
---@field path string absolute, symlinks resolved, no trailing slash
---@field used? integer os.time() of the last switch

local SCOPES = { global = "cd", tab = "tcd", window = "lcd" }

local cache ---@type core.Project[]?

---@return table
local function cfg()
  return config.get().projects
end

---@param path string
---@return string
local function normalize(path)
  local full = vim.fn.fnamemodify(vim.fs.normalize(path), ":p")
  full = vim.uv.fs_realpath(full) or full
  return (vim.fs.normalize(full):gsub("(.)/+$", "%1"))
end

---@return core.Project[]
local function load()
  if cache then
    return cache
  end
  cache = {}

  local file = cfg().file
  local f = io.open(file, "r")
  if not f then
    return cache
  end
  local text = f:read("*a")
  f:close()
  if text:match("^%s*$") then
    return cache
  end

  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    local bad = file .. ".corrupt"
    vim.uv.fs_rename(file, bad)
    util.notify(("Could not read %s; moved it to %s"):format(file, bad), vim.log.levels.WARN)
    return cache
  end
  for _, p in ipairs(data) do
    if type(p) == "table" and type(p.name) == "string" and type(p.path) == "string" then
      cache[#cache + 1] = { name = p.name, path = p.path, used = tonumber(p.used) }
    end
  end
  return cache
end

---@return boolean
local function save()
  local file = cfg().file
  vim.fn.mkdir(vim.fs.dirname(file), "p")
  local tmp = file .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then
    util.notify(("Could not write %s: %s"):format(tmp, err), vim.log.levels.ERROR)
    return false
  end
  f:write(vim.json.encode(load()))
  f:close()
  local ok, rename_err = vim.uv.fs_rename(tmp, file)
  if not ok then
    util.notify(("Could not write %s: %s"):format(file, rename_err), vim.log.levels.ERROR)
    return false
  end
  return true
end

--- Saved projects, most recently used first.
---@return core.Project[]
function M.list()
  local list = vim.list_slice(load(), 1)
  table.sort(list, function(a, b)
    local ua, ub = a.used or 0, b.used or 0
    if ua ~= ub then
      return ua > ub
    end
    return a.name:lower() < b.name:lower()
  end)
  return list
end

---@param path string normalized
---@return core.Project?
local function find(path)
  for _, p in ipairs(load()) do
    if p.path == path then
      return p
    end
  end
end

---@param p core.Project
---@return boolean
local function exists(p)
  return vim.fn.isdirectory(p.path) == 1
end

---@param p core.Project
---@param current string
---@return string
local function label(p, current)
  local text = ("%s  %s"):format(p.name, vim.fn.fnamemodify(p.path, ":~"))
  if p.path == current then
    text = text .. "  (current)"
  end
  if not exists(p) then
    text = text .. "  (missing)"
  end
  return (text:gsub("[\r\n]+", " "))
end

--- Open the picker over the saved projects.
---@param title string
---@param on_pick fun(p: core.Project, action: "edit"|"split"|"vsplit"|"tabedit")
local function choose(title, on_pick)
  local list = M.list()
  if #list == 0 then
    util.notify("No projects saved yet. :ProjectAdd saves the current directory.")
    return
  end

  local picker = require("core.picker")
  local current = normalize(vim.uv.cwd())
  local labels, lookup = {}, {}
  for i, p in ipairs(list) do
    labels[i] = label(p, current)
    lookup[labels[i]] = p
  end

  picker.open({
    title = title,
    matcher = picker.matcher(labels),
    on_select = function(item, action)
      local p = lookup[item]
      if p then
        on_pick(p, action)
      end
    end,
  })
end

---@param p core.Project
---@param scope "global"|"tab"|"window"
local function enter(p, scope)
  local ok, err = pcall(vim.cmd, ("%s %s"):format(SCOPES[scope], vim.fn.fnameescape(p.path)))
  if not ok then
    util.notify(("Could not switch to %s:\n%s"):format(p.path, err), vim.log.levels.ERROR)
    return
  end
  p.used = os.time()
  save()
  util.notify(("Project '%s' (%s)"):format(p.name, scope))
  if cfg().open_files then
    require("core.picker").files({ root = p.path })
  end
end

--- Pick a project and make it the working directory.
---@param scope? "global"|"tab"|"window" default: config.projects.scope
function M.switch(scope)
  scope = scope or cfg().scope
  if not SCOPES[scope] then
    util.notify(("Project: unknown scope '%s' (global|tab|window)"):format(tostring(scope)), vim.log.levels.ERROR)
    return
  end

  choose(("Project (%s)"):format(scope), function(p, action)
    if not exists(p) then
      util.notify(("'%s' no longer exists (%s). :ProjectPrune drops missing projects."):format(p.name, p.path), vim.log.levels.WARN)
      return
    end
    if action == "tabedit" then
      vim.cmd.tabnew()
      enter(p, "tab")
    elseif action == "split" then
      vim.cmd.split()
      enter(p, "window")
    elseif action == "vsplit" then
      vim.cmd.vsplit()
      enter(p, "window")
    else
      enter(p, scope)
    end
  end)
end

--- Save a directory as a project.
---@param path? string default: the current working directory
function M.add(path)
  local root = normalize((path and path ~= "") and path or vim.uv.cwd())
  if vim.fn.isdirectory(root) == 0 then
    util.notify("Not a directory: " .. root, vim.log.levels.ERROR)
    return
  end
  local existing = find(root)
  if existing then
    util.notify(("Already saved as '%s'"):format(existing.name))
    return
  end

  local name = vim.fs.basename(root)
  if name == "" then
    name = root
  end
  table.insert(load(), { name = name, path = root, used = os.time() })
  if save() then
    util.notify(("Saved project '%s' (%s)"):format(name, vim.fn.fnamemodify(root, ":~")))
  end
end

function M.remove()
  choose("Remove project", function(p)
    local list = load()
    for i, q in ipairs(list) do
      if q == p then
        table.remove(list, i)
        break
      end
    end
    if save() then
      util.notify(("Removed project '%s'"):format(p.name))
    end
  end)
end

function M.rename()
  choose("Rename project", function(p)
    vim.ui.input({ prompt = "Project name: ", default = p.name }, function(name)
      name = name and vim.trim(name)
      if not name or name == "" or name == p.name then
        return
      end
      p.name = name
      save()
    end)
  end)
end

--- Drop projects whose directory no longer exists.
function M.prune()
  local kept, removed = {}, 0
  for _, p in ipairs(load()) do
    if exists(p) then
      kept[#kept + 1] = p
    else
      removed = removed + 1
    end
  end
  if removed == 0 then
    util.notify("No missing projects")
    return
  end
  cache = kept
  if save() then
    util.notify(("Removed %d missing project(s)"):format(removed))
  end
end

function M.setup()
  local scopes = vim.tbl_keys(SCOPES)
  table.sort(scopes)

  vim.api.nvim_create_user_command("Project", function(o)
    M.switch(o.args ~= "" and o.args or nil)
  end, {
    nargs = "?",
    complete = function()
      return scopes
    end,
    desc = "Switch project (global|tab|window)",
  })
  vim.api.nvim_create_user_command("ProjectAdd", function(o)
    M.add(o.args)
  end, { nargs = "?", complete = "dir", desc = "Save a directory as a project (default: cwd)" })
  vim.api.nvim_create_user_command("ProjectRemove", M.remove, { desc = "Remove a saved project" })
  vim.api.nvim_create_user_command("ProjectRename", M.rename, { desc = "Rename a saved project" })
  vim.api.nvim_create_user_command("ProjectPrune", M.prune, { desc = "Remove projects whose directory is gone" })
end

return M
