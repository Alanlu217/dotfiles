-- Bridge to the C library in native/ (LuaJIT FFI).
--
-- Sources stay in the config dir (may be read-only, e.g. NixOS); the built
-- library lives in stdpath("data")/native. Each load stages a copy under a
-- name derived from the build, so :ReloadConfig can pick up a rebuilt library
-- (dlopen caches by path).
--
-- Nothing here blocks the editor: building uses vim.system, and scanning /
-- filtering run on libuv's thread pool. The native core is an accelerator:
-- every consumer must cope with it being unavailable.
local ffi = require("ffi")
local config = require("core.config")
local util = require("core.util")
local uv = vim.uv

local M = {}

local src_dir = vim.fs.joinpath(vim.fn.stdpath("config"), "native")
local build_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "native")
local loaded_dir = vim.fs.joinpath(build_dir, "loaded")
local ext = (jit.os == "OSX") and "dylib" or "so"
local lib_path = vim.fs.joinpath(build_dir, "libnvcore." .. ext)
local header_path = vim.fs.joinpath(src_dir, "include", "nvcore.h")

M.paths = { src = src_dir, build = build_dir, lib = lib_path }

-- Every library ever loaded in this process. Kept in _G so it survives
-- :ReloadConfig: an old library must never be dlclose'd while indices created
-- from it may still be alive.
_G.__nvcore_libs = _G.__nvcore_libs or {}

local state = {
  done = false, -- build + load finished (successfully or not)
  building = false,
  lib = nil,
  err = nil,
  libpath = nil, -- staged copy actually loaded; worker threads load the same file
  cdef = nil,
  waiters = {},
}

-- Build ----------------------------------------------------------------------

---@param targets string[]
---@return string[]
local function make_cmd(targets)
  local cmd = { "make", "-s", "-C", src_dir, "BUILD_DIR=" .. build_dir }
  return vim.list_extend(cmd, targets)
end

---@param res vim.SystemCompleted
---@return string
local function make_error(res)
  return vim.trim((res.stderr or "") .. (res.stdout or ""))
end

---@param targets string[]
---@return boolean ok, string? err
local function make_sync(targets)
  local started, proc = pcall(vim.system, make_cmd(targets), { text = true })
  if not started then
    return false, "cannot run make: " .. tostring(proc)
  end
  local res = proc:wait()
  if res.code ~= 0 then
    return false, make_error(res)
  end
  return true
end

---@param targets string[]
---@param cb fun(ok: boolean, err?: string)
local function make_async(targets, cb)
  local started, err = pcall(vim.system, make_cmd(targets), { text = true }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        cb(true)
      else
        cb(false, make_error(res))
      end
    end)
  end)
  if not started then
    vim.schedule(function()
      cb(false, "cannot run make: " .. tostring(err))
    end)
  end
end

-- Loading --------------------------------------------------------------------

--- Parse the public header into something ffi.cdef accepts.
---@return string cdef, integer abi
local function read_header()
  local f = assert(io.open(header_path, "r"))
  local src = "\n" .. f:read("*a")
  f:close()
  local abi = tonumber(src:match("#define%s+NV_ABI_VERSION%s+(%d+)")) or -1
  local cdef = src
    :gsub("/%*.-%*/", "")
    :gsub("//[^\n]*", "")
    :gsub("\n%s*#[^\n]*", "\n")
    :gsub("NV_API%s*", "")
  return cdef, abi
end

--- Copy the built library to a name derived from its mtime and size and return
--- that path. dlopen caches by path, so a fresh name is what makes a rebuilt
--- library loadable in a running session.
---@return string? path, string? err
local function stage()
  local st = uv.fs_stat(lib_path)
  if not st then
    return nil, "library not found: " .. lib_path
  end
  vim.fn.mkdir(loaded_dir, "p")

  local name = ("libnvcore-%d-%d-%d.%s"):format(st.mtime.sec, st.mtime.nsec, st.size, ext)
  local path = vim.fs.joinpath(loaded_dir, name)
  if not uv.fs_stat(path) then
    local ok, err = uv.fs_copyfile(lib_path, path)
    if not ok then
      return nil, "cannot stage library: " .. tostring(err)
    end
  end

  -- Prune older staged copies (unlinking a mapped file is safe on Unix).
  for fname in vim.fs.dir(loaded_dir) do
    if fname ~= name and fname:find("^libnvcore%-") then
      uv.fs_unlink(vim.fs.joinpath(loaded_dir, fname))
    end
  end
  return path
