-- A matcher ranks a fixed set of strings against a query, asynchronously.
-- Backend is the native index when available, otherwise a pure-Lua fallback.
-- Matchers are created immediately and become usable later: while `loading`
-- is true, count() is 0 and filter() yields nothing; subscribers are notified
-- once loading finishes.
local native = require("core.native")

local M = {}

---@class core.Matcher
---@field loading boolean
---@field truncated boolean
---@field count fun(): integer
---@field filter fun(query: string, limit: integer, cb: fun(items: string[]))
---@field subscribe fun(fn: fun()) called when loading finishes
---@field dispose fun() stop work and drop subscribers

---@return core.Matcher
local function new()
  local m = { loading = true, truncated = false, disposed = false }
  local listeners = {}

  m.count = function()
    return 0
  end
  m.filter = function(_, _, cb)
    cb({})
  end
  m.subscribe = function(fn)
    listeners[#listeners + 1] = fn
  end
  m.dispose = function()
    m.disposed = true
    listeners = {}
  end
  m.finish = function()
    if m.disposed then
      return
    end
    m.loading = false
    for _, fn in ipairs(listeners) do
      fn()
    end
  end
  return m
end

---@param m core.Matcher
---@param idx core.native.Index
local function use_index(m, idx)
  m.count = function()
    return idx:count()
  end
  m.filter = function(query, limit, cb)
    idx:filter_async(query, limit, cb)
  end
  m.truncated = idx:truncated()
end

--- Fallback: synchronous matchfuzzy, fine for modest lists.
---@param m core.Matcher
---@param items string[]
---@param truncated? boolean
local function use_list(m, items, truncated)
  m.count = function()
    return #items
  end
  m.filter = function(query, limit, cb)
    if query == "" then
      cb(vim.list_slice(items, 1, limit))
    else
      cb(vim.fn.matchfuzzy(items, query, { limit = limit }))
    end
  end
  m.truncated = truncated or false
end

---@param full string
---@param kind string?
---@return string?
local function resolve_kind(full, kind)
  if kind == "link" then -- keep links to files, never follow links to directories
    local st = vim.uv.fs_stat(full)
    return (st and st.type == "file") and "file" or nil
  end
  if kind == nil then
    local st = vim.uv.fs_lstat(full)
    if not st then
      return nil
    end
    return st.type == "link" and resolve_kind(full, "link") or st.type
  end
  return kind
end

--- Pure-Lua incremental directory walk; yields to the event loop every ~8ms.
---@param m core.Matcher
---@param root string
---@param opts { ignore: string[], hidden: boolean, max_files: integer }
---@param done fun(items: string[], truncated: boolean)
local function lua_scan(m, root, opts, done)
  local ignore = {}
  for _, name in ipairs(opts.ignore) do
    ignore[name] = true
  end
  local items, stack, truncated = {}, { "" }, false

  local function step()
    if m.disposed then
      return
    end
    local deadline = vim.uv.hrtime() + 8e6
    while #stack > 0 and not truncated and vim.uv.hrtime() < deadline do
      local rel = table.remove(stack)
      local dir = rel == "" and root or (root .. "/" .. rel)
      local req = vim.uv.fs_scandir(dir)
      while req do
        local name, kind = vim.uv.fs_scandir_next(req)
        if not name then
          break
        end
        if not ignore[name] and (opts.hidden or name:sub(1, 1) ~= ".") then
          local path = rel == "" and name or (rel .. "/" .. name)
          kind = resolve_kind(root .. "/" .. path, kind)
          if kind == "directory" then
            stack[#stack + 1] = path
          elseif kind == "file" then
            if #items >= opts.max_files then
              truncated = true
              break
            end
            items[#items + 1] = path
          end
        end
      end
    end

    if truncated or #stack == 0 then
      table.sort(items)
      done(items, truncated)
    else
      vim.schedule(step)
    end
  end

  vim.schedule(step)
end

---@param items string[] items must not contain newlines
---@return core.Matcher
function M.from_list(items)
  local m = new()
  native.ready(function(lib, err)
    if m.disposed then
      return
    end
    local idx = lib and native.from_list(items)
    if idx then
      use_index(m, idx)
    else
      if not lib then
        native.warn_unavailable(err)
      end
      use_list(m, items)
    end
    m.finish()
  end)
  return m
end

---@param root string
---@param opts { ignore: string[], hidden: boolean, max_files: integer }
---@return core.Matcher
function M.from_scan(root, opts)
  local m = new()

  local function fallback()
    lua_scan(m, root, opts, function(items, truncated)
      if m.disposed then
        return
      end
      use_list(m, items, truncated)
      m.finish()
    end)
  end

  native.ready(function(lib, err)
    if m.disposed then
      return
    end
    if not lib then
      native.warn_unavailable(err)
      return fallback()
    end
    native.scan_async(root, opts, function(idx, scan_err)
      if m.disposed then
        return
      end
      if not idx then
        native.warn_unavailable(scan_err)
        return fallback()
      end
      use_index(m, idx)
      m.finish()
    end)
  end)
  return m
end

return M
