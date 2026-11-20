-- Smart indentation: three small things on top of Neovim's own indent scripts.
--
--   1. Detect each file's indent style (tabs, or N spaces) from its content, so a
--      4-space or tab-indented file is edited the way it is written. Only the buffer's
--      'expandtab', 'shiftwidth' and 'softtabstop' change. Skipped when the file has
--      an indent modeline or EditorConfig sets the style; modelines and EditorConfig
--      always win. Empty or unclear files keep your defaults.
--   2. <CR> between any auto pair opens the block:  {|}  ->  {, an indented line, }
--      (brackets, quotes and typst's $; the pairs and filetype rules are autopairs.*)
--   3. <CR> after an opening bracket indents the next line in filetypes that have no
--      indent script of their own (no 'indentexpr', 'cindent' or 'lisp'). Never in
--      strings, comments or prose filetypes.
--
--   :IndentDetect       detect again for this buffer (also overrides modelines)
--   :IndentInfo         what is in effect and what was detected
--                       (vim.b.indent_detect = false opts a buffer out)
--
--   require("core.indent").enter()    keys for an Insert mode <CR> mapping; "<CR>" when it has nothing to add
--   require("core.indent").detect(buf, force?)
--
-- Mechanism only; no keymaps are defined here (see lua/user/keymaps.lua).
local config = require("core.config")
local context = require("core.context")
local util = require("core.util")

local M = {}

local CR = "<CR>"

---@return table
local function cfg()
  return config.get().indent
end

-- Detection ----------------------------------------------------------------------

---@class core.indent.Found
---@field kind "tabs"|"spaces"
---@field width? integer
---@field votes integer

--- Look at how lines step in: tab-indented lines against space-indented ones, and for
--- spaces which increase (2, 4, ...) between neighbouring lines is the most common.
---@param lines string[]
---@param sizes integer[] widths worth considering
---@param min_votes integer evidence needed
---@return core.indent.Found?
function M.detect_lines(lines, sizes, min_votes)
  local allowed = {}
  for _, n in ipairs(sizes) do
    allowed[n] = true
  end
  local tabs, spaces, votes, prev = 0, 0, {}, 0
  for _, line in ipairs(lines) do
    -- Blank lines and ' * ' block comment continuations say nothing about the style.
    if line:find("%S") and not line:find("^%s+%*") then
      local ws = line:match("^[ \t]*")
      if ws:sub(1, 1) == "\t" then
        tabs = tabs + 1
        prev = 0
      elseif ws == "" then
        prev = 0
      elseif not ws:find("\t", 1, true) then
        spaces = spaces + 1
        local delta = #ws - prev
        if delta > 0 and allowed[delta] then
          votes[delta] = (votes[delta] or 0) + 1
        end
        prev = #ws
      end
    end
  end

  if tabs >= min_votes and tabs >= spaces then
    return { kind = "tabs", votes = tabs }
  end
  local best, best_votes = nil, 0
  for width, n in pairs(votes) do
    if n > best_votes or (n == best_votes and best and width < best) then
      best, best_votes = width, n
    end
  end
  if best and best_votes >= min_votes then
    return { kind = "spaces", width = best, votes = best_votes }
  end
  return nil
end

local MODELINE_INDENT_OPTS = {
  "%f[%w]sw=", "%f[%w]shiftwidth=", "%f[%w]ts=", "%f[%w]tabstop=", "%f[%w]sts=", "%f[%w]softtabstop=",
  "%f[%w]expandtab%f[%W]", "%f[%w]noexpandtab%f[%W]", "%f[%w]et%f[%W]", "%f[%w]noet%f[%W]",
}

--- Does one of the first or last 'modelines' lines carry a modeline that sets indentation?
---@param lines string[]
---@return boolean
local function indent_modeline(lines)
  if not vim.o.modeline then
    return false
  end
  local span, n = vim.o.modelines, #lines
  for i, line in ipairs(lines) do
    local near_edge = i <= span or i > n - span
    if near_edge and (line:find("[vV]im?:") or line:find("%sex:")) then
      for _, pattern in ipairs(MODELINE_INDENT_OPTS) do
        if line:find(pattern) then
          return true
        end
      end
    end
  end
  return false
end

---@param buf integer
---@param found core.indent.Found
function M.apply(buf, found)
  local bo = vim.bo[buf]
  if found.kind == "tabs" then
    bo.expandtab = false
    bo.shiftwidth = 0 -- follow 'tabstop'
    bo.softtabstop = 0
  else
    bo.expandtab = true
    bo.shiftwidth = found.width
    bo.softtabstop = -1 -- follow 'shiftwidth'
  end
end

---@param found? core.indent.Found
---@return string
local function describe(found)
  if not found then
    return "unclear"
  end
  return found.kind == "tabs" and "tabs" or (found.width .. " spaces")
end

--- Detect and apply the indent style of `buf`.
---@param buf integer
---@param force? boolean also override modelines, EditorConfig and the opt-outs
---@return core.indent.Found? found
function M.detect(buf, force)
  local d = cfg().detect
  if not force and not d.enabled then
    return nil
  end
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" or not vim.bo[buf].modifiable then
    return nil
  end
  if not force then
    if vim.b[buf].indent_detect == false or vim.tbl_contains(d.ignore, vim.bo[buf].filetype) then
      return nil
    end
    local ec = vim.b[buf].editorconfig
    if type(ec) == "table" and (ec.indent_style or ec.indent_size or ec.tab_width) then
      return nil -- EditorConfig already decided
    end
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, d.max_lines, false)
  if not force and indent_modeline(lines) then
    return nil
  end
  local found = M.detect_lines(lines, d.sizes, d.min_votes)
  if found then
    M.apply(buf, found)
  end
  vim.b[buf].indent_detected = describe(found)
  return found
