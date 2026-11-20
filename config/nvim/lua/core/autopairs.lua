-- Auto pairs, deliberately timid: when in doubt it inserts just the key you typed.
--
-- A pair is only made when all of these hold:
--   * the character after the cursor is the end of the line, whitespace or one of
--     `autopairs.next_chars` (so `|foo` and `|"x"` never get a stray closer);
--   * the cursor is not in a string or a comment (treesitter, else regex syntax);
--   * the key is not escaped (`\(`), and the line has no unmatched closer for it yet
--     (typing the missing `(` of `foo)` adds nothing);
--   * quotes: the character before is not a word character (`don't`, `x'`), not the
--     same quote (`""` -> no third), and the quotes before the cursor on the line
--     are even in number (else this one is probably closing a string).
-- A closer typed in front of one *we* inserted steps over it; any other closer is
-- inserted as typed, so a pair never swallows what you meant. <BS> between a pair
-- we made removes both. Pairs we made are forgotten when Insert mode ends or the
-- cursor leaves the line.
--
--   :Autopairs [on|off|toggle]     runtime switch (vim.b.autopairs = false per buffer)
--
--   require("core.autopairs").keys()       { key, fn } to map in Insert mode ("open" | "close")
--   require("core.autopairs").open(key)    keys to insert for an opening or quote key
--   require("core.autopairs").close(key)   keys to insert for a closing bracket
--   require("core.autopairs").backspace()  keys for <BS>
--
-- The functions return keys for { expr = true } Insert mode mappings (see
-- lua/user/keymaps.lua) and fall back to the key itself on anything unexpected.
-- Mechanism only; no keymaps are defined here.
local config = require("core.config")
local context = require("core.context")
local util = require("core.util")

local M = {}

---@type boolean runtime switch (:Autopairs); config.autopairs.enabled is the static one
M.enabled = true

local ns = vim.api.nvim_create_namespace("core_autopairs")
local marks = {} ---@type table<integer, table<integer, string>> buffer -> extmark id -> closer

local LEFT = "<C-g>U<Left>" -- keeps the insert in one undo step
local RIGHT = "<C-g>U<Right>"

---@return table
local function cfg()
  return config.get().autopairs
end

---@param s string
---@return string?
local function last_char(s)
  return s:match("[\1-\127\194-\244][\128-\191]*$")
end

---@param s string
---@return string?
local function first_char(s)
  return s:match("^[\1-\127\194-\244][\128-\191]*")
end

--- Word characters, and anything non-ASCII: in doubt, it is a word.
---@param ch? string
---@return boolean
local function is_word(ch)
  return ch ~= nil and ch ~= "" and (ch:find("^[%w_]") ~= nil or ch:byte() >= 128)
end

---@return boolean
local function active()
  if not M.enabled or not cfg().enabled then
    return false
  end
  local buf = vim.api.nvim_get_current_buf()
  if vim.b[buf].autopairs == false then
    return false
  end
  local bo = vim.bo[buf]
  return bo.buftype == "" and bo.modifiable and not bo.readonly
end

--- The closer for `key` in filetype `ft`: its own pairs first, then the global ones.
---@param ft string
---@param key string
---@return string?
function M.pair_for(ft, key)
  local extra = cfg().filetype_pairs[ft]
  return (extra and extra[key]) or cfg().pairs[key]
end
local pair_for = M.pair_for

--- May `key` pair in filetype `ft` (per `autopairs.filetypes`)?
---@param ft string
---@param key string
---@return boolean
function M.allowed_in(ft, key)
  local rule = cfg().filetypes[ft]
  if rule == false then
    return false
  end
  return not (type(rule) == "table" and rule[key] == false)
end
local allowed_in = M.allowed_in

---@return { row: integer, col: integer, before: string, after: string, line: string }
local function snapshot()
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  return { row = pos[1] - 1, col = pos[2], before = line:sub(1, pos[2]), after = line:sub(pos[2] + 1), line = line }
end

-- Pairs we made ------------------------------------------------------------------

--- Called through <Cmd> once the pair is in the buffer and the cursor sits between
--- its halves: remember the closer. The mark moves right as you type before it.
function M._mark()
  pcall(function()
    local s = snapshot()
    local closer = first_char(s.after)
    if not closer then
      return
    end
    local buf = vim.api.nvim_get_current_buf()
    local id = vim.api.nvim_buf_set_extmark(buf, ns, s.row, s.col, {})
    marks[buf] = marks[buf] or {}
    marks[buf][id] = closer
  end)
end

--- The id of our mark for `closer` exactly at the cursor, if the text there still matches.
---@param buf integer
---@param s { row: integer, col: integer }
---@param closer string
---@return integer?
local function mark_here(buf, s, closer)
  local found = vim.api.nvim_buf_get_extmarks(buf, ns, { s.row, s.col }, { s.row, s.col }, {})
  for _, m in ipairs(found) do
    if marks[buf] and marks[buf][m[1]] == closer then
      return m[1]
    end
  end
  return nil
end

---@param buf integer
---@param id integer
local function drop_mark(buf, id)
  pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
  if marks[buf] then
    marks[buf][id] = nil
  end
end

---@param buf integer
local function clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
  marks[buf] = nil
end

--- Forget pairs on other lines than the cursor's.
---@param buf integer
local function prune(buf)
  if not marks[buf] then
    return
  end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})) do
    if m[2] ~= row then
      drop_mark(buf, m[1])
    end
  end
end

-- Rules --------------------------------------------------------------------------

