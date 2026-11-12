-- A matcher ranks a fixed set of strings against a query.
-- Backend is the native index when available, otherwise a pure-Lua fallback.
local native = require("core.native")

local M = {}

---@class core.Matcher
---@field count fun(): integer
---@field filter fun(query: string, limit: integer): string[]
---@field truncated boolean

---@param idx core.native.Index
---@return core.Matcher
local function from_index(idx)
  return {
    count = function()
      return idx:count()
    end,
    filter = function(query, limit)
      return idx:filter(query, limit)
    end,
    truncated = idx:truncated(),
  }
end

---@param items string[]
---@param truncated? boolean
---@return core.Matcher
local function from_lua(items, truncated)
  return {
    count = function()
      return #items
    end,
    filter = function(query, limit)
      if query == "" then
        return vim.list_slice(items, 1, limit)
      end
      return vim.fn.matchfuzzy(items, query, { limit = limit })
    end,
    truncated = truncated or false,
  }
end

---@param items string[] items must not contain newlines
---@return core.Matcher
function M.from_list(items)
  if native.available() then
    local idx = native.from_list(items)
    if idx then
      return from_index(idx)
    end
  end
  return from_lua(items)
end

---@param root string
---@param opts { ignore: string[], hidden: boolean, max_files: integer }
---@return core.Matcher
function M.from_scan(root, opts)
  if native.available() then
    local idx = native.scan(root, opts)
    if idx then
      return from_index(idx)
    end
  end

  local ignore = {}
  for _, name in ipairs(opts.ignore) do
    ignore[name] = true
  end
  local items, truncated = {}, false
  local iter = vim.fs.dir(root, {
    depth = 64,
    skip = function(dir)
      local base = vim.fs.basename(dir)
      return ignore[base] or (not opts.hidden and base:sub(1, 1) == ".") or nil
    end,
  })
  for name, kind in iter do
    local base = vim.fs.basename(name)
    local hidden = base:sub(1, 1) == "." or name:find("/%.", 1, false) ~= nil
    if kind == "file" and not ignore[base] and (opts.hidden or not hidden) then
      if #items >= opts.max_files then
        truncated = true
        break
      end
      items[#items + 1] = name
    end
  end
  table.sort(items)
  return from_lua(items, truncated)
end

return M
