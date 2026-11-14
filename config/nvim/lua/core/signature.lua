-- Parameter viewer: LSP signature help in a small floating window, meant to sit
-- next to the completion menu (lua/core/completion).
--
-- It opens when a server's trigger character ("(" or ",") is typed, follows the
-- cursor while the arguments are typed (the active parameter is highlighted) and
-- closes when the cursor leaves the call, on <Esc>, or when the server has
-- nothing to show. It never takes focus and never edits the buffer.
--
--   :Signature [on|off|toggle]      runtime switch for the auto-popup
--                                   (vim.b.signature = false disables it per buffer)
--
--   require("core.signature").trigger()    open it now
--   require("core.signature").toggle()     open it, or close it when it is open
--   require("core.signature").cycle(dir)   next (1) / previous (-1) overload
--   require("core.signature").hide()
--   require("core.signature").visible()
--   require("core.signature").current()    { index, count, label, param } of what is
--                                          shown (`param` is the highlighted text), or nil
--
-- With the completion menu open, the window goes to the other side of the cursor
-- line so the two do not cover each other (best effort: when that side has no
-- room they overlap). Only Insert mode is handled; in a snippet's Select mode
-- the window is closed.
--
-- Mechanism only; no keymaps are defined here (see lua/user/keymaps.lua).
local config = require("core.config")
local util = require("core.util")
local lsp_source = require("core.completion.sources.lsp")

local M = {}

---@type boolean runtime switch for the auto-popup (:Signature); config.signature.enabled is the static one
M.enabled = true

local ns = vim.api.nvim_create_namespace("core_signature")

-- lsp.SignatureHelpTriggerKind
local INVOKED, TRIGGER_CHAR, CONTENT_CHANGE = 1, 2, 3

---@class core.signature.State
---@field help table lsp.SignatureHelp as last answered
---@field index integer shown signature (1-based)
---@field count integer number of signatures in `help`
---@field chosen? integer set once the user cycled; kept while the signature list keeps its size
---@field label string label of the shown signature
---@field param? string text of the highlighted parameter
---@field buf integer
---@field win integer

---@type core.signature.State?
local state
local pending = false -- a request is scheduled or in flight
local gen = 0 -- bumped whenever in-flight work must be dropped
local last -- buffer/line/cursor of the last handled change, to ignore no-op changes
local cancel_request ---@type fun()?
local timer = assert(vim.uv.new_timer())

local function in_insert()
  return vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
end

--- Signature help is for ordinary buffers only (not prompt, terminal, help...).
---@param buf integer
local function eligible(buf)
  return vim.bo[buf].buftype == "" and vim.b[buf].signature ~= false and vim.fn.reg_executing() == ""
end

--- Characters (declared by the attached servers) that open the viewer.
---@param buf integer
---@return table<string, true>
local function trigger_chars(buf)
  local set = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, method = "textDocument/signatureHelp" })) do
    local provider = client.server_capabilities and client.server_capabilities.signatureHelpProvider
    if type(provider) == "table" then
      for _, ch in ipairs(provider.triggerCharacters or {}) do
        set[ch] = true
      end
    end
  end
  return set
end

-- Parameters ---------------------------------------------------------------------

--- The parameter that is being typed, or nil (also when the index is out of range).
---@param help table lsp.SignatureHelp
---@param sig table lsp.SignatureInformation
---@return table?
local function active_param(help, sig)
  local params = sig.parameters
  if type(params) ~= "table" then
    return nil
  end
  local i = sig.activeParameter
  if type(i) ~= "number" then
    i = help.activeParameter
  end
  if type(i) ~= "number" then
    i = 0
  end
  return params[i + 1]
end

