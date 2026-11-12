-- Floating prompt + result list. Knows nothing about what is being picked.
--
-- Anchored bottom-left, above the statusline. The list sits above the prompt
-- and is rendered bottom-up: the best match is the last list line, right above
-- the prompt.
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
}

-- { top-left, top, top-right, right, bottom-right, bottom, bottom-left, left }
-- "solid" borders are blank cells, so a bottom edge on the list plus a top edge
-- on the prompt would show as two empty rows. The list drops its bottom edge
-- and the prompt's top edge (which carries the title) is the only separator.
local SOLID_NO_BOTTOM = { " ", " ", " ", " ", "", "", "", " " }

local close_active ---@type fun()?

local function define_highlights()
  for name, link in pairs(HIGHLIGHTS) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

---@param cfg table
---@return table prompt, table list
local function layout(cfg)
  local border = cfg.border
  local edge = border == "none" and 0 or 1
  local solid = border == "solid"

  local status = vim.o.laststatus > 0 and 1 or 0
  local ui_height = vim.o.lines - vim.o.cmdheight - status
  local width = math.max(20, math.floor(vim.o.columns * cfg.width))
  local height = math.max(6, math.floor(ui_height * cfg.height))
  local top = ui_height - height

  local prompt_outer = 1 + 2 * edge
  local list_outer = height - prompt_outer
  local list_inner = list_outer - (solid and edge or 2 * edge)

  local base = {
    relative = "editor",
    style = "minimal",
    col = 0,
    width = width - 2 * edge,
  }
  local prompt = vim.tbl_extend("force", base, {
    border = border,
    row = top + list_outer,
    height = 1,
  })
  local list = vim.tbl_extend("force", base, {
    border = solid and SOLID_NO_BOTTOM or border,
    row = top,
    height = math.max(1, list_inner),
    focusable = false,
  })
  return prompt, list
end

---@class core.picker.Spec
---@field title string
---@field matcher core.Matcher
---@field on_select fun(item: string, action: "edit"|"split"|"vsplit"|"tabedit")
---@field on_cancel? fun()
---@field prompt? string

---@param spec core.picker.Spec
function M.open(spec)
  if close_active then
    close_active()
  end

  local cfg = config.get().picker
  local prompt_text = spec.prompt or cfg.prompt
  local total = spec.matcher.count()
  local prev_win = vim.api.nvim_get_current_win()
  local group = util.augroup("picker")

  local results = {} ---@type string[] best match first
  local sel = 0 -- 1 = best match
  local offset = 0 -- blank lines above the results in the list buffer
  local closed = false
  local chosen = false -- true once an item was picked (vs. dismissed)

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

  local prompt_cfg, list_cfg = layout(cfg)
  local list_win = vim.api.nvim_open_win(list_buf, false, list_cfg)
  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, prompt_cfg)
  for _, win in ipairs({ prompt_win, list_win }) do
    vim.wo[win].winhighlight = WINHL
  end
  vim.wo[list_win].wrap = false
  vim.wo[list_win].scrolloff = 0

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
    local count = ("%d/%d%s"):format(#results, total, spec.matcher.truncated and "+" or "")
    local title = (" %s  %s "):format(spec.title, count)
    vim.api.nvim_win_set_config(prompt_win, vim.tbl_extend("force", prompt_cfg, { title = title, title_pos = "left" }))
  end

  local function highlight()
    vim.api.nvim_buf_clear_namespace(list_buf, NS, 0, -1)
    if sel == 0 then
      return
    end
    local line = offset + #results - sel + 1 -- best match is the last line
    vim.api.nvim_buf_set_extmark(list_buf, NS, line - 1, 0, { line_hl_group = "PickerSelection", priority = 100 })
    vim.api.nvim_win_set_cursor(list_win, { line, 0 })
  end

  local function refresh()
    results = spec.matcher.filter(query(), cfg.max_results)
    sel = #results > 0 and 1 or 0

    -- Blank padding first, then results worst-to-best, so a short list stays
    -- pinned against the prompt.
    local height = vim.api.nvim_win_get_height(list_win)
    offset = math.max(0, height - #results)
    local lines = {}
    for _ = 1, offset do
      lines[#lines + 1] = ""
    end
    for i = #results, 1, -1 do
      lines[#lines + 1] = results[i]
    end

    vim.bo[list_buf].modifiable = true
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
    vim.bo[list_buf].modifiable = false

    -- A stale topline from a longer previous list would leave blank rows at the bottom.
    vim.api.nvim_win_call(list_win, function()
      vim.fn.winrestview({ topline = math.max(1, #lines - height + 1), lnum = #lines })
    end)

    highlight()
    update_title()
  end

  -- Actions -----------------------------------------------------------------
  --- delta > 0 moves the selection down the screen, toward the best match.
  ---@param delta integer
  local function move(delta)
    if #results == 0 then
      return
    end
    sel = math.min(#results, math.max(1, sel - delta))
    highlight()
  end

  local function page()
    return math.max(1, math.floor(vim.api.nvim_win_get_height(list_win) / 2))
  end

  local function close()
    if closed then
      return
    end
    closed = true
    close_active = nil
    pcall(vim.api.nvim_del_augroup_by_id, group)
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
  }
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
  bind({ "n" }, normal_only)

  -- Autocmds ----------------------------------------------------------------
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group = group,
    buffer = prompt_buf,
    callback = refresh,
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
      prompt_cfg, list_cfg = layout(cfg)
      vim.api.nvim_win_set_config(list_win, list_cfg)
      vim.api.nvim_win_set_config(prompt_win, prompt_cfg)
      refresh()
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_highlights })

  refresh()
  vim.cmd.startinsert()
end

return M
