-- Completion session: triggering, fetching from sources, ranking, rendering.
--
-- One session at a time, for the buffer being edited. The menu is Neovim's
-- native pum, fed through vim.fn.complete().
--
-- Every menu entry carries `word = <text already typed>`, so the buffer text is
-- identical whichever entry is highlighted, even when <C-n>/<C-p> "insert" the
-- selection. The real edit happens only on accept (apply.lua), from the
-- original item. `user_data` is the index into `shown.items`.
--
-- Stale work is dropped, as in the picker: a fetch is `dead` once superseded,
-- renders carry a counter, and a result is shown only if the buffer line and
-- cursor are still exactly what it was computed for.
local config = require("core.config")
local matcher = require("core.picker.matcher")
local util = require("core.util")
local lsp_source = require("core.completion.sources.lsp")
local path_source = require("core.completion.sources.path")

local M = {}

---@type boolean runtime switch (:Completion); config.completion.enabled is the static one
M.enabled = true

---@class core.completion.Item
---@field source string
---@field label string
---@field abbr? string
---@field filter string text matched against the typed word
---@field sort string
---@field kind? string
---@field menu? string
---@field doc? string
---@field insert? string plain text to insert (path, buffer)
---@field retrigger? boolean reopen the menu after accepting
---@field lsp? table raw lsp.CompletionItem
---@field client_id? integer
---@field enc? string
---@field resolved? table|false result of completionItem/resolve

---@class core.completion.Fetch
---@field ctx table context the sources were asked for
---@field by_source table<string, core.completion.Item[]>
---@field pending table<string, true>
---@field cancels table<string, fun()>
---@field matchers table<boolean, core.Matcher>
---@field ordered table<boolean, table>
---@field incomplete boolean
---@field grace_done boolean
---@field dead? boolean

---@type core.completion.Fetch?
local fetch
---@type { ctx: table, items: core.completion.Item[] }?
local shown
local latest -- context of the most recent keystroke
local staged -- { item, ctx } handed from the <Tab> mapping to commit()
local last -- line/cursor of the last handled change, to ignore no-op changes
local suppress_tick -- changedtick produced by our own edit: don't re-trigger on it
local pum_ours = false -- we put the current menu there
local gen = 0 -- bumped whenever in-flight work must be dropped
local render_gen = 0

local debounce = assert(vim.uv.new_timer())
local grace = assert(vim.uv.new_timer())
local resolve_timer = assert(vim.uv.new_timer())

---@param timer uv.uv_timer_t
---@param ms integer
---@param fn fun()
local function after(timer, ms, fn)
  timer:stop()
  timer:start(ms, 0, vim.schedule_wrap(fn))
end

local reported = {}
local function report_once(key, msg)
  if not reported[key] then
    reported[key] = true
    vim.schedule(function()
      util.notify(msg, vim.log.levels.ERROR)
    end)
  end
end

local function in_insert()
  return vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
end

--- Is the buffer line and cursor still what `ctx` was computed for?
---@param ctx table
local function same_state(ctx)
  if vim.api.nvim_get_current_buf() ~= ctx.buf then
    return false
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  return pos[1] - 1 == ctx.lnum and pos[2] == ctx.col and vim.api.nvim_get_current_line() == ctx.line
end

---@return table
local function context()
  local win = vim.api.nvim_get_current_win()
  local pos = vim.api.nvim_win_get_cursor(win)
  local line = vim.api.nvim_get_current_line()
  local col = pos[2]
  local before = line:sub(1, col)
  local prefix = vim.fn.matchstr(before, "\\k*$")
  return {
    buf = vim.api.nvim_win_get_buf(win),
    win = win,
    lnum = pos[1] - 1,
    col = col,
    line = line,
    before = before,
    prefix = prefix,
    start_col = col - #prefix,
  }
end

local function source(name)
  local ok, mod = pcall(require, "core.completion.sources." .. name)
  if not ok then
    report_once("source:" .. name, ("completion source '%s' failed to load:\n%s"):format(name, mod))
    return nil
  end
  return mod
end

-- Public state ---------------------------------------------------------------

--- Should auto-completion run in the current buffer?
function M.active()
  if not (config.get().completion.enabled and M.enabled) then
    return false
  end
  local buf = vim.api.nvim_get_current_buf()
  -- Prompt (picker), terminal, help, quickfix, scratch buffers: never.
  if vim.bo[buf].buftype ~= "" or vim.b[buf].completion == false then
    return false
  end
  return vim.fn.reg_executing() == ""
end

---@return boolean true while our menu is on screen and matches the buffer
function M.visible()
  return shown ~= nil and vim.fn.pumvisible() == 1 and same_state(shown.ctx)
