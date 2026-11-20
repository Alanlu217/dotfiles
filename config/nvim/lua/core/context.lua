-- Where is the insert-mode cursor: in code, a string or a comment?
--
--   require("core.context").at_cursor()   "string" | "comment" | nil (code, or unknown)
--
-- Uses treesitter when it is highlighting the buffer, otherwise the regex syntax
-- groups. When neither can tell, the answer is nil: callers must treat "unknown"
-- as "code" only where being wrong is harmless.
local M = {}

---@param a integer[]
---@param b integer[]
---@return boolean
local function before(a, b)
  return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
end

---@param buf integer
---@param row integer 0-based
---@param col integer 0-based byte column of the cursor (the insert position)
---@return string?
local function ts_kind(buf, row, col)
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, col } })
  local pos = { row, col }
  while node do
    local t = node:type()
    local is_comment = t:find("comment", 1, true) ~= nil
    local is_string = not is_comment and t:find("string", 1, true) ~= nil and not t:find("escape", 1, true)
    if is_comment or is_string then
      local sr, sc, er, ec = node:range()
      local start, stop = { sr, sc }, { er, ec }
      -- Strictly inside a string (`|"x"` and `"x"|` are outside it); a comment also
      -- contains the end of its line, where the cursor usually is while typing.
      if before(start, pos) and (before(pos, stop) or (is_comment and not before(stop, pos))) then
        return is_comment and "comment" or "string"
      end
    end
    node = node:parent()
  end
  return nil
end

---@param row1 integer
---@param col1 integer 1-based byte column
---@return string[]
local function syntax_names(row1, col1)
  local names = {}
  if col1 < 1 then
    return names
  end
  for _, id in ipairs(vim.fn.synstack(row1, col1)) do
    names[#names + 1] = vim.fn.synIDattr(id, "name")
  end
  return names
end

---@param names string[]
---@param pattern string
---@return boolean
local function any(names, pattern)
  for _, name in ipairs(names) do
    if name:find(pattern) then
      return true
    end
  end
  return false
end

---@param row integer 0-based
---@param col integer 0-based byte column of the cursor
---@return string?
local function syntax_kind(row, col)
  if vim.fn.exists("g:syntax_on") == 0 or vim.bo.syntax == "" then
    return nil
  end
  local prev = syntax_names(row + 1, col) -- the character before the cursor
  if any(prev, "[Cc]omment") then
    return "comment"
  end
  if any(prev, "[Ss]tring") and any(syntax_names(row + 1, col + 1), "[Ss]tring") then
    return "string"
  end
  return nil
end

---@return "string"|"comment"|nil
function M.at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1] - 1, pos[2]
  if vim.b[buf].ts_highlight then
    local ok, kind = pcall(ts_kind, buf, row, col)
    if ok then
      return kind
    end
  end
  local ok, kind = pcall(syntax_kind, row, col)
  return ok and kind or nil
end

return M
