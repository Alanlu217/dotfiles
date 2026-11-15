-- Git without a plugin: repo status for the statusline, and inline blame.
--
-- Status: `git status --porcelain=v2 --branch` runs in the background (never blocks,
-- never takes the index lock) and is cached per repository. It is refreshed on
-- BufEnter, saving, FocusGained, leaving a terminal and after :!cmd. The statusline
-- shows the branch, ahead/behind and the number of staged (+), modified (~),
-- untracked (?) and conflicted (!) files; symbols are in config.git.symbols.
--
-- Blame: the author, age and summary of the commit that last touched the cursor
-- line, as virtual text at the end of the line. The buffer is piped to
-- `git blame --contents -`, so unsaved edits blame correctly (those lines read
-- "Not committed yet"). Off by default; vim.g.git_blame switches it globally and
-- vim.b.git_blame overrides that for one buffer.
--
--   :GitBlameToggle[!] [on|off|toggle|reset]   inline blame; ! = this buffer only
--   :GitRefresh                                 re-read the status of this repository
--
--   require("core.git").statusline(buf?)        string for the statusline ("" outside a repo)
--   require("core.git").status(buf?)            { branch, ahead, behind, staged, modified, untracked, conflicts }?
--   require("core.git").blame_enabled(buf?) / .blame_set(value, buf?) / .blame_toggle(buf?)
--
-- Mechanism only; no keymaps are defined here (see lua/user/keymaps.lua).
local config = require("core.config")
local util = require("core.util")

local M = {}

---@type boolean false when git is missing or config.git.enabled is off
M.active = false

local uv = vim.uv or vim.loop

-- Repository root ---------------------------------------------------------------------

local roots = {} ---@type table<integer, { name: string, root: string|false }>

