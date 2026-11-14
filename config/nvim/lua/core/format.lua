-- Formatting: external formatters (stdin -> stdout) with an LSP fallback,
-- format-on-save, and toggles. A small conform.nvim-alike.
--
-- Which formatter runs for which filetype lives in lua/user/format.lua:
--
--   local format = require("core.format")
--   format.setup_formatters({
--     stylua = { cmd = "stylua", args = { "--stdin-filepath", "$FILENAME", "-" } },
--   })
--   format.by_ft({
--     lua = { "stylua" },                                      -- run in order, each feeds the next
--     js  = { "prettierd", "prettier", stop_after_first = true }, -- first one that is installed
--   })
--
-- A formatter is { cmd, args?, cwd?, env?, timeout_ms?, exit_codes?, condition? }.
-- It must read the buffer on stdin and write the result to stdout. `args` is a
-- list (or a function(ctx) returning one) in which $FILENAME, $DIRNAME and $EXT
-- are replaced; `cwd` defaults to the file's directory; `condition(ctx)` may veto
-- the formatter for a buffer. ctx = { buf, filename, dirname, ext }. A formatter
-- whose `cmd` is not executable is skipped silently (see :FormatInfo).
--
-- The result is applied as a minimal line diff, so cursor, marks, folds and
-- extmarks stay where they are, and it is a single undo step. If a formatter
-- fails or times out the buffer is left alone and the error is shown once.
--
-- LSP: config.format.lsp_fallback is "fallback" (default: LSP formats only when
-- no formatter is available for the filetype), "always" (LSP runs after the
-- formatters) or "never".
--
-- Format on save is synchronous (an async result would arrive after the write).
-- It is on by default; vim.g.format_on_save switches it globally, and
-- vim.b.format_on_save overrides that for one buffer.
--
--   :Format                      format the buffer (async); with a range, via LSP
--   :FormatToggle[!] [on|off|toggle|reset]   format on save; ! = this buffer only
--   :FormatInfo                  formatters for this buffer and the toggle state
--
--   require("core.format").format({ buf?, async?, timeout_ms?, quiet?, callback? })
--   require("core.format").format_range(first, last)   LSP range formatting
--   require("core.format").enabled(buf?) / .toggle(buf?) / .set(value, buf?)
--
-- Mechanism only; no keymaps are defined here (see lua/user/keymaps.lua).
local config = require("core.config")
local util = require("core.util")

local M = {}

---@class core.format.Formatter
---@field cmd string
---@field args? string[]|fun(ctx: core.format.Ctx): string[]
---@field cwd? string|fun(ctx: core.format.Ctx): string?
---@field env? table<string, string>
---@field timeout_ms? integer
---@field exit_codes? integer[] exit codes that count as success (default { 0 })
---@field condition? fun(ctx: core.format.Ctx): boolean

---@class core.format.Ctx
---@field buf integer
---@field filename string
---@field dirname string
---@field ext string

---@type table<string, core.format.Formatter>
M.formatters = {}
---@type table<string, table> filetype -> { "name", ..., stop_after_first? = boolean }
M.by_filetype = {}

--- Register formatter definitions (later calls override earlier ones by name).
---@param defs table<string, core.format.Formatter>
function M.setup_formatters(defs)
  M.formatters = vim.tbl_extend("force", M.formatters, defs)
end

--- Choose formatters per filetype.
---@param map table<string, table>
function M.by_ft(map)
  M.by_filetype = vim.tbl_extend("force", M.by_filetype, map)
end

-- Resolution ------------------------------------------------------------------------

