-- Live grep: the prompt is the search pattern and the list is the matching
-- lines of every file under the root, re-searched on each keystroke.
--
-- The tree is scanned once (same ignore/hidden/max_files rules as the file
-- picker); each query then greps that file list. With the native core the
-- search runs on a worker thread and is cancelled as soon as the query
-- changes; without it a plain-text Lua search is used (no regex).
--
-- Query syntax: regex (small RE2-like subset, see native/grep.c) with smartcase.
-- A leading ' searches the rest as plain text. A pattern that is not valid
-- regex yet (e.g. "foo(" while typing) is searched as plain text too.
--
-- Items are "path:line:col: text"; the picker hands the chosen one back to
-- on_select, which jumps to it.
local config = require("core.config")
local native = require("core.native")
local matcher = require("core.picker.matcher")
local ui = require("core.picker.ui")

local uv = vim.uv
local band = require("bit").band

local M = {}

---@param hit { path: string, line: integer, col: integer, text: string }
---@return string
local function label(hit)
  return ("%s:%d:%d: %s"):format(hit.path, hit.line, hit.col, hit.text)
end

---@param item string
---@return string? path, integer? line, integer? col
local function parse_label(item)
  local path, line, col = item:match("^(.-):(%d+):(%d+): ")
  if not path then
    return nil
  end
  return path, tonumber(line), tonumber(col)
end
M._parse_label = parse_label

--- A leading ' means "plain text".
---@param query string
---@param always_fixed boolean
---@return string pattern, boolean fixed
local function parse_query(query, always_fixed)
  if query:sub(1, 1) == "'" then
    return query:sub(2), true
  end
  return query, always_fixed
end
M._parse_query = parse_query

-- Pure-Lua fallback ------------------------------------------------------------

--- Cut `text` to at most `max` bytes without splitting a UTF-8 character.
---@param text string
---@param max integer
---@return string
local function clip(text, max)
  if #text <= max then
    return text
  end
  local start = max + vim.str_utf_start(text, max) -- first byte of the character holding byte `max`
  local cut = (vim.str_utf_end(text, max) == 0) and max or (start - 1)
  return text:sub(1, cut)
end

