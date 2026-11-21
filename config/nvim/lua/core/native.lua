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
local header_path = vim.fs.joinpath(src_dir, "nvcore.h")

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

-- Toolchain ------------------------------------------------------------------

-- How to install GNU make and a C compiler, per platform. Order matters only
-- for the "all platforms" listing.
local installers = {
  { id = "termux", name = "Termux (Android)", cmd = "pkg install make clang" },
  { id = "macos", name = "macOS", cmd = "xcode-select --install" },
  { id = "debian", name = "Debian / Ubuntu / Mint", cmd = "sudo apt install build-essential" },
  { id = "fedora", name = "Fedora / RHEL / CentOS", cmd = "sudo dnf install make gcc" },
  { id = "arch", name = "Arch / Manjaro", cmd = "sudo pacman -S base-devel" },
  { id = "alpine", name = "Alpine (musl)", cmd = "sudo apk add build-base" },
  { id = "void", name = "Void", cmd = "sudo xbps-install -S base-devel" },
  { id = "suse", name = "openSUSE", cmd = "sudo zypper install make gcc" },
  { id = "gentoo", name = "Gentoo", cmd = "sudo emerge sys-devel/make sys-devel/gcc" },
  { id = "nixos", name = "NixOS / Nix", cmd = "nix-shell -p gnumake gcc (or add gnumake and gcc to your packages)" },
  { id = "bsd", name = "FreeBSD / OpenBSD / NetBSD", cmd = "pkg install gmake (OpenBSD: pkg_add gmake); the compiler is in the base system" },
}

--- ID and ID_LIKE words from /etc/os-release, as a set.
---@return table<string, boolean>
local function os_release_ids()
  local ids = {}
  local f = io.open("/etc/os-release", "r") or io.open("/usr/lib/os-release", "r")
  if not f then
    return ids
  end
  for line in f:lines() do
    local key, val = line:match("^([%w_]+)=(.*)$")
    if key == "ID" or key == "ID_LIKE" then
      for word in (val:gsub("[\"']", "")):gmatch("%S+") do
        ids[word:lower()] = true
      end
    end
  end
  f:close()
  return ids
end

--- Which `installers` entry applies here, or nil when unknown.
---@return string?
local function detect_platform()
  if vim.env.TERMUX_VERSION or (vim.env.PREFIX or ""):find("com.termux", 1, true) then
    return "termux"
  end
  if jit.os == "OSX" then
    return "macos"
  end
  if jit.os == "BSD" then
    return "bsd"
  end
  local ids = os_release_ids()
  local families = {
    nixos = { "nixos" },
    alpine = { "alpine" },
    void = { "void" },
    arch = { "arch", "archlinux", "manjaro" },
    debian = { "debian", "ubuntu" },
    fedora = { "fedora", "rhel", "centos" },
    suse = { "suse", "opensuse" },
    gentoo = { "gentoo" },
  }
  for id, names in pairs(families) do
    for _, name in ipairs(names) do
      if ids[name] then
        return id
      end
    end
  end
  return nil
end

--- Install instructions. With `all`, or when the platform is not recognised,
--- every platform is listed (one per line); otherwise just the detected one.
---@param all? boolean
---@return string
function M.install_hint(all)
  local id = not all and detect_platform() or nil
  if id then
    for _, it in ipairs(installers) do
      if it.id == id then
        return it.cmd
      end
    end
  end
  local lines = {}
  for _, it in ipairs(installers) do
    table.insert(lines, ("%s: %s"):format(it.name, it.cmd))
  end
  return table.concat(lines, "\n")
end

---@param names string[]
---@return string?
local function first_executable(names)
  for _, name in ipairs(names) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end
end

--- The build tools found on this machine. The Makefile needs GNU make (`gmake`
--- on the BSDs, whose `make` is different) and any C11 compiler: $CC if set,
--- else cc, gcc or clang (the same order the Makefile uses).
---@return { make: string?, cc: string?, missing: string[] }
function M.toolchain()
  local make = first_executable(jit.os == "BSD" and { "gmake" } or { "make", "gmake" })
  local cc = first_executable(vim.list_extend({ (vim.env.CC or ""):match("%S+") or "cc" }, { "cc", "gcc", "clang" }))
  local missing = {}
  if not make then
    table.insert(missing, jit.os == "BSD" and "gmake" or "make")
  end
  if not cc then
    table.insert(missing, "a C compiler (cc, gcc or clang)")
  end
  return { make = make, cc = cc, missing = missing }
