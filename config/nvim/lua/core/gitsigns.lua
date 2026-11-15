-- Git signs: added / changed / deleted lines in the sign column (and the line number),
-- a small gitsigns.nvim-alike without the plugin.
--
--   +  added line            ~  changed line
--   _  lines deleted below   -  lines deleted above the first line
--
-- The buffer is diffed against the *index* (`git show :./file`), so staged changes
-- stop showing once you `git add` them, like `git diff`. The index copy is read in
-- the background when a buffer is entered, saved, or after focus returns / a
-- terminal or :!cmd ran; edits are diffed in-process (vim.diff) a moment after you
-- stop typing, so the signs follow unsaved changes. Untracked files, if not
-- ignored, show as fully added (config.git.signs.untracked).
--
--   :GitSignsToggle        signs on / off (vim.g.git_signs)
--   :GitHunkNext / :GitHunkPrev     jump to the next / previous hunk (honours 'wrapscan')
--   :GitHunkPreview        the old and new lines of the hunk under the cursor
--
--   require("core.gitsigns").next_hunk() / .prev_hunk() / .preview_hunk() / .toggle()
--
-- Mechanism only; no keymaps are defined here (see lua/user/keymaps.lua).
local config = require("core.config")
local util = require("core.util")

local M = {}

local uv = vim.uv or vim.loop
local ns = vim.api.nvim_create_namespace("core_git_signs")

---@alias core.gitsigns.Kind "add"|"change"|"delete"|"topdelete"

---@class core.gitsigns.Hunk
---@field kind core.gitsigns.Kind
---@field top integer line the hunk is anchored to (1-based; what ]h / [h jump to)
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer

---@class core.gitsigns.State
---@field base? string index copy of the file; nil = nothing to compare with (no signs)
---@field base_lines? string[]
---@field hunks core.gitsigns.Hunk[]
---@field loading? boolean
---@field reload? boolean another read was asked for while one was running
---@field stale? boolean the index may have changed; read it again on the next BufEnter
---@field timer? uv.uv_timer_t

local state = {} ---@type table<integer, core.gitsigns.State>

local HL = { add = "CoreGitSignAdd", change = "CoreGitSignChange", delete = "CoreGitSignDelete", topdelete = "CoreGitSignDelete" }

---@return boolean
function M.enabled()
  local g = vim.g.git_signs
  if g == nil then
    return config.get().git.signs.enabled
  end
  return g ~= false
end

-- Diff --------------------------------------------------------------------------------

