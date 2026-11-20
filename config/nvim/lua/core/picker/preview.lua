-- Preview pane for the picker: shows a file (or plain text) in a floating window.
-- Knows nothing about sources; ui.lua hands it a target the source resolved.
--
-- Files are read with libuv, never loaded as real buffers (no LSP attach, swap
-- files or autocmds for every file you merely browse). Each previewed file lives
-- in its own hidden scratch buffer, so going back to it is instant and its
-- treesitter tree is kept. The cache is per picker session and wiped on dispose().
local config = require("core.config")

local uv = vim.uv

local M = {}

local NS = vim.api.nvim_create_namespace("core.picker.preview")
local MAX_MARKED_LINES = 200

---@class core.picker.PreviewTarget
---@field kind "file"|"text"
---@field path? string       file: absolute path
---@field lines? string[]    text: what to show
---@field title? string      text: border title (files use their path)
---@field lnum? integer      file: 1-based line to centre and mark
---@field col? integer       file: 1-based byte column of the match on `lnum`
---@field end_lnum? integer  file: last marked line (default `lnum`)
---@field end_col? integer   file: 1-based byte column after the match; with `col` marks a range

---@param st uv.fs_stat.result
---@return string
local function stat_key(st)
  return ("%d:%d:%d"):format(st.size, st.mtime.sec, st.mtime.nsec)
end

---@param path string
---@return string
local function rel(path)
  return vim.fn.fnamemodify(path, ":~:.")
end

---@return integer
local function new_buf()
  local buf = vim.api.nvim_create_buf(false, true) -- nofile, hidden when not shown, no swap
  vim.bo[buf].undolevels = -1
  vim.b[buf].core_picker_preview = true
  return buf
end

---@param buf integer
---@param lines string[]
local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- Read up to `max_bytes` of a regular file.
---@param path string
---@param st uv.fs_stat.result
---@param max_bytes integer
---@return { lines: string[], truncated: boolean, bytes: integer }? data
---@return string? reason why there is nothing to show
local function read_file(path, st, max_bytes)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return nil, "cannot open file"
  end
  local want = math.min(st.size, max_bytes)
  local data = want > 0 and uv.fs_read(fd, want, 0) or ""
  uv.fs_close(fd)
  if not data then
    return nil, "cannot read file"
  end
  if data:find("\0", 1, true) then
    return nil, "binary file"
  end

  local bytes = #data
  local truncated = st.size > want
  if data:find("\r\n", 1, true) then
    data = data:gsub("\r\n", "\n")
  end
  local lines = vim.split(data, "\n", { plain = true })
  if truncated then
    table.remove(lines) -- the last line was probably cut mid-way
  elseif #lines > 1 and lines[#lines] == "" then
    table.remove(lines) -- trailing newline, not an extra line
  end
  if #lines == 0 then
    lines = { "" }
  end
  return { lines = lines, truncated = truncated, bytes = bytes }
end

---@param buf integer
---@param path string
---@param data { lines: string[], bytes: integer }
---@param cfg table
local function start_highlight(buf, path, data, cfg)
  local ts = config.get().treesitter
  if not ts.enabled or data.bytes > cfg.highlight_max_bytes then
    return
  end
  local ok, ft = pcall(vim.filetype.match, { filename = path, contents = vim.list_slice(data.lines, 1, 100) })
  if not ok or not ft or vim.tbl_contains(ts.disable or {}, ft) then
    return
  end
  -- 'filetype' stays unset on purpose: setting it would run ftplugins and user
  -- FileType autocmds for a buffer nobody edits. Treesitter only needs the language.
  local lang = vim.treesitter.language.get_lang(ft)
  if not lang then
    return
  end
  local has_parser, has_query = require("core.treesitter").available(lang)
  if has_parser and has_query then
    pcall(vim.treesitter.start, buf, lang)
  end
end