--- Byte range of a parameter inside the signature label: 0-based start,
--- exclusive end. A parameter label is either a substring of the signature label
--- or a [start, end] pair of UTF-16 offsets into it.
---@param label string signature label
---@param param table lsp.ParameterInformation
---@return integer? start, integer? stop
function M.param_range(label, param)
  local pl = param.label
  if type(pl) == "table" then
    if type(pl[1]) ~= "number" or type(pl[2]) ~= "number" then
      return nil
    end
    local ok1, s = pcall(vim.str_byteindex, label, "utf-16", pl[1], false)
    local ok2, e = pcall(vim.str_byteindex, label, "utf-16", pl[2], false)
    if ok1 and ok2 and type(s) == "number" and type(e) == "number" and e > s then
      return s, e
    end
  elseif type(pl) == "string" and pl ~= "" then
    local s, e = label:find(pl, 1, true)
    if s then
      return s - 1, e
    end
  end
  return nil
end

-- Window -------------------------------------------------------------------------

--- Size and position for `lines`: above the cursor line, or below it when there
--- is no room above or the completion menu is up there.
---@param lines string[]
---@return table
local function win_config(lines)
  local cfg = config.get().signature
  local b = (cfg.border == nil or cfg.border == "none" or cfg.border == "") and 0 or 2

  local width = 1
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.max(1, math.min(width, cfg.max_width, vim.o.columns - 2 - b))
  local height = 0
  for _, l in ipairs(lines) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / width))
  end
  height = math.min(height, cfg.max_height)

  -- Screen row (1-based) of the cursor line and the rows free on either side.
  local srow = vim.fn.win_screenpos(0)[1] + vim.fn.winline() - 1
  local bottom = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
  local room = { above = srow - 1 - b, below = bottom - srow - b }

  local pum_side
  if vim.fn.pumvisible() == 1 then
    local pos = vim.fn.pum_getpos()
    if pos.row then
      pum_side = (pos.row + 1 < srow) and "above" or "below"
    end
  end
  local side = (pum_side == "above") and "below" or "above"
  local other = (side == "above") and "below" or "above"
  if room[side] < 1 or (pum_side == nil and room[side] < height and room[other] > room[side]) then
    side = other
  end
  height = math.max(1, math.min(height, room[side]))

  return {
    relative = "cursor",
    anchor = "NW",
    row = (side == "above") and -(height + b) or 1,
    col = 0,
    width = width,
    height = height,
  }
end

---@param documentation any lsp string | MarkupContent
---@return string?
local function doc_of(documentation)
  return documentation and lsp_source.doc_text({ documentation = documentation }) or nil
end

