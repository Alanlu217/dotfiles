-- Statusline: one function evaluated per window by 'statusline' (%!). This file holds
-- both the mechanism and the layout; edit render() to change what is shown.
--
--   NORMAL  lua/core/git.lua [+]              main ^1 +2 ~3 ?1  E1 W2  lua_ls  lua  12:5  40%
--
-- The current window gets everything, in colour; other windows only the file name and
-- position, in the plain StatusLineNC colours. The git section comes from core.git
-- (cached, refreshed in the background).
--
-- Colours are taken from the active colorscheme (Function, String, Statement,
-- Diagnostic*, Added, Changed, Comment ...) on top of the StatusLine background, and
-- are recomputed on :colorscheme. The groups are named CoreSl*; override any of them
-- in a ColorScheme autocmd if you want something else.
local config = require("core.config")
local util = require("core.util")

local M = {}

-- label and highlight group per mode (keyed by the first character of the mode)
local modes = {
  n = { "NORMAL", "CoreSlModeNormal" },
  i = { "INSERT", "CoreSlModeInsert" },
  v = { "VISUAL", "CoreSlModeVisual" },
  V = { "V-LINE", "CoreSlModeVisual" },
  ["\22"] = { "V-BLOCK", "CoreSlModeVisual" },
  s = { "SELECT", "CoreSlModeVisual" },
  S = { "S-LINE", "CoreSlModeVisual" },
  ["\19"] = { "S-BLOCK", "CoreSlModeVisual" },
  R = { "REPLACE", "CoreSlModeReplace" },
  c = { "COMMAND", "CoreSlModeCommand" },
  r = { "PROMPT", "CoreSlModeCommand" },
  ["!"] = { "SHELL", "CoreSlModeTerminal" },
  t = { "TERMINAL", "CoreSlModeTerminal" },
}

--- Statusline items must not see a stray "%" in file names or branches.
---@param s string
---@return string
local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

--- Wrap already-escaped `text` in highlight group `group`, then back to the plain colours.
---@param group string
---@param text string
---@return string
local function hl(group, text)
  return "%#" .. group .. "#" .. text .. "%*"
end