--- Turn vim.diff() "indices" ({ start_a, count_a, start_b, count_b } per hunk) into hunks
--- and the sign to draw on each line. For a pure deletion count_b is 0 and start_b is
--- the line *before* the deleted text (0 = above the first line).
---@param indices integer[][]
---@return core.gitsigns.Hunk[] hunks, table<integer, core.gitsigns.Kind> marks
function M._classify(indices)
  local hunks, marks = {}, {}
  for _, d in ipairs(indices) do
    local sa, ca, sb, cb = d[1], d[2], d[3], d[4]
    if cb == 0 then
      local kind = sb == 0 and "topdelete" or "delete"
      local top = math.max(sb, 1)
      hunks[#hunks + 1] = { kind = kind, top = top, old_start = sa, old_count = ca, new_start = sb, new_count = 0 }
      marks[top] = marks[top] or kind
    else
      local kind = ca == 0 and "add" or "change"
      hunks[#hunks + 1] = { kind = kind, top = sb, old_start = sa, old_count = ca, new_start = sb, new_count = cb }
      for l = sb, sb + cb - 1 do
        -- A hunk that replaces ca lines with more: the first ca are changed, the rest added.
        marks[l] = (kind == "change" and l < sb + ca) and "change" or "add"
      end
    end
  end
  return hunks, marks
end

---@param buf integer
---@param marks table<integer, core.gitsigns.Kind>
local function place(buf, marks)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local cfg = config.get().git.signs
  local last = vim.api.nvim_buf_line_count(buf)
  for lnum, kind in pairs(marks) do
    if lnum >= 1 and lnum <= last then
      local hl = HL[kind]
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum - 1, 0, {
        sign_text = cfg.text[kind],
        sign_hl_group = hl,
        number_hl_group = cfg.numhl and hl or nil,
        priority = cfg.priority,
      })
    end
  end
end

---@param buf integer
local function clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
  if state[buf] then
    state[buf].hunks = {}
  end
end

--- Diff the buffer against its index copy and redraw the signs.
---@param buf integer
local function update(buf)
  local s = state[buf]
  if not s or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if not M.enabled() or s.base == nil then
    clear(buf)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  if #lines == 1 and lines[1] == "" then
    text = "" -- an empty file, not a file holding one empty line
  elseif vim.bo[buf].endofline then
    text = text .. "\n"
  end

  local diff = (vim.text and vim.text.diff) or vim.diff
  local ok, indices = pcall(diff, s.base, text, { result_type = "indices" })
  if not ok or type(indices) ~= "table" then
    clear(buf)
    return
  end
  local hunks, marks = M._classify(indices)
  s.hunks = hunks
  place(buf, marks)
end

--- Diff again once the cursor has been idle for config.git.signs.delay.
---@param buf integer
local function schedule_update(buf)
  local s = state[buf]
  if not s then
    return
  end
  s.timer = s.timer or uv.new_timer()
  s.timer:stop()
  s.timer:start(
    config.get().git.signs.delay,
    0,
    vim.schedule_wrap(function()
      update(buf)
    end)
  )
end

-- Index copy --------------------------------------------------------------------------

--- Read the index version of the buffer's file in the background, then update the signs.
---@param buf integer
local function load_base(buf)
  local s = state[buf]
  if s.loading then
    s.reload = true
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  local dir, file = vim.fs.dirname(name), vim.fs.basename(name)
  local untracked = config.get().git.signs.untracked
  s.loading = true
  s.stale = false

  local function finish(base)
    s.loading = false
    if state[buf] ~= s or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    s.base, s.base_lines = base, nil
    if s.reload then
      s.reload = false
      load_base(buf)
    else
      update(buf)
    end
  end

  local function git(args, on_done)
    local cmd = { "git", "--no-optional-locks", "-C", dir }
    vim.list_extend(cmd, args)
    local ok = pcall(vim.system, cmd, { text = true, timeout = 5000 }, vim.schedule_wrap(on_done))
    if not ok then
      s.loading = false
    end
  end

  git({ "show", ":./" .. file }, function(res)
    if res.code == 0 then
      local base = res.stdout or ""
      -- Binary files get no signs; CRLF in the index is compared as LF (the buffer has none).
      finish(not base:find("\0", 1, true) and (base:gsub("\r\n", "\n")) or nil)
    elseif untracked then
      -- Not in the index: untracked (all lines added) unless ignored (no signs).
      git({ "check-ignore", "-q", "--", file }, function(r)
        finish(r.code == 1 and "" or nil)
      end)
    else
      finish(nil)
    end
  end)
end

--- Start (or resume) tracking `buf` if it is a file in a repository.
---@param buf integer
local function attach(buf)
  local cfg = config.get().git.signs
  local eligible = M.enabled()
    and vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_buf_is_loaded(buf)
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) ~= ""
    and require("core.git").root(buf) ~= nil
    and vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) <= cfg.max_bytes
  if not eligible then
    if state[buf] then
      clear(buf)
      state[buf].base = nil
    end
    return
  end

  local s = state[buf]
  if not s then
    state[buf] = { hunks = {} }
    load_base(buf)
  elseif s.stale then
    load_base(buf)
  end
end

local function detach(buf)
  local s = state[buf]
  if s and s.timer then
    s.timer:stop()
    s.timer:close()
  end
  state[buf] = nil
end

-- Hunks -------------------------------------------------------------------------------