--- Plain-text, smartcase search of `files` (relative to `root`), in slices so
--- the editor stays responsive. `cb` always runs; `token.cancelled` ends the
--- search early with no results.
---@param root string
---@param files string[]
---@param query string
---@param opts { limit: integer, max_file_bytes: integer, max_text: integer }
---@param token { cancelled: boolean }
---@param cb fun(hits: table[], more: boolean)
local function lua_search(root, files, query, opts, token, cb)
  local icase = not query:find("%u")
  local needle = icase and query:lower() or query
  local hits, i = {}, 0

  local function finish()
    local more = #hits > opts.limit
    if more then
      hits[#hits] = nil
    end
    cb(hits, more)
  end

  local function scan_file(rel)
    local fd = uv.fs_open(root .. "/" .. rel, "r", 438)
    if not fd then
      return
    end
    local st = uv.fs_fstat(fd)
    local data = st and st.type == "file" and st.size > 0 and st.size <= opts.max_file_bytes and uv.fs_read(fd, st.size, 0)
    uv.fs_close(fd)
    if not data or data:find("\0", 1, true) then
      return
    end

    local hay = icase and data:lower() or data
    local pos, line_no, line_start = 1, 1, 1
    while #hits <= opts.limit do
      local s = hay:find(needle, pos, true)
      if not s then
        return
      end
      while true do -- count the line breaks before the match
        local nl = data:find("\n", line_start, true)
        if not nl or nl >= s then
          break
        end
        line_no = line_no + 1
        line_start = nl + 1
      end
      local nl = data:find("\n", s, true)
      local text = data:sub(line_start, (nl or #data + 1) - 1)
      text = vim.trim((text:gsub("[%c]", " ")))
      hits[#hits + 1] = { path = rel, line = line_no, col = s - line_start + 1, text = clip(text, opts.max_text) }
      if not nl then
        return
      end
      pos, line_start, line_no = nl + 1, nl + 1, line_no + 1
    end
  end

  local function step()
    if token.cancelled then
      cb({}, false)
      return
    end
    local deadline = uv.hrtime() + 8e6
    while i < #files and #hits <= opts.limit and uv.hrtime() < deadline do
      i = i + 1
      scan_file(files[i])
    end
    if i >= #files or #hits > opts.limit then
      finish()
    else
      vim.schedule(step)
    end
  end

  vim.schedule(step)
end

-- Narrowing --------------------------------------------------------------------
--
-- Typing extends the query, and every line matching "foobar" also matches "foo". So when
-- the shorter plain-text search found *all* its matches (it was neither cut at the hit
-- limit nor cancelled), the longer one only has to look in the files that had hits. That
-- turns most keystrokes from "read the whole tree" into "read a handful of files". The
-- last few complete results are kept, so backspacing narrows from an earlier one too.

---@param pattern string
---@param fixed boolean the query was marked plain text (or regex is switched off)
---@return boolean
local function is_plain(pattern, fixed)
  -- The characters native/grep.c treats as regex syntax.
  return fixed or not pattern:find("[\\%.%^%$%*%+%?%(%)%[%]{}|]")
end

--- ASCII-only, like the search itself (never the process locale).
---@param str string
---@return string
local function ascii_lower(str)
  return (str:gsub("[A-Z]", function(c)
    return string.char(c:byte() + 32)
  end))
end

---@class core.grep.Result
---@field pattern string
---@field icase boolean smartcase: no uppercase ASCII letter in the pattern
---@field paths string[] every file that had a match, in index order
---@field sub? core.native.Index paths as an index, built when first needed

---@param old core.grep.Result
---@param new { pattern: string, icase: boolean }
---@return boolean whether every line matching `new` also matches `old`
local function narrows(old, new)
  if old.icase then
    return ascii_lower(new.pattern):find(ascii_lower(old.pattern), 1, true) ~= nil
  end
  -- A case-sensitive old search says nothing about a case-insensitive new one.
  return not new.icase and new.pattern:find(old.pattern, 1, true) ~= nil
end
M._is_plain, M._narrows = is_plain, narrows

local HISTORY_MAX = 6

-- Matcher ----------------------------------------------------------------------

---@param root string
---@param cfg table config.get().picker
---@return core.Matcher
local function new_matcher(root, cfg)
  local gcfg = cfg.grep
  local m = { loading = true, truncated = false, disposed = false, hint = nil }
  local listeners = {}
  local index ---@type core.native.Index?   native file list
  local files ---@type string[]?             Lua file list (fallback)
  local last_count = 0
  local running ---@type { cancel: fun() }?
  local scan_truncated = false
  local history = {} ---@type core.grep.Result[] complete plain-text results, newest last

  --- Keep the file list of a complete plain-text search for narrowing later ones.
  ---@param pattern string
  ---@param hits table[]
  local function remember(pattern, hits)
    local paths, last = {}, nil
    for _, hit in ipairs(hits) do
      if hit.path:find("\n", 1, true) then
        return -- a native index is newline-separated text: such a path can't be listed in one
      end
      if hit.path ~= last then -- hits come grouped by file
        paths[#paths + 1] = hit.path
        last = hit.path
      end
    end
    for i = #history, 1, -1 do
      if history[i].pattern == pattern then
        table.remove(history, i)
      end
    end
    history[#history + 1] = { pattern = pattern, icase = not pattern:find("[A-Z]"), paths = paths }
    if #history > HISTORY_MAX then
      table.remove(history, 1)
    end
  end

  --- The remembered result with the fewest files that every match of `pattern` must be in.
  ---@param pattern string
  ---@return core.grep.Result?
  local function narrowest(pattern)
    local cur = { pattern = pattern, icase = not pattern:find("[A-Z]") }
    local best
    for _, h in ipairs(history) do
      if narrows(h, cur) and (not best or #h.paths < #best.paths) then
        best = h
      end
    end
    return best
  end

  m.count = function()
    return last_count
  end
  m.subscribe = function(fn)
    listeners[#listeners + 1] = fn
  end
  --- The query changed while a search runs: stop it, its answer is stale.
  m.cancel = function()
    if running then
      running.cancel()
    end
  end
  m.dispose = function()
    m.disposed = true
    m.cancel()
    listeners = {}
  end

  local function ready(idx, list, truncated)
    if m.disposed then
      return
    end
    index, files, scan_truncated = idx, list, truncated
    m.loading = false
    for _, fn in ipairs(listeners) do
      fn()
    end
  end

  local function use_lua_files()
    matcher.lua_scan(m, root, { ignore = cfg.ignore, hidden = cfg.hidden, max_files = cfg.max_files }, function(list, truncated)
      ready(nil, list, truncated)
    end)
  end

  native.ready(function(lib, err)
    if m.disposed then
      return
    end
    if not lib then
      native.warn_unavailable(err)
      return use_lua_files()
    end
    native.scan_async(root, {
      ignore = cfg.ignore,
      hidden = cfg.hidden,
      max_files = cfg.max_files,
      -- The list shown first may be from an earlier open: swap in the fresh one for later
      -- searches, and forget narrowing history built on the old list.
      on_refresh = function(fresh)
        if m.disposed then
          return
        end
        index, scan_truncated = fresh, fresh:truncated()
        history = {}
      end,
    }, function(idx, scan_err)
      if m.disposed then
        return
      end
      if not idx then
        native.warn_unavailable(scan_err)
        return use_lua_files()
      end
      ready(idx, nil, idx:truncated())
    end)
  end)

  ---@param hits table[]
  ---@param more boolean
  ---@param hint string?
  ---@param cb fun(items: string[])
  local function deliver(hits, more, hint, cb)
    local items = {}
    for i, hit in ipairs(hits) do
      items[i] = label(hit)
    end
    last_count = #items
    m.truncated = more
    if scan_truncated then
      hint = (hint and hint .. ", " or "") .. "file list truncated"
    end
    m.hint = hint
    cb(items)
  end

  m.filter = function(query, limit, cb)
    local pattern, fixed = parse_query(query, not gcfg.regex)
    if m.disposed or m.loading or vim.fn.strchars(pattern) < gcfg.min_query then
      last_count, m.truncated, m.hint = 0, false, nil
      cb({})
      return
    end

    local opts = { root = root, fixed = fixed, limit = limit, max_file_bytes = gcfg.max_filesize, max_text = gcfg.max_text }

    local plain = is_plain(pattern, fixed)
    local base = plain and narrowest(pattern) or nil

    if index then
      local target = index
      if base then
        if #base.paths == 0 then
          -- The shorter query matched nothing, so neither does this one.
          remember(pattern, {})
          deliver({}, false, fixed and "plain text" or nil, cb)
          return
        end
        base.sub = base.sub or native.from_list(base.paths)
        target = base.sub or index
      end
      running = target:grep_async(pattern, opts, function(hits, status)
        if not hits then
          running = nil
          require("core.util").notify("Grep failed: " .. tostring(status), vim.log.levels.ERROR)
          last_count, m.truncated, m.hint = 0, false, "search failed"
          cb({})
          return
        end
        local cancelled = band(status, native.GREP_CANCELLED) ~= 0
        local literal = band(status, native.GREP_LITERAL) ~= 0
        local more = band(status, native.GREP_MORE) ~= 0
        local hint = fixed and "plain text" or (literal and "plain text (not a regex)" or nil)
        if not cancelled and not more and (plain or literal) then
          remember(pattern, hits)
        end
        -- A cancelled search is partial; the picker discards it for the newer query.
        deliver(cancelled and {} or hits, more and not cancelled, hint, cb)
      end)
      return
    end

    -- Fallback: no regex, only plain text.
    local token = { cancelled = false }
    running = { cancel = function() token.cancelled = true end }
    -- (Here every query is plain text, so narrowing always applies.)
    base = narrowest(pattern)
    lua_search(root, base and base.paths or files or {}, pattern, opts, token, function(hits, more)
      if not token.cancelled and not more then
        remember(pattern, hits)
      end
      deliver(hits, more, "plain text (native core unavailable)", cb)
    end)
  end

  return m
end

-- Public -----------------------------------------------------------------------

---@param opts? { root?: string }
function M.open(opts)
  local cfg = config.get().picker
  local root = (opts and opts.root) or uv.cwd()

  local m = new_matcher(root, cfg)
  ui.open({
    title = "Grep",
    id = "grep",
    matcher = m,
    preview = function(item, query)
      local path, line, col = parse_label(item)
      if not path then
        return nil
      end
      local target = { kind = "file", path = vim.fs.joinpath(root, path), lnum = line, col = col }
      -- The whole line is always marked; the match itself too when the query says how long it is.
      local pattern, fixed = parse_query(query, not cfg.grep.regex)
      -- The matcher falls back to plain text for a pattern that is not a regex (yet).
      fixed = fixed or (m.hint ~= nil and m.hint:find("plain text", 1, true) ~= nil)
      if pattern ~= "" then
        target.search = { pattern = pattern, fixed = fixed }
      end
      return target
    end,
    on_select = function(item, action)
      local path, line, col = parse_label(item)
      if not path then
        return
      end
      vim.cmd(("%s %s"):format(action, vim.fn.fnameescape(vim.fs.joinpath(root, path))))
      local lnum = math.max(1, math.min(line, vim.api.nvim_buf_line_count(0)))
      pcall(vim.api.nvim_win_set_cursor, 0, { lnum, math.max(0, col - 1) })
      vim.cmd.normal({ "zvzz", bang = true })
    end,
  })
end

return M