---@param nxt? string the character after the cursor
---@return boolean
local function next_allows(nxt)
  if nxt == nil or nxt == "" or nxt:find("^%s") then
    return true
  end
  return cfg().next_chars:find(nxt, 1, true) ~= nil
end

--- More `closer`s than `opener`s on the line: the user is probably adding an opener.
---@param line string
---@param opener string
---@param closer string
---@return boolean
local function unbalanced(line, opener, closer)
  local _, opens = line:gsub(vim.pesc(opener), "")
  local _, closes = line:gsub(vim.pesc(closer), "")
  return closes > opens
end

--- Unescaped `q`s in `text`.
---@param text string
---@param q string
---@return integer
local function quote_count(text, q)
  local n, i = 0, 1
  while i <= #text do
    local ch = text:sub(i, i)
    if ch == "\\" then
      i = i + 2
    else
      if ch == q then
        n = n + 1
      end
      i = i + 1
    end
  end
  return n
end

---@param opener string
---@param closer string
---@return string
local function pair_keys(opener, closer)
  return opener .. closer .. LEFT .. "<Cmd>lua require('core.autopairs')._mark()<CR>"
end

---@param q string
---@param s table
---@param prev? string
---@param nxt? string
---@param ft string
---@return string
local function quote_keys(q, s, prev, nxt, ft)
  local buf = vim.api.nvim_get_current_buf()
  if nxt == q then
    -- Typing the closing quote of a pair we made: step over it.
    local id = mark_here(buf, s, q)
    if id then
      drop_mark(buf, id)
      return RIGHT
    end
  end
  if prev == q then
    return q
  end
  if is_word(prev) then
    -- Only a string prefix (f"..", b'..') may sit right before an opening quote.
    local pattern = cfg().string_prefixes[ft]
    local word = s.before:match("[%w_]+$")
    if not (pattern and word and word:find("^" .. pattern .. "+$")) then
      return q
    end
  end
  if quote_count(s.before, q) % 2 == 1 then
    return q
  end
  if not next_allows(nxt) or context.at_cursor() then
    return q
  end
  return pair_keys(q, q)
end

-- Keys ---------------------------------------------------------------------------

--- Keys for an opening bracket or a quote.
---@param key string
---@return string
function M.open(key)
  local ft = vim.bo.filetype
  local closer = pair_for(ft, key)
  if not closer or not active() then
    return key
  end
  local ok, keys = pcall(function()
    if not allowed_in(ft, key) then
      return key
    end
    local s = snapshot()
    local prev, nxt = last_char(s.before), first_char(s.after)
    if prev == "\\" then
      return key
    end
    if key == closer then
      return quote_keys(key, s, prev, nxt, ft)
    end
    if not next_allows(nxt) or unbalanced(s.line, key, closer) or context.at_cursor() then
      return key
    end
    return pair_keys(key, closer)
  end)
  return ok and keys or key
end

--- Keys for a closing bracket: step over the one we inserted, else type it.
---@param key string
---@return string
function M.close(key)
  if not active() then
    return key
  end
  local ok, keys = pcall(function()
    local s = snapshot()
    if first_char(s.after) == key then
      local buf = vim.api.nvim_get_current_buf()
      local id = mark_here(buf, s, key)
      if id then
        drop_mark(buf, id)
        return RIGHT
      end
    end
    return key
  end)
  return ok and keys or key
end

--- <BS> between a pair we made deletes both halves.
---@return string
function M.backspace()
  if not active() then
    return "<BS>"
  end
  local ok, keys = pcall(function()
    local s = snapshot()
    local prev, nxt = last_char(s.before), first_char(s.after)
    if prev and nxt and pair_for(vim.bo.filetype, prev) == nxt then
      local buf = vim.api.nvim_get_current_buf()
      local id = mark_here(buf, s, nxt)
      if id then
        drop_mark(buf, id)
        return "<BS><Del>"
      end
    end
    return "<BS>"
  end)
  return ok and keys or "<BS>"
end

--- What to map in Insert mode: { key, fn } with fn "open" or "close".
---@return { key: string, fn: "open"|"close" }[]
function M.keys()
  -- Every key any filetype pairs; open()/close() know per buffer whether it applies.
  local all = vim.deepcopy(cfg().pairs)
  for _, extra in pairs(cfg().filetype_pairs) do
    for opener, closer in pairs(extra) do
      all[opener] = closer
    end
  end
  local out = {}
  for opener, closer in pairs(all) do
    out[#out + 1] = { key = opener, fn = "open" }
    if closer ~= opener then
      out[#out + 1] = { key = closer, fn = "close" }
    end
  end
  table.sort(out, function(a, b)
    return a.key < b.key
  end)
  return out
end

function M.setup()
  if not cfg().enabled then
    return
  end
  local group = util.augroup("autopairs")
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function(ev)
      clear(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = group,
    callback = function(ev)
      prune(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(ev)
      marks[ev.buf] = nil
    end,
  })

  vim.api.nvim_create_user_command("Autopairs", function(o)
    local arg = o.args
    if arg == "on" then
      M.enabled = true
    elseif arg == "off" then
      M.enabled = false
    elseif arg == "" or arg == "toggle" then
      M.enabled = not M.enabled
    else
      util.notify("Autopairs: expected on, off or toggle", vim.log.levels.ERROR)
      return
    end
    util.notify("Auto pairs " .. (M.enabled and "on" or "off"))
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "toggle" }
    end,
    desc = "Switch auto pairs on or off",
  })
end

return M
