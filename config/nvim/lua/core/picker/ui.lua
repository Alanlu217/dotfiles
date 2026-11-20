-- Floating prompt + result list (+ optional preview). Knows nothing about what is
-- being picked.
--
-- Anchored bottom-left, above the statusline. The prompt sits on top and the
-- list below it is rendered top-down: the best match is the first list line,
-- right under the prompt. With a preview, prompt and list take the left part and
-- the preview the full height on the right. Filtering is asynchronous: only the
-- latest query is ever rendered, and the UI stays responsive while a worker
-- ranks the items.
local config = require("core.config")
local util = require("core.util")

local M = {}

local NS = vim.api.nvim_create_namespace("core.picker")
local WINHL = "Normal:PickerNormal,FloatBorder:PickerBorder,FloatTitle:PickerTitle"
local HIGHLIGHTS = {
  PickerNormal = "NormalFloat",
  PickerBorder = "FloatBorder",
  PickerTitle = "FloatTitle",
  PickerSelection = "PmenuSel",
  PickerPreviewLine = "CursorLine",
  PickerPreviewMatch = "Search",
}

-- { top-left, top, top-right, right, bottom-right, bottom, bottom-left, left }
-- "solid" borders are blank cells, so a top edge on the list plus a bottom edge
-- on the prompt would show as two empty rows. The list drops its top edge and
-- the prompt's bottom edge is the only separator (its top edge carries the title).
local SOLID_NO_TOP = { "", "", "", " ", " ", " ", " ", " " }

local close_active ---@type fun()?
local preview_hidden = false -- the user turned the preview off; kept across pickers

local function define_highlights()
  for name, link in pairs(HIGHLIGHTS) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

---@param cfg table
---@param pcfg? table preview settings; nil = no preview pane
---@return table prompt, table list, table? preview
local function layout(cfg, pcfg)
  local with_preview = pcfg ~= nil
  local border = cfg.border
  local edge = border == "none" and 0 or 1
  local solid = border == "solid"

  local status = vim.o.laststatus > 0 and 1 or 0
  local ui_height = vim.o.lines - vim.o.cmdheight - status
  local width = math.max(20, math.floor(vim.o.columns * (with_preview and pcfg.picker_width or cfg.width)))
  local height = math.max(6, math.floor(ui_height * cfg.height))
  local top = ui_height - height

  -- Outer widths (border included): prompt and list on the left, preview right.
  local preview_outer = with_preview and math.min(math.floor(width * pcfg.width), width - 20) or 0
  local left = width - preview_outer

  local prompt_outer = 1 + 2 * edge
  local list_outer = height - prompt_outer
  local list_inner = list_outer - (solid and edge or 2 * edge)

  local base = {
    relative = "editor",
    style = "minimal",
    col = 0,
    width = left - 2 * edge,
  }
  local prompt = vim.tbl_extend("force", base, {
    border = border,
    row = top,
    height = 1,
  })
  local list = vim.tbl_extend("force", base, {
    border = solid and SOLID_NO_TOP or border,
    row = top + prompt_outer,
    height = math.max(1, list_inner),
    focusable = false,
  })
  local preview
  if with_preview then
    -- A full border of its own: it spans the prompt and list rows, and the title is the path.
    preview = {
      relative = "editor",
      style = "minimal",
      border = border,
      focusable = false,
      row = top,
      col = left,
      width = math.max(1, preview_outer - 2 * edge),
      height = math.max(1, height - 2 * edge),
    }
  end
  return prompt, list, preview
end

---@class core.picker.Spec
---@field title string
---@field id? string source id for `picker.preview.sources` overrides (files, grep, ...)
---@field matcher core.Matcher
---@field on_select fun(item: string, action: "edit"|"split"|"vsplit"|"tabedit")
---@field on_cancel? fun()
---@field prompt? string
---@field preview? false|fun(item: string, query: string): core.picker.PreviewTarget? what to show for the selected item (`query` is the one that produced the list); no preview pane without it