end

--- Everything after a successful build: declare, stage, load, verify.
---@return table? lib, string? err
local function init_lib()
  local ok, cdef, abi = pcall(read_header)
  if not ok then
    return nil, "cannot read header: " .. tostring(cdef)
  end

  -- Statement by statement, so a reload can pick up newly added functions;
  -- "redefine" errors for things already declared are expected.
  for stmt in cdef:gmatch("[^;]+;") do
    local cdef_ok, cdef_err = pcall(ffi.cdef, stmt)
    if not cdef_ok and not tostring(cdef_err):find("redefine") then
      return nil, "ffi.cdef failed: " .. tostring(cdef_err)
    end
  end

  local path, stage_err = stage()
  if not path then
    return nil, stage_err
  end

  local loaded, lib = pcall(ffi.load, path)
  if not loaded then
    return nil, "cannot load " .. path .. ": " .. tostring(lib)
  end
  if lib.nv_abi_version() ~= abi then
    return nil,
      ("ABI mismatch (header %d, library %d); run :NativeRebuild and restart"):format(abi, lib.nv_abi_version())
  end

  table.insert(_G.__nvcore_libs, lib)
  state.libpath, state.cdef = path, cdef
  return lib
end

---@param lib table?
---@param err string?
local function resolve(lib, err)
  state.done, state.building, state.lib, state.err = true, false, lib, err
  local waiters = state.waiters
  state.waiters = {}
  for _, cb in ipairs(waiters) do
    vim.schedule(function()
      cb(lib, err)
    end)
  end
end

--- Build (if needed) and load the library without blocking. `cb` always runs
--- on the main loop, never synchronously.
---@param cb fun(lib: table?, err: string?)
function M.ready(cb)
  if state.done then
    vim.schedule(function()
      cb(state.lib, state.err)
    end)
    return
  end
  table.insert(state.waiters, cb)
  if state.building then
    return
  end
  state.building = true

  if not config.get().native.auto_build then
    resolve(init_lib())
    return
  end
  make_async({ "all" }, function(ok, err)
    if ok then
      resolve(init_lib())
    else
      resolve(nil, "build failed: " .. err)
    end
  end)
end

--- Blocking variant, for :checkhealth only.
---@return table? lib, string? err
function M.load()
  if state.done then
    return state.lib, state.err
  end
  if state.building then
    return nil, "build in progress, try again in a moment"
  end
  if config.get().native.auto_build then
    local ok, err = make_sync({ "all" })
    if not ok then
      resolve(nil, "build failed: " .. err)
      return nil, state.err
    end
  end
  resolve(init_lib())
  return state.lib, state.err
end

local warned = false

--- Tell the user once per session that the Lua fallback is in use.
---@param err string?
function M.warn_unavailable(err)
  if warned then
    return
  end
  warned = true
  util.notify(
    ("Native core unavailable (%s). Using the slower Lua fallback; see :checkhealth core."):format(err or "unknown"),
    vim.log.levels.WARN
  )
end

function M.version()
  local lib = M.load()
  return lib and ffi.string(lib.nv_version()) or nil
end

-- Thread-pool jobs -----------------------------------------------------------

-- Runs in a libuv thread-pool thread: a separate Lua state with no `vim` and
-- no upvalues (the function is dumped and re-loaded there). Only ffi and the C
-- library are available; arguments and return values must be plain strings,
-- numbers or booleans. Returns: id, ok, r1, r2, r3.
local function worker(op, id, libpath, cdef, a, b, c, d)
  local ok, r1, r2, r3 = pcall(function()
    local ffi = require("ffi")
    for stmt in cdef:gmatch("[^;]+;") do
      pcall(ffi.cdef, stmt)
    end
    local lib = ffi.load(libpath)

    if op == "scan" then -- a=root b=ignore csv c=hidden d=max_files
      local ptr = lib.nv_index_scan(a, b, c, d)
      if ptr == nil then
        return 0, 0, false
      end
      return tonumber(ffi.cast("uintptr_t", ptr)), tonumber(lib.nv_index_count(ptr)), lib.nv_index_truncated(ptr) ~= 0
    end

    -- "filter": a=index address b=query c=limit
    local ptr = ffi.cast("nv_index *", ffi.cast("uintptr_t", a))
    local out = ffi.new("uint32_t[?]", c)
    local n = tonumber(lib.nv_index_filter(ptr, b, out, c))
    local items = {}
    for i = 0, n - 1 do
      items[i + 1] = ffi.string(lib.nv_index_get(ptr, out[i]))
    end
    return n, table.concat(items, "\0"), false
  end)
  if not ok then
    return id, false, tostring(r1), 0, false
  end
  return id, true, r1, r2, r3