end

--- Why a build cannot start, or nil when the tools are there. One line, with the
--- install command for this platform when it can be told.
---@return string?
local function toolchain_error()
  local tc = M.toolchain()
  if #tc.missing == 0 then
    return nil
  end
  local hint = M.install_hint()
  local sep = hint:find("\n", 1, true) and "; install one of:\n" or "; install with: "
  return ("%s not found%s%s"):format(table.concat(tc.missing, " and "), sep, hint)
end

-- Build ----------------------------------------------------------------------

---@param targets string[]
---@return string[]
local function make_cmd(targets)
  local cmd = { M.toolchain().make or "make", "-s", "-C", src_dir, "BUILD_DIR=" .. build_dir }
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
  local missing = toolchain_error()
  if missing then
    return false, missing
  end
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
  local missing = toolchain_error()
  if missing then
    vim.schedule(function()
      cb(false, missing)
    end)
    return
  end
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

--- Is the built library newer than every source file? Then `make` has nothing to do and
--- starting a process just to learn that is skipped. (Test drivers don't count: they are
--- not part of the library, so touching one must not keep this false forever.)
---@return boolean
local function up_to_date()
  local lib = uv.fs_stat(lib_path)
  if not lib then
    return false
  end
  local req = uv.fs_scandir(src_dir)
  while req do
    local name = uv.fs_scandir_next(req)
    if not name then
      break
    end
    if (name:find("%.[ch]$") and not name:find("^test_")) or name == "Makefile" then
      local st = uv.fs_stat(vim.fs.joinpath(src_dir, name))
      if not st or st.mtime.sec > lib.mtime.sec or (st.mtime.sec == lib.mtime.sec and st.mtime.nsec > lib.mtime.nsec) then
        return false
      end
    end
  end
  return true
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

  if not config.get().native.auto_build or up_to_date() then
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