end

-- <CR> ---------------------------------------------------------------------------

--- Called through <Cmd> right after <C-o>O opened the line between a pair: make sure
--- it is one level deeper than the closing line, whatever the indent script said.
function M._fix_inner()
  pcall(function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_get_current_line()
    if line:find("%S") then
      return
    end
    local want = vim.fn.indent(row + 1) + vim.fn.shiftwidth()
    if vim.fn.indent(row) >= want then
      return
    end
    local ws
    if vim.bo.expandtab then
      ws = (" "):rep(want)
    else
      local ts = vim.bo.tabstop
      ws = ("\t"):rep(math.floor(want / ts)) .. (" "):rep(want % ts)
    end
    vim.api.nvim_set_current_line(ws)
    vim.api.nvim_win_set_cursor(0, { row, #ws })
  end)
end

---@param before string text before the cursor
---@param after string text after the cursor
---@return boolean
local function wants_opener_indent(before, after)
  local o = cfg().openers
  local bo = vim.bo
  if not o.enabled or bo.indentexpr ~= "" or bo.cindent or bo.lisp then
    return false
  end
  if vim.tbl_contains(o.skip, bo.filetype) or after:find("%S") then
    return false
  end
  local opener = before:match("([%(%[{])%s*$")
  if not opener or (opener == "{" and bo.smartindent) then
    return false -- 'smartindent' already indents after a {
  end
  return context.at_cursor() == nil
end

---@return string
local function enter_keys()
  local bo = vim.bo
  if bo.buftype ~= "" or not bo.modifiable then
    return CR
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local before, after = line:sub(1, pos[2]), line:sub(pos[2] + 1)

  local prev, nxt = before:sub(-1), after:sub(1, 1)
  if cfg().expand_pairs and prev ~= "" and nxt ~= "" then
    local ap = require("core.autopairs")
    local ft = bo.filetype
    if ap.pair_for(ft, prev) == nxt and ap.allowed_in(ft, prev) then
      -- Between two quotes the cursor is in a string by definition, so only brackets are
      -- checked for being inside a string or comment.
      if prev == nxt or context.at_cursor() == nil then
        return CR .. "<C-o>O<Cmd>lua require('core.indent')._fix_inner()<CR>"
      end
    end
  end
  if wants_opener_indent(before, after) then
    return CR .. "<C-t>"
  end
  return CR
end

--- Keys for Insert mode <CR> (call it once completion has nothing to accept).
---@return string
function M.enter()
  local ok, keys = pcall(enter_keys)
  return ok and keys or CR
end

function M.setup()
  local group = util.augroup("indent")

  -- BufWinEnter, not BufReadPost: by then filetype plugins, modelines and EditorConfig
  -- have run, so detection only fills in what nobody decided explicitly.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      if vim.b[ev.buf].indent_checked then
        return
      end
      vim.b[ev.buf].indent_checked = true
      pcall(M.detect, ev.buf)
    end,
  })

  -- :ReloadConfig runs setup() again with files already open.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and not vim.b[buf].indent_checked and #vim.fn.win_findbuf(buf) > 0 then
      vim.b[buf].indent_checked = true
      pcall(M.detect, buf)
    end
  end

  vim.api.nvim_create_user_command("IndentDetect", function()
    local buf = vim.api.nvim_get_current_buf()
    vim.b[buf].indent_checked = true
    local found = M.detect(buf, true)
    util.notify("Indent: " .. describe(found) .. (found and "" or " (options unchanged)"))
  end, { desc = "Detect the indent style of this buffer from its content" })

  vim.api.nvim_create_user_command("IndentInfo", function()
    local bo = vim.bo
    util.notify(table.concat({
      ("detected: %s"):format(vim.b.indent_detected or "not run"),
      ("expandtab=%s shiftwidth=%d (effective %d) tabstop=%d softtabstop=%d"):format(
        tostring(bo.expandtab), bo.shiftwidth, vim.fn.shiftwidth(), bo.tabstop, bo.softtabstop),
      ("indentexpr=%s cindent=%s smartindent=%s"):format(bo.indentexpr ~= "" and bo.indentexpr or "-", tostring(bo.cindent), tostring(bo.smartindent)),
    }, "\n"))
  end, { desc = "Show the indent settings in effect for this buffer" })
end

return M