---@param opts { cfg: table, winhl: string }
function M.new(opts)
  local cfg = opts.cfg
  local winhl = opts.winhl

  local self = {}
  local win ---@type integer?
  local win_cfg ---@type table?
  local text_buf ---@type integer? shared by every text target
  local files = {} ---@type table<string, { buf: integer, key: string }>
  local lru = {} ---@type string[] least recently used first
  local last_sig ---@type string? signature of the file target on screen
  local disposed = false

  ---@return boolean
  local function alive()
    return win ~= nil and vim.api.nvim_win_is_valid(win)
  end

  local function style_win()
    local wo = vim.wo[win]
    -- Re-applied whenever the buffer changes: window options can be remembered per buffer.
    wo.winhighlight = winhl
    -- Wrapping follows the editor unless `preview.wrap` forces it.
    local wrap = cfg.wrap
    if wrap == nil then
      wrap = vim.o.wrap
    end
    wo.wrap = wrap
    for _, name in ipairs({ "linebreak", "breakindent", "breakindentopt", "showbreak" }) do
      wo[name] = vim.o[name]
    end
    wo.smoothscroll = true -- <C-e>/<C-y> then move by screen rows, so a wrapped line scrolls row by row
    wo.scrolloff = 0
    wo.signcolumn = "no"
    wo.number = false
    wo.relativenumber = false
    wo.foldenable = false
    wo.fillchars = "eob: " -- no ~ below a short file
    wo.cursorline = false
    wo.list = false
    wo.spell = false
  end

  ---@param buf integer
  local function show_buf(buf)
    if vim.api.nvim_win_get_buf(win) ~= buf then
      -- Entering a buffer in a float the user never focuses must not wake their autocmds.
      local saved = vim.o.eventignore
      vim.o.eventignore = "all"
      pcall(vim.api.nvim_win_set_buf, win, buf)
      vim.o.eventignore = saved
    end
    style_win()
  end

  --- Border title; `suffix` is kept whole, the path is cut from the left.
  ---@param text? string
  ---@param suffix? string
  local function set_title(text, suffix)
    if not alive() then
      return
    end
    if not text or win_cfg.border == "none" then
      vim.api.nvim_win_set_config(win, win_cfg)
      style_win() -- set_config re-applies style = "minimal" over our options
      return
    end
    suffix = suffix or ""
    local room = math.max(1, win_cfg.width - 2 - vim.fn.strdisplaywidth(suffix))
    if vim.fn.strdisplaywidth(text) > room then
      local n = vim.fn.strchars(text)
      text = "…" .. vim.fn.strcharpart(text, n - math.max(1, room - 1))
    end
    local title = " " .. text .. suffix .. " "
    vim.api.nvim_win_set_config(win, vim.tbl_extend("force", win_cfg, { title = title, title_pos = "left" }))
    style_win()
  end

  --- Make room: drop the least recently used files, never the one on screen.
  local function evict()
    local limit = math.max(1, cfg.cache)
    while #lru > limit do
      local idx
      for i, path in ipairs(lru) do
        local entry = files[path]
        if not (entry and alive() and vim.api.nvim_win_get_buf(win) == entry.buf) then
          idx = i
          break
        end
      end
      if not idx then
        return
      end
      local path = table.remove(lru, idx)
      local entry = files[path]
      files[path] = nil
      if entry and vim.api.nvim_buf_is_valid(entry.buf) then
        pcall(vim.api.nvim_buf_delete, entry.buf, { force = true })
      end
    end
  end

  ---@param path string
  local function touch(path)
    for i, p in ipairs(lru) do
      if p == path then
        table.remove(lru, i)
        break
      end
    end
    lru[#lru + 1] = path
  end

  --- Screen rows buffer line `lnum` takes in the preview window (wrapping included).
  ---@param lnum integer 1-based
  ---@return integer
  local function line_rows(lnum)
    return vim.api.nvim_win_text_height(win, { start_row = lnum - 1, end_row = lnum - 1 }).all
  end

  --- Highest topline that still fills the window down to the last line of the file.
  ---@param count integer lines in the buffer
  ---@param height integer
  ---@return integer
  local function max_top(count, height)
    local top, used = count + 1, 0
    while top > 1 do
      local rows = line_rows(top - 1)
      if used + rows > height then
        break
      end
      used = used + rows
      top = top - 1
    end
    return top
  end

  --- Topline that centres line `lnum` in screen rows, never leaving blank rows below the file.
  ---@param lnum integer
  ---@param count integer
  ---@param height integer
  ---@return integer
  local function centred_top(lnum, count, height)
    local above = math.floor((height - math.min(line_rows(lnum), height)) / 2)
    local top, used = lnum, 0
    while top > 1 do
      local rows = line_rows(top - 1)
      if used + rows > above then
        break
      end
      used = used + rows
      top = top - 1
    end
    return math.min(top, max_top(count, height))
  end

  ---@param buf integer
  ---@param t core.picker.PreviewTarget
  local function mark_and_place(buf, t)
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    local count = vim.api.nvim_buf_line_count(buf)
    local height = vim.api.nvim_win_get_height(win)

    if not t.lnum then
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview({ topline = 1, lnum = 1, col = 0, leftcol = 0, skipcol = 0, curswant = 0 })
      end)
      return
    end

    local first = math.min(math.max(t.lnum, 1), count)
    local last = math.min(math.max(t.end_lnum or first, first), count, first + MAX_MARKED_LINES - 1)
    for l = first, last do
      vim.api.nvim_buf_set_extmark(buf, NS, l - 1, 0, { line_hl_group = "PickerPreviewLine", priority = 100 })
    end
    if t.col and t.end_col then
      vim.api.nvim_buf_set_extmark(buf, NS, first - 1, t.col - 1, {
        end_row = last - 1,
        end_col = t.end_col - 1,
        hl_group = "PickerPreviewMatch",
        priority = 200,
        strict = false,
      })
    end

    local top = centred_top(first, count, height)
    -- Without wrapping a match far to the right would be invisible: scroll to it.
    local leftcol, col = 0, 0
    if t.col and not vim.wo[win].wrap then
      local line = vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1] or ""
      local bytecol = math.min(math.max(t.col - 1, 0), #line)
      local vcol = vim.fn.strdisplaywidth(line:sub(1, bytecol))
      local width = vim.api.nvim_win_get_width(win)
      if vcol >= width - 8 then
        leftcol = vcol - math.floor(width / 3)
        col = bytecol
      end
    end
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ topline = top, lnum = first, col = col, leftcol = leftcol, skipcol = 0, curswant = col })
    end)
  end

  ---@param t { title?: string, lines?: string[] }
  local function show_text(t)
    if not text_buf or not vim.api.nvim_buf_is_valid(text_buf) then
      text_buf = new_buf()
    end
    local lines = t.lines and #t.lines > 0 and vim.split(table.concat(t.lines, "\n"), "\n", { plain = true }) or { "" }
    set_lines(text_buf, lines)
    show_buf(text_buf)
    mark_and_place(text_buf, {})
    set_title(t.title)
  end

  ---@param title string
  ---@param message string
  local function notice(title, message)
    show_text({ title = title, lines = { "", "  " .. message } })
  end

  ---@param t core.picker.PreviewTarget
  local function show_file(t)
    local path = t.path
    local title = rel(path)
    local st = uv.fs_stat(path)
    if not st then
      return notice(title, "file not found")
    end
    if st.type ~= "file" then
      -- Opening a FIFO or device would block the editor, so only regular files are read.
      return notice(title, st.type == "directory" and "directory" or ("not a regular file (" .. st.type .. ")"))
    end

    local key = stat_key(st)
    local entry = files[path]
    local truncated = false
    if entry and entry.key == key and vim.api.nvim_buf_is_valid(entry.buf) then
      truncated = entry.truncated
    else
      local data, reason = read_file(path, st, cfg.max_filesize)
      if not data then
        return notice(title, reason or "cannot preview")
      end
      local fresh = not (entry and vim.api.nvim_buf_is_valid(entry.buf))
      local buf = fresh and new_buf() or entry.buf
      set_lines(buf, data.lines)
      if fresh or not vim.b[buf].ts_highlight then
        start_highlight(buf, path, data, cfg)
      end
      entry = { buf = buf, key = key, truncated = data.truncated }
      files[path] = entry
      truncated = data.truncated
    end

    touch(path)
    show_buf(entry.buf)
    mark_and_place(entry.buf, t)
    local suffix = truncated and "  [truncated]" or (st.size == 0 and "  [empty]" or nil)
    set_title(title, suffix)
    evict() -- after the swap: the buffer that was on screen may now go
  end

  -- API ---------------------------------------------------------------------

  --- Open, move or (with nil) close the window.
  ---@param c? table nvim_open_win config
  function self.set_layout(c)
    if disposed then
      return
    end
    if not c then
      if alive() then
        pcall(vim.api.nvim_win_close, win, true)
      end
      win, win_cfg, last_sig = nil, nil, nil
      return
    end
    win_cfg = c
    if alive() then
      vim.api.nvim_win_set_config(win, c) -- drops the title, the next show() sets it again
      style_win()
      last_sig = nil
    else
      if not text_buf or not vim.api.nvim_buf_is_valid(text_buf) then
        text_buf = new_buf()
      end
      win = vim.api.nvim_open_win(text_buf, false, vim.tbl_extend("force", c, { noautocmd = true }))
      style_win()
      last_sig = nil
    end
  end

  --- Show `target`; nil empties the pane. Showing the target already on screen is free.
  ---@param target? core.picker.PreviewTarget
  function self.show(target)
    if not alive() then
      return
    end
    if not target then
      return self.clear()
    end
    if target.kind == "file" and target.path then
      local sig = table.concat({ target.path, target.lnum or "", target.col or "", target.end_lnum or "", target.end_col or "" }, "\0")
      if sig == last_sig then
        return
      end
      last_sig = sig
      show_file(target)
    else
      last_sig = nil
      show_text(target)
    end
  end

  function self.clear()
    last_sig = nil
    if alive() then
      show_text({})
    end
  end

  --- Scroll by screen rows (a wrapped line counts once per row it takes); rows > 0 goes down.
  --- Stops where the last line of the file reaches the bottom: no blank space beyond it.
  ---@param rows integer
  function self.scroll(rows)
    if not alive() or rows == 0 then
      return
    end
    vim.api.nvim_win_call(win, function()
      local limit = max_top(vim.api.nvim_buf_line_count(0), vim.api.nvim_win_get_height(0))
      local view = vim.fn.winsaveview()
      if rows > 0 and (view.topline > limit or (view.topline == limit and view.skipcol > 0)) then
        return -- already at the end
      end
      vim.cmd.normal({ args = { math.abs(rows) .. (rows > 0 and "\5" or "\25") }, bang = true }) -- <C-e> / <C-y>
      view = vim.fn.winsaveview()
      if view.topline > limit or (view.topline == limit and view.skipcol > 0) then
        view.topline, view.skipcol = limit, 0
        view.lnum = math.max(view.lnum, limit)
        vim.fn.winrestview(view)
      end
    end)
  end

  --- Half a page; dir > 0 goes down.
  ---@param dir integer
  function self.page(dir)
    if alive() then
      self.scroll(dir * math.max(1, math.floor(vim.api.nvim_win_get_height(win) / 2)))
    end
  end

  --- Scroll sideways; only meaningful without wrapping.
  ---@param cols integer > 0 goes right
  function self.scroll_cols(cols)
    if not alive() or vim.wo[win].wrap or cols == 0 then
      return
    end
    vim.api.nvim_win_call(win, function()
      vim.cmd.normal({ args = { math.abs(cols) .. (cols > 0 and "zl" or "zh") }, bang = true })
    end)
  end

  --- Is the (1-based) screen cell over the preview, border included?
  ---@param row integer
  ---@param col integer
  ---@return boolean
  function self.contains(row, col)
    if not alive() then
      return false
    end
    local edge = win_cfg.border == "none" and 0 or 1
    return row > win_cfg.row
      and row <= win_cfg.row + win_cfg.height + 2 * edge
      and col > win_cfg.col
      and col <= win_cfg.col + win_cfg.width + 2 * edge
  end

  --- One mouse wheel tick, in the amounts of 'mousescroll'.
  ---@param dir "up"|"down"|"left"|"right"
  function self.wheel(dir)
    local ms = vim.o.mousescroll
    local ver = tonumber(ms:match("ver:(%d+)")) or 3
    local hor = tonumber(ms:match("hor:(%d+)")) or 6
    if dir == "up" or dir == "down" then
      self.scroll(dir == "down" and ver or -ver)
    else
      self.scroll_cols(dir == "right" and hor or -hor)
    end
  end

  --- Close the window first, then free the buffers: wiping a buffer that is on screen closes its window.
  function self.dispose()
    if disposed then
      return
    end
    disposed = true
    if alive() then
      pcall(vim.api.nvim_win_close, win, true)
    end
    win = nil
    for _, entry in pairs(files) do
      if vim.api.nvim_buf_is_valid(entry.buf) then
        pcall(vim.api.nvim_buf_delete, entry.buf, { force = true })
      end
    end
    files, lru = {}, {}
    if text_buf and vim.api.nvim_buf_is_valid(text_buf) then
      pcall(vim.api.nvim_buf_delete, text_buf, { force = true })
    end
    text_buf = nil
  end

  return self
end

return M