---@param buf integer
---@return string
local function diagnostics(buf)
  local count = vim.diagnostic.count(buf)
  local sev = vim.diagnostic.severity
  local out = {}
  for _, item in ipairs({
    { sev.ERROR, "E", "CoreSlError" },
    { sev.WARN, "W", "CoreSlWarn" },
    { sev.INFO, "I", "CoreSlInfo" },
    { sev.HINT, "H", "CoreSlHint" },
  }) do
    local n = count[item[1]]
    if n and n > 0 then
      out[#out + 1] = hl(item[3], item[2] .. n)
    end
  end
  return table.concat(out, " ")
end

local lsp_cache = {} ---@type table<integer, string> buffer -> text; dropped when a client attaches or detaches

---@param buf integer
---@return string
local function lsp_names(buf)
  local hit = lsp_cache[buf]
  if hit then
    return hit
  end
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    names[#names + 1] = client.name
  end
  local text = #names > 0 and hl("CoreSlDim", esc(table.concat(names, ","))) or ""
  lsp_cache[buf] = text
  return text
end

local git_cache = {} ---@type table<integer, { status: table, text: string }>

--- "main ^1 +2 ~3 ?4", each count in its own colour; "" outside a repository.
---@param buf integer
---@return string
local function git_section(buf)
  local s = require("core.git").status(buf)
  if not s then
    return ""
  end
  -- Every refresh builds a new status table, so identity says whether the text is current.
  local hit = git_cache[buf]
  if hit and hit.status == s then
    return hit.text
  end
  local sym = config.get().git.symbols
  local parts = { hl("CoreSlBranch", esc(s.branch)) }
  for _, item in ipairs({
    { "CoreSlAhead", sym.ahead, s.ahead },
    { "CoreSlBehind", sym.behind, s.behind },
    { "CoreSlStaged", sym.staged, s.staged },
    { "CoreSlModified", sym.modified, s.modified },
    { "CoreSlUntracked", sym.untracked, s.untracked },
    { "CoreSlConflict", sym.conflict, s.conflicts },
  }) do
    if item[3] > 0 then
      parts[#parts + 1] = hl(item[1], esc(item[2] .. item[3]))
    end
  end
  local text = table.concat(parts, " ")
  git_cache[buf] = { status = s, text = text }
  return text
end

---@param buf integer
---@return string
local function file_name(buf)
  local bt = vim.bo[buf].buftype
  if bt == "terminal" then
    return "terminal"
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return bt == "" and "[No Name]" or ("[%s]"):format(bt)
  end
  return vim.fn.fnamemodify(name, ":~:.")
end

---@param win integer
---@return string
local function build(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local current = win == vim.api.nvim_get_current_win()

  local left = ""
  if current then
    local mode = vim.api.nvim_get_mode().mode
    local m = modes[mode] or modes[mode:sub(1, 1)] or { mode:upper(), "CoreSlModeNormal" }
    left = hl(m[2], " " .. m[1] .. " ")
  end
  -- %m = [+] when modified, %r = [RO] when read-only
  left = left .. " %<" .. esc(file_name(buf)) .. (current and hl("CoreSlFlag", "%m%r") or "%m%r")

  local right = {}
  if current then
    local ft = vim.bo[buf].filetype
    for _, item in ipairs({ git_section(buf), diagnostics(buf), lsp_names(buf), ft ~= "" and hl("CoreSlDim", esc(ft)) or "" }) do
      if item ~= "" then
        right[#right + 1] = item
      end
    end
  end
  right[#right + 1] = "%l:%c"
  if current then
    right[#right + 1] = "%p%%"
  end

  return left .. "%=" .. table.concat(right, "  ") .. " "
end

--- Called by 'statusline' for each window being drawn.
---@return string
function M.render()
  local win = vim.g.statusline_winid
  if not win or not vim.api.nvim_win_is_valid(win) then
    win = vim.api.nvim_get_current_win()
  end
  local ok, line = pcall(build, win)
  -- An error here would make Neovim drop 'statusline' altogether; fall back instead.
  return ok and line or " %<%f %m%r%=%l:%c "
end

-- Colours ---------------------------------------------------------------------------

local function set_hl()
  local function attr(group, key)
    return vim.api.nvim_get_hl(0, { name = group, link = false })[key]
  end
  local function fg(group, fallback)
    return attr(group, "fg") or fallback
  end

  -- Items sit on the StatusLine background; a reversed StatusLine keeps it in fg.
  local bar = attr("StatusLine", "reverse") and attr("StatusLine", "fg") or attr("StatusLine", "bg")
  local function text(name, color)
    vim.api.nvim_set_hl(0, name, { fg = color, bg = bar })
  end
  local function pill(name, color)
    vim.api.nvim_set_hl(0, name, { fg = bar or "#16161e", bg = color, bold = true })
  end

  local normal, insert, visual = fg("Function", "#61afef"), fg("String", "#98c379"), fg("Statement", "#c678dd")
  local err, warn, info, hint =
    fg("DiagnosticError", "#e06c75"), fg("DiagnosticWarn", "#e5c07b"), fg("DiagnosticInfo", "#61afef"), fg("DiagnosticHint", "#56b6c2")

  pill("CoreSlModeNormal", normal)
  pill("CoreSlModeInsert", insert)
  pill("CoreSlModeVisual", visual)
  pill("CoreSlModeReplace", err)
  pill("CoreSlModeCommand", warn)
  pill("CoreSlModeTerminal", hint)

  text("CoreSlBranch", visual)
  text("CoreSlAhead", info)
  text("CoreSlBehind", info)
  text("CoreSlStaged", fg("Added", "#98c379"))
  text("CoreSlModified", fg("Changed", "#e5c07b"))
  text("CoreSlUntracked", hint)
  text("CoreSlConflict", err)

  text("CoreSlError", err)
  text("CoreSlWarn", warn)
  text("CoreSlInfo", info)
  text("CoreSlHint", hint)

  text("CoreSlFlag", warn)
  text("CoreSlDim", fg("Comment", "#7f849c"))
end

function M.setup()
  if not config.get().statusline.enabled then
    return
  end
  vim.o.statusline = [[%!v:lua.require'core.statusline'.render()]]
  set_hl()

  local group = util.augroup("statusline")
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })
  -- Mode, diagnostics, LSP and git are only shown in the current window's statusline, so
  -- redrawing that one is enough (`redrawstatus!` would rebuild every window's).
  vim.api.nvim_create_autocmd({ "DiagnosticChanged", "ModeChanged" }, {
    group = group,
    callback = function()
      vim.cmd("redrawstatus")
    end,
  })
  vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
    group = group,
    callback = function()
      lsp_cache = {}
      vim.schedule(function()
        lsp_cache = {} -- LspDetach fires before the client is gone from get_clients()
        vim.cmd("redrawstatus")
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      lsp_cache[ev.buf], git_cache[ev.buf] = nil, nil
    end,
  })
end

return M