---@param buf integer
---@return core.format.Ctx
local function make_ctx(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return {
    buf = buf,
    filename = name,
    dirname = name ~= "" and (vim.fs.dirname(name) or "") or "",
    ext = name:match("%.([^./\\]+)$") or "",
  }
end

--- The by_ft entry for a filetype; "cpp.doxygen" tries "cpp.doxygen", then each part.
---@param ft string
---@return table?
local function entry_for(ft)
  if M.by_filetype[ft] then
    return M.by_filetype[ft]
  end
  for _, part in ipairs(vim.split(ft, ".", { plain = true })) do
    if M.by_filetype[part] then
      return M.by_filetype[part]
    end
  end
  return nil
end

---@param spec core.format.Formatter
---@param ctx core.format.Ctx
---@return boolean ok, string? why
local function available(spec, ctx)
  if type(spec.cmd) ~= "string" or vim.fn.executable(spec.cmd) == 0 then
    return false, ("'%s' not found in PATH"):format(tostring(spec.cmd))
  end
  if spec.condition then
    local ok, res = pcall(spec.condition, ctx)
    if not ok or not res then
      return false, "condition not met"
    end
  end
  return true
end

--- The formatters that will run for `buf`, in order.
---@param buf integer
---@return { name: string, spec: core.format.Formatter }[] list, core.format.Ctx ctx
function M.resolve(buf)
  local ctx = make_ctx(buf)
  local list = {}
  local entry = entry_for(vim.bo[buf].filetype)
  for _, name in ipairs(entry or {}) do
    local spec = M.formatters[name]
    if spec and available(spec, ctx) then
      list[#list + 1] = { name = name, spec = spec }
      if entry.stop_after_first then
        break
      end
    end
  end
  return list, ctx
end

---@return "fallback"|"always"|"never"
local function lsp_mode()
  local v = config.get().format.lsp_fallback
  if v == true or v == "always" then
    return "always"
  elseif v == false or v == "never" then
    return "never"
  end
  return "fallback"
end

---@param buf integer
local function has_lsp(buf)
  return #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/formatting" }) > 0
end

-- Running a formatter ---------------------------------------------------------------

local VARS = { FILENAME = "filename", DIRNAME = "dirname", EXT = "ext" }

---@param arg string
---@param ctx core.format.Ctx
local function expand(arg, ctx)
  return (arg:gsub("%$(%u+)", function(key)
    local field = VARS[key]
    return field and ctx[field] or nil -- unknown $NAMEs stay as written
  end))
end

---@param spec core.format.Formatter
---@param ctx core.format.Ctx
---@param input string
---@param timeout integer
---@return string[] cmd, table opts
local function prepare(spec, ctx, input, timeout)
  local args = spec.args or {}
  if type(args) == "function" then
    args = args(ctx) or {}
  end
  local cmd = { spec.cmd }
  for _, a in ipairs(args) do
    cmd[#cmd + 1] = expand(a, ctx)
  end
  local cwd = spec.cwd
  if type(cwd) == "function" then
    cwd = cwd(ctx)
  end
  cwd = cwd or ctx.dirname
  if cwd == nil or cwd == "" or vim.fn.isdirectory(cwd) == 0 then
    cwd = nil
  end
  return cmd, { stdin = input, text = true, cwd = cwd, env = spec.env, timeout = spec.timeout_ms or timeout }
end

--- Turn a finished process into the formatted text, or nil plus a reason.
---@param spec core.format.Formatter
---@param res vim.SystemCompleted
---@return string? out, string? err
local function outcome(spec, res)
  if res.code == 124 and (res.signal or 0) ~= 0 then
    return nil, "timed out"
  end
  if vim.tbl_contains(spec.exit_codes or { 0 }, res.code) then
    return res.stdout or ""
  end
  local msg = vim.trim(res.stderr or "")
  return nil, msg ~= "" and msg or ("exit code " .. tostring(res.code))
end

---@return string? out, string? err
local function exec_sync(spec, ctx, input, timeout)
  local cmd, opts = prepare(spec, ctx, input, timeout)
  local ok, obj = pcall(vim.system, cmd, opts)
  if not ok then
    return nil, tostring(obj)
  end
  return outcome(spec, obj:wait())
end

---@param cb fun(out: string?, err: string?)
local function exec_async(spec, ctx, input, timeout, cb)
  local cmd, opts = prepare(spec, ctx, input, timeout)
  local ok, err = pcall(vim.system, cmd, opts, function(res)
    local out, why = outcome(spec, res)
    vim.schedule(function()
      cb(out, why)
    end)
  end)
  if not ok then
    cb(nil, tostring(err))
  end
end

-- Applying the result ----------------------------------------------------------------

local diff = (vim.text and vim.text.diff) or vim.diff

--- Replace the buffer text by `out`, touching only the lines that differ.
---@param buf integer
---@param out string
---@return boolean ok, string? err
local function apply(buf, out)
  local old = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if out:match("^%s*$") and table.concat(old, "\n"):match("%S") then
    return false, "formatter produced no output"
  end
  local new = vim.split((out:gsub("\n$", "")), "\n", { plain = true })

  local a = table.concat(old, "\n") .. "\n"
  local b = table.concat(new, "\n") .. "\n"
  if a == b then
    return true
  end
  local hunks = diff(a, b, { result_type = "indices", algorithm = "histogram" })
  for i = #hunks, 1, -1 do -- bottom to top: earlier line numbers stay valid
    local start_a, count_a, start_b, count_b = unpack(hunks[i])
    local first = count_a == 0 and start_a or start_a - 1 -- count 0: "after line start"
    vim.api.nvim_buf_set_lines(buf, first, first + count_a, false, vim.list_slice(new, start_b, start_b + count_b - 1))
  end
  return true
end

local last_error = {} ---@type table<integer, string>

---@param buf integer
---@param msg string
local function report(buf, msg)
  if last_error[buf] == msg then
    return -- the same failure on every save would only be noise
  end
  last_error[buf] = msg
  util.notify("format: " .. msg, vim.log.levels.ERROR)
end

-- Public API ------------------------------------------------------------------------

---@class core.format.Opts
---@field buf? integer
---@field async? boolean default false
---@field timeout_ms? integer
---@field quiet? boolean no notice when there is nothing to format with
---@field callback? fun(ok: boolean)

--- Format a buffer. Returns whether anything was (or, async, is being) run.
---@param opts? core.format.Opts
---@return boolean
function M.format(opts)
  opts = opts or {}
  local cfg = config.get().format
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modifiable then
    return false
  end
  local timeout = opts.timeout_ms or cfg.timeout_ms
  local mode = lsp_mode()

  local function lsp_format()
    if not has_lsp(buf) then
      return false
    end
    vim.lsp.buf.format({ bufnr = buf, async = opts.async or false, timeout_ms = timeout })
    return true
  end

  local list, ctx = M.resolve(buf)
  if #list == 0 then
    local ran = mode ~= "never" and lsp_format()
    if not ran and not opts.quiet then
      util.notify(("format: no formatter available for filetype '%s'"):format(vim.bo[buf].filetype))
    end
    if opts.callback then
      opts.callback(ran)
    end
    return ran
  end

  local function finish(ok)
    if ok then
      last_error[buf] = nil
      if mode == "always" and vim.api.nvim_buf_is_valid(buf) then
        lsp_format()
      end
    end
    if opts.callback then
      opts.callback(ok)
    end
  end

  local input = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"

  if not opts.async then
    local text = input
    for _, f in ipairs(list) do
      local out, err = exec_sync(f.spec, ctx, text, timeout)
      if not out then
        report(buf, ("%s: %s"):format(f.name, err))
        finish(false)
        return false
      end
      text = out
    end
    local ok, err = apply(buf, text)
    if not ok then
      report(buf, err or "failed")
    end
    finish(ok)
    return ok
  end

  -- Async: drop the result if the buffer was edited while the formatters ran.
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local function step(i, text)
    local f = list[i]
    if not f then
      if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        return finish(false)
      end
      local ok, err = apply(buf, text)
      if not ok then
        report(buf, err or "failed")
      end
      return finish(ok)
    end
    exec_async(f.spec, ctx, text, timeout, function(out, err)
      if not out then
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_changedtick(buf) == tick then
          report(buf, ("%s: %s"):format(f.name, err))
        end
        return finish(false)
      end
      step(i + 1, out)
    end)
  end
  step(1, input)
  return true
end

--- Format lines first..last (1-based) through the LSP; external formatters
--- always take the whole buffer.
---@param first integer
---@param last integer
function M.format_range(first, last)
  local buf = vim.api.nvim_get_current_buf()
  if #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/rangeFormatting" }) == 0 then
    util.notify("format: no language server here can format a range")
    return
  end
  local text = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] or ""
  vim.lsp.buf.format({
    bufnr = buf,
    async = true,
    timeout_ms = config.get().format.timeout_ms,
    range = { start = { first, 0 }, ["end"] = { last, #text } },
  })
end

-- Toggles ---------------------------------------------------------------------------

---@return boolean
local function global_enabled()
  local g = vim.g.format_on_save
  if g == nil then
    return config.get().format.on_save
  end
  return g ~= false
end

--- Is format-on-save active for `buf`? (buffer override, else global)
---@param buf? integer
---@return boolean
function M.enabled(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local b = vim.b[buf].format_on_save
  if b ~= nil then
    return b ~= false
  end
  return global_enabled()
end

--- Set format-on-save: globally, or for `buf` only (nil clears a buffer override).
---@param value boolean?
---@param buf? integer
function M.set(value, buf)
  if buf then
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    vim.b[buf].format_on_save = value
  else
    vim.g.format_on_save = value
  end
end

--- Flip format-on-save, globally or for `buf` only. Returns the new state.
---@param buf? integer
---@return boolean
function M.toggle(buf)
  if buf then
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    local value = not M.enabled(buf)
    vim.b[buf].format_on_save = value
    return value
  end
  local value = not global_enabled()
  vim.g.format_on_save = value
  return value
end

-- Info --------------------------------------------------------------------------------

---@param buf integer
---@return string[]
function M.info(buf)
  local ft = vim.bo[buf].filetype
  local ctx = make_ctx(buf)
  local lines = { ("filetype: %s"):format(ft ~= "" and ft or "(none)") }

  local entry = entry_for(ft)
  if not entry then
    lines[#lines + 1] = "formatters: none configured"
  else
    lines[#lines + 1] = "formatters" .. (entry.stop_after_first and " (first available):" or ":")
    for _, name in ipairs(entry) do
      local spec = M.formatters[name]
      if not spec then
        lines[#lines + 1] = ("  %s: not defined"):format(name)
      else
        local ok, why = available(spec, ctx)
        lines[#lines + 1] = ("  %s: %s"):format(name, ok and "ok" or ("skipped, " .. why))
      end
    end
  end

  local names = {}
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf, method = "textDocument/formatting" })) do
    names[#names + 1] = c.name
  end
  lines[#lines + 1] = ("lsp fallback: %s (%s)"):format(lsp_mode(), #names > 0 and table.concat(names, ", ") or "no server can format")

  local b = vim.b[buf].format_on_save
  lines[#lines + 1] = ("format on save: %s (global %s%s)"):format(
    M.enabled(buf) and "on" or "off",
    global_enabled() and "on" or "off",
    b ~= nil and (", buffer override " .. (b and "on" or "off")) or ""
  )
  return lines
end

-- Setup -------------------------------------------------------------------------------

---@param fn fun(ev: table)
local function guarded(fn)
  return function(ev)
    local ok, err = pcall(fn, ev)
    if not ok then
      vim.schedule(function()
        util.notify("format error:\n" .. tostring(err), vim.log.levels.ERROR)
      end)
    end
  end
end

function M.setup()
  local cfg = config.get().format
  if not cfg.enabled then
    return
  end
  if vim.g.format_on_save == nil then
    vim.g.format_on_save = cfg.on_save
  end

  local group = util.augroup("format")
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    callback = guarded(function(ev)
      local buf = ev.buf
      if vim.bo[buf].buftype ~= "" or not M.enabled(buf) then
        return
      end
      local size = vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf))
      if size > config.get().format.max_bytes then
        return
      end
      M.format({ buf = buf, quiet = true })
    end),
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      last_error[ev.buf] = nil
    end,
  })

  vim.api.nvim_create_user_command("Format", function(o)
    if o.range > 0 then
      M.format_range(o.line1, o.line2)
    else
      M.format({ async = true })
    end
  end, { range = true, desc = "Format the buffer (a range goes through the LSP)" })

  vim.api.nvim_create_user_command("FormatToggle", function(o)
    local arg = o.args
    local value ---@type boolean?
    if arg == "on" then
      value = true
    elseif arg == "off" then
      value = false
    elseif arg ~= "" and arg ~= "toggle" and arg ~= "reset" then
      util.notify("FormatToggle: expected on, off, toggle or reset", vim.log.levels.ERROR)
      return
    end
    if arg == "reset" and not o.bang then
      util.notify("FormatToggle: reset clears a buffer override, use :FormatToggle! reset", vim.log.levels.ERROR)
      return
    end

    if o.bang then
      local buf = vim.api.nvim_get_current_buf()
      if arg == "reset" then
        M.set(nil, buf)
        util.notify(("Format on save: buffer override cleared (%s)"):format(M.enabled(buf) and "on" or "off"))
        return
      end
      if value == nil then
        value = not M.enabled(buf)
      end
      M.set(value, buf)
      util.notify("Format on save (buffer): " .. (value and "on" or "off"))
    else
      if value == nil then
        value = not global_enabled()
      end
      M.set(value)
      util.notify("Format on save (global): " .. (value and "on" or "off"))
    end
  end, {
    nargs = "?",
    bang = true,
    complete = function()
      return { "on", "off", "toggle", "reset" }
    end,
    desc = "Toggle format on save (! = this buffer only)",
  })

  vim.api.nvim_create_user_command("FormatInfo", function()
    util.notify(table.concat(M.info(vim.api.nvim_get_current_buf()), "\n"))
  end, { desc = "Show the formatters for this buffer and the format-on-save state" })
end

return M