--- Draw signature `idx` of `help` (creating the window if needed).
---@param help table lsp.SignatureHelp
---@param idx integer
---@param chosen? integer
local function show(help, idx, chosen)
  local cfg = config.get().signature
  local sig = help.signatures[idx]
  local count = #help.signatures
  local label = (tostring(sig.label):gsub("[\r\n]", " ")) -- same length per char: offsets stay valid

  local param = active_param(help, sig)
  local bs, be
  if param then
    bs, be = M.param_range(label, param)
  end

  local text = label
  if count > 1 then
    text = ("%s  (%d/%d)"):format(label, idx, count)
  end
  local lines = { text }

  if cfg.docs then
    local docs = {}
    for _, d in ipairs({ doc_of(param and param.documentation) or false, doc_of(sig.documentation) or false }) do
      if d then
        docs[#docs + 1] = d
      end
    end
    if #docs > 0 then
      lines[#lines + 1] = ""
      local body = table.concat(docs, "\n\n"):gsub("\r\n?", "\n")
      vim.list_extend(lines, vim.split(body, "\n", { plain = true }))
    end
  end

  if state and not vim.api.nvim_win_is_valid(state.win) then
    state = nil -- closed behind our back
  end

  local wc = win_config(lines)
  local buf, win
  if state then
    buf, win = state.buf, state.win
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_config(win, wc)
  else
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    win = vim.api.nvim_open_win(
      buf,
      false,
      vim.tbl_extend("force", wc, { style = "minimal", border = cfg.border, focusable = false })
    )
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
  end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if bs and be then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, bs, { end_col = be, hl_group = "LspSignatureActiveParameter", strict = false })
  end
  if count > 1 then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, #label, { end_col = #text, hl_group = "Comment", strict = false })
  end

  state = {
    help = help,
    index = idx,
    count = count,
    chosen = chosen,
    label = label,
    param = (bs and be) and label:sub(bs + 1, be) or nil,
    buf = buf,
    win = win,
  }
end

-- Public state ---------------------------------------------------------------------

--- Close the window and drop everything in flight.
function M.hide()
  gen = gen + 1
  timer:stop()
  pending = false
  last = nil
  if cancel_request then
    pcall(cancel_request)
    cancel_request = nil
  end
  if state then
    local s = state
    state = nil
    if vim.api.nvim_win_is_valid(s.win) then
      pcall(vim.api.nvim_win_close, s.win, true)
    end
    if vim.api.nvim_buf_is_valid(s.buf) then
      pcall(vim.api.nvim_buf_delete, s.buf, { force = true })
    end
  end
end

---@return boolean
function M.visible()
  return state ~= nil and vim.api.nvim_win_is_valid(state.win)
end

---@return { index: integer, count: integer, label: string, param?: string }?
function M.current()
  if not M.visible() then
    return nil
  end
  return { index = state.index, count = state.count, label = state.label, param = state.param }
end

--- Show the next (dir = 1) or previous (dir = -1) overload. Kept while typing,
--- as long as the server keeps answering with the same number of signatures.
---@param dir integer
function M.cycle(dir)
  if not M.visible() or state.count < 2 then
    return
  end
  local idx = (state.index - 1 + dir) % state.count + 1
  show(state.help, idx, idx)
end

-- Requests -------------------------------------------------------------------------

local reported = false
---@param err any
local function report_once(err)
  if reported then
    return
  end
  reported = true
  vim.schedule(function()
    util.notify("signature error:\n" .. tostring(err), vim.log.levels.ERROR)
  end)
end

---@param help any lsp.SignatureHelp?
local function apply(help)
  if type(help) ~= "table" or type(help.signatures) ~= "table" or #help.signatures == 0 then
    M.hide()
    return
  end
  local n = #help.signatures
  local idx
  local chosen
  if state and state.chosen and state.count == n then
    idx, chosen = state.chosen, state.chosen
  else
    local a = help.activeSignature
    idx = (type(a) == "number" and a or 0) + 1
  end
  show(help, math.max(1, math.min(idx, n)), chosen)
end

---@param kind integer lsp.SignatureHelpTriggerKind
---@param char? string
local function request(kind, char)
  local buf = vim.api.nvim_get_current_buf()
  if not in_insert() or not eligible(buf) then
    M.hide()
    return
  end
  local win = vim.api.nvim_get_current_win()
  local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/signatureHelp" })
  if #clients == 0 then
    M.hide()
    return
  end

  if cancel_request then
    pcall(cancel_request)
    cancel_request = nil
  end
  gen = gen + 1
  local g = gen
  pending = true

  local results, remaining, cancelled = {}, #clients, false
  local requests = {} ---@type { client: vim.lsp.Client, id: integer }[]

  -- The first client (in attach order) with something to show wins.
  local function done()
    remaining = remaining - 1
    if remaining > 0 or cancelled or g ~= gen then
      return
    end
    pending = false
    cancel_request = nil
    if not in_insert() or vim.api.nvim_get_current_buf() ~= buf then
      return
    end
    for i = 1, #clients do
      local r = results[i]
      if type(r) == "table" and type(r.signatures) == "table" and #r.signatures > 0 then
        local ok, err = pcall(apply, r)
        if not ok then
          M.hide()
          report_once(err)
        end
        return
      end
    end
    M.hide()
  end

  for i, client in ipairs(clients) do
    local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
    params.context = {
      triggerKind = kind,
      triggerCharacter = char,
      isRetrigger = state ~= nil,
      activeSignatureHelp = state and vim.tbl_extend("force", state.help, { activeSignature = state.index - 1 }) or nil,
    }
    local ok, id = client:request("textDocument/signatureHelp", params, function(err, result)
      if cancelled then
        return
      end
      if not err then
        results[i] = result
      end
      done()
    end, buf)
    if ok and id then
      requests[#requests + 1] = { client = client, id = id }
    else
      done()
    end
  end

  if remaining > 0 then
    cancel_request = function()
      cancelled = true
      for _, req in ipairs(requests) do
        pcall(req.client.cancel_request, req.client, req.id)
      end
    end
  end
end

--- Ask the servers after `delay` ms; a newer call supersedes this one.
---@param kind integer
---@param char? string
---@param delay integer
local function schedule(kind, char, delay)
  gen = gen + 1
  local g = gen
  pending = true
  timer:stop()
  timer:start(
    delay,
    0,
    vim.schedule_wrap(function()
      if g ~= gen then
        return
      end
      request(kind, char)
    end)
  )
end

-- Events ---------------------------------------------------------------------------

--- TextChangedI / TextChangedP
local function on_change()
  local buf = vim.api.nvim_get_current_buf()
  if not in_insert() or not eligible(buf) then
    return
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  -- <C-n>/<C-p> in the completion menu "re-insert" the identical word.
  if last and last.buf == buf and last.row == pos[1] and last.col == pos[2] and last.line == line then
    return
  end
  last = { buf = buf, row = pos[1], col = pos[2], line = line }

  local cfg = config.get().signature
  local ch = line:sub(pos[2], pos[2]) -- the character before the cursor (trigger characters are ASCII)
  local is_trigger = ch ~= "" and trigger_chars(buf)[ch] == true
  if is_trigger and (state or pending or (M.enabled and cfg.auto)) then
    schedule(TRIGGER_CHAR, ch, cfg.delay)
  elseif state or pending then
    schedule(CONTENT_CHANGE, nil, cfg.delay) -- the active parameter may have changed
  end
end

--- CursorMovedI: the cursor moved without an edit (arrows, mouse).
local function on_cursor()
  if not (state or pending) then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if not in_insert() then
    return
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  if last and last.buf == buf and last.line ~= line then
    return -- an edit: on_change handles it
  end
  last = { buf = buf, row = pos[1], col = pos[2], line = line }
  schedule(CONTENT_CHANGE, nil, config.get().signature.delay)
end

--- The completion menu came or changed: keep the two windows apart.
local function reposition()
  if not M.visible() then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  pcall(vim.api.nvim_win_set_config, state.win, win_config(lines))
end

--- Open now, even when the auto-popup is off.
function M.trigger()
  if not in_insert() or not eligible(vim.api.nvim_get_current_buf()) then
    return
  end
  schedule(INVOKED, nil, 0)
end

--- Open now, or close if it is open.
function M.toggle()
  if M.visible() then
    M.hide()
  else
    M.trigger()
  end
end

--- Wrap an autocmd handler: an error closes the window and is reported once,
--- instead of repeating on every keystroke.
---@param fn fun(ev: table)
local function guarded(fn)
  return function(ev)
    local ok, err = pcall(fn, ev)
    if not ok then
      pcall(M.hide)
      report_once(err)
    end
  end
end

function M.setup()
  if not config.get().signature.enabled then
    return
  end
  local group = util.augroup("signature")
  local function on(events, fn)
    vim.api.nvim_create_autocmd(events, { group = group, callback = guarded(fn) })
  end

  on({ "TextChangedI", "TextChangedP" }, on_change)
  on("CursorMovedI", on_cursor)
  on({ "InsertLeave", "BufLeave" }, M.hide)
  on("ModeChanged", function(ev)
    local new = vim.v.event.new_mode or ""
    if state and new:sub(1, 1) ~= "i" then
      M.hide()
    end
  end)
  -- Textlock applies inside this event, so the move happens right after it.
  on("CompleteChanged", function()
    vim.schedule(function()
      pcall(reposition)
    end)
  end)

  vim.api.nvim_create_user_command("Signature", function(o)
    local arg = o.args
    if arg == "on" then
      M.enabled = true
    elseif arg == "off" then
      M.enabled = false
    elseif arg == "" or arg == "toggle" then
      M.enabled = not M.enabled
    else
      util.notify("Signature: expected on, off or toggle", vim.log.levels.ERROR)
      return
    end
    if not M.enabled then
      M.hide()
    end
    util.notify("Parameter viewer auto-popup " .. (M.enabled and "on" or "off"))
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "toggle" }
    end,
    desc = "Toggle the parameter viewer's auto-popup (on|off|toggle)",
  })
end

return M