--- The loaded library if it is ready right now, else nil. Never builds or blocks;
--- for hot paths that have a Lua fallback.
---@return table? lib
function M.loaded()
  return state.done and state.lib or nil
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
local function worker(op, id, libpath, cdef, a, b, c, d, e)
  local ok, r1, r2, r3 = pcall(function()
    local ffi = require("ffi")
    -- The thread's Lua state outlives the job: declare and load once per staged library
    -- (the path changes with every rebuild) instead of on every keystroke.
    local cache = package.loaded["nvcore.worker"]
    if not cache then
      cache = {}
      package.loaded["nvcore.worker"] = cache
    end
    local lib = cache[libpath]
    if not lib then
      for stmt in cdef:gmatch("[^;]+;") do
        pcall(ffi.cdef, stmt)
      end
      lib = ffi.load(libpath)
      cache[libpath] = lib
    end

    if op == "scan" then -- a=root b=ignore csv c=hidden d=max_files
      local ptr = lib.nv_index_scan(a, b, c, d)
      if ptr == nil then
        return 0, 0, false
      end
      return tonumber(ffi.cast("uintptr_t", ptr)), tonumber(lib.nv_index_count(ptr)), lib.nv_index_truncated(ptr) ~= 0
    end

    -- (uv work functions receive at most 9 arguments in total, hence the packed numbers)
    if op == "grep" then -- a=index address b=root c=pattern d=cancel address e="limit,max_file_bytes,max_text,flags"
      local limit, max_file, max_text, flags = e:match("^(%d+),(%d+),(%d+),(%d+)$")
      local idx = ffi.cast("nv_index *", ffi.cast("uintptr_t", a))
      local cancel = ffi.cast("nv_cancel *", ffi.cast("uintptr_t", d))
      local res = lib.nv_grep_run(idx, b, c, tonumber(flags), tonumber(limit), tonumber(max_file), tonumber(max_text), cancel)
      if res == nil then
        return 0, "", 0
      end
      local n = tonumber(lib.nv_grep_count(res))
      local parts = {}
      for i = 0, n - 1 do
        local k = i * 4
        parts[k + 1] = ffi.string(lib.nv_grep_path(res, i))
        parts[k + 2] = tostring(tonumber(lib.nv_grep_line(res, i)))
        parts[k + 3] = tostring(tonumber(lib.nv_grep_col(res, i)))
        parts[k + 4] = ffi.string(lib.nv_grep_text(res, i))
      end
      local status = tonumber(lib.nv_grep_status(res))
      lib.nv_grep_free(res)
      return n, table.concat(parts, "\0"), status
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

---@param op "scan"|"filter"|"grep"
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

-- Mirrors of the NV_GREP_* constants in nvcore.h.
M.GREP_MORE, M.GREP_CANCELLED, M.GREP_LITERAL = 1, 2, 4

---@class core.native.GrepHit
---@field path string relative to the index root
---@field line integer 1-based
---@field col integer 1-based byte column of the match
---@field text string the line, trimmed

--- Search the files of this index on a worker thread. The search stops at its
--- next check once the returned handle is cancelled; `cb` still runs, on the
--- main loop, with whatever was found (status has GREP_CANCELLED set).
--- On failure `hits` is nil and `status` is the error message.
---@param pattern string
---@param opts { root: string, fixed?: boolean, limit: integer, max_file_bytes?: integer, max_text?: integer }
---@param cb fun(hits: core.native.GrepHit[]?, status: integer|string)
---@return { cancel: fun() }
function Index:grep_async(pattern, opts, cb)
  local lib = self.lib
  local raw = lib.nv_cancel_new()
  local token = raw ~= nil and ffi.gc(raw, lib.nv_cancel_free) or nil
  local token_addr = token and tonumber(ffi.cast("uintptr_t", token)) or 0
  local keep_alive = self -- the index must outlive the worker's read of it

  dispatch("grep", function(ok, n, joined, status)
    local _ = { keep_alive, token } -- and so must the cancel token
    if not ok then
      cb(nil, tostring(n))
      return
    end
    local hits = {}
    if n > 0 then
      local f = vim.split(joined, "\0", { plain = true })
      for i = 0, n - 1 do
        hits[i + 1] = {
          path = f[4 * i + 1],
          line = tonumber(f[4 * i + 2]),
          col = tonumber(f[4 * i + 3]),
          text = f[4 * i + 4],
        }
      end
    end
    cb(hits, status)
  end, self.addr, opts.root, pattern, token_addr, ("%d,%d,%d,%d"):format(opts.limit, opts.max_file_bytes or 0, opts.max_text or 0, opts.fixed and 1 or 0))

  return {
    cancel = function()
      if token then
        lib.nv_cancel_set(token)
      end
    end,
  }
end

-- Walk `root` on a worker thread. Requires M.ready() to have succeeded.
---@param root string
---@param opts { ignore: string[], hidden: boolean, max_files: integer }
---@param cb fun(idx: core.native.Index?, err: string?)
local function scan_walk(root, opts, cb)
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


--- File list from git: tracked plus untracked-but-not-ignored files, so .gitignore is
--- honoured and no directory tree is walked. Calls `cb(idx)`, or `cb(nil)` when git is
--- unavailable, `root` is not in a work tree, or the list exceeds max_files (the walk
--- then takes over, which knows how to truncate).
---@param root string
---@param opts { ignore: string[], hidden: boolean, max_files: integer }
---@param cb fun(idx: core.native.Index?)
local function scan_git(root, opts, cb)
  local lib = state.lib
  if not lib or vim.fn.executable("git") ~= 1 then
    return cb(nil)
  end
  local list = { "git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "." }
  for _, name in ipairs(opts.ignore) do
    list[#list + 1] = ":(exclude,glob)**/" .. name .. "/**"
  end
  if not opts.hidden then
    list[#list + 1] = ":(exclude,glob)**/.*"
    list[#list + 1] = ":(exclude,glob)**/.*/**"
  end
  local pending, files, deleted, failed = 2, nil, nil, false
  local function done()
    pending = pending - 1
    if pending > 0 then
      return
    end
    vim.schedule(function()
      if failed or not files then
        return cb(nil)
      end
      local text = files:gsub("%z", "\n")
      if deleted and deleted ~= "" then
        -- Tracked files that are gone from disk still show in ls-files.
        local gone = {}
        for path in deleted:gmatch("[^%z]+") do
          gone[path] = true
        end
        local kept = {}
        for path in text:gmatch("[^\n]+") do
          if not gone[path] then
            kept[#kept + 1] = path
          end
        end
        text = table.concat(kept, "\n")
      end
      -- More files than max_files: let the walker truncate and flag it.
      local pos = 0
      for _ = 1, opts.max_files do
        pos = text:find("\n", pos + 1, true)
        if not pos then
          break
        end
      end
      if pos and text:find("[^\n]", pos + 1) then
        return cb(nil)
      end
      cb(wrap(lib, lib.nv_index_from_text(text, #text)))
    end)
  end
  local ok = pcall(function()
    vim.system(list, { text = false }, function(res)
      if res.code == 0 then
        files = res.stdout or ""
      else
        failed = true
      end
      done()
    end)
    vim.system({ "git", "-C", root, "ls-files", "-z", "--deleted" }, { text = false }, function(res)
      deleted = res.code == 0 and (res.stdout or "") or nil
      done()
    end)
  end)
  if not ok then
    -- vim.system threw before both callbacks were registered: finish on the walker.
    pending = math.huge
    cb(nil)
  end
end

-- Last file index per scan (root + options), most recently used last. Opening a
-- picker on a root seen before starts from it at once and refreshes in the background.
local scan_cache, scan_order, SCAN_CACHE_MAX = {}, {}, 3

---@param key string
---@param idx core.native.Index
local function cache_store(key, idx)
  scan_cache[key] = idx
  for i = #scan_order, 1, -1 do
    if scan_order[i] == key then
      table.remove(scan_order, i)
    end
  end
  scan_order[#scan_order + 1] = key
  while #scan_order > SCAN_CACHE_MAX do
    scan_cache[table.remove(scan_order, 1)] = nil
  end
end

--- Scan without the cache.
local function scan_fresh(root, opts, cb)
  if not config.get().picker.use_git then
    return scan_walk(root, opts, cb)
  end
  scan_git(root, opts, function(idx)
    if idx then
      cb(idx)
    else
      scan_walk(root, opts, cb)
    end
  end)
end

--- Index the files under `root`. With `picker.use_git` (default) a git work tree is
--- listed through git, which honours .gitignore; everything else is walked on a worker
--- thread. Requires M.ready() to have succeeded.
---
--- With `picker.scan_cache` (default) and an `opts.on_refresh`, a root scanned before answers
--- `cb` immediately with the previous result while a fresh scan runs; `on_refresh(idx)` then
--- receives the fresh index (not called when nothing was cached: `cb` already has it).
--- Callers that cannot swap an index later (no on_refresh) always get a fresh scan.
---@param root string
---@param opts { ignore: string[], hidden: boolean, max_files: integer, on_refresh?: fun(idx: core.native.Index) }
---@param cb fun(idx: core.native.Index?, err: string?)
function M.scan_async(root, opts, cb)
  local key = table.concat({ root, table.concat(opts.ignore, ","), tostring(opts.hidden), tostring(opts.max_files) }, "\0")
  local use_cache = config.get().picker.scan_cache
  local hit = use_cache and opts.on_refresh and scan_cache[key] or nil
  if hit then
    cache_store(key, hit) -- most recently used
    cb(hit)
    scan_fresh(root, opts, function(idx)
      if idx then
        cache_store(key, idx)
        if opts.on_refresh then
          opts.on_refresh(idx)
        end
      end
    end)
    return
  end
  scan_fresh(root, opts, function(idx, err)
    if idx and use_cache then
      cache_store(key, idx)
    end
    cb(idx, err)
  end)
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

  -- Warm up in the background so the library is ready before first use, but only once the
  -- editor is up: the first screen never waits for it, and a session that never opens a
  -- picker pays nothing more (the first use starts the load itself).
  local function warm()
    vim.defer_fn(function()
      M.ready(function() end)
    end, 50)
  end
  if vim.v.vim_did_enter == 1 then
    warm()
  else
    vim.api.nvim_create_autocmd("VimEnter", { group = util.augroup("native"), once = true, callback = warm })
  end
end

return M
