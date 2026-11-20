-- Diagnostics picker: every diagnostic of the open buffers, or one buffer only.
-- Only buffers that were opened have diagnostics; servers don't report the rest.
local matcher = require("core.picker.matcher")
local ui = require("core.picker.ui")
local util = require("core.util")

local M = {}

local severity = vim.diagnostic.severity
local LETTER = {
  [severity.ERROR] = "E",
  [severity.WARN] = "W",
  [severity.INFO] = "I",
  [severity.HINT] = "H",
}
local RANGE_HL = {
  [severity.ERROR] = "DiagnosticUnderlineError",
  [severity.WARN] = "DiagnosticUnderlineWarn",
  [severity.INFO] = "DiagnosticUnderlineInfo",
  [severity.HINT] = "DiagnosticUnderlineHint",
}
local CMDS = { edit = "buffer", split = "sbuffer", vsplit = "vertical sbuffer", tabedit = "tab sbuffer" }

---@param buf integer
---@return string
local function buf_name(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return ("[No Name %d]"):format(buf)
  end
  return (vim.fn.fnamemodify(name, ":~:."):gsub("[\r\n]", " "))
end

--- "  [source code]" when the diagnostic says where it came from.
---@param d vim.Diagnostic
---@return string
local function origin(d)
  local parts = {}
  if d.source and d.source ~= "" then
    parts[#parts + 1] = d.source
  end
  if d.code ~= nil and d.code ~= "" then
    parts[#parts + 1] = tostring(d.code)
  end
  return #parts > 0 and ("  [" .. table.concat(parts, " ") .. "]") or ""
end

---@param d vim.Diagnostic
---@param action "edit"|"split"|"vsplit"|"tabedit"
local function jump(d, action)
  if not vim.api.nvim_buf_is_valid(d.bufnr) then
    return
  end
  vim.cmd(("%s %d"):format(CMDS[action], d.bufnr))
  local last = vim.api.nvim_buf_line_count(0)
  local lnum = math.min(d.lnum + 1, last)
  local text = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
  vim.api.nvim_win_set_cursor(0, { lnum, math.min(d.col, math.max(#text - 1, 0)) })
  vim.cmd("normal! zvzz")
end

---@param d vim.Diagnostic
---@return core.picker.PreviewTarget
local function preview_target(d)
  local lnum, col = d.lnum + 1, d.col + 1
  local end_lnum = (d.end_lnum or d.lnum) + 1
  local end_col = (d.end_col or d.col) + 1
  if end_lnum == lnum and end_col <= col then
    end_col = col + 1 -- an empty range would show nothing
  end
  return {
    kind = "buf",
    bufnr = d.bufnr,
    lnum = lnum,
    col = col,
    end_lnum = end_lnum,
    end_col = end_col,
    match_hl = RANGE_HL[d.severity],
  }
end

---@param opts? { buffer?: boolean } restrict to the current buffer
function M.open(opts)
  local only_current = opts and opts.buffer
  local source = only_current and vim.api.nvim_get_current_buf() or nil

  local entries = {}
  for _, d in ipairs(vim.diagnostic.get(source)) do
    if vim.api.nvim_buf_is_valid(d.bufnr) then
      entries[#entries + 1] = { diag = d, name = buf_name(d.bufnr) }
    end
  end
  if #entries == 0 then
    util.notify(only_current and "No diagnostics in this buffer" or "No diagnostics in open buffers")
    return
  end

  -- Most severe first, then by file and position.
  table.sort(entries, function(a, b)
    local x, y = a.diag, b.diag
    if x.severity ~= y.severity then
      return (x.severity or 99) < (y.severity or 99)
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    if x.lnum ~= y.lnum then
      return x.lnum < y.lnum
    end
    return x.col < y.col
  end)

  local labels, lookup, seen = {}, {}, {}
  for _, entry in ipairs(entries) do
    local d = entry.diag
    local pos = ("%d:%d"):format(d.lnum + 1, d.col + 1)
    local where = only_current and pos or (entry.name .. ":" .. pos)
    local message = (tostring(d.message):gsub("%s+", " "))
    local label = ("%s  %s  %s%s"):format(LETTER[d.severity] or "?", where, message, origin(d))

    seen[label] = (seen[label] or 0) + 1
    if seen[label] > 1 then
      label = ("%s (%d)"):format(label, seen[label])
    end
    labels[#labels + 1] = label
    lookup[label] = d
  end

  ui.open({
    title = only_current and "Buffer diagnostics" or "Diagnostics",
    id = "diagnostics",
    matcher = matcher.from_list(labels),
    on_select = function(item, action)
      local d = lookup[item]
      if d then
        jump(d, action)
      end
    end,
    preview = function(item)
      local d = lookup[item]
      return d and preview_target(d) or nil
    end,
  })
end

return M