end

---@return boolean true while a request is pending or about to start
function M.busy()
  if debounce:is_active() then
    return true
  end
  return fetch ~= nil and not fetch.dead and next(fetch.pending) ~= nil
end

--- Drop everything in flight; optionally close our menu.
---@param close_pum boolean
function M.reset(close_pum)
  gen = gen + 1
  render_gen = render_gen + 1
  debounce:stop()
  grace:stop()
  resolve_timer:stop()
  if fetch then
    fetch.dead = true
    for _, cancel in pairs(fetch.cancels) do
      pcall(cancel)
    end
    for _, m in pairs(fetch.matchers) do
      m.dispose()
    end
    fetch = nil
  end
  shown = nil
  if close_pum then
    if pum_ours and in_insert() and vim.fn.pumvisible() == 1 then
      pcall(vim.fn.complete, vim.fn.col("."), {})
    end
    pum_ours = false
  end
end

--- Remember the buffer's current tick: the change was ours, don't react to it.
---@param buf integer
function M.suppress(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    suppress_tick = vim.api.nvim_buf_get_changedtick(buf)
  end
  last = nil
end

-- Ranking --------------------------------------------------------------------

local function by_sort(a, b)
  if a.sort ~= b.sort then
    return a.sort < b.sort
  end
  return a.label < b.label
end

--- All items in display order (source priority, then sortText), without
--- cross-source duplicates; plus the match keys for the fuzzy matcher.
---@param f core.completion.Fetch
---@param use_buffer boolean
local function merge(f, use_buffer)
  local items, seen = {}, {}
  for _, name in ipairs(config.get().completion.sources) do
    local list = f.by_source[name]
    if list and (name ~= "buffer" or use_buffer) then
      table.sort(list, by_sort)
      local mine = {}
      for _, it in ipairs(list) do
        if not seen[it.filter] then
          items[#items + 1] = it
        end
        mine[it.filter] = true
      end
      for word in pairs(mine) do
        seen[word] = true
      end
    end
  end

  local keys, lookup = {}, {}
  for _, it in ipairs(items) do
    local key = it.filter ~= "" and it.filter or it.label
    if key:find("[\r\n]") then
      key = key:gsub("[\r\n]+", " ")
    end
    local bucket = lookup[key]
    if bucket then
      bucket[#bucket + 1] = it
    else
      lookup[key] = { it }
      keys[#keys + 1] = key
    end
  end
  return { items = items, keys = keys, lookup = lookup }
end

---@param f core.completion.Fetch
---@param query string
---@param cb fun(items: core.completion.Item[])
local function rank(f, query, cb)
  local cfg = config.get().completion
  local use_buffer = f.ctx.manual or #query >= cfg.buffer.min_prefix
  local set = f.ordered[use_buffer]
  if not set then
    set = merge(f, use_buffer)
    f.ordered[use_buffer] = set
  end

  if query == "" then
    cb(vim.list_slice(set.items, 1, cfg.max_items))
    return
  end
  if #set.keys == 0 then
    cb({})
    return
  end

  local m = f.matchers[use_buffer]
  if not m then
    m = matcher.from_list(set.keys)
    f.matchers[use_buffer] = m
  end

  local function go()
    m.filter(query, cfg.max_items, function(matched)
      local out = {}
      for _, key in ipairs(matched) do
        for _, it in ipairs(set.lookup[key] or {}) do
          if #out < cfg.max_items then
            out[#out + 1] = it
          end
        end
      end
      cb(out)
    end)
  end
  if m.loading then
    m.subscribe(go)
  else
    go()
  end
end

-- Rendering ------------------------------------------------------------------

---@param ctx table
---@param list core.completion.Item[]
local function show(ctx, list)
  if not in_insert() or not same_state(ctx) then
    return
  end
  if #list == 0 then
    shown = nil
    if pum_ours and vim.fn.pumvisible() == 1 then
      pcall(vim.fn.complete, ctx.col + 1, {})
    end
    pum_ours = false
    return
  end

  local entries = {}
  for i, it in ipairs(list) do
    if it.doc == nil and it.lsp then
      it.doc = lsp_source.doc_text(it.lsp) -- only for what is displayed; see sources/lsp.lua
    end
    entries[i] = {
      word = ctx.prefix, -- see the header comment
      abbr = it.abbr or it.label,
      kind = it.kind,
      menu = it.menu,
      info = it.doc,
      user_data = i,
      dup = 1,
      empty = 1,
    }
  end
  shown = { ctx = ctx, items = list }
  pum_ours = true
  local ok, err = pcall(vim.fn.complete, ctx.start_col + 1, entries)
  if not ok then
    shown, pum_ours = nil, false
    report_once("complete", "completion: showing the menu failed:\n" .. tostring(err))
  end
end

---@param f core.completion.Fetch
local function request_render(f)
  local ctx = latest
  if not ctx then
    return
  end
  render_gen = render_gen + 1
  local id, g = render_gen, gen
  rank(f, ctx.prefix, function(list)
    if id ~= render_gen or g ~= gen or f.dead then
      return
    end
    show(ctx, list)
  end)
end

-- Fetching -------------------------------------------------------------------

---@param ctx table
---@param names string[]
local function launch(ctx, names)
  local f = {
    ctx = ctx,
    by_source = {},
    pending = {},
    cancels = {},
    matchers = {},
    ordered = {},
    incomplete = false,
    grace_done = false,
  }
  fetch = f
  for _, name in ipairs(names) do
    f.pending[name] = true -- all flagged before any source runs: sources may answer synchronously
  end

  local function finish(name, items, incomplete)
    if f.dead or not f.pending[name] then
      return
    end
    f.pending[name] = nil
    f.by_source[name] = items
    f.incomplete = f.incomplete or incomplete
    for _, m in pairs(f.matchers) do
      m.dispose()
    end
    f.matchers, f.ordered = {}, {}

    if next(f.pending) == nil then
      grace:stop()
      request_render(f)
    elseif f.grace_done then
      request_render(f) -- a slow source arrived after we showed the rest
    end
  end

  -- Don't make fast sources wait for a slow server forever: after `grace` ms
  -- show what we have; the late source is merged in when it answers.
  after(grace, config.get().completion.grace, function()
    if f.dead then
      return
    end
    f.grace_done = true
    if next(f.pending) ~= nil then
      request_render(f)
    end
  end)

  for _, name in ipairs(names) do
    local mod = source(name)
    if not mod then
      finish(name, {}, false)
    else
      local ok, cancel = pcall(mod.fetch, ctx, function(items, incomplete)
        finish(name, items, incomplete)
      end)
      if ok then
        f.cancels[name] = cancel
      else
        report_once("fetch:" .. name, ("completion source '%s' failed:\n%s"):format(name, cancel))
        finish(name, {}, false)
      end
    end
  end
end

---@param ctx table
---@param manual boolean
local function trigger(ctx, manual)
  local cfg = config.get().completion

  local has = {}
  for _, name in ipairs(cfg.sources) do
    has[name] = true
  end

  if has.path and ctx.before:find("/", 1, true) then
    local p = path_source.detect(ctx)
    if p then
      ctx.path = p
      ctx.prefix = p.frag
      ctx.start_col = ctx.col - #p.frag
    end
  end

  -- A word with nothing typed yet only opens the menu after a trigger character.
  local ch = ctx.before:sub(-1)
  local is_trigger = false
  if ctx.prefix == "" and ch ~= "" then
    if ctx.path and ch == "/" then
      is_trigger = true
    elseif lsp_source.trigger_chars(ctx.buf)[ch] then
      is_trigger = true
    else
      is_trigger = vim.tbl_contains(cfg.trigger_chars, ch)
    end
  end
  if ctx.prefix == "" and not is_trigger and not manual then
    M.reset(true)
    return
  end

  ctx.manual = manual
  latest = ctx

  local names = {}
  if ctx.path then
    names[1] = "path"
  else
    for _, name in ipairs(cfg.sources) do
      if name ~= "path" and not (name == "buffer" and ctx.prefix == "" and not manual) then
        names[#names + 1] = name
      end
    end
  end
  if #names == 0 then
    M.reset(true)
    return
  end

  -- Same word as the running/last fetch, only longer: filter what we have
  -- instead of asking the sources again (unless a source said isIncomplete).
  local f = fetch
  local same_word = f ~= nil
    and not f.dead
    and f.ctx.buf == ctx.buf
    and f.ctx.lnum == ctx.lnum
    and f.ctx.start_col == ctx.start_col
    and (f.ctx.path and f.ctx.path.dir) == (ctx.path and ctx.path.dir)
    and ctx.prefix:sub(1, #f.ctx.prefix) == f.ctx.prefix
  if same_word and not manual and not f.incomplete then
    after(debounce, 0, function()
      -- While a source is still outstanding and within its grace period the
      -- render happens when it answers (or the grace timer fires), not now.
      local waiting = next(f.pending) ~= nil and not f.grace_done
      if fetch == f and not f.dead and not waiting and same_state(ctx) then
        request_render(f)
      end
    end)
    return
  end

  ctx.incomplete = same_word and f.incomplete or false
  M.reset(false) -- the old menu stays up until the new results replace it, to avoid flicker
  local g = gen
  after(debounce, manual and 0 or cfg.delay, function()
    if g ~= gen or not in_insert() or not same_state(ctx) then
      return
    end
    launch(ctx, names)
  end)
end

-- Events ----------------------------------------------------------------------

--- TextChangedI / TextChangedP
function M.on_change()
  if not M.active() or not in_insert() then
    return
  end
  if suppress_tick and suppress_tick == vim.api.nvim_buf_get_changedtick(0) then
    return
  end
  local ctx = context()
  -- <C-n>/<C-p> "re-insert" the identical word, which counts as a change.
  if last and last.buf == ctx.buf and last.lnum == ctx.lnum and last.col == ctx.col and last.line == ctx.line then
    return
  end
  last = { buf = ctx.buf, lnum = ctx.lnum, col = ctx.col, line = ctx.line }

  if not config.get().completion.auto then
    if shown then
      M.reset(true)
    end
    return
  end
  trigger(ctx, false)
end

--- CursorMovedI: moving without editing dismisses the menu.
function M.on_cursor()
  if shown and vim.api.nvim_get_current_line() == shown.ctx.line and not same_state(shown.ctx) then
    M.reset(true)
  end
end

--- Open the menu on request (<C-Space>), even with nothing typed.
function M.manual()
  if not M.active() then
    return
  end
  trigger(context(), true)
end

--- Reopen after accepting a directory.
local function retrigger()
  vim.schedule(function()
    if in_insert() and M.active() then
      trigger(context(), true)
    end
  end)
end

-- Accepting ------------------------------------------------------------------

--- The entry highlighted in our menu (the first one if none is), with the
--- context it was built for. Safe to call from an <expr> mapping.
---@return core.completion.Item? item, table? ctx
function M.selected()
  if not shown or vim.fn.pumvisible() == 0 or not same_state(shown.ctx) then
    return nil
  end
  local info = vim.fn.complete_info({ "selected", "items" })
  local sel = info.selected or -1
  local entry = info.items and info.items[sel + 1]
  local i = entry and tonumber(entry.user_data) or (sel >= 0 and sel + 1) or 1
  local item = shown.items[i]
  if not item then
    return nil
  end
  return item, shown.ctx
end

--- Phase 1, inside the <expr> mapping (the buffer must not change there):
--- remember what to accept. Returns false if there is nothing to accept.
---@return boolean
function M.stage_accept()
  local item, ctx = M.selected()
  if not item then
    return false
  end
  staged = { item = item, ctx = ctx }
  return true
end

--- Phase 2, after <C-e> has closed the native menu: apply the staged item.
function M.commit()
  local s = staged
  staged = nil
  M.reset(false)
  pum_ours = false
  if not s or not in_insert() or not same_state(s.ctx) then
    return
  end
  local ok, err = pcall(require("core.completion.apply").accept, s.item, s.ctx)
  if not ok then
    util.notify("completion: accept failed:\n" .. tostring(err), vim.log.levels.ERROR)
    return
  end
  if s.item.retrigger then
    retrigger()
  end
end

-- Documentation ----------------------------------------------------------------

--- CompleteChanged: resolve the highlighted LSP item lazily and show its docs.
function M.on_select()
  if not config.get().completion.docs or not shown then
    return
  end
  local chosen = vim.v.event.completed_item
  local i = chosen and tonumber(chosen.user_data)
  local item = i and shown.items[i]
  if not item or item.doc or item.source ~= "lsp" or item.resolved ~= nil or item.resolving then
    return
  end
  local sel = vim.fn.complete_info({ "selected" }).selected

  local client = vim.lsp.get_client_by_id(item.client_id)
  local provider = client and client.server_capabilities and client.server_capabilities.completionProvider
  if not (provider and provider.resolveProvider) then
    item.resolved = false
    return
  end

  local snapshot = shown
  after(resolve_timer, 60, function()
    if shown ~= snapshot or item.resolving then
      return
    end
    item.resolving = true
    client:request("completionItem/resolve", item.lsp, function(err, res)
      item.resolving = nil
      item.resolved = (not err and res) or false
      local doc = res and lsp_source.doc_text(res)
      if not doc then
        return
      end
      item.doc = doc
      if shown ~= snapshot or vim.fn.pumvisible() == 0 or vim.fn.complete_info({ "selected" }).selected ~= sel then
        return
      end
      -- Named nvim__complete_set in 0.11, nvim_complete_set from 0.12.
      local set = vim.api.nvim_complete_set or vim.api.nvim__complete_set
      if set then
        pcall(set, sel, { info = doc })
      end
    end, snapshot.ctx.buf)
  end)
end

return M
