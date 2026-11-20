-- Keymap picker: search every mapping that applies to the current buffer
-- (buffer-local ones included) by key, description or command.
-- <CR> runs a mapping that works in normal mode; others just show their details.
local matcher = require("core.picker.matcher")
local ui = require("core.picker.ui")
local util = require("core.util")

local M = {}

local QUERY_MODES = { "n", "i", "x", "s", "o", "t", "c" }
-- Display order for the mode letters of one entry.
local DISPLAY_ORDER = { "n", "v", "x", "s", "o", "i", "c", "t" }
-- nvim_get_keymap() reports some mappings under combined mode characters.
local EXPAND = {
  [" "] = { "n", "x", "s", "o" }, -- :map
  ["!"] = { "i", "c" }, -- :map!
  v = { "x", "s" }, -- :vmap
}

---@param map table
---@return string
local function describe(map)
  if map.desc and map.desc ~= "" then
    return map.desc
  end
  if map.rhs and map.rhs ~= "" then
    return map.rhs
  end
  if map.callback then
    local info = debug.getinfo(map.callback, "S")
    return ("<lua %s:%d>"):format(vim.fn.fnamemodify(info.short_src, ":t"), info.linedefined)
  end
  return ""
end

--- Show the leader as <leader>. nvim_get_keymap() expands it to the literal
--- leader character (a plain space for the default <Space> leader).
---@param lhs string
---@return string
local function pretty_lhs(lhs)
  local leader = vim.g.mapleader or "\\"
  if leader ~= "" and lhs:sub(1, #leader) == leader then
    return "<leader>" .. lhs:sub(#leader + 1)
  end
  return lhs
end

--- Collapse a set of modes to a short string: "n", "nv", "it", ...
---@param set table<string, boolean>
---@return string
local function mode_string(set)
  local copy = vim.deepcopy(set)
  if copy.x and copy.s then
    copy.x, copy.s, copy.v = nil, nil, true
  end
  local out = {}
  for _, m in ipairs(DISPLAY_ORDER) do
    if copy[m] then
      out[#out + 1] = m
    end
  end
  return table.concat(out)
end

--- One entry per distinct mapping, with the modes it applies to merged.
---@return table[]
local function collect()
  local entries, index = {}, {}

  ---@param map table
  ---@param buffer boolean
  local function add(map, buffer)
    local lhs = map.lhs
    if lhs:find("^<Plug>") or lhs:find("^<SNR>") then
      return
    end
    local key = table.concat({ buffer and "b" or "g", lhs, map.rhs or "", tostring(map.callback or "") }, "\0")
    local entry = index[key]
    if not entry then
      entry = {
        lhs = lhs,
        lhsraw = map.lhsraw or vim.api.nvim_replace_termcodes(lhs, true, true, true),
        desc = describe(map),
        rhs = map.rhs,
        callback = map.callback,
        buffer = buffer,
        modes = {},
      }
      index[key] = entry
      entries[#entries + 1] = entry
    end
    for _, m in ipairs(EXPAND[map.mode] or { map.mode }) do
      entry.modes[m] = true
    end
  end

  for _, mode in ipairs(QUERY_MODES) do
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
      add(map, true)
    end
    for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
      add(map, false)
    end
  end

  -- Buffer-local mappings first, then by key.
  table.sort(entries, function(a, b)
    if a.buffer ~= b.buffer then
      return a.buffer
    end
    return a.lhs < b.lhs
  end)
  return entries
end

local MAX_MARKED = 30 -- lines of a callback marked in the preview

--- A Lua callback shows its definition; anything else shows the mapping's details.
---@param entry table
---@return core.picker.PreviewTarget
local function preview_target(entry)
  local note = entry.mode_text .. "  " .. entry.shown_lhs
  if entry.callback then
    local info = debug.getinfo(entry.callback, "S")
    local path = info and info.source:sub(1, 1) == "@" and info.source:sub(2) or nil
    if path and info.linedefined > 0 and vim.uv.fs_stat(path) then
      local last = info.lastlinedefined > 0 and info.lastlinedefined or info.linedefined
      return {
        kind = "file",
        path = vim.fn.fnamemodify(path, ":p"),
        lnum = info.linedefined,
        end_lnum = math.min(last, info.linedefined + MAX_MARKED - 1),
        note = note,
      }
    end
  end

  local lines = {
    "",
    "  mode    " .. entry.mode_text,
    "  keys    " .. entry.shown_lhs,
    "  scope   " .. (entry.buffer and "buffer" or "global"),
  }
  if entry.desc ~= "" then
    lines[#lines + 1] = "  desc    " .. entry.desc
  end
  if entry.rhs and entry.rhs ~= "" then
    lines[#lines + 1] = "  rhs     " .. entry.rhs
  elseif entry.callback then
    lines[#lines + 1] = "  rhs     <lua function> (no source available)"
  end
  return { kind = "text", title = "keymap", lines = lines }
end

function M.open()
  local entries = collect()
  if #entries == 0 then
    util.notify("No keymaps found")
    return
  end

  local labels, lookup, seen = {}, {}, {}
  for _, entry in ipairs(entries) do
    entry.mode_text = mode_string(entry.modes)
    entry.shown_lhs = pretty_lhs(entry.lhs)
    local label = ("%-4s %-14s %s%s"):format(
      entry.mode_text,
      entry.shown_lhs,
      entry.desc,
      entry.buffer and "  [buffer]" or ""
    )
    label = (label:gsub("[\r\n]+", " "):gsub("%s+$", ""))

    seen[label] = (seen[label] or 0) + 1
    if seen[label] > 1 then
      label = ("%s (%d)"):format(label, seen[label])
    end
    labels[#labels + 1] = label
    lookup[label] = entry
  end

  ui.open({
    title = "Keymaps",
    id = "keymaps",
    matcher = matcher.from_list(labels),
    preview = function(item)
      local entry = lookup[item]
      return entry and preview_target(entry) or nil
    end,
    on_select = function(item)
      local entry = lookup[item]
      if not entry then
        return
      end
      if entry.modes.n then
        -- Remap + typed, as if the keys were pressed in the window we came from.
        vim.api.nvim_feedkeys(entry.lhsraw, "mt", false)
      else
        util.notify(("%s  %s  ->  %s\n(not a normal-mode mapping, not run)"):format(
          entry.mode_text,
          entry.shown_lhs,
          entry.desc
        ))
      end
    end,
  })
end

return M
