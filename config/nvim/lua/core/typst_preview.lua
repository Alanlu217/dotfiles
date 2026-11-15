-- Typst preview through tinymist's LSP commands: no plugin, no websocket client.
--
--   :TypstPreview         start the preview for this buffer and open it in the
--                         browser (or just reopen it when one is already running)
--   :TypstPreviewToggle   start / stop
--   :TypstPreviewStop
--   :TypstPreviewSync     scroll the preview to the cursor, once
--   :TypstPreviewFollow   toggle scrolling the preview as the cursor moves
--   :TypstPreviewDebug    toggle printing what the preview sends back (jumps)
--   :TypstPreviewTheme [auto|light|dark]
--                         set the preview colours; no argument toggles light <-> dark.
--                         A running preview is restarted (tinymist fixes the colours
--                         when the preview starts).
--
-- Neovim -> preview: the `tinymist.scrollPreview` command, debounced on cursor moves.
-- Preview -> Neovim: tinymist sends `tinymist/preview/scrollSource` when you click
-- in the preview; the handler below moves the cursor to that source position.
-- Keys live in lua/user/typst.lua.
--
-- The previewed file is the buffer's own file. For a project whose root is another
-- file, set b:typst_main (or g:typst_main) to that file before starting.
local config = require("core.config")
local util = require("core.util")

local M = {}

---@class core.typst_preview.State
---@field id string tinymist task id
---@field client_id integer
---@field url string
---@field file string

local state ---@type core.typst_preview.State?
local starting = false
local following ---@type boolean?
local debugging = false
local timer ---@type uv.uv_timer_t?
local ignore_until = 0 -- cursor moves before this time (ms, vim.uv.now) are our own jumps
local last_sent ---@type string?
local theme ---@type string? "auto" | "light" | "dark"; nil = config value

---@return table
local function cfg()
  return config.get().typst_preview
end

---@param msg string
---@param level? integer
local function notify(msg, level)
  util.notify("typst preview: " .. msg, level)
end

---@return boolean
local function is_following()
  if following == nil then
    following = cfg().follow
  end
  return following
end

--- The client running the preview, or nil (and the state is dropped) when it is gone.
---@return vim.lsp.Client?
local function live_client()
  if not state then
    return nil
  end
  local client = vim.lsp.get_client_by_id(state.client_id)
  if not client or client:is_stopped() then
    state = nil
    return nil
  end
  return client
end

---@param client vim.lsp.Client
---@param command string
---@param args any[]
---@param cb? fun(err: any, result: any)
local function exec(client, command, args, cb)
  client:request("workspace/executeCommand", { command = command, arguments = args }, function(err, result)
    if err and debugging then
      notify(("%s failed: %s"):format(command, vim.inspect(err)), vim.log.levels.WARN)
    end
    if cb then
      cb(err, result)
    end
  end)
end

---@param url string
local function open_url(url)
  local browser = cfg().browser
  if type(browser) == "table" and #browser > 0 then
    local cmd = vim.list_extend(vim.deepcopy(browser), { url })
    local ok, err = pcall(vim.system, cmd, { detach = true })
    if not ok then
      notify(("could not run %s: %s"):format(browser[1], err), vim.log.levels.ERROR)
    end
    return
  end
  local _, err = vim.ui.open(url)
  if err then
    notify(("could not open a browser (%s). The preview is at %s"):format(err, url), vim.log.levels.WARN)
  end
end

---@return string
local function current_theme()
  return theme or cfg().theme or "auto"
end

