-- Path source: entries of the directory named by the path-like word before the
-- cursor. Only active when that directory exists, so `a/b` in code or `//`
-- comments never turn into path completion.
local config = require("core.config")

local M = {}

M.name = "path"

--- Detect a path being typed.
---@param ctx { before: string, buf: integer }
---@return { dir: string, frag: string }? where `frag` is the part after the last "/"
function M.detect(ctx)
  local token = ctx.before:match("[^%s\"'`<>()|;,=%[%]{}]*$")
  if not token or not token:find("/", 1, true) or token:find("^//") then
    return nil
  end
  local dir, frag = token:match("^(.*/)([^/]*)$")
  if not dir then
    return nil
  end

  local candidates = {}
  if dir:find("^[/~$]") then
    candidates[1] = dir
  else
    local bufdir = vim.fs.dirname(vim.api.nvim_buf_get_name(ctx.buf))
    if bufdir and bufdir ~= "" and bufdir ~= "." then
      candidates[#candidates + 1] = bufdir .. "/" .. dir
    end
    candidates[#candidates + 1] = dir -- relative to the working directory
  end

  for _, candidate in ipairs(candidates) do
    local full = vim.fs.normalize(candidate)
    local st = vim.uv.fs_stat(full)
    if st and st.type == "directory" then
      return { dir = full, frag = frag }
    end
  end
  return nil
end

---@param ctx table with `path = { dir, frag }`
---@param cb fun(items: table[], incomplete: boolean)
---@return fun() cancel
function M.fetch(ctx, cb)
  local cfg = config.get().completion.path
  local items = {}
  local show_hidden = ctx.path.frag:sub(1, 1) == "."

  local req = vim.uv.fs_scandir(ctx.path.dir)
  while req and #items < cfg.max_entries do
    local name, kind = vim.uv.fs_scandir_next(req)
    if not name then
      break
    end
    if show_hidden or name:sub(1, 1) ~= "." then
      if kind == "link" or kind == nil then
        local st = vim.uv.fs_stat(ctx.path.dir .. "/" .. name)
        kind = st and st.type or "file"
      end
      local is_dir = kind == "directory"
      local text = is_dir and (name .. "/") or name
      items[#items + 1] = {
        source = "path",
        label = text,
        filter = name,
        sort = (is_dir and "0" or "1") .. name, -- directories first
        kind = is_dir and "Dir" or "File",
        menu = "path",
        insert = text,
        retrigger = is_dir, -- keep going after accepting a directory
      }
    end
  end

  cb(items, false)
  return function() end
end

return M
