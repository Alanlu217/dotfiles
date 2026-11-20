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

---@class core.picker.PreviewSearch
---@field pattern string
---@field fixed boolean  plain text (true) or regex

---@class core.picker.PreviewTarget
---@field kind "file"|"buf"|"text"
---@field path? string       file: absolute path (shown from its buffer instead when it is loaded)
---@field bufnr? integer     buf: a loaded buffer, shown as it is now (unsaved edits included)
---@field lines? string[]    text: what to show
---@field title? string      text: border title (files and buffers use their name)
---@field note? string       file/buf: short text added to the border title
---@field lnum? integer      file/buf: 1-based line to centre and mark
---@field col? integer       file/buf: 1-based byte column of the match on `lnum`
---@field end_lnum? integer  file/buf: last marked line (default `lnum`)
---@field end_col? integer   file/buf: 1-based byte column after the match (on `end_lnum`); with `col` marks a range
---@field search? core.picker.PreviewSearch file/buf: find the length of the match at `lnum`/`col` here (no `end_col` needed)
---@field match_hl? string   file/buf: highlight group of the matched range (default PickerPreviewMatch)

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

--- The loaded, ordinary buffer editing `path`, if any: it holds the truth, unsaved edits included.
---@param path string
---@return integer?
function M.loaded_buf(path)
  path = vim.fs.normalize(path)
  for _, nr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(nr) and vim.bo[nr].buftype == "" and vim.api.nvim_buf_get_name(nr) == path then
      return nr
    end
  end
end

local regex_cache = {} ---@type table<string, vim.regex|false>