--- Preview arguments with the colour mode applied on top of `cfg().args`.
---@return string[]
local function preview_args()
  local args = {}
  local skip = false
  for _, a in ipairs(cfg().args) do
    if skip then
      skip = false
    elseif a == "--invert-colors" then
      skip = true
    elseif not a:match("^%-%-invert%-colors=") then
      args[#args + 1] = a
    end
  end
  local mode = ({ auto = "auto", light = "never", dark = "always" })[current_theme()] or "auto"
  args[#args + 1] = "--invert-colors=" .. mode
  return args
end

---@param buf integer
---@return string
local function main_file(buf)
  local path = vim.b[buf].typst_main or vim.g.typst_main or vim.api.nvim_buf_get_name(buf)
  return vim.fn.fnamemodify(path, ":p")
end

-- Neovim -> preview ---------------------------------------------------------

--- Scroll the preview to the cursor.
---@param force? boolean send even when the position has not changed
function M.sync(force)
  local client = live_client()
  if not client or not state then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "typst" then
    return
  end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then
    return
  end

  local pos = vim.lsp.util.make_position_params(0, client.offset_encoding).position
  local key = ("%s:%d:%d"):format(file, pos.line, pos.character)
  if key == last_sent and not force then
    return
  end
  last_sent = key

  exec(client, "tinymist.scrollPreview", {
    state.id,
    { event = "panelScrollTo", filepath = file, line = pos.line, character = pos.character },
  })
end

local function schedule_sync()
  if not state or not is_following() or vim.uv.now() < ignore_until then
    return
  end
  timer = timer or vim.uv.new_timer()
  timer:stop()
  timer:start(
    cfg().debounce,
    0,
    vim.schedule_wrap(function()
      M.sync()
    end)
  )
end

-- Preview -> Neovim ---------------------------------------------------------

---@param p any `{ line, character }` or `{ line, character }` as a list
---@return integer? line, integer? col (0-based)
local function position_of(p)
  if type(p) ~= "table" then
    return nil
  end
  local line = p.line or p[1]
  local col = p.character or p.column or p.col or p[2]
  if type(line) ~= "number" then
    return nil
  end
  return line, type(col) == "number" and col or 0
end

--- UTF-16 column (what LSP speaks) to a byte column of `text`.
---@param text string
---@param col integer
---@return integer
local function byte_col(text, col)
  local ok, res = pcall(vim.str_byteindex, text, "utf-16", col)
  if ok and type(res) == "number" then
    return res
  end
  return math.min(col, #text)
end

---@param path string
---@param line integer 0-based
---@param col integer 0-based, UTF-16
local function jump(path, line, col)
  if path:match("^file://") then
    path = vim.uri_to_fname(path)
  end
  path = vim.fn.fnamemodify(path, ":p")

  local win
  local nr = vim.fn.bufnr(path)
  if nr ~= -1 then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(w) == nr and vim.api.nvim_win_get_config(w).relative == "" then
        win = w
        break
      end
    end
  end
  if win then
    vim.api.nvim_set_current_win(win)
  else
    local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(path))
    if not ok then
      notify(("cannot open %s:\n%s"):format(path, err), vim.log.levels.ERROR)
      return
    end
  end

  local buf = vim.api.nvim_get_current_buf()
  local last = math.max(vim.api.nvim_buf_line_count(buf) - 1, 0)
  line = math.min(math.max(line, 0), last)
  local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""

  ignore_until = vim.uv.now() + 250
  vim.api.nvim_win_set_cursor(0, { line + 1, byte_col(text, col) })
  if cfg().jump_center then
    vim.cmd("normal! zz")
  end
end

---@param result any tinymist/preview/scrollSource params
local function on_scroll_source(_, result)
  vim.schedule(function()
    if debugging then
      notify("scrollSource: " .. vim.inspect(result))
    end
    if type(result) ~= "table" then
      return
    end
    local path = result.filepath or result.file or result.uri
    local line, col = position_of(result.start)
    if type(path) ~= "string" or not line then
      if not debugging then
        notify("unrecognised jump from the preview (:TypstPreviewDebug shows it)", vim.log.levels.WARN)
      end
      return
    end
    jump(path, line, col or 0)
  end)
end

local function on_dispose(_, result)
  vim.schedule(function()
    if state and type(result) == "table" and result.taskId == state.id then
      state = nil
      last_sent = nil
    end
  end)
end

-- Control -------------------------------------------------------------------

--- Start the preview for the current buffer and open it, or reopen a running one.
function M.open()
  if live_client() and state then
    open_url(state.url)
    return
  end
  if starting then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "typst" then
    notify("not a typst buffer", vim.log.levels.WARN)
    return
  end
  local client = vim.lsp.get_clients({ bufnr = buf, name = "tinymist" })[1]
  if not client then
    notify("tinymist is not attached to this buffer (:LspInfo)", vim.log.levels.WARN)
    return
  end

  local file = main_file(buf)
  local id = ("nvim-%d-%d"):format(vim.uv.os_getpid(), vim.uv.hrtime() % 1000000)
  local args = { "--task-id", id, "--data-plane-host=127.0.0.1:0" }
  vim.list_extend(args, preview_args())
  args[#args + 1] = file

  starting = true
  exec(client, "tinymist.doStartPreview", { args }, function(err, res)
    vim.schedule(function()
      starting = false
      if err or type(res) ~= "table" or not res.staticServerAddr then
        notify("could not start the preview:\n" .. vim.inspect(err or res), vim.log.levels.ERROR)
        return
      end
      state = { id = id, client_id = client.id, url = "http://" .. res.staticServerAddr, file = file }
      last_sent = nil
      open_url(state.url)
      -- The page needs a moment to connect before it can be scrolled.
      vim.defer_fn(function()
        M.sync(true)
      end, 1500)
    end)
  end)
end

function M.stop()
  local client = live_client()
  if not client or not state then
    notify("no preview running")
    return
  end
  local id = state.id
  state, last_sent = nil, nil
  exec(client, "tinymist.doKillPreview", { id })
  notify("stopped")
end

function M.toggle()
  if live_client() then
    M.stop()
  else
    M.open()
  end
end

--- Set the preview colours and restart a running preview so they take effect.
---@param value? string "auto" | "light" | "dark"; nil toggles light <-> dark
function M.set_theme(value)
  if value == nil or value == "" then
    value = current_theme() == "dark" and "light" or "dark"
  end
  if value ~= "auto" and value ~= "light" and value ~= "dark" then
    notify("theme must be auto, light or dark", vim.log.levels.WARN)
    return
  end
  theme = value
  notify("theme " .. value)

  local client = live_client()
  if not client or not state then
    return
  end
  local id = state.id
  state, last_sent = nil, nil
  exec(client, "tinymist.doKillPreview", { id }, function()
    vim.schedule(M.open)
  end)
end

function M.toggle_theme()
  M.set_theme()
end

---@param value? boolean nil toggles
function M.follow(value)
  if value == nil then
    value = not is_following()
  end
  following = value
  notify("follow cursor " .. (value and "on" or "off"))
  if value then
    M.sync(true)
  end
end

function M.toggle_debug()
  debugging = not debugging
  notify("debug " .. (debugging and "on" or "off"))
end

---@return core.typst_preview.State?
function M.status()
  live_client()
  return state
end

function M.setup()
  vim.lsp.handlers["tinymist/preview/scrollSource"] = on_scroll_source
  vim.lsp.handlers["tinymist/preview/dispose"] = on_dispose

  local group = util.augroup("typst_preview")
  local events = { "CursorMoved" }
  if cfg().follow_insert then
    events[#events + 1] = "CursorMovedI"
  end
  vim.api.nvim_create_autocmd(events, {
    group = group,
    callback = function(ev)
      if state and vim.bo[ev.buf].filetype == "typst" then
        schedule_sync()
      end
    end,
  })

  vim.api.nvim_create_user_command("TypstPreview", M.open, { desc = "Start the typst preview and open it (or reopen it)" })
  vim.api.nvim_create_user_command("TypstPreviewToggle", M.toggle, { desc = "Start / stop the typst preview" })
  vim.api.nvim_create_user_command("TypstPreviewStop", M.stop, { desc = "Stop the typst preview" })
  vim.api.nvim_create_user_command("TypstPreviewSync", function()
    M.sync(true)
  end, { desc = "Scroll the typst preview to the cursor" })
  vim.api.nvim_create_user_command("TypstPreviewFollow", function()
    M.follow()
  end, { desc = "Toggle scrolling the preview with the cursor" })
  vim.api.nvim_create_user_command("TypstPreviewTheme", function(opts)
    M.set_theme(opts.args)
  end, {
    nargs = "?",
    complete = function()
      return { "auto", "light", "dark" }
    end,
    desc = "Typst preview colours: auto | light | dark (no argument toggles)",
  })
  vim.api.nvim_create_user_command("TypstPreviewDebug", M.toggle_debug, { desc = "Toggle printing preview jumps" })
end

return M