--- Root of the repository `buf` belongs to (nil for scratch buffers and files outside one).
---@param buf integer
---@return string?
local function buf_root(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  local hit = roots[buf]
  if not hit or hit.name ~= name then
    hit = { name = name, root = vim.fs.root(name, ".git") or false }
    roots[buf] = hit
  end
  return hit.root or nil
end

--- Root of the repository `buf` belongs to (nil for scratch buffers and files outside one).
---@param buf integer
---@return string?
function M.root(buf)
  return buf_root(buf)
end

-- Status ------------------------------------------------------------------------------

---@class core.git.Status
---@field branch string
---@field ahead integer
---@field behind integer
---@field staged integer
---@field modified integer
---@field untracked integer
---@field conflicts integer

---@param out string output of `git status --porcelain=v2 --branch`
---@return core.git.Status
local function parse_status(out)
  local s = { branch = "", ahead = 0, behind = 0, staged = 0, modified = 0, untracked = 0, conflicts = 0 }
  local oid
  for line in vim.gsplit(out, "\n", { plain = true, trimempty = true }) do
    local c = line:sub(1, 1)
    if c == "#" then
      local head = line:match("^# branch%.head (.+)$")
      if head then
        s.branch = head
      end
      local o = line:match("^# branch%.oid (%S+)$")
      if o then
        oid = o
      end
      local a, b = line:match("^# branch%.ab %+(%d+) %-(%d+)$")
      if a then
        s.ahead, s.behind = tonumber(a), tonumber(b)
      end
    elseif c == "1" or c == "2" then
      -- "1 XY ..." (changed) / "2 XY ..." (renamed or copied): X = index, Y = worktree.
      local x, y = line:match("^[12] (.)(.)")
      if x and x ~= "." then
        s.staged = s.staged + 1
      end
      if y and y ~= "." then
        s.modified = s.modified + 1
      end
    elseif c == "u" then
      s.conflicts = s.conflicts + 1
    elseif c == "?" then
      s.untracked = s.untracked + 1
    end
  end
  if s.branch == "(detached)" then
    s.branch = "@" .. (oid and oid:sub(1, 7) or "?")
  end
  return s
end

local cache = {} ---@type table<string, { status?: core.git.Status, running?: boolean, again?: boolean, at?: integer }>
local pending = {} ---@type table<string, boolean> root -> force
local status_timer ---@type uv.uv_timer_t?

local function run_status(root)
  local entry = cache[root]
  if entry.running then
    entry.again = true
    return
  end
  entry.running = true
  entry.at = uv.now()

  local cmd = { "git", "--no-optional-locks", "-C", root, "status", "--porcelain=v2", "--branch" }
  if not config.get().git.untracked then
    cmd[#cmd + 1] = "--untracked-files=no"
  end

  local ok = pcall(
    vim.system,
    cmd,
    { text = true, timeout = 5000 },
    vim.schedule_wrap(function(res)
      entry.running = false
      entry.status = res.code == 0 and parse_status(res.stdout or "") or nil
      if entry.again then
        entry.again = false
        run_status(root)
      else
        vim.cmd("redrawstatus!")
      end
    end)
  )
  if not ok then
    entry.running = false
  end
end

--- Ask for a refresh of `root` (debounced). Without `force`, a repository that was read
--- in the last two seconds is left alone, so hopping between windows stays cheap.
---@param root string
---@param force? boolean
local function request_status(root, force)
  local entry = cache[root]
  if not entry then
    entry = {}
    cache[root] = entry
  elseif not force and entry.at and uv.now() - entry.at < 2000 then
    return
  end

  pending[root] = pending[root] or force or false
  status_timer = status_timer or uv.new_timer()
  status_timer:stop()
  status_timer:start(
    config.get().git.refresh_ms,
    0,
    vim.schedule_wrap(function()
      local batch = pending
      pending = {}
      for r in pairs(batch) do
        run_status(r)
      end
    end)
  )
end

--- Cached status of the repository `buf` is in (nil outside one, or until the first read).
---@param buf? integer
---@return core.git.Status?
function M.status(buf)
  if not M.active then
    return nil
  end
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local root = buf_root(buf)
  if not root then
    return nil
  end
  if not cache[root] then
    request_status(root, true)
    return nil
  end
  return cache[root].status
end

--- "main ^1 v2 +3 ~4 ?5" for the statusline; "" outside a repository.
---@param buf? integer
---@return string
function M.statusline(buf)
  local s = M.status(buf)
  if not s then
    return ""
  end
  local sym = config.get().git.symbols
  local parts = { s.branch }
  local function add(symbol, n)
    if n > 0 then
      parts[#parts + 1] = symbol .. n
    end
  end
  add(sym.ahead, s.ahead)
  add(sym.behind, s.behind)
  add(sym.staged, s.staged)
  add(sym.modified, s.modified)
  add(sym.untracked, s.untracked)
  add(sym.conflict, s.conflicts)
  return table.concat(parts, " ")
end

-- Blame -------------------------------------------------------------------------------

local ns = vim.api.nvim_create_namespace("core_git_blame")
local blame_timer ---@type uv.uv_timer_t?
local token = 0 -- bumped on every cursor move; an answer for an older token is dropped
local shown ---@type { buf: integer, lnum: integer, tick: integer }?

local function global_blame()
  local g = vim.g.git_blame
  if g == nil then
    return config.get().git.blame.enabled
  end
  return g ~= false
end

--- Is inline blame active for `buf`? (buffer override, else global)
---@param buf? integer
---@return boolean
function M.blame_enabled(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local b = vim.b[buf].git_blame
  if b ~= nil then
    return b ~= false
  end
  return global_blame()
end

---@param ts integer unix time
---@return string
local function relative(ts)
  local d = math.max(os.time() - ts, 0)
  local function fmt(n, unit)
    n = math.floor(n)
    return ("%d %s%s ago"):format(n, unit, n == 1 and "" or "s")
  end
  if d < 60 then
    return "just now"
  elseif d < 3600 then
    return fmt(d / 60, "minute")
  elseif d < 86400 then
    return fmt(d / 3600, "hour")
  elseif d < 86400 * 30 then
    return fmt(d / 86400, "day")
  elseif d < 86400 * 365 then
    return fmt(d / (86400 * 30), "month")
  end
  return fmt(d / (86400 * 365), "year")
end

--- Parse the output of `git blame --porcelain -L n,n` (one line, one header block).
---@param out string
---@return { sha: string, author: string, time?: integer, summary: string }?
local function parse_blame(out)
  local sha = out:match("^(%x+) ")
  if not sha then
    return nil
  end
  return {
    sha = sha,
    author = out:match("\nauthor ([^\n]*)") or "?",
    time = tonumber(out:match("\nauthor%-time (%d+)")),
    summary = out:match("\nsummary ([^\n]*)") or "",
  }
end

---@param b { sha: string, author: string, time?: integer, summary: string }
---@return string
local function blame_text(b)
  local cfg = config.get().git.blame
  if b.sha:match("^0+$") then
    return cfg.uncommitted
  end
  local fields = { author = b.author, time = b.time and relative(b.time) or "", summary = b.summary, sha = b.sha:sub(1, 7) }
  return (cfg.format:gsub("{(%w+)}", fields))
end

local function clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
  if shown and shown.buf == buf then
    shown = nil
  end
end

local function clear_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    clear(buf)
  end
  shown = nil
end

--- Blame the line under the cursor of the current window and show it.
---@param buf integer
local function request_blame(buf)
  if not M.active or buf ~= vim.api.nvim_get_current_buf() or not M.blame_enabled(buf) then
    return
  end
  local root = buf_root(buf)
  if not root then
    return
  end
  local cfg = config.get().git.blame
  if vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) > cfg.max_bytes then
    return
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if shown and shown.buf == buf and shown.lnum == lnum and shown.tick == tick then
    return
  end

  token = token + 1
  local mine = token
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
  local cmd = { "git", "--no-optional-locks", "-C", root, "blame", "--porcelain" }
  vim.list_extend(cmd, { "-L", lnum .. "," .. lnum, "--contents", "-", "--", vim.api.nvim_buf_get_name(buf) })

  pcall(
    vim.system,
    cmd,
    { text = true, stdin = content, timeout = 5000 },
    vim.schedule_wrap(function(res)
      -- Dropped when the cursor moved or the buffer changed while git was working.
      if mine ~= token or not vim.api.nvim_buf_is_valid(buf) or buf ~= vim.api.nvim_get_current_buf() then
        return
      end
      if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        return
      end
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      shown = nil
      -- Untracked files, empty buffers and the like make git fail: show nothing.
      local b = res.code == 0 and parse_blame(res.stdout or "") or nil
      if not b or lnum > vim.api.nvim_buf_line_count(buf) then
        return
      end
      local ok = pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum - 1, 0, {
        virt_text = { { cfg.prefix .. blame_text(b), "CoreGitBlame" } },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })
      if ok then
        shown = { buf = buf, lnum = lnum, tick = tick }
      end
    end)
  )
end

--- Cursor moved (or text changed): drop what is shown and ask again once the cursor rests.
local function on_move()
  token = token + 1
  local buf = vim.api.nvim_get_current_buf()
  if not M.active or not M.blame_enabled(buf) then
    if shown then
      clear_all()
    end
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  if shown and shown.buf == buf and shown.lnum == lnum and shown.tick == vim.api.nvim_buf_get_changedtick(buf) then
    return -- same line, same text: horizontal moves keep the virtual text
  end
  clear(buf)
  blame_timer = blame_timer or uv.new_timer()
  blame_timer:stop()
  blame_timer:start(
    config.get().git.blame.delay,
    0,
    vim.schedule_wrap(function()
      request_blame(vim.api.nvim_get_current_buf())
    end)
  )
end

local function after_blame_change()
  clear_all()
  if M.blame_enabled() then
    request_blame(vim.api.nvim_get_current_buf())
  end
end

--- Set inline blame: globally, or for `buf` only (nil clears a buffer override).
---@param value boolean?
---@param buf? integer
function M.blame_set(value, buf)
  if buf then
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    vim.b[buf].git_blame = value
  else
    vim.g.git_blame = value
  end
  after_blame_change()
end

--- Flip inline blame, globally or for `buf` only. Returns the new state.
---@param buf? integer
---@return boolean
function M.blame_toggle(buf)
  if not M.active then
    util.notify("Git is not available (git missing or config.git.enabled is off)", vim.log.levels.WARN)
    return false
  end
  local value ---@type boolean
  if buf then
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    value = not M.blame_enabled(buf)
    M.blame_set(value, buf)
    util.notify("Git blame (buffer): " .. (value and "on" or "off"))
  else
    value = not global_blame()
    M.blame_set(value)
    util.notify("Git blame (global): " .. (value and "on" or "off"))
  end
  return value
end

-- Setup -------------------------------------------------------------------------------

function M.setup()
  local cfg = config.get().git
  M.active = cfg.enabled and vim.fn.executable("git") == 1
  if not M.active then
    return
  end
  if vim.g.git_blame == nil then
    vim.g.git_blame = cfg.blame.enabled
  end

  local function set_hl()
    vim.api.nvim_set_hl(0, "CoreGitBlame", { link = "Comment", default = true })
  end
  set_hl()

  local group = util.augroup("git")
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })

  -- Status.
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      local root = buf_root(ev.buf)
      if root then
        request_status(root)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained", "ShellCmdPost", "TermLeave", "TermClose" }, {
    group = group,
    callback = function(ev)
      local root = buf_root(vim.api.nvim_get_current_buf()) or buf_root(ev.buf)
      if root then
        request_status(root, true)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      roots[ev.buf] = nil
    end,
  })

  -- Blame.
  vim.api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "BufEnter", "InsertLeave" }, {
    group = group,
    callback = on_move,
  })
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
      token = token + 1
      clear(vim.api.nvim_get_current_buf())
    end,
  })

  vim.api.nvim_create_user_command("GitBlameToggle", function(o)
    local arg = o.args
    if arg ~= "" and arg ~= "on" and arg ~= "off" and arg ~= "toggle" and arg ~= "reset" then
      util.notify("GitBlameToggle: expected on, off, toggle or reset", vim.log.levels.ERROR)
      return
    end
    if arg == "reset" and not o.bang then
      util.notify("GitBlameToggle: reset clears a buffer override, use :GitBlameToggle! reset", vim.log.levels.ERROR)
      return
    end
    local buf = o.bang and vim.api.nvim_get_current_buf() or nil
    if arg == "" or arg == "toggle" then
      M.blame_toggle(buf)
      return
    end
    local value ---@type boolean?
    if arg == "on" then
      value = true
    elseif arg == "off" then
      value = false
    end
    M.blame_set(value, buf)
    if arg == "reset" then
      util.notify(("Git blame: buffer override cleared (%s)"):format(M.blame_enabled(buf) and "on" or "off"))
    else
      util.notify(("Git blame (%s): %s"):format(buf and "buffer" or "global", value and "on" or "off"))
    end
  end, {
    nargs = "?",
    bang = true,
    complete = function()
      return { "on", "off", "toggle", "reset" }
    end,
    desc = "Toggle inline git blame (! = this buffer only)",
  })

  vim.api.nvim_create_user_command("GitRefresh", function()
    local root = buf_root(vim.api.nvim_get_current_buf())
    if root then
      request_status(root, true)
    else
      util.notify("Not in a git repository")
    end
  end, { desc = "Re-read the git status shown in the statusline" })
end

-- Exposed for tests.
M._parse_status = parse_status
M._parse_blame = parse_blame
M._relative = relative

return M