---@param forward boolean
local function goto_hunk(forward)
  local buf = vim.api.nvim_get_current_buf()
  local s = state[buf]
  if not s or #s.hunks == 0 then
    util.notify("No git hunks in this buffer")
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local target ---@type core.gitsigns.Hunk?
  if forward then
    for _, h in ipairs(s.hunks) do
      if h.top > lnum then
        target = h
        break
      end
    end
    target = target or (vim.o.wrapscan and s.hunks[1] or nil)
  else
    for i = #s.hunks, 1, -1 do
      if s.hunks[i].top < lnum then
        target = s.hunks[i]
        break
      end
    end
    target = target or (vim.o.wrapscan and s.hunks[#s.hunks] or nil)
  end
  if not target then
    util.notify("No more git hunks")
    return
  end
  vim.cmd("normal! m'") -- so <C-o> goes back
  vim.api.nvim_win_set_cursor(0, { math.min(target.top, vim.api.nvim_buf_line_count(buf)), 0 })
end

function M.next_hunk()
  goto_hunk(true)
end

function M.prev_hunk()
  goto_hunk(false)
end

--- Show the old and new lines of the hunk under the cursor in a floating window.
function M.preview_hunk()
  local buf = vim.api.nvim_get_current_buf()
  local s = state[buf]
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local hunk ---@type core.gitsigns.Hunk?
  for _, h in ipairs(s and s.hunks or {}) do
    if lnum >= h.top and lnum <= h.top + math.max(h.new_count, 1) - 1 then
      hunk = h
      break
    end
  end
  if not s or not hunk or not s.base then
    util.notify("No git hunk under the cursor")
    return
  end

  s.base_lines = s.base_lines or vim.split(s.base, "\n", { plain = true })
  local lines = { ("@@ -%d,%d +%d,%d @@"):format(hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count) }
  for i = hunk.old_start, hunk.old_start + hunk.old_count - 1 do
    lines[#lines + 1] = "-" .. (s.base_lines[i] or "")
  end
  if hunk.new_count > 0 then
    local first = hunk.new_start - 1
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, first, first + hunk.new_count, false)) do
      lines[#lines + 1] = "+" .. l
    end
  end
  vim.lsp.util.open_floating_preview(lines, "diff", { border = "solid", focus_id = "core_git_hunk" })
end

-- Toggle ------------------------------------------------------------------------------

--- Switch signs on / off for every buffer. Returns the new state.
---@return boolean
function M.toggle()
  local value = not M.enabled()
  vim.g.git_signs = value
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if value then
      detach(buf) -- forget everything; buffers re-attach as they are entered
    else
      clear(buf)
      detach(buf)
    end
  end
  if value then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      attach(vim.api.nvim_win_get_buf(win))
    end
  end
  util.notify("Git signs: " .. (value and "on" or "off"))
  return value
end

-- Setup -------------------------------------------------------------------------------

local function set_hl()
  --- Colour from an existing group (foreground only), else a fixed fallback.
  local function def(name, group, fallback)
    local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
    vim.api.nvim_set_hl(0, name, { fg = hl.fg or fallback })
  end
  def("CoreGitSignAdd", "Added", "#98c379")
  def("CoreGitSignChange", "Changed", "#e5c07b")
  def("CoreGitSignDelete", "Removed", "#e06c75")
end

function M.setup()
  local cfg = config.get().git
  if not cfg.enabled or not require("core.git").active then
    return
  end
  if vim.g.git_signs == nil then
    vim.g.git_signs = cfg.signs.enabled
  end
  set_hl()

  local group = util.augroup("gitsigns")
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      attach(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufFilePost", { -- renamed: a different file now
    group = group,
    callback = function(ev)
      detach(ev.buf)
      attach(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(ev)
      if state[ev.buf] then
        load_base(ev.buf)
      else
        attach(ev.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(ev)
      schedule_update(ev.buf)
    end,
  })
  -- The index may have changed behind our back (git add / commit / checkout in a
  -- terminal or with :!): re-read the current buffer now, the others when entered.
  vim.api.nvim_create_autocmd({ "FocusGained", "ShellCmdPost", "TermLeave", "TermClose" }, {
    group = group,
    callback = function()
      for _, s in pairs(state) do
        s.stale = true
      end
      attach(vim.api.nvim_get_current_buf())
    end,
  })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    callback = function(ev)
      detach(ev.buf)
    end,
  })

  vim.api.nvim_create_user_command("GitSignsToggle", function()
    M.toggle()
  end, { desc = "Toggle git signs in the sign column" })
  vim.api.nvim_create_user_command("GitHunkNext", M.next_hunk, { desc = "Jump to the next git hunk" })
  vim.api.nvim_create_user_command("GitHunkPrev", M.prev_hunk, { desc = "Jump to the previous git hunk" })
  vim.api.nvim_create_user_command("GitHunkPreview", M.preview_hunk, { desc = "Preview the git hunk under the cursor" })

  -- :ReloadConfig runs setup() again with files already open.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    attach(vim.api.nvim_win_get_buf(win))
  end
end

return M