end

local work
local jobs = {} ---@type table<integer, fun(ok: boolean, r1: any, r2: any, r3: any)>
local next_id = 0

---@param op "scan"|"filter"
---@param cb fun(ok: boolean, r1: any, r2: any, r3: any)
local function dispatch(op, cb, ...)
  work = work
    or uv.new_work(
      worker,
      vim.schedule_wrap(function(id, ok, r1, r2, r3)
        local job = jobs[id]
        jobs[id] = nil
        if job then
          job(ok, r1, r2, r3)
        end
      end)
    )
  next_id = next_id + 1
  jobs[next_id] = cb
  work:queue(op, next_id, state.libpath, state.cdef, ...)
end

-- Index ----------------------------------------------------------------------

---@class core.native.Index
---@field private ptr ffi.cdata*
---@field private addr integer
---@field private lib table
local Index = {}
Index.__index = Index

---@param lib table
---@param ptr ffi.cdata*?
---@return core.native.Index?
local function wrap(lib, ptr)
  if ptr == nil then
    return nil
  end
  return setmetatable({
    lib = lib,
    ptr = ffi.gc(ptr, lib.nv_index_free),
    addr = tonumber(ffi.cast("uintptr_t", ptr)),
  }, Index)
end

---@return integer
function Index:count()
  return tonumber(self.lib.nv_index_count(self.ptr))
end

---@return boolean
function Index:truncated()
  return self.lib.nv_index_truncated(self.ptr) ~= 0
end

--- Rank on a worker thread; `cb` runs on the main loop with the best matches.
---@param query string
---@param limit integer
---@param cb fun(items: string[])
function Index:filter_async(query, limit, cb)
  local keep_alive = self -- the index must outlive the worker's read of it
  dispatch("filter", function(ok, n, joined)
    local _ = keep_alive
    if not ok or n == 0 then
      cb({})
    else
      cb(vim.split(joined, "\0", { plain = true }))
    end
  end, self.addr, query, limit)
end

--- Walk `root` on a worker thread. Requires M.ready() to have succeeded.
---@param root string
---@param opts { ignore: string[], hidden: boolean, max_files: integer }
---@param cb fun(idx: core.native.Index?, err: string?)
function M.scan_async(root, opts, cb)
  local lib = state.lib
  if not lib then
    cb(nil, state.err or "native core not loaded")
    return
  end
  dispatch("scan", function(ok, addr)
    if not ok then
      cb(nil, addr)
    elseif addr == 0 then
      cb(nil, "allocation failed")
    else
      cb(wrap(lib, ffi.cast("nv_index *", ffi.cast("uintptr_t", addr))))
    end
  end, root, table.concat(opts.ignore, ","), opts.hidden and 1 or 0, opts.max_files)
end

--- Items must not contain newlines. Requires M.ready() to have succeeded.
---@param items string[]
---@return core.native.Index?
function M.from_list(items)
  local lib = state.lib
  if not lib then
    return nil
  end
  local text = table.concat(items, "\n")
  return wrap(lib, lib.nv_index_from_text(text, #text))
end

function M.setup()
  vim.api.nvim_create_user_command("NativeRebuild", function()
    util.notify("Rebuilding native core...")
    make_async({ "clean", "all" }, function(ok, err)
      if ok then
        util.notify("Native core rebuilt. Run :ReloadConfig to load it.")
      else
        util.notify("Native build failed:\n" .. err, vim.log.levels.ERROR)
      end
    end)
  end, { desc = "Clean and rebuild the native C library" })

  -- Start building/loading in the background so it is ready before first use.
  M.ready(function() end)
end

return M
