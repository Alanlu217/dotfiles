-- Bridge to the C library in native/ (LuaJIT FFI).
--
-- Sources stay in the config dir (may be read-only, e.g. NixOS); the built
-- library lives in stdpath("data")/native. The native core is an accelerator:
-- every consumer must cope with `load()` returning nil.
local ffi = require("ffi")
local config = require("core.config")
local util = require("core.util")

local M = {}

local src_dir = vim.fs.joinpath(vim.fn.stdpath("config"), "native")
local build_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "native")
local ext = (jit.os == "OSX") and "dylib" or "so"
local lib_path = vim.fs.joinpath(build_dir, "libnvcore." .. ext)
local header_path = vim.fs.joinpath(src_dir, "include", "nvcore.h")
local loaded_dir = vim.fs.joinpath(build_dir, "loaded")

-- Every library ever loaded in this process. Kept in _G so it survives
-- :ReloadConfig: an old library must never be dlclose'd while indices created
-- from it may still be alive.
_G.__nvcore_libs = _G.__nvcore_libs or {}

M.paths = { src = src_dir, build = build_dir, lib = lib_path }

local state = { tried = false, lib = nil, err = nil }

---@param targets string[]
---@return boolean ok, string? err
local function make(targets)
  local cmd = { "make", "-s", "-C", src_dir, "BUILD_DIR=" .. build_dir }
  vim.list_extend(cmd, targets)
  local started, proc = pcall(vim.system, cmd, { text = true })
  if not started then
    return false, "cannot run make: " .. tostring(proc)
  end
  local res = proc:wait()
  if res.code ~= 0 then
    return false, vim.trim((res.stderr or "") .. (res.stdout or ""))
  end
  return true
end

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
  local st = vim.uv.fs_stat(lib_path)
  if not st then
    return nil, "library not found: " .. lib_path
  end
  vim.fn.mkdir(loaded_dir, "p")

  local name = ("libnvcore-%d-%d-%d.%s"):format(st.mtime.sec, st.mtime.nsec, st.size, ext)
  local path = vim.fs.joinpath(loaded_dir, name)
  if not vim.uv.fs_stat(path) then
    local ok, err = vim.uv.fs_copyfile(lib_path, path)
    if not ok then
      return nil, "cannot stage library: " .. tostring(err)
    end
  end

  -- Prune older staged copies (unlinking a mapped file is safe on Unix).
  for fname in vim.fs.dir(loaded_dir) do
    if fname ~= name and fname:find("^libnvcore%-") then
      vim.uv.fs_unlink(vim.fs.joinpath(loaded_dir, fname))
    end
  end
  return path
end

---@return table? lib, string? err
function M.load()
  if state.tried then
    return state.lib, state.err
  end
  state.tried = true

  if config.get().native.auto_build then
    local ok, err = make({ "all" })
    if not ok then
      state.err = "build failed: " .. err
      return nil, state.err
    end
  end

  local ok, header_or_err, abi = pcall(read_header)
  if not ok then
    state.err = "cannot read header: " .. tostring(header_or_err)
    return nil, state.err
  end

  -- Declare statement by statement so a reload can pick up newly added
  -- functions; "redefine" errors for things already declared are expected.
  for stmt in header_or_err:gmatch("[^;]+;") do
    local cdef_ok, cdef_err = pcall(ffi.cdef, stmt)
    if not cdef_ok and not tostring(cdef_err):find("redefine") then
      state.err = "ffi.cdef failed: " .. tostring(cdef_err)
      return nil, state.err
    end
  end

  local path, stage_err = stage()
  if not path then
    state.err = stage_err
    return nil, state.err
  end

  local loaded, lib = pcall(ffi.load, path)
  if not loaded then
    state.err = "cannot load " .. path .. ": " .. tostring(lib)
    return nil, state.err
  end
  if lib.nv_abi_version() ~= abi then
    state.err = ("ABI mismatch (header %d, library %d); run :NativeRebuild and restart"):format(
      abi,
      lib.nv_abi_version()
    )
    return nil, state.err
  end

  table.insert(_G.__nvcore_libs, lib)
  state.lib = lib
  return lib
end

local warned = false

--- Like load(), but warns once per session when unavailable.
---@return table? lib
function M.available()
  local lib, err = M.load()
  if not lib and not warned then
    warned = true
    util.notify(
      ("Native core unavailable (%s). Using the slower Lua fallback; see :checkhealth core."):format(err),
      vim.log.levels.WARN
    )
  end
  return lib
end

function M.version()
  local lib = M.load()
  return lib and ffi.string(lib.nv_version()) or nil
end

---@class core.native.Index
---@field private ptr ffi.cdata*
---@field private lib table
---@field private out table<integer, ffi.cdata*>
local Index = {}
Index.__index = Index

---@param lib table
---@param ptr ffi.cdata*?
---@return core.native.Index?
local function wrap(lib, ptr)
  if ptr == nil then
    return nil
  end
  return setmetatable({ lib = lib, ptr = ffi.gc(ptr, lib.nv_index_free), out = {} }, Index)
end

---@return integer
function Index:count()
  return tonumber(self.lib.nv_index_count(self.ptr))
end

---@return boolean
function Index:truncated()
  return self.lib.nv_index_truncated(self.ptr) ~= 0
end

---@param query string
---@param limit integer
---@return string[]
function Index:filter(query, limit)
  local buf = self.out[limit]
  if not buf then
    buf = ffi.new("uint32_t[?]", limit)
    self.out[limit] = buf
  end
  local n = tonumber(self.lib.nv_index_filter(self.ptr, query, buf, limit))
  local res = {}
  for i = 0, n - 1 do
    res[i + 1] = ffi.string(self.lib.nv_index_get(self.ptr, buf[i]))
  end
  return res
end

---@param root string
---@param opts { ignore: string[], hidden: boolean, max_files: integer }
---@return core.native.Index?
function M.scan(root, opts)
  local lib = M.load()
  if not lib then
    return nil
  end
  return wrap(lib, lib.nv_index_scan(root, table.concat(opts.ignore, ","), opts.hidden and 1 or 0, opts.max_files))
end

--- Items must not contain newlines.
---@param items string[]
---@return core.native.Index?
function M.from_list(items)
  local lib = M.load()
  if not lib then
    return nil
  end
  local text = table.concat(items, "\n")
  return wrap(lib, lib.nv_index_from_text(text, #text))
end

function M.setup()
  vim.api.nvim_create_user_command("NativeRebuild", function()
    util.notify("Rebuilding native core...")
    local ok, err = make({ "clean", "all" })
    if ok then
      util.notify("Native core rebuilt. Run :ReloadConfig to load it.")
    else
      util.notify("Native build failed:\n" .. err, vim.log.levels.ERROR)
    end
  end, { desc = "Clean and rebuild the native C library" })
end

return M
