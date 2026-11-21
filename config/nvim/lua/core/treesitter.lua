-- Treesitter highlighting without nvim-treesitter: Neovim ships the runtime
-- (vim.treesitter) but not a parser installer, so this only *starts* highlighting
-- for filetypes whose parser and highlights query are already on 'runtimepath'.
-- Everything else keeps the regex syntax, so nothing is ever left unhighlighted.
--
-- Neovim's own parsers (c, lua, vim, vimdoc, markdown, query) work out of the box.
-- For other languages (rust, cpp, typst, ...) drop a compiled parser and its
-- queries somewhere on the runtimepath; stdpath("data")/site is already on it:
--
--   <data>/site/parser/rust.so
--   <data>/site/queries/rust/highlights.scm
--
-- (`:checkhealth core` lists what is found for config.treesitter.languages.)
--
--   :TSInfo     filetype, language, parser, query and whether highlighting is on
--   :TSToggle   switch treesitter highlighting for this buffer (regex syntax <-> tree)
--
--   require("core.treesitter").start(buf?) / .available(lang)
--
-- Mechanism only; no keymaps are defined here (see lua/user/keymaps.lua).
local config = require("core.config")
local util = require("core.util")

local M = {}

-- Looking for a parser that is not there searches the whole 'runtimepath' every time,
-- and most filetypes have none. Negative answers are remembered briefly.
local missing = {} ---@type table<string, { at: integer, parser: boolean, query: boolean }>
local MISSING_TTL = 10000 -- ms; a parser dropped in during the session is found within this

--- Is there a parser for `lang`, and a highlights query for it?
---@param lang string
---@param fresh? boolean ignore remembered negative answers (for :TSInfo and :checkhealth)
---@return boolean has_parser, boolean has_query
function M.available(lang, fresh)
  local hit = missing[lang]
  if hit and not fresh and vim.uv.now() - hit.at < MISSING_TTL then
    return hit.parser, hit.query
  end
  local has_parser, has_query = false, false
  if pcall(vim.treesitter.language.inspect, lang) then
    local ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
    has_parser, has_query = true, ok and query ~= nil
  end
  missing[lang] = (has_parser and has_query) and nil or { at = vim.uv.now(), parser = has_parser, query = has_query }
  return has_parser, has_query
end

--- Start treesitter highlighting for `buf` when it can work. Returns whether it is running.
---@param buf? integer
---@return boolean
function M.start(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local cfg = config.get().treesitter
  if not cfg.enabled or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return false
  end
  if vim.b[buf].ts_highlight then
    return true -- already running, e.g. started by Neovim's own ftplugin
  end

  local ft = vim.bo[buf].filetype
  if ft == "" or vim.bo[buf].buftype ~= "" or vim.tbl_contains(cfg.disable, ft) then
    return false
  end
  if vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) > cfg.max_bytes then
    return false
  end

  local lang = vim.treesitter.language.get_lang(ft)
  if not lang then
    return false
  end
  local has_parser, has_query = M.available(lang)
  if not (has_parser and has_query) then
    return false -- without a highlights query the tree would switch regex syntax off for nothing
  end
  return (pcall(vim.treesitter.start, buf, lang))
end

---@param buf integer
---@return string[]
function M.info(buf)
  local ft = vim.bo[buf].filetype
  local lines = { ("filetype: %s"):format(ft ~= "" and ft or "(none)") }
  local lang = ft ~= "" and vim.treesitter.language.get_lang(ft) or nil
  if not lang then
    lines[#lines + 1] = "language: (none)"
  else
    local has_parser, has_query = M.available(lang, true)
    lines[#lines + 1] = "language: " .. lang
    lines[#lines + 1] = "parser: " .. (has_parser and "found" or "missing")
    lines[#lines + 1] = "highlights query: " .. (has_query and "found" or "missing")
  end
  lines[#lines + 1] = "highlighting: " .. (vim.b[buf].ts_highlight and "treesitter" or "regex syntax")
  return lines
end

function M.setup()
  local cfg = config.get().treesitter
  if not cfg.enabled then
    return
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = util.augroup("treesitter"),
    callback = function(ev)
      M.start(ev.buf)
    end,
  })

  -- :ReloadConfig runs setup() again with files already open.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    M.start(buf)
  end

  vim.api.nvim_create_user_command("TSInfo", function()
    util.notify(table.concat(M.info(vim.api.nvim_get_current_buf()), "\n"))
  end, { desc = "Show the treesitter parser and highlighting state for this buffer" })

  vim.api.nvim_create_user_command("TSToggle", function()
    local buf = vim.api.nvim_get_current_buf()
    if vim.b[buf].ts_highlight then
      pcall(vim.treesitter.stop, buf)
      util.notify("Treesitter highlighting: off (regex syntax)")
    elseif M.start(buf) then
      util.notify("Treesitter highlighting: on")
    else
      util.notify("Treesitter highlighting: no parser or highlights query for this buffer (:TSInfo)", vim.log.levels.WARN)
    end
  end, { desc = "Toggle treesitter highlighting for this buffer" })
end

return M