---@param spec core.picker.Spec
function M.open(spec)
  if close_active then
    close_active()
  end

  local cfg = config.get().picker
  local matcher = spec.matcher
  local prompt_text = spec.prompt or cfg.prompt
  local prev_win = vim.api.nvim_get_current_win()
  local group = util.augroup("picker")

  local results = {} ---@type string[] best match first
  local results_query = "" -- the query `results` answers (the prompt may have moved on since)
  local sel = 0 -- 1 = best match
  local closed = false
  local chosen = false -- true once an item was picked (vs. dismissed)
  local inflight, dirty = false, false

  -- Buffers and windows -----------------------------------------------------
  define_highlights()

  local prompt_buf = vim.api.nvim_create_buf(false, true)
  local list_buf = vim.api.nvim_create_buf(false, true)
  for _, buf in ipairs({ prompt_buf, list_buf }) do
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
  end
  vim.bo[prompt_buf].buftype = "prompt"
  vim.bo[list_buf].modifiable = false
  vim.fn.prompt_setprompt(prompt_buf, prompt_text)

  -- The preview pane only exists for sources that can resolve a preview, on wide enough editors.
  -- `picker.preview.sources[id]` = false turns the pane off for that source; a table overrides
  -- any preview setting (e.g. { width = 0.65 } for a wider pane).
  local override = spec.id and cfg.preview.sources and cfg.preview.sources[spec.id]
  local pcfg = type(override) == "table" and vim.tbl_extend("force", cfg.preview, override) or cfg.preview
  local resolver = type(spec.preview) == "function" and override ~= false and spec.preview or nil
  local previewer ---@type table?

  local function preview_wanted()
    return resolver ~= nil and pcfg.enabled ~= false and not preview_hidden and vim.o.columns >= pcfg.min_columns
  end

  local function new_previewer()
    return require("core.picker.preview").new({ cfg = pcfg, winhl = WINHL })
  end

  local want_preview = preview_wanted()
  local prompt_cfg, list_cfg, preview_cfg = layout(cfg, want_preview and pcfg or nil)
  local list_win = vim.api.nvim_open_win(list_buf, false, list_cfg)
  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, prompt_cfg)
  for _, win in ipairs({ prompt_win, list_win }) do
    vim.wo[win].winhighlight = WINHL
  end
  vim.wo[list_win].wrap = false
  vim.wo[list_win].scrolloff = 0
  if want_preview then
    previewer = new_previewer()
    previewer.set_layout(preview_cfg) -- opened without entering: the prompt keeps the focus
  end

  -- Preview updates are throttled: at most one per `debounce` ms, the leading one
  -- immediate after idle and the last one always delivered. Holding <C-n> keeps
  -- the preview following instead of freezing until the key is released.
  local timer ---@type uv.uv_timer_t?
  local last_preview = 0

  local function update_preview()
    if closed or not previewer then
      return
    end
    last_preview = vim.uv.hrtime()
    local item = results[sel]
    if not item then
      previewer.clear()
      return
    end
    local ok, target = pcall(resolver, item, results_query)
    if ok then
      previewer.show(target)
    else
      previewer.show({ kind = "text", title = "preview failed", lines = vim.split(tostring(target), "\n", { plain = true }) })
    end
  end

  local function schedule_preview()
    if closed or not previewer then
      return
    end
    timer = timer or vim.uv.new_timer()
    local elapsed = (vim.uv.hrtime() - last_preview) / 1e6
    timer:stop()
    timer:start(math.max(0, math.ceil(pcfg.debounce - elapsed)), 0, vim.schedule_wrap(update_preview))
  end

  -- Rendering ---------------------------------------------------------------
  ---@return string
  local function query()
    local ok, text = pcall(vim.fn.prompt_getinput, prompt_buf)
    if ok then
      return text
    end
    local line = vim.api.nvim_buf_get_lines(prompt_buf, -2, -1, false)[1] or ""
    return line:sub(#prompt_text + 1)
  end

  local function update_title()
    if cfg.border == "none" then
      return
    end
    local count = ("%d/%d%s"):format(#results, matcher.count(), matcher.truncated and "+" or "")
    if matcher.loading then
      count = count .. "  scanning..."
    end
    if matcher.hint then
      count = count .. "  [" .. matcher.hint .. "]"
    end
    local title = (" %s  %s "):format(spec.title, count)
    vim.api.nvim_win_set_config(prompt_win, vim.tbl_extend("force", prompt_cfg, { title = title, title_pos = "left" }))
  end

  local function highlight()
    vim.api.nvim_buf_clear_namespace(list_buf, NS, 0, -1)
    schedule_preview() -- also for sel == 0: an empty list empties the preview
    if sel == 0 then
      return
    end
    vim.api.nvim_buf_set_extmark(list_buf, NS, sel - 1, 0, { line_hl_group = "PickerSelection", priority = 100 })
    vim.api.nvim_win_set_cursor(list_win, { sel, 0 })
  end

  ---@param items string[]
  ---@param for_query string
  local function render(items, for_query)
    results, results_query = items, for_query
    sel = #results > 0 and 1 or 0

    -- Best match first, so a short list stays pinned under the prompt.
    local lines = vim.list_slice(results)

    vim.bo[list_buf].modifiable = true
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
    vim.bo[list_buf].modifiable = false

    -- Start from the top; a stale topline from a previous list would hide the best match.
    vim.api.nvim_win_call(list_win, function()
      vim.fn.winrestview({ topline = 1, lnum = 1 })
    end)

    highlight()
    update_title()
  end

  --- Ask the matcher for the current query. Only one request is in flight; if
  --- the query changes meanwhile, the stale answer is dropped and the latest
  --- query is requested next.
  local function request()
    if closed then
      return
    end
    if inflight then
      dirty = true
      if matcher.cancel then
        matcher.cancel() -- the running answer is stale; let a live matcher stop early
      end
      return
    end
    inflight = true
    local asked = query()
    matcher.filter(asked, cfg.max_results, function(items)
      inflight = false
      if closed then
        return
      end
      if dirty then
        dirty = false
        request()
        return
      end
      render(items, asked)
    end)
  end

  -- Actions -----------------------------------------------------------------
  --- delta > 0 moves the selection down the screen, away from the best match.
  ---@param delta integer
  local function move(delta)
    if #results == 0 then
      return
    end
    sel = math.min(#results, math.max(1, sel + delta))
    highlight()
  end

  local function page()
    return math.max(1, math.floor(vim.api.nvim_win_get_height(list_win) / 2))
  end

  --- Re-lay out after a resize or a preview toggle: opens or closes the pane as needed.
  local function apply_layout()
    local want = preview_wanted()
    prompt_cfg, list_cfg, preview_cfg = layout(cfg, want and pcfg or nil)
    vim.api.nvim_win_set_config(list_win, list_cfg)
    vim.api.nvim_win_set_config(prompt_win, prompt_cfg)
    if want then
      previewer = previewer or new_previewer()
      previewer.set_layout(preview_cfg)
    elseif previewer then
      previewer.dispose()
      previewer = nil
    end
    update_title() -- set_config dropped the prompt's title
    schedule_preview()
  end

  local function toggle_preview()
    if resolver then
      preview_hidden = not preview_hidden
      apply_layout()
    end
  end

  local function close()
    if closed then
      return
    end
    closed = true
    close_active = nil
    pcall(vim.api.nvim_del_augroup_by_id, group)
    if matcher.dispose then
      matcher.dispose()
    end
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    if previewer then
      previewer.dispose()
      previewer = nil
    end
    vim.cmd.stopinsert()
    for _, win in ipairs({ prompt_win, list_win }) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    if vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
    if not chosen and spec.on_cancel then
      vim.schedule(spec.on_cancel)
    end
  end
  close_active = close

  ---@param action "edit"|"split"|"vsplit"|"tabedit"
  local function select(action)
    local item = results[sel]
    chosen = item ~= nil
    close()
    if item then
      vim.schedule(function()
        spec.on_select(item, action)
      end)
    end
  end

  -- Keymaps -----------------------------------------------------------------
  local keys = cfg.keys
  local bindings = {
    { keys.next, function() move(1) end },
    { keys.prev, function() move(-1) end },
    { keys.page_down, function() move(page()) end },
    { keys.page_up, function() move(-page()) end },
    { keys.close, close },
    { { "<CR>" }, function() select("edit") end },
    { keys.split, function() select("split") end },
    { keys.vsplit, function() select("vsplit") end },
    { keys.tab, function() select("tabedit") end },
    { keys.preview_toggle or {}, toggle_preview },
    { keys.preview_down or {}, function() if previewer then previewer.page(1) end end },
    { keys.preview_up or {}, function() if previewer then previewer.page(-1) end end },
  }
  -- The preview can't be focused, so wheel events are caught here and routed by
  -- pointer position. Anywhere else the key keeps its default behaviour.
  local wheel_keys = { up = "<ScrollWheelUp>", down = "<ScrollWheelDown>", left = "<ScrollWheelLeft>", right = "<ScrollWheelRight>" }
  local function wheel(dir)
    local pos = vim.fn.getmousepos()
    if previewer and previewer.contains(pos.screenrow, pos.screencol) then
      previewer.wheel(dir)
    else
      vim.api.nvim_feedkeys(vim.keycode(wheel_keys[dir]), "n", false)
    end
  end
  local mouse = {}
  for dir, key in pairs(wheel_keys) do
    mouse[#mouse + 1] = { { key }, function() wheel(dir) end }
  end
  local normal_only = {
    { { "j" }, function() move(1) end },
    { { "k" }, function() move(-1) end },
    { { "q" }, close },
  }

  ---@param modes string[]
  ---@param list table[]
  local function bind(modes, list)
    for _, entry in ipairs(list) do
      for _, key in ipairs(entry[1]) do
        vim.keymap.set(modes, key, entry[2], { buffer = prompt_buf, nowait = true, silent = true })
      end
    end
  end
  bind({ "i", "n" }, bindings)
  bind({ "i", "n" }, mouse)
  bind({ "n" }, normal_only)

  -- Autocmds ----------------------------------------------------------------
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group = group,
    buffer = prompt_buf,
    callback = request,
  })
  -- Clicking away or switching windows dismisses the picker.
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    buffer = prompt_buf,
    callback = function()
      vim.schedule(close)
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if closed then
        return
      end
      apply_layout()
      request()
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_highlights })

  -- A still-loading matcher (scan in progress) re-requests when it finishes.
  if matcher.subscribe then
    matcher.subscribe(request)
  end

  request()
  vim.cmd.startinsert()
end

return M