--- 1-based byte column after the match that starts at `col` of line `lnum`, or nil when
--- it can't be told (the line changed, a regex flavour we can't translate, ...).
---@param buf integer
---@param lnum integer
---@param col integer
---@param search core.picker.PreviewSearch
---@return integer?
local function match_end(buf, lnum, col, search)
  local pattern = search.pattern
  if pattern == "" then
    return nil
  end
  local icase = not pattern:find("%u") -- smartcase, like the search itself
  if search.fixed then
    local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
    local found = line:sub(col, col + #pattern - 1)
    if #found == #pattern and (found == pattern or (icase and found:lower() == pattern:lower())) then
      return col + #pattern
    end
    return nil
  end
  -- The native search speaks a small RE2-like regex, which is close to Vim's very magic.
  local key = (icase and "i" or "c") .. pattern
  local re = regex_cache[key]
  if re == nil then
    local ok, compiled = pcall(vim.regex, "\\v" .. (icase and "\\c" or "\\C") .. pattern)
    re = ok and compiled or false
    regex_cache[key] = re
  end
  if not re then
    return nil
  end
  local ok, s, e = pcall(re.match_line, re, buf, lnum - 1, col - 1)
  if ok and s == 0 and e and e > s then
    return col + e -- 1-based column after the match: it spans col .. col + e - 1
  end
  return nil
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
---@param ft? string
---@param bytes integer
---@param cfg table
local function start_highlight(buf, ft, bytes, cfg)
  if not ft or ft == "" or bytes > cfg.highlight_max_bytes then
    return
  end
  local ts = config.get().treesitter
  if ts.enabled and not vim.tbl_contains(ts.disable or {}, ft) then
    -- 'filetype' stays unset on purpose: setting it would run ftplugins and user
    -- FileType autocmds for a buffer nobody edits. Treesitter only needs the language.
    local lang = vim.treesitter.language.get_lang(ft)
    if lang then
      local has_parser, has_query = require("core.treesitter").available(lang)
      if has_parser and has_query and pcall(vim.treesitter.start, buf, lang) then
        return
      end
    end
  end
  -- No usable parser: classic regex syntax, like the editor does. Setting only 'syntax'
  -- (not 'filetype') loads syntax/<ft>.vim without running ftplugins or FileType autocmds.
  if vim.g.syntax_on ~= nil or vim.fn.exists("g:syntax_on") == 1 then
    pcall(vim.api.nvim_buf_call, buf, function()
      vim.bo[buf].syntax = ft
    end)
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

    if t.lnum > count then
      -- Beyond what was loaded (a truncated big file): say nothing rather than mark the wrong line.
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview({ topline = 1, lnum = 1, col = 0, leftcol = 0, skipcol = 0, curswant = 0 })
      end)
      return
    end
    local first = math.max(t.lnum, 1)
    local wanted = math.max(t.end_lnum or first, first)
    local last = math.min(wanted, count, first + MAX_MARKED_LINES - 1)
    for l = first, last do
      vim.api.nvim_buf_set_extmark(buf, NS, l - 1, 0, { line_hl_group = "PickerPreviewLine", priority = 100 })
    end
    local end_col = t.end_col
    if t.col and not end_col and t.search then
      end_col = match_end(buf, first, t.col, t.search)
    end
    -- A range cut short by the caps would end at the wrong place: mark only the lines then.
    if t.col and end_col and last == wanted and (last > first or end_col > t.col) then
      vim.api.nvim_buf_set_extmark(buf, NS, first - 1, t.col - 1, {
        end_row = last - 1,
        end_col = end_col - 1,
        hl_group = t.match_hl or "PickerPreviewMatch",
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
      if fresh or (not vim.b[buf].ts_highlight and vim.bo[buf].syntax == "") then
        local ok, ft = pcall(vim.filetype.match, { filename = path, contents = vim.list_slice(data.lines, 1, 100) })
        start_highlight(buf, ok and ft or nil, data.bytes, cfg)
      end
      entry = { buf = buf, key = key, truncated = data.truncated }
      files[path] = entry
      truncated = data.truncated
    end

    touch(path)
    show_buf(entry.buf)
    mark_and_place(entry.buf, t)
    local suffix = (t.note and ("  " .. t.note) or "") .. (truncated and "  [truncated]" or (st.size == 0 and "  [empty]" or ""))
    set_title(title, suffix ~= "" and suffix or nil)
    evict() -- after the swap: the buffer that was on screen may now go
  end

  --- A loaded buffer, copied as it is now. The copy lives in a scratch buffer like a file's:
  --- the real buffer never enters the float, so no autocmd or window option leaks either way.
  ---@param t core.picker.PreviewTarget
  local function show_buffer(t)
    local nr = t.bufnr
    if not (nr and vim.api.nvim_buf_is_valid(nr)) then
      return notice("buffer", "buffer no longer exists")
    end
    local name = vim.api.nvim_buf_get_name(nr)
    if not vim.api.nvim_buf_is_loaded(nr) then
      if name ~= "" then
        return show_file(vim.tbl_extend("force", t, { kind = "file", path = name }))
      end
      return notice("[No Name]", "buffer is not loaded")
    end

    local title = name ~= "" and rel(name) or "[No Name]"
    local ckey = "buf:" .. nr
    local key = tostring(vim.api.nvim_buf_get_changedtick(nr))
    local entry = files[ckey]
    local truncated
    if entry and entry.key == key and vim.api.nvim_buf_is_valid(entry.buf) then
      truncated = entry.truncated
    else
      local count = vim.api.nvim_buf_line_count(nr)
      local bytes = math.max(vim.api.nvim_buf_get_offset(nr, count), 0)
      local upto = count
      truncated = bytes > cfg.max_filesize
      if truncated then
        upto = math.max(1, math.floor(count * cfg.max_filesize / bytes))
      end
      local lines = vim.api.nvim_buf_get_lines(nr, 0, upto, false)
      for i, line in ipairs(lines) do
        if line:find("\n", 1, true) then -- a NUL in the buffer; set_lines refuses newlines
          lines[i] = line:gsub("\n", "^@")
        end
      end
      if #lines == 0 then
        lines = { "" }
      end
      local fresh = not (entry and vim.api.nvim_buf_is_valid(entry.buf))
      local buf = fresh and new_buf() or entry.buf
      set_lines(buf, lines)
      if fresh or (not vim.b[buf].ts_highlight and vim.bo[buf].syntax == "") then
        start_highlight(buf, vim.bo[nr].filetype, bytes, cfg)
      end
      entry = { buf = buf, key = key, truncated = truncated }
      files[ckey] = entry
    end

    touch(ckey)
    show_buf(entry.buf)
    mark_and_place(entry.buf, t)
    local suffix = (t.note and ("  " .. t.note) or "")
      .. (vim.bo[nr].modified and "  [+]" or "")
      .. (truncated and "  [truncated]" or "")
    set_title(title, suffix ~= "" and suffix or nil)
    evict()
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
      -- A file that is open in an editor buffer is shown from there: unsaved edits count.
      local nr = M.loaded_buf(target.path)
      if nr then
        target = vim.tbl_extend("force", target, { kind = "buf", bufnr = nr })
      end
    end
    if (target.kind == "file" and target.path) or (target.kind == "buf" and target.bufnr) then
      local sig = table.concat({
        target.kind,
        target.path or target.bufnr,
        target.lnum or "",
        target.col or "",
        target.end_lnum or "",
        target.end_col or "",
        target.search and target.search.pattern or "",
        target.search and tostring(target.search.fixed) or "",
        target.note or "",
        target.match_hl or "",
      }, "\0")
      if sig == last_sig then
        return
      end
      last_sig = sig
      if target.kind == "buf" then
        show_buffer(target)
      else
        show_file(target)
      end
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

  --- Scroll by buffer lines; lines > 0 goes down. Works on an absolute topline instead of
  --- nudging with <C-e>/<C-y>, so there is never an overshoot to snap back from: the view
  --- stops where the last line of the file reaches the bottom.
  ---@param lines integer
  function self.scroll(lines)
    if not alive() or lines == 0 then
      return
    end
    vim.api.nvim_win_call(win, function()
      local limit = max_top(vim.api.nvim_buf_line_count(0), vim.api.nvim_win_get_height(0))
      local view = vim.fn.winsaveview()
      local top = math.min(math.max(view.topline + lines, 1), math.max(limit, 1))
      if top == view.topline and view.skipcol == 0 then
        return
      end
      view.topline, view.lnum, view.col, view.curswant, view.skipcol = top, top, 0, 0, 0
      vim.fn.winrestview(view)
    end)
  end

  --- Half a window of screen rows (wrapped lines count for every row they take); dir > 0 goes down.
  ---@param dir integer
  function self.page(dir)
    if not alive() then
      return
    end
    local half = math.max(1, math.floor(vim.api.nvim_win_get_height(win) / 2))
    local count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
    local top = vim.fn.getwininfo(win)[1].topline
    local n, used = 0, 0
    if dir > 0 then
      while top + n <= count and used < half do
        used = used + line_rows(top + n)
        n = n + 1
      end
    else
      while top - n - 1 >= 1 and used < half do
        used = used + line_rows(top - n - 1)
        n = n + 1
      end
    end
    self.scroll(dir * math.max(1, n))
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
